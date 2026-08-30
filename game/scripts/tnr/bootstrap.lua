local GameSession = require("tnr.core.game_session")
local Constants = require("tnr.core.constants")
local Command = require("tnr.core.command")
local LocalTransport = require("tnr.multiplayer.local_transport")
local SinglePlayerInputProvider = require("tnr.input.single_player")
local MapScene = require("tnr.map.map_scene")
local LuaSTGInputProvider = require("tnr.input.luastg_input")
local MapRenderer = require("tnr.ui.map_renderer")
local StageAdapter = require("tnr.battle.stage_adapter")
local DebugConsole = require("tnr.debug.console")
local Event = require("tnr.core.event")
local AudioManager = require("tnr.audio.audio_manager")
local TrainingCatalog = require("tnr.training.card_training_catalog")
local NonSpellCatalog = require("tnr.training.nonspell_training_catalog")
local EnemyCatalog = require("tnr.training.enemy_training_catalog")
local BattleSync = require("tnr.multiplayer.battle_sync")
local LANTransport = require("tnr.multiplayer.lan_transport")
local NetworkMenu = require("tnr.multiplayer.network_menu")
local NativeSyncAudit = require("tnr.multiplayer.native_sync_audit")

local Bootstrap = {}
Bootstrap.__index = Bootstrap

-- The host sends one shared wall-clock timestamp after the clock handshake.
-- This fallback is used only when no RTT sample is available.
local ENCOUNTER_START_LEAD_FALLBACK = 0.35
local ENCOUNTER_START_LEAD_MIN = 0.12
local ENCOUNTER_START_LEAD_MAX = 0.75

local NETWORK_TRACE_ENABLED = os.getenv("TNR_NETWORK_TRACE") == "1"

