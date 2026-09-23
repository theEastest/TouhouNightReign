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
local MusicCatalog = require("tnr.audio.music_catalog")
local TrainingCatalog = require("tnr.training.card_training_catalog")
local NonSpellCatalog = require("tnr.training.nonspell_training_catalog")
local EnemyCatalog = require("tnr.training.enemy_training_catalog")
local BattleSync = require("tnr.multiplayer.battle_sync")
local LANTransport = require("tnr.multiplayer.lan_transport")
local NetworkMenu = require("tnr.multiplayer.network_menu")local NativeSyncAudit = require("tnr.multiplayer.native_sync_audit")
local ScrollState = require("tnr.ui.scroll_state")
local CharacterCatalog = require("tnr.character.character_catalog")

local Bootstrap = {}
Bootstrap.__index = Bootstrap

-- The host sends one shared wall-clock timestamp after the clock handshake.
-- This fallback is used only when no RTT sample is available.
local ENCOUNTER_START_LEAD_FALLBACK = 0.35
local ENCOUNTER_START_LEAD_MIN = 0.12
local ENCOUNTER_START_LEAD_MAX = 0.75

local NETWORK_TRACE_ENABLED = os.getenv("TNR_NETWORK_TRACE") == "1"

local function random_run_seed()
    local seconds = os.time()
    local micros = math.floor((os.clock() % 1) * 1000000)
    return math.max(1, (seconds * 1103515245 + micros) % 2147483647)
