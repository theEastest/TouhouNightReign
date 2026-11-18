local LANTransport = {}
LANTransport.__index = LANTransport

-- LuaSTG embeds LuaSocket's native module as `socket.core`, but does not
-- necessarily ship the optional `socket.lua` convenience wrapper. Keep the
-- transport usable in both layouts and provide the one wrapper operation we
-- need (`bind`) when only the native module is available.
local function load_socket_module(explicit)
    if explicit ~= nil then return explicit end

    local ok, loaded = pcall(require, "socket")
    if ok and loaded then return loaded end

    local core_ok, core = pcall(require, "socket.core")
    if core_ok and core then
        if core.bind == nil then
            core.bind = function(host, port, backlog)
                if host == "*" then host = "0.0.0.0" end
                local server, err = core.tcp()
                if not server then return nil, err end
                server:setoption("reuseaddr", true)
                local bound, bind_error = server:bind(host, port)
                if not bound then
                    server:close()
                    return nil, bind_error
                end
                local listening, listen_error = server:listen(backlog)
                if not listening then
                    server:close()
                    return nil, listen_error
                end
                return server
            end
        end
        return core
    end

    return nil
end

local function encode(value, seen)
    local value_type = type(value)
    if value == nil then return "n" end
    if value_type == "boolean" then return value and "b1" or "b0" end
    if value_type == "number" then return "d" .. string.format("%.17g", value) .. ";" end
    if value_type == "string" then return "s" .. #value .. ":" .. value end
    if value_type ~= "table" then return "n" end
    seen = seen or {}
    if seen[value] then error("cannot encode cyclic LAN payload") end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    local parts = { "t", tostring(#keys), ":" }
    for _, key in ipairs(keys) do
        parts[#parts + 1] = encode(key, seen)
        parts[#parts + 1] = encode(value[key], seen)
    end
    seen[value] = nil
    return table.concat(parts)
end

local function decode(data)
    local position = 1
    local function parse()
        local tag = data:sub(position, position)
        position = position + 1
        if tag == "n" then return nil end
        if tag == "b" then
            local value = data:sub(position, position) == "1"
            position = position + 1
            return value
        end
        if tag == "d" then
            local finish = assert(data:find(";", position, true), "invalid LAN number")
            local value = tonumber(data:sub(position, finish - 1))
            position = finish + 1
            return value
        end
        if tag == "s" then
            local separator = assert(data:find(":", position, true), "invalid LAN string")
            local length = tonumber(data:sub(position, separator - 1))
            position = separator + 1
            local value = data:sub(position, position + length - 1)
            position = position + length
            return value
        end
        if tag == "t" then
            local separator = assert(data:find(":", position, true), "invalid LAN table")
            local count = tonumber(data:sub(position, separator - 1))
            position = separator + 1
            local result = {}
            for _ = 1, count do
                result[parse()] = parse()
            end
            return result
        end
        error("invalid LAN payload tag: " .. tostring(tag))
    end
    return parse()
end

-- Movement/focus state may be safely coalesced to the newest packet, but
-- actions such as Bomb are edge-triggered.  Keep those edges latched while
-- draining the socket so a one-frame action cannot be overwritten by the
-- following ordinary input packet in the same update.
local REMOTE_INPUT_EDGES = {
    "bomb", "confirm", "cancel", "mouse_primary_pressed",
}

local function merge_remote_input(previous, incoming)
    if not previous then return incoming end
    local previous_tick = tonumber(previous.tick) or 0
    local incoming_tick = tonumber(incoming.tick) or 0
    if incoming_tick < previous_tick then return previous end
    local merged = {}
    for key, value in pairs(incoming) do
        merged[key] = value
    end
    for _, key in ipairs(REMOTE_INPUT_EDGES) do
        if previous[key] == true then
            merged[key] = true
            if key == "bomb" and merged.bomb_tick == nil then
                merged.bomb_tick = previous.bomb_tick or previous.tick
                merged.bomb_charged = previous.bomb_charged == true
                merged.bomb_success = previous.bomb_success == true
            end
        end
    end
    if incoming.bomb == true then
        merged.bomb_tick = incoming.bomb_tick or incoming.tick
    end
    return merged
end

local function copy_payload(payload)
    if type(payload) ~= "table" then return payload end
    local result = {}
    for key, value in pairs(payload) do result[key] = value end
    return result
end

local PREPARATION_COMMANDS = {
    EQUIP_ITEM=true, UNEQUIP_ITEM=true, DISCARD_ITEM=true,
    DISCARD_EQUIPPED_ITEM=true, TOGGLE_WEAPON=true, TOGGLE_SUPPORT=true,
    ACCEPT_PENDING_ITEM=true, REJECT_PENDING_ITEM=true, SHOP_READY=true, SHOP_PURCHASE=true,
    CLAIM_REWARD=true, UNCLAIM_REWARD=true, ADVANCE_FLOOR=true, SHRINE_ACTION=true,
}

-- Include all relevant state but omit process-local instance IDs.  The latter
-- depend on each process's previous runs and need not agree across peers.
local function preparation_digest(session, player_id)
    local player = session and session:get_player(player_id)
    if not player or not player.loadout then return nil end
    local loadout = player.loadout
    local function item(value)
        if not value then return false end
        return { definition_id=value.definition_id, owner_player_id=value.owner_player_id,
            equipment_type=value.equipment_type,
            weight=value.weight, runtime_data=value.runtime_data, random_affixes=value.random_affixes }
    end
    local run_state=session.run_state
    if run_state == "MAP_PREPARATION" then run_state="MAP" end
    local state = { capacity=loadout.inventory.capacity, items={}, slots={}, run_state=run_state,
        character_id=player.character_id, loadout_character_id=loadout.character_id,
        current_capacity=player.current_capacity, base_capacity=player.base_capacity,
        capacity_level=player.capacity_level, loadout_version=loadout.version,
        registry_hash=session.equipment_registry and session.equipment_registry:hash(),
        money=player.money, session_money=session.money, bomb=player.bomb,
        team_life=session.party and session.party.team_life,
        life_fragments=session.party and session.party.life_fragments,
        pending_queue={}, claims={}, reward_choices=session.reward_choices,
        reward_required=session.reward_required,
        pending_reward_claims={},
        editable=session.preparation and session.preparation:can_edit(player_id) or false }
    if session.preparation then
        state.pending=item(session.preparation.pending_acquisition[player_id])
        for i, value in ipairs(session.preparation.pending_acquisition_queue[player_id] or {}) do
            state.pending_queue[i]=item(value)
        end
    end
    for _, owner in ipairs(session.party.player_ids or {}) do
        state.pending_reward_claims[owner]=tonumber((session.pending_reward_claims or {})[owner]) or false
        state.claims[owner]={}
        for i, claim in ipairs((session.reward_claims or {})[owner] or {}) do
            state.claims[owner][i]={choice_index=claim.choice_index, definition_id=claim.definition_id,
                kind=claim.kind, resource=claim.resource, amount=claim.amount,
                pending=claim.pending, acquired=claim.acquired, equipment=item(claim.equipment),
                replaced_equipment=item(claim.replaced_equipment), replaced_index=claim.replaced_index}
        end
    end
    local shop=session.shop_service
    if shop then
        local purchase=shop.pending_purchases[player_id]
        state.shop={node_id=shop.node_id, offers=shop.offers, ready1=shop.ready[1] == true, ready2=shop.ready[2] == true,
            purchases=shop.purchases[player_id] or {},
            pending_purchase=purchase and {slot=purchase.slot, price=purchase.price} or false}
    end
    for i, value in ipairs(loadout.inventory.items) do state.items[i]=item(value) end
    for _, group in ipairs({"high_weapons","low_weapons","supports","self_modifiers","support_modifiers"}) do
        state.slots[group]={}
        for i, value in ipairs(loadout[group]) do state.slots[group][i]=item(value) end
    end
    local payload=encode(state)
    local a,b=17,29
    for i=1,#payload do a=(a*131+payload:byte(i))%2147483647; b=(b*65599+payload:byte(i))%2147483629 end
    return string.format("%08x%08x",a,b)
end

local function preparation_dispatch_succeeded(session, command, result, err)
    if result then return true end
    if command.type == "CLAIM_REWARD" and err == "REWARD_PENDING"
            and session.run_state ~= "REWARD"
            and tonumber((session.pending_reward_claims or {})[command.player_id]) == tonumber(command.choice_index) then
        return true
    end
    return command.type == "SHOP_READY" and result == false and err == nil
end

local PRE_ROOM_COMMANDS = {
    VOTE_NODE = true,
    SET_RUN_SEED = true,
    LOADOUT_COMMIT = true,
    ENCOUNTER_READY = true,
    START_ENCOUNTER_AT = true,
    SYNC_NODE = true,
    ADVANCE_FLOOR = true,
}

function LANTransport.new(options)
    options = options or {}
    local socket_module = load_socket_module(options.socket)
    local mode = options.mode or "client"
    return setmetatable({
        options = options,
        socket = socket_module,
        mode = mode,
        role = mode,
        player_id = options.player_id or (mode == "host" and 1 or 2),
        host = options.host or "127.0.0.1",
        port = options.port or 27123,
        connected = false,
        listening = false,
        socket_handle = nil,
        inbox = {},
        outgoing = {},
        remote_inputs = {},
        events = {},
        last_snapshot = nil,
        last_peer_snapshot = nil,
        last_pong = nil,
        receive_buffer = "",
        preparation_sequence = 0,
        preparation_pending = nil,
        preparation_seen = {},
        preparation_result = nil,
        session = nil,
        last_error = nil,
        -- Clock handshake used by the encounter start barrier. The client
        -- estimates host_time - local_time from several ping/pong samples.
        clock_offset = 0,
        clock_error = nil,
        clock_samples = {},
        clock_rtts = {},
        clock_pending = {},
        clock_ping_nonce = 0,
        clock_next_ping = 0,
        clock_synced = mode == "host",
        peer_clock_synced = mode ~= "host",
        clock_rtt = nil,
        peer_clock_rtt = nil,
        clock_ready_sent = false,
        room_generation = nil,
        stale_packets = 0,
        disconnect_notified = false,
    }, LANTransport)
end

function LANTransport:is_available()
    return self.socket ~= nil
end

function LANTransport:is_host()
    return self.mode == "host"
end

function LANTransport:attach_session(session)
    self.session = session
    return self
end

function LANTransport:set_room_generation(generation)
    self.room_generation = generation ~= nil and tostring(generation) or nil
    return self.room_generation
end

function LANTransport:get_room_generation()
    return self.room_generation
end

function LANTransport:_with_room_generation(payload)
    if not self.room_generation or type(payload) ~= "table" then return payload end
    if payload.room_generation ~= nil then return payload end
    local result = copy_payload(payload)
    result.room_generation = self.room_generation
    return result
end

function LANTransport:_accept_room_message(message)
    if type(message) ~= "table" then return true end
    local kind = message.kind
    local payload = message.payload
    if kind ~= "input" and kind ~= "snapshot" and kind ~= "peer_snapshot"
            and kind ~= "event" and kind ~= "command" then
        return true
    end
    -- Menu/handshake commands may be generation-less. Any packet carrying a
    -- generation must match an active room, including after a room ended.
    if type(payload) ~= "table" or payload.room_generation == nil then
        if not self.room_generation then return true end
        self.stale_packets = self.stale_packets + 1
        return false
    end
    -- During the start barrier the session already owns the next encounter,
    -- but the transport may still carry the previous native room generation.
    -- Accept only handshake commands whose generation matches that pending
    -- encounter. Without this rollover case both peers discard the second
    -- room's LOADOUT/READY packets and remain on the preparation screen.
    if kind == "command" and PRE_ROOM_COMMANDS[payload.type] then
        if not self.room_generation then return true end
        local session = self.session
        local encounter = session and session.current_encounter
        local pending_generation = encounter and encounter.room_generation
            or (session and session.room_generation)
        if payload.room_generation ~= nil and pending_generation ~= nil
                and tostring(payload.room_generation) == tostring(pending_generation) then
            return true
        end
    end
    if not self.room_generation
            or tostring(payload.room_generation) ~= tostring(self.room_generation) then
        self.stale_packets = self.stale_packets + 1
        return false
    end
    return true
end

function LANTransport:now()
    if self.socket and type(self.socket.gettime) == "function" then
        local ok, value = pcall(self.socket.gettime)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return os.time()
end

function LANTransport:clock_sync_step()
    if not self.connected or self:is_host() or self.clock_synced then return end
    local now = self:now()
    if now < (self.clock_next_ping or 0) then return end
    self.clock_ping_nonce = (self.clock_ping_nonce or 0) + 1
    local nonce = self.clock_ping_nonce
    self.clock_pending[nonce] = now
    self.clock_next_ping = now + 0.10
    self:_queue("clock_ping", { nonce = nonce, client_time = now })
end

function LANTransport:is_clock_synced()
    return self.clock_synced == true
end

function LANTransport:is_clock_synced_with_peer()
    if self:is_host() then return self.peer_clock_synced == true end
    return self.clock_synced == true
end

function LANTransport:host_time_to_local(host_time)
    return (tonumber(host_time) or self:now()) - (tonumber(self.clock_offset) or 0)
end

function LANTransport:_record_clock_pong(payload)
    if self:is_host() or type(payload) ~= "table" then return end
    local nonce = tonumber(payload.nonce)
    local sent_at = nonce and self.clock_pending[nonce]
    local host_time = tonumber(payload.host_time)
    if not sent_at or not host_time then return end
    self.clock_pending[nonce] = nil
    local received_at = self:now()
    local sample = host_time - (sent_at + received_at) * 0.5
    self.clock_samples[#self.clock_samples + 1] = sample
    self.clock_rtts[#self.clock_rtts + 1] = math.max(0, received_at - sent_at)
    if #self.clock_samples < 3 then return end
    local sorted = {}
    for _, value in ipairs(self.clock_samples) do sorted[#sorted + 1] = value end
    table.sort(sorted)
    local middle = sorted[math.floor((#sorted + 1) * 0.5)]
    self.clock_offset = middle or 0
    local error_sum = 0
    for _, value in ipairs(sorted) do error_sum = error_sum + math.abs(value - self.clock_offset) end
    self.clock_error = error_sum / #sorted
    local sorted_rtts = {}
    for _, value in ipairs(self.clock_rtts) do sorted_rtts[#sorted_rtts + 1] = value end
    table.sort(sorted_rtts)
    self.clock_rtt = sorted_rtts[math.floor((#sorted_rtts + 1) * 0.5)]
    self.clock_synced = true
    if not self.clock_ready_sent then
        self.clock_ready_sent = true
        self:_queue("clock_ready", {
            offset = self.clock_offset,
            error = self.clock_error,
            rtt = self.clock_rtt,
        })
    end
end

function LANTransport:connect()
    if not self.socket then
        self.last_error = "LuaSocket is unavailable; rebuild LuaSTG with LUASTG_LINK_LUASOCKET=ON"
        return false, self.last_error
    end
    if self.connected or self.listening then return true end
    if self.mode == "host" then
        local server, err = self.socket.bind(self.host, self.port)
        if not server then
            self.last_error = err
            return false, err
        end
        server:settimeout(0)
        self.socket_handle = server
        self.listening = true
        self.disconnect_notified = false
        return true
    end
    local client, err = self.socket.tcp()
    if not client then
        self.last_error = err
        return false, err
    end
    client:settimeout(self.options.connect_timeout or 1)
    local ok, connect_error = client:connect(self.host, self.port)
    if not ok then
        client:close()
        self.last_error = connect_error
        return false, connect_error
    end
    client:settimeout(0)
    if client.setoption then client:setoption("tcp-nodelay", true) end
    self.socket_handle = client
    self.connected = true
    self.disconnect_notified = false
    return true
end

function LANTransport:_accept_client()
    if not self.listening or not self.socket_handle then return end
    local client = self.socket_handle:accept()
    if client then
        client:settimeout(0)
        if client.setoption then client:setoption("tcp-nodelay", true) end
        self.socket_handle:close()
        self.socket_handle = client
        self.listening = false
        self.connected = true
        self.disconnect_notified = false
    end
end

function LANTransport:_queue(kind, payload)
    local body = encode({ kind = kind, payload = payload })
    self.outgoing[#self.outgoing + 1] = string.format("%08x", #body) .. body
end

function LANTransport:consume_preparation_result()
    local result = self.preparation_result
    self.preparation_result = nil
    return result
end

function LANTransport:_preparation_abort(reason, notify_peer)
    reason = "配装操作未确认：" .. tostring(reason) .. "；本次联机已终止"
    if notify_peer and self.connected then
        self:_queue("prep_abort", {reason=reason})
        self:_flush()
    end
    self.preparation_result = {ok=false, error=reason}
    self:disconnect(reason)
end

function LANTransport:send_preparation(command)
    if not self.connected then return nil, "连接已断开" end
    if self.preparation_pending then return nil, "等待上一项配装操作确认" end
    if not PREPARATION_COMMANDS[command.type] or command.player_id ~= self.player_id then return nil, "无效配装命令" end
    if command.type == "ADVANCE_FLOOR" and not self:is_host() then return nil, "只有房主可以继续" end
    local before = preparation_digest(self.session, command.player_id)
    if not before then return nil, "无法读取配装状态" end
    self.preparation_sequence = self.preparation_sequence + 1
    local id = self.role .. ":" .. tostring(self.preparation_sequence)
    self.preparation_pending = { id=id, command=command, before=before,
        phase="prepare", started=self:now(), initiator=true }
    self:_queue("prep_prepare", {id=id, command=command, before=before})
    return true
end

function LANTransport:_preparation_commit(pending)
    if preparation_digest(self.session, pending.command.player_id) ~= pending.before then
        return self:_preparation_abort("操作前状态已变化", true)
    end
    local result, err = self.session:dispatch(pending.command)
    if not preparation_dispatch_succeeded(self.session, pending.command, result, err) then
        self:_queue("prep_reject", {id=pending.id, error=err or "操作失败"})
        self.preparation_result = {ok=false, error=err or "操作失败"}
        self.preparation_pending = nil
        return
    end
    pending.after = preparation_digest(self.session, pending.command.player_id)
    pending.phase = "ack"
    self:_queue("prep_commit", {id=pending.id, command=pending.command,
        before=pending.before, after=pending.after})
end

function LANTransport:_handle_preparation(kind, message)
    if type(message) ~= "table" then return self:_preparation_abort("无效消息", true) end
    if kind == "prep_abort" then return self:_preparation_abort(message.reason or "对端终止", false) end
    local pending = self.preparation_pending
    if kind == "prep_prepare" then
        local command, id = message.command, message.id
        local remote_id = self:is_host() and 2 or 1
        local prefix = self:is_host() and "client:" or "host:"
        if type(id) ~= "string" or id:sub(1,#prefix) ~= prefix
                or type(command) ~= "table" or not PREPARATION_COMMANDS[command.type]
                or command.player_id ~= remote_id or type(message.before) ~= "string"
                or (command.type == "ADVANCE_FLOOR" and self:is_host()) then
            return self:_preparation_abort("无效配装请求", true)
        end
        if self.preparation_seen[id] then return end
        self.preparation_seen[id] = true
        if pending then self:_queue("prep_reject", {id=id,error="对端正在处理另一项配装操作"}); return end
        if preparation_digest(self.session, command.player_id) ~= message.before then
            return self:_preparation_abort("双方配装状态不一致", true)
        end
        pending = {id=id, command=command, before=message.before,
            started=self:now(), initiator=false}
        self.preparation_pending = pending
        if self:is_host() then self:_preparation_commit(pending)
        else pending.phase="commit"; self:_queue("prep_ready", {id=id}) end
    elseif kind == "prep_reject" then
        if not pending or pending.id ~= message.id then return end
        self.preparation_pending = nil
        self.preparation_result = {ok=false, error=message.error or "操作被拒绝"}
    elseif kind == "prep_ready" then
        if not pending or pending.id ~= message.id or not self:is_host() or pending.phase ~= "prepare" then return end
        self:_preparation_commit(pending)
    elseif kind == "prep_commit" then
        if not pending or pending.id ~= message.id or self:is_host()
                or (pending.phase ~= "prepare" and pending.phase ~= "commit") then return end
        if message.before ~= pending.before or preparation_digest(self.session, pending.command.player_id) ~= pending.before then
            return self:_preparation_abort("操作前状态不一致", true)
        end
        local result, err = self.session:dispatch(pending.command)
        if not preparation_dispatch_succeeded(self.session, pending.command, result, err)
                or preparation_digest(self.session, pending.command.player_id) ~= message.after then
            return self:_preparation_abort("操作结果不一致", true)
        end
        pending.phase="done"
        pending.after=message.after
        self:_queue("prep_ack", {id=pending.id, after=message.after})
    elseif kind == "prep_ack" then
        if not pending or pending.id ~= message.id or not self:is_host() or pending.phase ~= "ack" then return end
        if message.after ~= pending.after or preparation_digest(self.session, pending.command.player_id) ~= pending.after then
            return self:_preparation_abort("操作确认不一致", true)
        end
        self:_queue("prep_done", {id=pending.id, after=pending.after})
        pending.phase = "sending_done"
    elseif kind == "prep_done" then
        if not pending or pending.id ~= message.id or self:is_host() or pending.phase ~= "done" then return end
        if message.after ~= pending.after or preparation_digest(self.session, pending.command.player_id) ~= pending.after then
            return self:_preparation_abort("最终配装状态不一致", true)
        end
        self.preparation_result = {ok=true}
        self.preparation_pending = nil
    end
end

function LANTransport:send(payload)
    if payload and PREPARATION_COMMANDS[payload.type] then return self:send_preparation(payload) end
    local kind = payload and payload.type and "command" or (payload and payload.kind) or "message"
    -- Capture the wire payload before host-local dispatch. A SET_READY can
    -- synchronously advance the session into a new encounter, and tagging it
    -- after that transition would make the peer reject the preparation
    -- command as belonging to the new room.
    payload = self:_with_room_generation(payload)
    if self:is_host() and self.session and kind == "command" then
        self.session:dispatch(payload)
    end
    self:_queue(kind, payload)
    return true
end

function LANTransport:broadcast(event)
    if not self:is_host() then return false end
    self:_queue("event", self:_with_room_generation(event))
    return true
end

function LANTransport:submit_input(player_input)
    -- Inputs are bidirectional in native co-op as well: the host publishes
    -- P1 input so the client can render the same arena, while the client
    -- publishes P2 input for the host simulation.
    if player_input and self.connected then
        -- The transport is the authority for the sender identity. Older
        -- callers sometimes passed a plain action table without player_id;
        -- attach the configured local id so the peer cannot discard it or
        -- route it to the wrong avatar.
        if type(player_input) == "table" and player_input.player_id == nil then
            local normalized = {}
            for key, value in pairs(player_input) do
                normalized[key] = value
            end
            normalized.player_id = self.player_id
            player_input = normalized
        end
        player_input = self:_with_room_generation(player_input)
        self:_queue("input", player_input)
    end
    return true
end

function LANTransport:publish_snapshot(snapshot)
    if not self.connected then return false end
    self:_queue("snapshot", self:_with_room_generation(snapshot))
    return true
end

-- Peer snapshots are deliberately separate from host-authoritative room
-- snapshots. Both LAN endpoints may publish these compact enemy/player sync
-- records; neither side sends a full bullet or particle object pool.
function LANTransport:publish_peer_snapshot(snapshot)
    if not self.connected then return false end
    self:_queue("peer_snapshot", self:_with_room_generation(snapshot))
    return true
end

function LANTransport:poll()
    local message = table.remove(self.inbox, 1)
    if message and not self:_accept_room_message(message) then
        return nil
    end
    if message and message.kind=="replay" then
        self.replay_messages=self.replay_messages or {}
        self.replay_messages[#self.replay_messages+1]=message.payload
    elseif message and message.kind == "input" and message.payload and message.payload.player_id then
        local player_id = message.payload.player_id
        local previous = self.remote_inputs[player_id]
        self.remote_inputs[player_id] = merge_remote_input(previous, message.payload)
    elseif message and message.kind == "event" then
        self.events[#self.events + 1] = message.payload
    elseif message and message.kind == "snapshot" then
        self.last_snapshot = message.payload
    elseif message and message.kind == "peer_snapshot" then
        self.last_peer_snapshot = message.payload
    elseif message and message.kind == "pong" then
        self.last_pong = message.payload
    elseif message and message.kind == "clock_pong" then
        self:_record_clock_pong(message.payload)
    elseif message and message.kind == "clock_ready" then
        self.peer_clock_synced = true
        self.peer_clock_error = message.payload and tonumber(message.payload.error) or nil
        self.peer_clock_rtt = message.payload and tonumber(message.payload.rtt) or nil
    end
    return message
end

function LANTransport:send_replay(payload)
    if not self.connected then return false end
    self:_queue("replay",payload)
    return true
end
function LANTransport:consume_replay()
    local messages=self.replay_messages or {}
    self.replay_messages={}
    return messages
end

function LANTransport:consume_snapshot()
    local snapshot = self.last_snapshot
    self.last_snapshot = nil
    return snapshot
end

function LANTransport:consume_peer_snapshot()
    local snapshot = self.last_peer_snapshot
    self.last_peer_snapshot = nil
    return snapshot
end

function LANTransport:consume_inputs()
    local result = self.remote_inputs
    self.remote_inputs = {}
    return result
end

function LANTransport:consume_events()
    local result = self.events
    self.events = {}
    return result
end

function LANTransport:ping()
    self:_queue("ping", { sent_at = os.clock() })
    return true
end

function LANTransport:_flush()
    if not self.connected or not self.socket_handle then return end
    while #self.outgoing > 0 do
        local payload = self.outgoing[1]
        local sent, err, partial = self.socket_handle:send(payload)
        if sent then
            table.remove(self.outgoing, 1)
        elseif err == "timeout" then
            if partial and partial > 0 then
                self.outgoing[1] = payload:sub(partial + 1)
            end
            break
        else
            self.last_error = err
            self:disconnect()
            break
        end
    end
    if self.connected and #self.outgoing == 0 and self.preparation_pending
            and self.preparation_pending.phase == "sending_done" then
        self.preparation_result = {ok=true}
        self.preparation_pending = nil
    end
end

function LANTransport:_receive()
    if not self.connected or not self.socket_handle then return end
    while true do
        local chunk, err, partial = self.socket_handle:receive(4096)
        local received = chunk or partial
        if received and #received > 0 then
            self.receive_buffer = self.receive_buffer .. received
        end
        while #self.receive_buffer >= 8 do
            local length = tonumber(self.receive_buffer:sub(1, 8), 16)
            if not length then
                self.last_error = "invalid LAN frame header"
                self:disconnect()
                return
            end
            if #self.receive_buffer < 8 + length then break end
            local body = self.receive_buffer:sub(9, 8 + length)
            self.receive_buffer = self.receive_buffer:sub(9 + length)
            local ok, message = pcall(decode, body)
            if ok and message then
                self.inbox[#self.inbox + 1] = message
            elseif not ok then
                self.last_error = tostring(message)
            end
        end
        if chunk then
            -- A full 4096-byte read may have more data immediately available.
        elseif err ~= "timeout" then
            self.last_error = err
            self:disconnect()
            break
        else
            break
        end
    end
end

function LANTransport:update()
    if self.listening then self:_accept_client() end
    self:_flush()
    self:_receive()
    while #self.inbox > 0 do
        local message = self:poll()
        if message then
            if message.kind == "command" and self.session then
                if message.payload and PREPARATION_COMMANDS[message.payload.type] then
                    self:_preparation_abort("对端发送了未确认的配装命令", true)
                    break
                end
                self.session:dispatch(message.payload)
                if self:is_host() then
                    self:_queue("command", message.payload)
                end
            elseif type(message.kind) == "string" and message.kind:sub(1,5) == "prep_" then
                self:_handle_preparation(message.kind, message.payload)
                if not self.connected then break end
            elseif message.kind == "snapshot" then
                self.last_snapshot = message.payload
            elseif message.kind == "peer_snapshot" then
                self.last_peer_snapshot = message.payload
            elseif message.kind == "ping" then
                self:_queue("pong", message.payload)
            elseif message.kind == "clock_ping" and type(message.payload) == "table" then
                -- Reply with the host's wall-clock sample. The client combines
                -- this with its send/receive times to estimate clock offset.
                self:_queue("clock_pong", {
                    nonce = message.payload.nonce,
                    client_time = message.payload.client_time,
                    host_time = self:now(),
                })
            end
        end
    end
    self:_flush()
    if self.connected and self.preparation_pending and self:now() - self.preparation_pending.started > 8 then
        self:_preparation_abort("等待对端确认超时", true)
    end
end

function LANTransport:disconnect(reason)
    if self.socket_handle then self.socket_handle:close() end
    self.socket_handle = nil
    self.connected = false
    self.listening = false
    self.receive_buffer = ""
    reason = reason or self.last_error or "connection closed"
    if self.preparation_pending then
        reason = "配装操作未确认：" .. tostring(reason) .. "；本次联机已终止"
    end
    self.preparation_pending = nil
    self.outgoing = {}
    if not self.disconnect_notified then
        self.disconnect_notified = true
        local callback = self.options and self.options.on_disconnect
        if type(callback) == "function" then pcall(callback, reason) end
    end
end

LANTransport.encode = encode
LANTransport.decode = decode

return LANTransport