function Bootstrap:_network_trace(event_name, details)
    if not NETWORK_TRACE_ENABLED then return end
    local transport = self.transport
    local player_id = transport and transport.player_id or os.getenv("TNR_PLAYER_ID") or "?"
    local role = transport and transport.mode or "local"
    local path = "network_trace_" .. tostring(player_id) .. ".log"
    local file = io.open(path, "a")
    if not file then return end
    local fields = {
        string.format("%.6f", transport and transport:now() or os.clock()),
        tostring(role),
        tostring(event_name),
    }
    if type(details) == "table" then
        local keys = {}
        for key in pairs(details) do keys[#keys + 1] = key end
        table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
        for _, key in ipairs(keys) do
            local value = details[key]
            fields[#fields + 1] = tostring(key) .. "=" .. tostring(value)
        end
    end
    file:write(table.concat(fields, " "), "\n")
    file:close()
end

function Bootstrap.create(options)
    options = options or {}
    local session = GameSession.new(options)
    local transport = options.transport or LocalTransport.new(session)
    if transport.attach_session then
        transport:attach_session(session)
    end
    local input = options.lstg and LuaSTGInputProvider.new(options.lstg, options.input) or SinglePlayerInputProvider.new(options.input)
    local map_scene = MapScene.new(session)
    local renderer = options.lstg and MapRenderer.new(options.lstg, options.width or 1280, options.height or 720) or nil
    local audio = AudioManager.new(options.lstg)
    local stage_adapter = StageAdapter.new(session, options.stage, options.lstg, audio)
    local battle_sync = BattleSync.new(transport, {
        role = options.network_role,
        local_player_id = options.local_player_id or session.local_player_id,
        snapshot_interval = options.snapshot_interval,
    })
    local debug_console = DebugConsole.new(session, {
        on_kill_all = function()
            return stage_adapter:kill_all()
        end,
        on_net_status = function()
            local audit = instance and instance.native_sync_audit
            return {
                transport = transport.last_error or "OK",
                room_generation = transport.get_room_generation and transport:get_room_generation() or nil,
                stale_packets = transport.stale_packets or 0,
                preflight = stage_adapter.native_preflight,
                native = audit and audit:status() or nil,
            }
        end,
    })
    local instance
    session:on(Event.ENCOUNTER_STARTED, function(event)
        if instance and instance:_network_start_barrier_enabled() then
            instance:_queue_encounter_start(event.encounter)
        else
            stage_adapter:start(event.encounter)
        end
    end)

    instance = setmetatable({
        session = session,
        transport = transport,
        input = input,
        map_scene = map_scene,
        renderer = renderer,
        stage_adapter = stage_adapter,
        battle_sync = battle_sync,
        debug_console = debug_console,
        audio = audio,
        initialized = false,
        menu_cursor = 1,
        training_cursor = 1,
        failure_cursor = 1,
        preparation_cursor = 1,
        preparation_message = "",
        preparation_discard_pending = nil,
        selection_catalog = TrainingCatalog,
        selection_kind = "card",
        selection_title = "符卡训练",
        network_menu = NetworkMenu.new(),
        -- Native LAN rooms run one local simulation per process. Keep the
        -- latest remote movement/shoot state between packets so a transient
        -- socket frame cannot freeze the other player's avatar.
        native_remote_inputs = {},
        native_remote_last_tick = {},
        native_peer_sync_tick = 0,
        native_peer_silence_tick = 0,
        native_peer_seen = false,
        lan_transport_factory = options.lan_transport_factory or function(config)
            return LANTransport.new(config)
        end,
        network_seed = options.network_seed or options.run_seed or 20260826,
        suppress_peer_leave = false,
        pending_encounter = nil,
        pending_encounter_start_at = nil,
        pending_encounter_start_host_at = nil,
        pending_encounter_start_node_id = nil,
        pending_encounter_start_encounter_id = nil,
        pending_encounter_start_content_seed = nil,
        pending_encounter_start_room_generation = nil,
        peer_encounter_ready = {},
        loadout_commit_sent = {},
        native_sync_audit = NativeSyncAudit.new({ interval = 30 }),
        native_sync_tick = 0,
    }, Bootstrap)
    session:on(Event.BATTLE_FAILURE_ACTION, function(event)
        instance:_handle_battle_failure_action(event.choice)
    end)
    session:on("NATIVE_PEER_LEAVE", function()
        -- A remote menu/exit is a shared battle transition. Suppress the
        -- reciprocal command so the two endpoints do not bounce the event.
        if instance.session.run_state == Constants.run_states.ENCOUNTER
                or instance.session.run_state == Constants.run_states.RUN_FAILED
                or instance.session.run_state == Constants.run_states.CARD_TRAINING_FAILED then
            instance.suppress_peer_leave = true
            instance:return_to_menu()
            instance.suppress_peer_leave = false
        end
    end)
    session:on(Event.ENCOUNTER_START_AT, function(event)
        instance:_receive_encounter_start(event)
    end)
    session:on(Event.ENCOUNTER_READY, function(event)
        instance:_receive_encounter_ready(event)
    end)
    return instance
end

function Bootstrap:init()
    if self.initialized then
        return
    end
    self.initialized = true
end

function Bootstrap:_network_start_barrier_enabled()
    return self.battle_sync and self.battle_sync:is_networked()
        and self.transport and type(self.transport.clock_sync_step) == "function"
end

function Bootstrap:_clear_native_room_transport_state()
    -- Snapshots from the previous encounter may contain a dead/hidden player
    -- and can arrive after the map vote. Discard them before constructing the
    -- next native stage so both proxies start visible and alive.
    if self.transport and self.transport.consume_snapshot then
        self.transport:consume_snapshot()
    end
    if self.transport and self.transport.consume_peer_snapshot then
        self.transport:consume_peer_snapshot()
    end
    if self.transport and self.transport.set_room_generation then
        self.transport:set_room_generation(nil)
    end
    self.native_remote_inputs = {}
    self.native_remote_last_tick = {}
    self.native_peer_sync_tick = 0
    self.native_peer_silence_tick = 0
    self.native_peer_seen = false
    self.peer_encounter_ready = {}
    self.loadout_commit_sent = {}
    self.pending_encounter = nil
    self.pending_encounter_start_at = nil
    self.pending_encounter_start_host_at = nil
    self.pending_encounter_start_node_id = nil
    self.pending_encounter_start_encounter_id = nil
    self.pending_encounter_start_content_seed = nil
    self.pending_encounter_start_room_generation = nil
end

function Bootstrap:_receive_encounter_ready(event)
    if not self:_network_start_barrier_enabled()
            or not self.transport:is_host() then
        return
    end
    local node_id = event and tonumber(event.node_id)
    local encounter = self.pending_encounter or self.session.current_encounter
    if not node_id or not encounter or tonumber(encounter.node_id) ~= node_id
            or (event.room_generation ~= nil
                and tostring(event.room_generation) ~= tostring(encounter.room_generation)) then
        self:_network_trace("ready_ignored", {
            node = node_id,
            current = encounter and encounter.node_id or "nil",
        })
        return
    end
    self.peer_encounter_ready[node_id] = true
    self:_network_trace("ready_received", { node = node_id })
    self:_try_send_encounter_start()
end

function Bootstrap:_receive_encounter_start(event)
    local start_at = event and tonumber(event.start_at)
    if not start_at or not self:_network_start_barrier_enabled() then
        return
    end
    local node_id = event and tonumber(event.node_id)
    local encounter = self.pending_encounter or self.session.current_encounter
    if not encounter then
        -- The map vote and the synchronized start command travel on the same
        -- TCP stream, but they are dispatched on different frames. Preserve
        -- an early timestamp until the local ENCOUNTER_STARTED event arrives.
        self.pending_encounter_start_host_at = start_at
        self.pending_encounter_start_node_id = node_id
        self.pending_encounter_start_encounter_id = event.encounter_id
        self.pending_encounter_start_content_seed = event.content_seed
        self.pending_encounter_start_room_generation = event.room_generation
        self:_network_trace("start_cached", { node = node_id, host_at = start_at })
        return
    end
    if node_id and tonumber(encounter.node_id) ~= node_id then
        self:_network_trace("start_ignored", {
            node = node_id,
            current = encounter and encounter.node_id or "nil",
        })
        return
    end
    if event.encounter_id and tostring(event.encounter_id) ~= tostring(encounter.id) then return end
    if event.content_seed ~= nil and tonumber(event.content_seed) ~= tonumber(encounter.content_seed) then return end
    if event.room_generation ~= nil and tostring(event.room_generation) ~= tostring(encounter.room_generation) then return end
    self.pending_encounter = encounter
    self.pending_encounter_start_node_id = node_id or tonumber(encounter.node_id)
    self.pending_encounter_start_host_at = start_at
    self.pending_encounter_start_encounter_id = event.encounter_id
    self.pending_encounter_start_content_seed = event.content_seed
    self.pending_encounter_start_room_generation = event.room_generation
    if self.transport.host_time_to_local then
        self.pending_encounter_start_at = self.transport:host_time_to_local(start_at)
    else
        self.pending_encounter_start_at = start_at
    end
    self:_network_trace("start_received", {
        node = node_id or encounter.node_id,
        host_at = start_at,
        local_at = self.pending_encounter_start_at,
    })
end

function Bootstrap:_try_send_encounter_start()
    if not self.pending_encounter or self.pending_encounter_start_at then return end
    if not self.transport:is_host() or not self.transport:is_clock_synced_with_peer() then
        return
    end
    local node_id = tonumber(self.pending_encounter.node_id)
    if not node_id or not self.peer_encounter_ready[node_id] then
        return
    end
    -- Both peers must publish an immutable loadout descriptor before the
    -- host schedules the native room.  This keeps the two local simulations
    -- on the same character/equipment contract without synchronizing every
    -- projectile.
    if self.session.player_count > 1 and not self.session:all_loadouts_committed() then
        return
    end
    local lead = ENCOUNTER_START_LEAD_FALLBACK
    local peer_rtt = tonumber(self.transport.peer_clock_rtt)
    if peer_rtt then
        -- Leave one half-RTT for command delivery plus a small frame margin.
        lead = math.max(ENCOUNTER_START_LEAD_MIN,
            math.min(ENCOUNTER_START_LEAD_MAX, peer_rtt * 1.5 + 0.05))
    end
    local start_at = self.transport:now() + lead
    self.pending_encounter_start_host_at = start_at
    self.pending_encounter_start_at = start_at
    self.transport:send({
        type = Command.START_ENCOUNTER_AT,
        start_at = start_at,
        node_id = self.pending_encounter.node_id,
        encounter_id = self.pending_encounter.id,
        content_seed = self.pending_encounter.content_seed,
        room_generation = self.pending_encounter.room_generation,
        player_id = self.session.local_player_id,
    })
    self:_network_trace("start_sent", {
        node = node_id,
        host_at = start_at,
        lead = lead,
    })
end

function Bootstrap:_queue_encounter_start(encounter)
    self.pending_encounter = encounter
    local node_id = tonumber(encounter and encounter.node_id)
    local local_id = self.session.local_player_id or 1
    if self.session.player_count > 1 and not self.loadout_commit_sent[local_id] then
        local commit, commit_err = self.session:commit_loadout(local_id)
        if not commit then
            self.stage_adapter.network_status = "Loadout commit failed: " .. tostring(commit_err)
            self:_network_trace("loadout_commit_failed", { node = node_id, error = commit_err })
            return
        end
        self.loadout_commit_sent[local_id] = true
        self.transport:send({
            type = Command.LOADOUT_COMMIT,
            player_id = local_id,
            commit = commit,
            node_id = node_id,
            room_generation = encounter and encounter.room_generation,
        })
        self:_network_trace("loadout_commit_sent", {
            node = node_id,
            hash = commit.loadout_hash,
        })
    end
    local cached_node_id = tonumber(self.pending_encounter_start_node_id)
    local cached_start_at = tonumber(self.pending_encounter_start_host_at)
    self.pending_encounter_start_at = nil
    if not cached_start_at or (cached_node_id and cached_node_id ~= node_id) then
        self.pending_encounter_start_host_at = nil
        self.pending_encounter_start_node_id = nil
        self.pending_encounter_start_encounter_id = nil
        self.pending_encounter_start_content_seed = nil
        self.pending_encounter_start_room_generation = nil
        cached_start_at = nil
    end
    self:_network_trace("encounter_queued", {
        node = encounter and encounter.node_id or "nil",
        host = self.transport:is_host(),
    })
    if self.transport:is_host() then
        self.peer_encounter_ready[node_id] = true
        self:_network_trace("ready_local", { node = encounter.node_id })
    else
        if not cached_start_at then
            self.transport:send({
                type = Command.ENCOUNTER_READY,
                node_id = encounter.node_id,
                encounter_id = encounter.id,
                content_seed = encounter.content_seed,
                room_generation = encounter.room_generation,
                player_id = self.session.local_player_id,
            })
            self:_network_trace("ready_sent", { node = encounter.node_id })
        end
    end
    if cached_start_at then
        if self.pending_encounter_start_encounter_id
                and tostring(self.pending_encounter_start_encounter_id) ~= tostring(encounter.id) then
            return
        end
        if self.pending_encounter_start_content_seed ~= nil
                and tonumber(self.pending_encounter_start_content_seed) ~= tonumber(encounter.content_seed) then
            return
        end
        if self.pending_encounter_start_room_generation ~= nil
                and tostring(self.pending_encounter_start_room_generation) ~= tostring(encounter.room_generation) then
            return
        end
        self.pending_encounter_start_at = self.transport.host_time_to_local
            and self.transport:host_time_to_local(cached_start_at) or cached_start_at
        self:_network_trace("start_applied_cached", {
            node = node_id,
            host_at = cached_start_at,
            local_at = self.pending_encounter_start_at,
        })
    end
    self:_try_send_encounter_start()
end

function Bootstrap:_start_scheduled_encounter()
    if not self.pending_encounter or not self.pending_encounter_start_at then return end
    local now = self.transport and self.transport.now and self.transport:now() or os.time()
    if now < self.pending_encounter_start_at then return end
    local encounter = self.pending_encounter
    -- Drain packets already buffered on the socket before replacing the
    -- native stage. This prevents the tail of the previous room's death or
    -- hidden-player snapshot from being applied to the newly created room.
    if self.transport and self.transport.update then
        self.transport:update()
    end
    if self.session.run_state ~= Constants.run_states.ENCOUNTER then
        return
    end
    self:_clear_native_room_transport_state()
    if self.transport and self.transport.set_room_generation then
        self.transport:set_room_generation(encounter.room_generation)
    end
    if self.stage_adapter.native_bridge and self.stage_adapter.native_bridge.set_room_generation then
        self.stage_adapter.native_bridge.set_room_generation(encounter.room_generation)
    end
    if self.native_sync_audit then
        self.native_sync_audit:reset(encounter.room_generation)
    end
    self.pending_encounter = nil
    self.pending_encounter_start_at = nil
    self.pending_encounter_start_host_at = nil
    self.pending_encounter_start_node_id = nil
    self.pending_encounter_start_encounter_id = nil
    self.pending_encounter_start_content_seed = nil
    self.pending_encounter_start_room_generation = nil
    self.peer_encounter_ready = {}
    self:_network_trace("stage_started", { node = encounter.node_id })
    self.stage_adapter:start(encounter)
end

function Bootstrap:_poll_inputs()
    local player_ids = self.session.party and self.session.party.player_ids or { 1 }
    if #player_ids == 0 then
        player_ids = { 1 }
    end
    if self.battle_sync and self.battle_sync:is_networked() then
        player_ids = { self.session.local_player_id }
    end
    if self.input.poll_all then
        return self.input:poll_all(player_ids)
    end
    local result = {}
    for _, player_id in ipairs(player_ids) do
        result[player_id] = self.input:poll(player_id)
    end
    return result
end

function Bootstrap:start_game(run_seed)
    if not (self.battle_sync and self.battle_sync:is_networked()) then
        self.session.player_count = 1
        self.session.local_player_id = 1
        if self.stage_adapter.native_bridge and self.stage_adapter.native_bridge.set_authority then
            self.stage_adapter.native_bridge.set_authority(true)
        end
    end
    self.session:start_new(run_seed)
    self.loadout_commit_sent = {}
    self.native_remote_inputs = {}
    self.native_remote_last_tick = {}
    self.native_peer_sync_tick = 0
    self.native_peer_silence_tick = 0
    self.native_peer_seen = false
    self.pending_encounter = nil
    self.pending_encounter_start_at = nil
    self.pending_encounter_start_host_at = nil
    self.pending_encounter_start_node_id = nil
    self.map_scene.cursor_node_id = nil
    self.menu_cursor = 1
    if self.audio then
        self.audio:play_music("stage")
    end
end

function Bootstrap:open_network_menu(mode)
    self.network_menu:open(mode)
    if self.input.begin_text_input then self.input:begin_text_input() end
end

function Bootstrap:close_network_menu()
    self.network_menu:close()
    if self.input.end_text_input then self.input:end_text_input() end
end

function Bootstrap:start_network_game(config)
    if self.transport and self.transport.disconnect then self.transport:disconnect() end
    local local_player_id = config.mode == "host" and 1 or 2
    local transport = self.lan_transport_factory({
        mode = config.mode,
        player_id = local_player_id,
        host = config.host,
        port = config.port,
    })
    if transport.attach_session then transport:attach_session(self.session) end
    local connected, connect_error = transport:connect()
    if not connected then
        if transport.disconnect then transport:disconnect() end
        self.network_menu:set_error(connect_error)
        return nil, connect_error
    end

    self.transport = transport
    if self.stage_adapter.native_bridge and self.stage_adapter.native_bridge.set_authority then
        self.stage_adapter.native_bridge.set_authority(config.mode == "host")
    end
    self.native_remote_inputs = {}
    self.native_remote_last_tick = {}
    self.native_peer_sync_tick = 0
    self.native_peer_silence_tick = 0
    self.native_peer_seen = false
    self.peer_encounter_ready = {}
    self.session.player_count = 2
    self.session.local_player_id = local_player_id
    self.battle_sync = BattleSync.new(transport, {
        role = config.mode,
        local_player_id = local_player_id,
        snapshot_interval = 30,
    })
    self:close_network_menu()
    self:start_game(self.network_seed)
    if config.mode == "host" then
        self.stage_adapter.network_status = string.format("等待客户端连接  端口 %d", config.port)
    else
        self.stage_adapter.network_status = string.format("已连接 %s:%d", config.host, config.port)
    end
    return true
end

function Bootstrap:_submit_map_choice(node_id)
    if not node_id then
        return nil, "no selectable node"
    end

    local player_ids = self.session.party and self.session.party.player_ids or { 1 }
    if self.battle_sync and self.battle_sync:is_networked() then
        player_ids = { self.session.local_player_id }
    end
    for _, player_id in ipairs(player_ids) do
        self.transport:send({
            type = Command.VOTE_NODE,
            node_id = node_id,
            player_id = player_id,
        })
    end
    return true
end

function Bootstrap:_open_preparation()
    local result, err = self.session:enter_preparation()
    if not result then
        self.preparation_message = err or "无法打开地图整备"
        return nil, self.preparation_message
    end
    self.preparation_cursor = 1
    self.preparation_message = ""
    self.preparation_discard_pending = nil
    return result
end

function Bootstrap:_preparation_rows()
    local player = self.session:get_player(self.session.local_player_id or 1) or self.session:get_player(1)
    local rows = { { kind = "action" } }
    if not player or not player.loadout then return rows end
    rows[#rows + 1] = { kind = "relic" }
    for _, group in ipairs({ "high_weapons", "low_weapons", "supports", "self_modifiers", "support_modifiers" }) do
        rows[#rows + 1] = { kind = "header" }
        for index, instance in ipairs(player.loadout[group]) do
            rows[#rows + 1] = { kind = "equipped", group = group, index = index, instance = instance }
        end
    end
    rows[#rows + 1] = { kind = "header" }
    for index, instance in ipairs(player.loadout.inventory.items) do
        rows[#rows + 1] = { kind = "inventory", index = index, instance = instance }
    end
    return rows
end

function Bootstrap:_activate_preparation()
    local player_id = self.session.local_player_id or 1
    local player = self.session:get_player(player_id)
    local row = self:_preparation_rows()[self.preparation_cursor]
    if not row or not player then return nil end
    if row.kind == "action" then
        local result, err = self.session:set_player_ready(player_id, not player.map_ready)
        if result and (self.session.player_count or 1) == 1 then
            local committed, commit_err = self.session:commit_prepared_node()
            if not committed then
                err = commit_err or "READY_COMMIT_FAILED"
                result = nil
            end
        end
        if not result and err then self.preparation_message = err else self.preparation_message = result and "Ready 已锁定配装" or "已取消 Ready" end
        return result
    elseif row.kind == "equipped" then
        local result, err = self.session:dispatch({ type = Command.UNEQUIP_ITEM, player_id = player_id, slot_type = row.group, slot_index = row.index })
        self.preparation_message = result and "装备已卸下到仓库" or (err or "卸下失败")
        return result
    elseif row.kind == "inventory" then
        local definition = self.session.equipment_registry:get(row.instance.definition_id)
        local group
        if definition and definition.equipment_type == "WEAPON" then
            local allowed = definition.allowed_slots
            group = allowed and not allowed.HIGH_WEAPON and allowed.LOW_WEAPON and "low_weapons" or "high_weapons"
        elseif definition and definition.equipment_type == "SUPPORT" then group = "supports"
        elseif definition and definition.equipment_type == "SELF_MODIFIER" then group = "self_modifiers"
        elseif definition and definition.equipment_type == "SUPPORT_MODIFIER" then group = "support_modifiers" end
        if not group then self.preparation_message = "该物品不能装备"; return nil end
        local target = 1
        for index, value in ipairs(player.loadout[group]) do
            if not value or value == false then target = index; break end
        end
        local result, err = self.session:dispatch({ type = Command.EQUIP_ITEM, player_id = player_id, inventory_index = row.index, slot_type = group, slot_index = target })
        self.preparation_message = result and "装备已从仓库移入槽位" or (err or "装备失败")
        return result
    end
end

function Bootstrap:_activate_main_menu(index)
    if index == 1 then
        self.session.player_count = 1
        self.session.local_player_id = 1
        self:start_game()
    elseif index == 2 then
        self:open_network_menu("host")
    elseif index == 3 then
        self:open_network_menu("client")
    elseif index == 4 then
        self:open_training_selection("card")
    elseif index == 5 then
        self:open_training_selection("nonspell")
    elseif index == 6 then
        self:open_training_selection("enemy")
    elseif index == 7 then
        return true
    end
    return false
end

function Bootstrap:_update_network_menu(player_input)
    local menu = self.network_menu
    local text = player_input.text or ""
    if self.input.consume_text then text = text .. self.input:consume_text() end
    if text ~= "" then menu:append_text(text) end
    if player_input.backspace then menu:backspace() end
    if player_input.tab then
        menu:move_cursor(1)
    elseif player_input.move_y ~= 0 then
        menu:move_cursor(-player_input.move_y)
    end
    if self.input.get_mouse_position and self.renderer and self.renderer.network_menu_hit_test then
        local mouse_x, mouse_y = self.input:get_mouse_position()
        local hit = self.renderer:network_menu_hit_test(mouse_x, mouse_y, menu:get_item_count())
        if hit then
            menu.cursor = hit
            if player_input.mouse_primary_pressed and hit == menu:get_item_count() then
                local config = menu:confirm()
                if config then self:start_network_game(config) end
            end
        end
    end
    if player_input.confirm then
        local config = menu:confirm()
        if config then self:start_network_game(config) end
    elseif player_input.cancel then
        self:close_network_menu()
    end
end

function Bootstrap:open_training_selection(kind)
    local states = { card = Constants.run_states.CARD_SELECT, nonspell = Constants.run_states.NON_SPELL_SELECT, enemy = Constants.run_states.ENEMY_SELECT }
    local catalogs = { card = TrainingCatalog, nonspell = NonSpellCatalog, enemy = EnemyCatalog }
    local titles = { card = "符卡训练", nonspell = "非符练习", enemy = "小怪练习" }
    self.selection_kind = kind
    self.selection_catalog = catalogs[kind] or TrainingCatalog
    self.selection_title = titles[kind] or "练习"
    self.session.player_count = 1
    self.session.local_player_id = 1
    self.training_cursor = 1
    self.session.run_state = states[kind] or Constants.run_states.CARD_SELECT
end

function Bootstrap:start_selected_training(index)
    local catalog = self.selection_catalog or TrainingCatalog
    local requested = index or self.training_cursor
    local card = type(requested) == "string" and nil or catalog[requested]
    if type(requested) == "string" then
        for _, candidate in ipairs(catalog) do
            if candidate.id == requested then
                card = candidate
                break
            end
        end
    end
    if not card then
        return nil
    end
    for cursor, candidate in ipairs(catalog) do
        if candidate.id == card.id then
            self.training_cursor = cursor
            break
        end
    end
    local player_total = #self.session.players:get_players()
    if not self.session.map or player_total ~= 1 then
        self.session:start_new()
    end
    if self.selection_kind == "enemy" then
        self.stage_adapter:start_enemy_training(card.id)
    else
        self.stage_adapter:start_training(card.id)
        if self.selection_kind == "nonspell" then
            self.stage_adapter.training_return_state = Constants.run_states.NON_SPELL_SELECT
        else
            self.stage_adapter.training_return_state = Constants.run_states.CARD_SELECT
        end
    end
    if self.audio then
        self.audio:play_music("spellcard")
    end
    return card
end

function Bootstrap:restart_training()
    return self:start_selected_training(self.stage_adapter.training_target_id)
end

function Bootstrap:_failure_option_count()
    if (self.session.player_count or 1) > 1 and self.battle_sync and self.battle_sync:is_networked() then
        return 3
    end
    return 2
end

function Bootstrap:_failure_choice(index)
    if index == 1 then return "RETRY_ENCOUNTER" end
    if index == 2 and self:_failure_option_count() == 3 then return "RESTART_RUN" end
    return "RETURN_MENU"
end

function Bootstrap:_handle_battle_failure_action(choice)
    if choice == "RETRY_ENCOUNTER" then
        self.failure_cursor = 1
        self.stage_adapter:retry_encounter()
    elseif choice == "RESTART_RUN" then
        -- Both peers derive the reroll from the same completed run seed, so
        -- restarting remains deterministic across the LAN connection while
        -- still producing a new map instead of replaying the old one.
        local previous_seed = math.floor(tonumber(self.session.run_seed) or os.time())
        local seed = (previous_seed * 1664525 + 1013904223) % 2147483647
        if seed == previous_seed then
            seed = (seed + 1) % 2147483647
        end
        self.stage_adapter:reset_for_new_run()
        self:start_game(seed)
    elseif choice == "RETURN_MENU" then
        self:return_to_menu()
    end
end

function Bootstrap:_choose_battle_failure(index)
    local choice = self:_failure_choice(index)
    if self:_failure_option_count() == 3 then
        self.transport:send({
            type = Command.BATTLE_FAILURE_VOTE,
            choice = choice,
            player_id = self.session.local_player_id,
        })
        return
    end
    self:_handle_battle_failure_action(choice)
end

function Bootstrap:return_to_menu()
    local was_battle = self.session.run_state == Constants.run_states.ENCOUNTER
        or self.session.run_state == Constants.run_states.RUN_FAILED
        or self.session.run_state == Constants.run_states.CARD_TRAINING_FAILED
    if was_battle and not self.suppress_peer_leave
            and self.battle_sync and self.battle_sync:is_networked()
            and self.transport and self.transport.send then
        self.transport:send({
            type = Command.NATIVE_LEAVE_BATTLE,
            player_id = self.session.local_player_id,
        })
    end
    if self.stage_adapter.training_mode then
        self.stage_adapter:leave_training()
    end
    self.session.run_state = Constants.run_states.MENU
    self.menu_cursor = 1
    self.native_remote_inputs = {}
    self.native_remote_last_tick = {}
    self.native_peer_sync_tick = 0
    self.native_peer_silence_tick = 0
    self.native_peer_seen = false
    self.pending_encounter = nil
    self.pending_encounter_start_at = nil
    self.pending_encounter_start_host_at = nil
    if self.audio then
        self.audio:play_music("menu")
    end
end

function Bootstrap:update()
    if not self.initialized then
        self:init()
    end
    local inputs = self:_poll_inputs()
    local player_input = inputs[self.session.local_player_id] or inputs[1]
    if not player_input then
        for _, input in pairs(inputs) do
            player_input = input
            break
        end
    end
    player_input = player_input or self.input:poll(self.session.local_player_id)
    if self:_network_start_barrier_enabled() then
        -- Keep the clock handshake alive from the network menu onward. The
        -- host publishes an encounter start timestamp only after the client
        -- reports a stable clock offset.
        self.transport:clock_sync_step()
        self:_try_send_encounter_start()
        self:_start_scheduled_encounter()
    end
    local network_battle = self.session.run_state == Constants.run_states.ENCOUNTER
        and self.battle_sync and self.battle_sync:is_networked()
    -- Native legacy rooms are driven by the reference object pool rather than
    -- StageAdapter's project runtime.  BattleSync intentionally waits for a
    -- runtime tick, so applying it to these rooms would return nil forever and
    -- freeze both host and client at the room entrance.
    local native_network_battle = network_battle
        and self.stage_adapter:is_native_active()
    local transport_polled_for_native = false
    if native_network_battle then
        -- Native rooms do not use BattleSync's runtime tick. Poll the LAN
        -- socket before advancing the legacy object pool so remote movement
        -- is available on this frame.
        self.transport:update()
        transport_polled_for_native = true
    end
    local battle_inputs = inputs
    local native_received_snapshot = nil
    if native_network_battle then
        for remote_id, remote_input in pairs(self.transport:consume_inputs()) do
            self.native_remote_inputs[tonumber(remote_id) or remote_id] = remote_input
        end
        for remote_id, remote_input in pairs(self.native_remote_inputs) do
            local frame_input = {}
            for key, value in pairs(remote_input) do
                frame_input[key] = value
            end
            -- Edge-triggered actions must not repeat when the cached state is
            -- used for a frame without a fresh packet. Movement and shooting
            -- intentionally remain latched until the next packet arrives.
            local input_tick = remote_input.tick or 0
            if input_tick ~= (self.native_remote_last_tick[remote_id] or -1) then
                frame_input.bomb = remote_input.bomb == true
                frame_input.confirm = remote_input.confirm == true
                frame_input.cancel = remote_input.cancel == true
                frame_input.mouse_primary_pressed = remote_input.mouse_primary_pressed == true
                self.native_remote_last_tick[remote_id] = input_tick
            else
                frame_input.bomb = false
                frame_input.confirm = false
                frame_input.cancel = false
                frame_input.mouse_primary_pressed = false
            end
            battle_inputs[remote_id] = frame_input
        end
        if not self.transport:is_host() and self.stage_adapter.native_bridge.apply_snapshot then
            native_received_snapshot = self.transport:consume_snapshot()
            self.stage_adapter.native_bridge.apply_snapshot(native_received_snapshot)
        end
        if self.stage_adapter.native_bridge.apply_peer_snapshot then
            local peer_snapshot = self.transport:consume_peer_snapshot()
            if peer_snapshot then
                self.native_peer_silence_tick = 0
                self.native_peer_seen = true
                self.stage_adapter.native_bridge.apply_peer_snapshot(peer_snapshot)
            elseif self.native_peer_seen then
                self.native_peer_silence_tick = (self.native_peer_silence_tick or 0) + 1
                -- Once the first snapshot has arrived, tolerate a temporary
                -- socket stall. Never fail the room before that first packet:
                -- the two native stages can legitimately start a few frames
                -- apart while the scheduled timestamp is being delivered.
                if self.native_peer_silence_tick > 600
                        and self.session.player_count > 1
                        and self.session.run_state == Constants.run_states.ENCOUNTER then
                    self.suppress_peer_leave = true
                    self:return_to_menu()
                    self.suppress_peer_leave = false
                    return false
                end
            end
        end
    end
    if network_battle and not native_network_battle then
        battle_inputs = self.battle_sync:before_update(inputs, self.stage_adapter)
    end
    if self.session.run_state == Constants.run_states.MENU then
        if self.network_menu:is_open() then
            self:_update_network_menu(player_input)
        else
            if player_input.move_y ~= 0 then
                self.menu_cursor = ((self.menu_cursor - 1 - player_input.move_y) % 7) + 1
            end
            if self.input.get_mouse_position and self.renderer and self.renderer.menu_hit_test then
                local mouse_x, mouse_y = self.input:get_mouse_position()
                local hit = self.renderer:menu_hit_test(mouse_x, mouse_y)
                if hit then
                    self.menu_cursor = hit
                    if player_input.mouse_primary_pressed and self:_activate_main_menu(hit) then return true end
                end
            end
            if player_input.confirm then
                if self:_activate_main_menu(self.menu_cursor) then return true end
            elseif player_input.cancel then
                return true
            end
        end
    elseif self.session.run_state == Constants.run_states.MAP then
        if player_input.tab then
            self:_open_preparation()
        elseif player_input.move_x ~= 0 then
            self.map_scene:move_cursor(player_input.move_x)
        elseif player_input.move_y ~= 0 then
            self.map_scene:move_cursor(player_input.move_y)
        end
        if player_input.confirm then
            local first_node = self.map_scene:get_selectable_nodes()[1]
            self:_submit_map_choice(self.map_scene.cursor_node_id or (first_node and first_node.id))
        end
        if self.input.get_mouse_position then
            local x, y = self.input:get_mouse_position()
            local map_x, map_y = x / 1280, y / 720
            if self.renderer and self.renderer.screen_to_map then
                map_x, map_y = self.renderer:screen_to_map(x, y)
            end
            if map_x and map_y then
                self.map_scene:hover_with_mouse(map_x, map_y)
                if player_input.mouse_primary_pressed then
                    local node = self.map_scene:find_mouse_node(map_x, map_y)
                    self:_submit_map_choice(node and node.id)
                end
            else
                self.map_scene.cursor_node_id = nil
            end
        end
    elseif self.session.run_state == Constants.run_states.MAP_PREPARATION then
        local row_count = #self:_preparation_rows()
        if self.preparation_cursor < 1 or self.preparation_cursor > row_count then self.preparation_cursor = 1 end
        if player_input.move_y ~= 0 then
            self.preparation_cursor = ((self.preparation_cursor - 1 - player_input.move_y) % row_count) + 1
            self.preparation_discard_pending = nil
        end
        if self.input.get_mouse_position and self.renderer and self.renderer.preparation_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local hit = self.renderer:preparation_hit_test(mouse_x, mouse_y, row_count)
            if hit then
                self.preparation_cursor = hit
                if player_input.mouse_primary_pressed then self:_activate_preparation() end
            end
        end
        if player_input.confirm then
            self:_activate_preparation()
        elseif player_input.backspace then
            local row = self:_preparation_rows()[self.preparation_cursor]
            if row and row.kind == "inventory" then
                local player_id = self.session.local_player_id or 1
                local pending = self.preparation_discard_pending
                if not pending or pending.player_id ~= player_id
                        or pending.index ~= row.index
                        or pending.instance_id ~= row.instance.instance_id then
                    self.preparation_discard_pending = {
                        player_id = player_id,
                        index = row.index,
                        instance_id = row.instance.instance_id,
                    }
                    self.preparation_message = "Press Backspace again to confirm discard"
                    return
                end
                local result, err = self.session:dispatch({ type = Command.DISCARD_ITEM, player_id = self.session.local_player_id or 1, inventory_index = row.index })
                self.preparation_message = result and "仓库物品已丢弃" or (err or "丢弃失败")
            end
        elseif player_input.tab or player_input.cancel then
            self.session:leave_preparation()
            self.preparation_message = ""
            self.preparation_discard_pending = nil
        end
    elseif self.session.run_state == Constants.run_states.CARD_SELECT or self.session.run_state == Constants.run_states.NON_SPELL_SELECT or self.session.run_state == Constants.run_states.ENEMY_SELECT then
        if player_input.move_y ~= 0 then
            self.training_cursor = ((self.training_cursor - 1 - player_input.move_y) % #self.selection_catalog) + 1
        end
        if self.input.get_mouse_position and self.renderer and self.renderer.card_training_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local hit = self.renderer:card_training_hit_test(mouse_x, mouse_y, #self.selection_catalog, self.training_cursor)
            if hit then
                self.training_cursor = hit
                if player_input.mouse_primary_pressed then
                    self:start_selected_training(hit)
                end
            end
        end
        if player_input.confirm then
            self:start_selected_training(self.training_cursor)
        elseif player_input.cancel then
            self:return_to_menu()
        end
    elseif self.session.run_state == Constants.run_states.CARD_TRAINING_FAILED then
        if self.failure_cursor < 1 or self.failure_cursor > 2 then
            self.failure_cursor = 1
        end
        if player_input.move_y ~= 0 then
            self.failure_cursor = ((self.failure_cursor - 1 - player_input.move_y) % 2) + 1
        end
        if self.input.get_mouse_position and self.renderer and self.renderer.training_failed_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local hit = self.renderer:training_failed_hit_test(mouse_x, mouse_y)
            if hit then
                self.failure_cursor = hit
                if player_input.mouse_primary_pressed then
                    if hit == 1 then
                        self:restart_training()
                    else
                        self:return_to_menu()
                    end
                end
            end
        end
        if player_input.confirm then
            if self.failure_cursor == 1 then
                self:restart_training()
            else
                self:return_to_menu()
            end
        elseif player_input.cancel then
            self:return_to_menu()
        end
    elseif self.session.run_state == Constants.run_states.RUN_FAILED then
        local option_count = self:_failure_option_count()
        if self.failure_cursor < 1 or self.failure_cursor > option_count then
            self.failure_cursor = 1
        end
        if player_input.move_y ~= 0 then
            self.failure_cursor = ((self.failure_cursor - 1 - player_input.move_y) % option_count) + 1
        end
        if self.input.get_mouse_position and self.renderer and self.renderer.battle_failed_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local hit = self.renderer:battle_failed_hit_test(mouse_x, mouse_y, option_count)
            if hit then
                self.failure_cursor = hit
                if player_input.mouse_primary_pressed then
                    self:_choose_battle_failure(hit)
                end
            end
        end
        if player_input.confirm then
            self:_choose_battle_failure(self.failure_cursor)
        elseif player_input.cancel then
            self:_choose_battle_failure(option_count)
        end
    elseif self.session.run_state == Constants.run_states.CARD_TRAINING then
        self.stage_adapter:update(inputs)
    elseif self.session.run_state == Constants.run_states.ENCOUNTER then
        if not network_battle or battle_inputs then
            self.stage_adapter:update(battle_inputs or inputs)
            if native_network_battle and self.native_sync_audit and self.stage_adapter.native_bridge.snapshot then
                self.native_sync_tick = (self.native_sync_tick or 0) + 1
                local local_snapshot = self.stage_adapter.native_bridge.snapshot()
                self.native_sync_audit:observe(self.transport:is_host() and "host" or "client", local_snapshot, self.native_sync_tick)
                if native_received_snapshot then
                    local ok, reason = self.native_sync_audit:compare(local_snapshot, native_received_snapshot, self.native_sync_tick)
                    if not ok then
                        self.stage_adapter.network_status = "NativeSyncAudit: " .. tostring(reason)
                    end
                end
            end
            if native_network_battle and self.transport:is_host()
                    and self.stage_adapter.native_bridge.snapshot then
                self.transport:publish_snapshot(self.stage_adapter.native_bridge.snapshot())
            end
            if native_network_battle and self.stage_adapter.native_bridge.peer_snapshot
                    and self.transport.publish_peer_snapshot then
                self.native_peer_sync_tick = (self.native_peer_sync_tick or 0) + 1
                if self.native_peer_sync_tick >= 30 then
                    self.native_peer_sync_tick = 0
                    self.transport:publish_peer_snapshot(self.stage_adapter.native_bridge.peer_snapshot())
                end
            end
            if network_battle and not native_network_battle then
                self.battle_sync:after_update(self.stage_adapter)
                local status, mismatch_tick = self.battle_sync:get_status()
                self.stage_adapter.network_status = mismatch_tick and (status .. "  first mismatch tick = " .. tostring(mismatch_tick)) or status
            end
        end
    elseif self.session.run_state == Constants.run_states.PLACEHOLDER and (player_input.confirm or player_input.cancel) then
        self.transport:send({ type = "RETURN_TO_MAP" })
    end
    if not network_battle or native_network_battle then
        for _, input in pairs(inputs) do
            self.transport:submit_input(input)
        end
        if not transport_polled_for_native then
            self.transport:update()
        end
    end
    return false
end

function Bootstrap:render()
    if (self.session.run_state == Constants.run_states.ENCOUNTER or self.session.run_state == Constants.run_states.CARD_TRAINING) and self.stage_adapter.is_native_active and self.stage_adapter:is_native_active() then
        self.stage_adapter.native_bridge.render()
    elseif (self.session.run_state == Constants.run_states.ENCOUNTER or self.session.run_state == Constants.run_states.CARD_TRAINING) and self.stage_adapter:is_fallback_active() then
        self.stage_adapter:render()
    elseif self.renderer then
        local cursor = (self.session.run_state == Constants.run_states.CARD_TRAINING_FAILED or self.session.run_state == Constants.run_states.RUN_FAILED) and self.failure_cursor or self.training_cursor
        self.renderer:render(self.map_scene:get_view(), self.session, self.menu_cursor, cursor, self.stage_adapter.training_card_id, self.selection_catalog, self.selection_title, self.stage_adapter.training_display_name, self.network_menu, self.preparation_cursor, self.preparation_message)
    end
end

function Bootstrap:execute_debug(line)
    return self.debug_console:write(line)
end

function Bootstrap:shutdown()
    if self.input.end_text_input then self.input:end_text_input() end
    if self.transport and self.transport.disconnect then self.transport:disconnect() end
    self.initialized = false
end

return Bootstrap