end

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
    local input_options = options.input or {}
    if options.lstg then
        local configured_input = {}
        for key, value in pairs(input_options) do configured_input[key] = value end
        configured_input.bomb_available = function(player_id)
            local player = session:get_player(player_id)
            return player ~= nil and tonumber(player.bomb) ~= nil and player.bomb > 0
        end
        input_options = configured_input
    end
    local input = options.lstg and LuaSTGInputProvider.new(options.lstg, input_options) or SinglePlayerInputProvider.new(input_options)
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
    session:on(Event.NODE_SELECTED, function(event)
        -- The host is the authority that advances the shared map. Broadcast
        -- the selected node so a client whose local current node briefly lags
        -- behind the host still follows the exact node instead of diverging.
        if instance and instance.transport and instance.transport.is_host
                and instance.transport:is_host()
                and instance.battle_sync and instance.battle_sync:is_networked()
                and event and event.node_id ~= nil then
            instance.transport:send({
                type = Command.SYNC_NODE,
                node_id = event.node_id,
                player_id = 1,
            })
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
        music_cursor = 1,
        catalog_cursor = 1,
        catalog_entries = nil,
        -- Character select (shown after choosing single player or a network
        -- mode, before the map is generated).
        character_cursor = 1,
        character_catalog = CharacterCatalog,
        -- Deferred action to run once the character is confirmed.
        pending_start = nil,
        failure_cursor = 1,
        preparation_cursor = 1,
        preparation_message = "",
        preparation_discard_pending = nil,
        preparation_edit_only = false,
        -- When the loadout screen is opened from the shop it is rendered as an
        -- overlay on top of the shop state; exiting returns to the shop.
        preparation_overlay = false,
        shop_cursor = 1,
        relic_cursor = 1,
        reward_cursor = 1,
        scroll_states = {},
        ui_mouse_x = nil,
        ui_mouse_y = nil,
        ui_mouse_moved = false,
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
        network_seed = options.network_seed or options.run_seed,
        -- When launched with TNR_NETWORK_MODE the client may start before
        -- the host has finished loading LuaSTG and opened its socket. Keep
        -- retrying that initial connection from the frame loop instead of
        -- leaving one endpoint stranded at the menu.
        network_initial_connect = options.network_role == "host"
            or options.network_role == "client",
        network_retry_at = 0,
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
    session:on(Event.RUN_CLEARED, function()
        -- RUN_CLEAR is terminal for the native room. Release the legacy
        -- object pool and invalidate transport snapshots before any later
        -- menu action can be processed.
        if instance.stage_adapter and instance.stage_adapter.reset_for_new_run then
            instance.stage_adapter:reset_for_new_run()
        end
        instance:_clear_native_room_transport_state()
    end)
    session:on(Event.MAP_ENTERED, function()
        -- Returning from rewards marks the previous native room as finished.
        -- Clear its transport generation before either player votes for the
        -- next node or publishes the newly edited loadout.
        if instance and instance:_network_start_barrier_enabled()
                and not session.current_encounter then
            instance:_clear_native_room_transport_state()
        end
    end)
    session:on("NATIVE_PEER_LEAVE", function()
        -- A remote menu/exit is a shared battle transition. Suppress the
        -- reciprocal command so the two endpoints do not bounce the event.
        if instance.session.run_state == Constants.run_states.ENCOUNTER
                or instance.session.run_state == Constants.run_states.RUN_FAILED
                or instance.session.run_state == Constants.run_states.CARD_TRAINING_FAILED
                or instance.session.run_state == Constants.run_states.REWARD then
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
    session:on(Event.PLAYER_READY_CHANGED, function()
        -- In LAN preparation, either endpoint may receive the second Ready
        -- command. Once both Ready flags and both immutable loadout commits
        -- are present, advance the selected node exactly once.
        if not instance or session.run_state ~= Constants.run_states.MAP_PREPARATION then return end
        if not session.preparation:is_party_ready(session.party.player_ids)
                or not session:all_loadouts_committed() then
            return
        end
        local result, err = session:commit_prepared_node()
        if not result and err then instance.preparation_message = err end
    end)
    return instance
end

function Bootstrap:init()
    if self.initialized then
        return
    end
    self.initialized = true
end

function Bootstrap:open_music_player()
    self.music_cursor = math.max(1, math.min(#MusicCatalog, self.music_cursor or 1))
    self.session.run_state = Constants.run_states.MUSIC_PLAYER
    local entry = MusicCatalog[self.music_cursor]
    if entry and self.audio then
        self.audio:play_original(entry.key)
    end
end

function Bootstrap:close_music_player()
    self.session.run_state = Constants.run_states.MENU
    self.menu_cursor = 1
    if self.audio then
        self.audio:play_music("menu")
    end
end

--- Build a stable, sorted list of every non-test equipment definition.
function Bootstrap:_equipment_catalog_entries()
    local registry = self.session and self.session.equipment_registry
    if not registry then return {} end
    local entries = {}
    for id, definition in pairs(registry:all()) do
        if definition.test_only ~= true then
            entries[#entries + 1] = { id = id, definition = definition }
        end
    end
    table.sort(entries, function(left, right)
        local left_type = tostring(left.definition.equipment_type or "")
        local right_type = tostring(right.definition.equipment_type or "")
        if left_type ~= right_type then return left_type < right_type end
        return tostring(left.id) < tostring(right.id)
    end)
    return entries
end

function Bootstrap:open_equipment_catalog()
    self.catalog_entries = self:_equipment_catalog_entries()
    self.catalog_cursor = 1
    self.scroll_states["catalog"] = nil
    self.session.run_state = Constants.run_states.EQUIPMENT_CATALOG
end

function Bootstrap:close_equipment_catalog()
    self.session.run_state = Constants.run_states.MENU
    self.menu_cursor = 1
    self.scroll_states["menu"] = nil
end

--- Open the character select screen. `start_action` is the deferred action to
--- run after the player confirms a character (for example `start_game` or
--- `start_network_game`).
function Bootstrap:open_character_select(start_action)
    self.character_cursor = 1
    self.pending_start = start_action
    self.session.run_state = Constants.run_states.CHARACTER_SELECT
end

function Bootstrap:close_character_select()
    self.pending_start = nil
    self.session.run_state = Constants.run_states.MENU
    self.menu_cursor = 1
end

--- Confirm the highlighted character and run the deferred start action.
function Bootstrap:confirm_character_select()
    local entry = self.character_catalog[self.character_cursor]
    if not entry then return nil, "no character selected" end
    local applied, err = self.session:set_local_character(entry.id)
    if not applied then return nil, err end
    local action = self.pending_start
    self.pending_start = nil
    if action then return action() end
    return true
end

function Bootstrap:_network_start_barrier_enabled()
    return self.battle_sync and self.battle_sync:is_networked()
        and self.transport and type(self.transport.clock_sync_step) == "function"
end

function Bootstrap:_retry_initial_network_connection()
    if not self.network_initial_connect or not self.transport
            or type(self.transport.connect) ~= "function" then
        return
    end
    if self.transport.connected or self.transport.listening then
        if self.transport.connected then self.network_initial_connect = false end
        return
    end
    local now = self.transport.now and self.transport:now() or os.clock()
    if now < (self.network_retry_at or 0) then return end
    local connected, error_message = self.transport:connect()
    if connected then
        self.network_initial_connect = false
        self.stage_adapter.network_status = self.transport:is_host()
            and "等待客机连接" or "已连接主机"
        self:_network_trace("network_connected", {})
    else
        self:_network_trace("network_connect_retry_failed", {
            error = error_message or self.transport.last_error or "unknown",
        })
        self.network_retry_at = now + 0.5
    end
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
    self.network_seed = self.session.run_seed
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
    if self.battle_sync and self.battle_sync:is_networked() then
        self.network_initial_connect = self.network_initial_connect ~= false
    end
    self.map_scene.cursor_node_id = nil
    self.preparation_edit_only = false
    self.menu_cursor = 1
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
        on_disconnect = function(reason)
            self:_on_network_disconnect(reason)
        end,
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
    local run_seed
    if config.mode == "host" then
        run_seed = tonumber(config.seed) or random_run_seed()
        self.network_seed = run_seed
    else
        -- The client uses a placeholder until the host sends SET_RUN_SEED.
        run_seed = self.network_seed or 1
    end
    self:close_network_menu()
    -- The run seed is fixed at connect time on the host so both peers agree.
    -- The actual room starts only after the character select screen confirms.
    if config.mode == "host" and self.transport.send then
        self.transport:send({ type = Command.SET_RUN_SEED, run_seed = run_seed, player_id = 1 })
    end
    if config.mode == "host" then
        self.stage_adapter.network_status = string.format("等待客户端连接  端口 %d", config.port)
    else
        self.stage_adapter.network_status = string.format("已连接 %s:%d", config.host, config.port)
    end
    self:open_character_select(function()
        self:start_game(run_seed)
    end)
    return true
end

function Bootstrap:_on_network_disconnect(reason)
    if self._handling_network_disconnect then return end
    self._handling_network_disconnect = true
    local message = "网络连接已断开"
    if reason and tostring(reason) ~= "" then
        message = message .. ": " .. tostring(reason)
    end
    self.stage_adapter.network_status = message
    self.suppress_peer_leave = true
    if self.stage_adapter and self.stage_adapter.reset_for_new_run then
        self.stage_adapter:reset_for_new_run()
    end
    self.session.current_encounter = nil
    self.session.room_generation = nil
    self.session.run_state = Constants.run_states.MENU
    if self.transport and self.transport.set_room_generation then
        self.transport:set_room_generation(nil)
    end
    self.native_remote_inputs = {}
    self.native_remote_last_tick = {}
    self.pending_encounter = nil
    self.pending_encounter_start_at = nil
    self.pending_encounter_start_host_at = nil
    self.suppress_peer_leave = false
    if self.network_menu then self.network_menu:set_error(message) end
    self._handling_network_disconnect = false
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

function Bootstrap:_open_preparation(edit_only)
    local result, err = self.session:enter_preparation()
    if not result then
        self.preparation_message = err or "无法打开地图整备"
        return nil, self.preparation_message
    end
    self.preparation_cursor = 1
    self.preparation_edit_only = edit_only == true
    self.preparation_message = ""
    self.preparation_discard_pending = nil
    return result
end

--- The local player's loadout, used to make the preparation slot grid match
--- the character's actual slot counts.
function Bootstrap:_local_loadout()
    local player = self.session:get_player(self.session.local_player_id or 1)
        or self.session:get_player(1)
    return player and player.loadout or nil
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
        if self.preparation_overlay then
            -- Opened from the shop: the action row just closes the overlay and
            -- returns to the shop instead of toggling the map Ready flag.
            self:close_preparation_overlay()
            return true
        end
        if self.preparation_edit_only then
            self.session:leave_preparation()
            self.preparation_edit_only = false
            self.preparation_message = "Saved"
            self.preparation_discard_pending = nil
            return true
        end
        local next_ready = not player.map_ready
        local networked = self.battle_sync and self.battle_sync:is_networked()
        local result, err
        if networked then
            -- Apply locally for immediate UI feedback, then send the same
            -- transition and descriptor so the peer can validate and mirror
            -- the exact player state before the start barrier.
            if next_ready then
                local commit, commit_err = self.session:build_loadout_commit(player_id)
                if not commit then
                    result, err = nil, commit_err
                else
                    -- Client transports do not dispatch their own packets.
                    -- Register the local descriptor first so the client can
                    -- pass the all-loadouts gate when the peer Ready arrives.
                    local local_commit, local_commit_err = self.session:commit_loadout(player_id, commit)
                    if not local_commit then
                        result, err = nil, local_commit_err
                    else
                        self.transport:send({
                            type = Command.SET_READY,
                            player_id = player_id,
                            commit = commit,
                        })
                        if self.session.run_state == Constants.run_states.MAP_PREPARATION then
                            result, err = self.session:set_player_ready(player_id, true)
                        else
                            -- Host transport dispatches its own command
                            -- synchronously; the ready listener may already
                            -- have advanced into the encounter.
                            result, err = true, nil
                        end
                    end
                end
            else
                self.transport:send({ type = Command.CANCEL_READY, player_id = player_id })
                result, err = self.session:set_player_ready(player_id, false)
            end
        else
            result, err = self.session:set_player_ready(player_id, next_ready)
        end
        if result and not networked and (self.session.player_count or 1) == 1 then
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

function Bootstrap:_update_preparation(player_input, overlay)
    local row_count = #self:_preparation_rows()
    if self.preparation_cursor < 1 or self.preparation_cursor > row_count then self.preparation_cursor = 1 end
    local preparation_visible = self.renderer and math.max(1, math.floor((self.renderer.height - 245) / 38)) or 12
    local previous_preparation_cursor = self.preparation_cursor
    self.preparation_cursor = self:_scroll_step("preparation", self.preparation_cursor, row_count, preparation_visible, player_input.move_y)
    if self.preparation_cursor ~= previous_preparation_cursor then
        self.preparation_discard_pending = nil
    end
    if self.input.get_mouse_position and self.renderer and self.renderer.preparation_hit_test then
        local mouse_x, mouse_y = self.input:get_mouse_position()
        local visible = math.max(1, math.floor((self.renderer.height - 245) / 38))
        local scrollbar_hit = self.renderer:scrollbar_index(mouse_x, mouse_y, 92, self.renderer.width * 0.65, 88, self.renderer.height - 188, row_count, visible)
        local hit = scrollbar_hit or self.renderer:preparation_hit_test(mouse_x, mouse_y, row_count, self.preparation_cursor, self:_local_loadout())
        if hit and (self.ui_mouse_moved or player_input.mouse_primary_pressed or player_input.mouse_primary_down) then
            if not scrollbar_hit or player_input.mouse_primary_down or player_input.mouse_primary_pressed then
                self.preparation_cursor = hit
            end
            if player_input.mouse_primary_pressed and not scrollbar_hit then self:_activate_preparation() end
        end
    end
    if player_input.confirm then
        self:_activate_preparation()
    elseif player_input.backspace then
        local row = self:_preparation_rows()[self.preparation_cursor]
        local player_id = self.session.local_player_id or 1
        -- Both inventory items and currently equipped items can be discarded.
        -- Discarding an equipped item first unequips it, then removes it, so
        -- the slot is freed and the item is gone for good.
        local discardable = row and (row.kind == "inventory" or row.kind == "equipped")
            and row.instance and row.instance ~= false
        if discardable then
            local pending = self.preparation_discard_pending
            if not pending or pending.player_id ~= player_id
                    or pending.group ~= row.group
                    or pending.index ~= row.index
                    or pending.instance_id ~= row.instance.instance_id then
                self.preparation_discard_pending = {
                    player_id = player_id,
                    group = row.group,
                    index = row.index,
                    instance_id = row.instance.instance_id,
                }
                self.preparation_message = "再次按 Backspace 确认丢弃"
                return
            end
            if row.kind == "equipped" then
                local unequipped, unequip_err = self.session:dispatch({
                    type = Command.UNEQUIP_ITEM,
                    player_id = player_id,
                    slot_type = row.group,
                    slot_index = row.index,
                })
                if not unequipped then
                    self.preparation_message = unequip_err or "卸下失败"
                    self.preparation_discard_pending = nil
                    return
                end
                local player = self.session:get_player(player_id)
                local items = player and player.loadout and player.loadout.inventory.items or {}
                local target_index
                for index, item in ipairs(items) do
                    if item and item.instance_id == row.instance.instance_id then target_index = index break end
                end
                if target_index then
                    local result, err = self.session:dispatch({ type = Command.DISCARD_ITEM, player_id = player_id, inventory_index = target_index })
                    self.preparation_message = result and "装备已丢弃" or (err or "丢弃失败")
                else
                    self.preparation_message = "装备已卸下"
                end
            else
                local result, err = self.session:dispatch({ type = Command.DISCARD_ITEM, player_id = player_id, inventory_index = row.index })
                self.preparation_message = result and "仓库物品已丢弃" or (err or "丢弃失败")
            end
            self.preparation_discard_pending = nil
        end
    elseif player_input.tab or player_input.cancel then
        if overlay then
            self:close_preparation_overlay()
        else
            self.session:leave_preparation()
            self.preparation_edit_only = false
            self.preparation_message = ""
            self.preparation_discard_pending = nil
        end
    end
end

function Bootstrap:open_preparation_overlay()
    self.preparation_cursor = 1
    self.preparation_edit_only = false
    self.preparation_message = ""
    self.preparation_discard_pending = nil
    self.preparation_overlay = true
end

function Bootstrap:close_preparation_overlay()
    self.preparation_overlay = false
    self.preparation_discard_pending = nil
    self.preparation_message = ""
end

function Bootstrap:_activate_main_menu(index)
    if index == 1 then
        -- Single player picks a character before the map is generated.
        self.session.player_count = 1
        self.session.local_player_id = 1
        self:open_character_select(function()
            self:start_game()
        end)
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
        self:open_music_player()
    elseif index == 8 then
        self:open_equipment_catalog()
    elseif index == 9 then
        return true
    end
    return false
end

function Bootstrap:_update_network_menu(player_input)
    local menu = self.network_menu
    local text = player_input.text or ""
    if self.input.consume_text then text = text .. self.input:consume_text() end
    if text ~= "" then menu:append_text(text) end
    local paste = player_input.paste or ""
    if paste ~= "" then menu:paste_text(paste) end
    if player_input.backspace then menu:backspace() end
    if player_input.tab then
        menu:move_cursor(1)
    else
        menu.cursor = self:_scroll_step("network", menu.cursor, menu:get_item_count(), menu:get_item_count(), player_input.move_y)
    end
    if self.input.get_mouse_position and self.renderer and self.renderer.network_menu_hit_test then
        local mouse_x, mouse_y = self.input:get_mouse_position()
        local hit = self.renderer:network_menu_hit_test(mouse_x, mouse_y, menu:get_item_count())
        if hit and (self.ui_mouse_moved or player_input.mouse_primary_pressed or player_input.mouse_primary_down) then
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

function Bootstrap:_scroll_step(key, cursor, count, visible, direction)
    local state = self.scroll_states[key]
    if not state then
        state = ScrollState.new(count, visible, cursor)
        self.scroll_states[key] = state
    end
    state:set_count(count, visible)
    state:set_cursor(cursor)
    return state:update(-(direction or 0))
end

function Bootstrap:_scroll_drag(key, cursor, count, visible, x, y, left, right, bottom, top)
    local state = self.scroll_states[key]
    if not state then
        state = ScrollState.new(count, visible, cursor)
        self.scroll_states[key] = state
    end
    state:set_count(count, visible)
    state:set_cursor(cursor)
    local index = self.renderer and self.renderer:scrollbar_index(x, y, left, right, bottom, top, count, visible)
    if index then return state:set_cursor(index) end
    return nil
end

function Bootstrap:_update_ui_mouse()
    if not self.input.get_mouse_position then
        self.ui_mouse_moved = false
        return
    end
    local x, y = self.input:get_mouse_position()
    self.ui_mouse_moved = x ~= self.ui_mouse_x or y ~= self.ui_mouse_y
    self.ui_mouse_x, self.ui_mouse_y = x, y
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
    if self.audio and not self.stage_adapter:is_native_active() then
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
    self.network_initial_connect = false
    local was_battle = self.session.run_state == Constants.run_states.ENCOUNTER
        or self.session.run_state == Constants.run_states.RUN_FAILED
        or self.session.run_state == Constants.run_states.CARD_TRAINING_FAILED
        or self.session.run_state == Constants.run_states.REWARD
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
    if self.stage_adapter and self.stage_adapter.reset_for_new_run then
        self.stage_adapter:reset_for_new_run()
    end
    self.session.current_encounter = nil
    self.session.room_generation = nil
    self.session.preparation:reset(self.session.party.player_ids)
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
    if self.transport and self.transport.set_room_generation then
        self.transport:set_room_generation(nil)
    end
    if self.audio then
        -- Stop any battle/stage track before switching to the menu theme so
        -- returning from a room can never leave the stage BGM playing.
        self.audio:stop_all_music()
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
    self:_update_ui_mouse()
    self.ui_mouse_down = player_input.mouse_primary_down == true
    self:_retry_initial_network_connection()
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
    if self.session.run_state == Constants.run_states.MUSIC_PLAYER then
        self.music_cursor = self:_scroll_step("music", self.music_cursor, #MusicCatalog, 10, player_input.move_y)
        if player_input.confirm then
            local entry = MusicCatalog[self.music_cursor]
            if entry and self.audio then self.audio:play_original(entry.key) end
        elseif player_input.cancel then
            self:close_music_player()
        end
    elseif self.session.run_state == Constants.run_states.CHARACTER_SELECT then
        local catalog = self.character_catalog or CharacterCatalog
        local count = math.max(1, #catalog)
        if self.character_cursor < 1 or self.character_cursor > count then self.character_cursor = 1 end
        local direction = player_input.move_x ~= 0 and player_input.move_x or player_input.move_y
        self.character_cursor = self:_scroll_step("character", self.character_cursor, count, count, direction)
        if self.input.get_mouse_position and self.renderer and self.renderer.character_select_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local hit = self.renderer:character_select_hit_test(mouse_x, mouse_y, count)
            if hit and (self.ui_mouse_moved or player_input.mouse_primary_pressed) then
                self.character_cursor = hit
                if player_input.mouse_primary_pressed then self:confirm_character_select() end
            end
        end
        if player_input.confirm then
            self:confirm_character_select()
        elseif player_input.cancel then
            -- Abort: disconnect a pending network session and return to menu.
            if self.transport and self.transport.disconnect then self.transport:disconnect() end
            self:close_character_select()
        end
    elseif self.session.run_state == Constants.run_states.EQUIPMENT_CATALOG then
        local entries = self.catalog_entries or self:_equipment_catalog_entries()
        self.catalog_entries = entries
        self.catalog_cursor = self:_scroll_step("catalog", self.catalog_cursor, #entries, 10, player_input.move_y)
        if self.input.get_mouse_position and self.renderer and self.renderer.equipment_catalog_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local hit = self.renderer:equipment_catalog_hit_test(mouse_x, mouse_y, #entries, self.catalog_cursor)
            if hit and (self.ui_mouse_moved or player_input.mouse_primary_pressed) then
                self.catalog_cursor = hit
            end
        end
        if player_input.cancel or player_input.confirm then
            self:close_equipment_catalog()
        end
    elseif self.session.run_state == Constants.run_states.MENU then
        if self.network_menu:is_open() then
            self:_update_network_menu(player_input)
        else
            self.menu_cursor = self:_scroll_step("menu", self.menu_cursor, 9, 9, player_input.move_y)
            if self.input.get_mouse_position and self.renderer and self.renderer.menu_hit_test then
                local mouse_x, mouse_y = self.input:get_mouse_position()
                local hit = self.renderer:menu_hit_test(mouse_x, mouse_y)
                if hit and (self.ui_mouse_moved or player_input.mouse_primary_pressed or player_input.mouse_primary_down) then
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
        local equipment_locked = self.session.preparation and self.session.preparation.selected_node_id ~= nil
        local equipment_button_hit = false
        if self.input.get_mouse_position and self.renderer and self.renderer.map_equipment_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            equipment_button_hit = self.renderer:map_equipment_hit_test(mouse_x, mouse_y) == true
            if equipment_button_hit and player_input.mouse_primary_pressed and not equipment_locked then
                self:_open_preparation(true)
            end
        end
        if player_input.tab and not equipment_locked then
            self:_open_preparation(false)
        elseif player_input.move_x ~= 0 then
            self.map_scene:move_cursor(player_input.move_x)
        elseif player_input.move_y ~= 0 then
            self.map_scene:move_cursor(player_input.move_y)
        end
        if player_input.confirm and not equipment_button_hit then
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
                if self.ui_mouse_moved then self.map_scene:hover_with_mouse(map_x, map_y) end
                if player_input.mouse_primary_pressed then
                    local node = self.map_scene:find_mouse_node(map_x, map_y)
                    self:_submit_map_choice(node and node.id)
                end
            else
                self.map_scene.cursor_node_id = nil
            end
        end
    elseif self.preparation_overlay or self.session.run_state == Constants.run_states.MAP_PREPARATION then
        self:_update_preparation(player_input, self.preparation_overlay)
    elseif self.session.run_state == Constants.run_states.SHOP then
        local shop_count = (self.session.shop_service and #self.session.shop_service:get_offers() or 0) + 1
        if self.shop_cursor < 1 or self.shop_cursor > shop_count then self.shop_cursor = 1 end
        local shop_direction = player_input.move_x
        if shop_direction == 0 then shop_direction = player_input.move_y end
        self.shop_cursor = self:_scroll_step("shop", self.shop_cursor, shop_count, shop_count, shop_direction)
        -- The loadout screen can be opened from the shop at any time (Tab, the
        -- top-right button or the mouse click) so a full inventory can be
        -- managed without leaving the shop.
        local equipment_button_hit = false
        if self.input.get_mouse_position and self.renderer and self.renderer.shop_equipment_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            equipment_button_hit = self.renderer:shop_equipment_hit_test(mouse_x, mouse_y) == true
            if equipment_button_hit and player_input.mouse_primary_pressed then
                self:open_preparation_overlay()
                return
            end
        end
        if player_input.tab and not equipment_button_hit then
            self:open_preparation_overlay()
            return
        end
        if self.input.get_mouse_position and self.renderer and self.renderer.shop_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local hit = self.renderer:shop_hit_test(mouse_x, mouse_y)
            if hit and (self.ui_mouse_moved or player_input.mouse_primary_pressed or player_input.mouse_primary_down) then
                self.shop_cursor = hit
                if player_input.mouse_primary_pressed then
                    if hit <= shop_count - 1 then
                        self.transport:send({ type = Command.SHOP_PURCHASE, player_id = self.session.local_player_id, slot = hit })
                    else
                        self.transport:send({ type = Command.SHOP_READY, player_id = self.session.local_player_id })
                    end
                end
            end
        end
        if player_input.confirm then
            if self.shop_cursor <= shop_count - 1 then
                self.transport:send({ type = Command.SHOP_PURCHASE, player_id = self.session.local_player_id, slot = self.shop_cursor })
            else
                self.transport:send({ type = Command.SHOP_READY, player_id = self.session.local_player_id })
            end
        elseif player_input.cancel then
            self.transport:send({ type = Command.SHOP_READY, player_id = self.session.local_player_id })
        end
    elseif self.session.run_state == Constants.run_states.FLOOR_CLEAR then
        -- The floor transition is a short confirmation screen. Confirming
        -- advances the shared run; in a LAN game the host owns the run seed so
        -- the command is broadcast so both peers rebuild the same next floor.
        if player_input.confirm then
            if self.battle_sync and self.battle_sync:is_networked() then
                if self.transport:is_host() then
                    self.transport:send({ type = Command.ADVANCE_FLOOR, player_id = 1 })
                end
            else
                self.session:advance_floor()
            end
        end
    elseif self.session.run_state == Constants.run_states.RELIC_SELECT then
        local choices = self.session.relic_choices[self.session.local_player_id or 1] or {}
        local count = math.max(1, #choices)
        if self.relic_cursor < 1 or self.relic_cursor > count then self.relic_cursor = 1 end
        self.relic_cursor = self:_scroll_step("relic", self.relic_cursor, count, 5, player_input.move_y)
        if self.input.get_mouse_position and self.renderer and self.renderer.relic_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local hit = self.renderer:relic_hit_test(self.session, mouse_x, mouse_y)
            if hit and (self.ui_mouse_moved or player_input.mouse_primary_pressed or player_input.mouse_primary_down) then
                self.relic_cursor = hit
                if player_input.mouse_primary_pressed and choices[hit] then
                    self.transport:send({ type = Command.RELIC_CHOICE, player_id = self.session.local_player_id, relic_id = choices[hit] })
                end
            end
        end
        if player_input.confirm and choices[self.relic_cursor] then
            self.transport:send({
                type = Command.RELIC_CHOICE,
                player_id = self.session.local_player_id,
                relic_id = choices[self.relic_cursor],
            })
        end
    elseif self.session.run_state == Constants.run_states.REWARD then
        local choices = self.session.reward_choices or {}
        local count = math.max(1, #choices)
        if self.reward_cursor < 1 or self.reward_cursor > count then self.reward_cursor = 1 end
        local direction = player_input.move_x ~= 0 and player_input.move_x or player_input.move_y
        self.reward_cursor = self:_scroll_step("reward", self.reward_cursor, count, count, direction)
        -- Selecting an already-claimed choice again cancels that selection, so
        -- a mis-click before confirming the whole reward is recoverable.
        local function is_claimed(index)
            local claims = self.session.reward_claims and self.session.reward_claims[self.session.local_player_id or 1] or {}
            for _, claim in ipairs(claims) do
                if claim.choice_index == index then return true end
            end
            return false
        end
        local function toggle_claim(index)
            local command_type = is_claimed(index) and Command.UNCLAIM_REWARD or Command.CLAIM_REWARD
            self.transport:send({ type = command_type, player_id = self.session.local_player_id, choice_index = index })
        end
        if self.input.get_mouse_position and self.renderer and self.renderer.reward_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local hit = self.renderer:reward_hit_test(mouse_x, mouse_y, count)
            if hit and (self.ui_mouse_moved or player_input.mouse_primary_pressed or player_input.mouse_primary_down) then
                self.reward_cursor = hit
                if player_input.mouse_primary_pressed then
                    toggle_claim(hit)
                end
            end
        end
        if player_input.confirm then
            toggle_claim(self.reward_cursor)
        end
    elseif self.session.run_state == Constants.run_states.RUN_CLEAR then
        if player_input.confirm or player_input.cancel then self:return_to_menu() end
    elseif self.session.run_state == Constants.run_states.CARD_SELECT or self.session.run_state == Constants.run_states.NON_SPELL_SELECT or self.session.run_state == Constants.run_states.ENEMY_SELECT then
        self.training_cursor = self:_scroll_step("training", self.training_cursor, #self.selection_catalog, 8, player_input.move_y)
        if self.input.get_mouse_position and self.renderer and self.renderer.card_training_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local scrollbar_hit = self.renderer:scrollbar_index(mouse_x, mouse_y, 100, self.renderer.width - 100, 105, 610, #self.selection_catalog, 8)
            local hit = scrollbar_hit or self.renderer:card_training_hit_test(mouse_x, mouse_y, #self.selection_catalog, self.training_cursor)
            if hit and (self.ui_mouse_moved or player_input.mouse_primary_pressed or player_input.mouse_primary_down) then
                if not scrollbar_hit or player_input.mouse_primary_down or player_input.mouse_primary_pressed then
                    self.training_cursor = hit
                end
                if player_input.mouse_primary_pressed and not scrollbar_hit then
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
        self.failure_cursor = self:_scroll_step("training_failed", self.failure_cursor, 2, 2, player_input.move_y)
        if self.input.get_mouse_position and self.renderer and self.renderer.training_failed_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local hit = self.renderer:training_failed_hit_test(mouse_x, mouse_y)
            if hit and (self.ui_mouse_moved or player_input.mouse_primary_pressed or player_input.mouse_primary_down) then
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
        self.failure_cursor = self:_scroll_step("battle_failed", self.failure_cursor, option_count, option_count, player_input.move_y)
        if self.input.get_mouse_position and self.renderer and self.renderer.battle_failed_hit_test then
            local mouse_x, mouse_y = self.input:get_mouse_position()
            local hit = self.renderer:battle_failed_hit_test(mouse_x, mouse_y, option_count)
            if hit and (self.ui_mouse_moved or player_input.mouse_primary_pressed or player_input.mouse_primary_down) then
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
        self.renderer:render(self.map_scene:get_view(), self.session, self.menu_cursor, cursor, self.stage_adapter.training_card_id, self.selection_catalog, self.selection_title, self.stage_adapter.training_display_name, self.network_menu, self.preparation_cursor, self.preparation_message, self.shop_cursor, self.relic_cursor, self.reward_cursor, self.ui_mouse_x, self.ui_mouse_y, self.ui_mouse_down, self.preparation_edit_only, self.music_cursor, MusicCatalog, self.catalog_cursor, self.catalog_entries, self.preparation_overlay, self.character_cursor, self.character_catalog)
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
