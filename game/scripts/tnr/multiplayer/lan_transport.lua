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

local PRE_ROOM_COMMANDS = {
    VOTE_NODE = true,
    SET_RUN_SEED = true,
    LOADOUT_COMMIT = true,
    ENCOUNTER_READY = true,
    START_ENCOUNTER_AT = true,
    SYNC_NODE = true,
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

function LANTransport:send(payload)
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
    if message and message.kind == "input" and message.payload and message.payload.player_id then
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
                self.session:dispatch(message.payload)
                if self:is_host() then
                    self:_queue("command", message.payload)
                end
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
end

function LANTransport:disconnect(reason)
    if self.socket_handle then self.socket_handle:close() end
    self.socket_handle = nil
    self.connected = false
    self.listening = false
    self.receive_buffer = ""
    reason = reason or self.last_error or "connection closed"
    if not self.disconnect_notified then
        self.disconnect_notified = true
        local callback = self.options and self.options.on_disconnect
        if type(callback) == "function" then pcall(callback, reason) end
    end
end

LANTransport.encode = encode
LANTransport.decode = decode

return LANTransport
