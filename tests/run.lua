local root = (...)
package.path = "game/scripts/?.lua;game/scripts/?/init.lua;tests/?.lua;" .. package.path

local Constants = require("tnr.core.constants")
local Command = require("tnr.core.command")
local GameSession = require("tnr.core.game_session")
local MapGenerator = require("tnr.map.map_generator")
local RewardService = require("tnr.reward.reward_service")
local LocalTransport = require("tnr.multiplayer.local_transport")
local BattleManager = require("tnr.battle.battle_manager")
local StageAdapter = require("tnr.battle.stage_adapter")
local StageDefinitions = require("tnr.stages.definitions")
local ContentCatalog = require("tnr.stages.content_catalog")
local PlayerProfiles = require("tnr.player.player_profile")
local MapScene = require("tnr.map.map_scene")
local DebugCommand = require("tnr.debug.debug_command")
local DebugConsole = require("tnr.debug.console")
local Bootstrap = require("tnr.bootstrap")
local NonSpellCatalog = require("tnr.training.nonspell_training_catalog")
local EnemyCatalog = require("tnr.training.enemy_training_catalog")
local BattleTick = require("tnr.core.battle_tick")
local FakeTransport = require("tnr.multiplayer.fake_transport")
local LANTransport = require("tnr.multiplayer.lan_transport")
local BattleSync = require("tnr.multiplayer.battle_sync")
local NetworkMenu = require("tnr.multiplayer.network_menu")
local LuaSTGInputProvider = require("tnr.input.luastg_input")
local ScrollState = require("tnr.ui.scroll_state")
local Aggro = require("tnr.multiplayer.aggro")
local CharacterLoadoutSpec = require("character_loadout_spec")
local LoadoutOperationsSpec = require("loadout_operations_spec")
local StateAuthoritySpec = require("state_authority_spec")
local NativeSyncProtocolSpec = require("native_sync_protocol_spec")
local WeightRuntimeSpec = require("weight_runtime_spec")
local WeaponRuntimeSpec = require("weapon_runtime_spec")
local SupportRuntimeSpec = require("support_runtime_spec")
local ModifierRuntimeSpec = require("modifier_runtime_spec")
local LoadoutCommitSpec = require("loadout_commit_spec")
local Gate0ValidationSpec = require("gate0_validation_spec")
local RewardRuntimeSpec = require("reward_runtime_spec")
local CapacityProgressionSpec = require("capacity_progression_spec")
local ShopSpec = require("shop_spec")
local RelicRuntimeSpec = require("relic_runtime_spec")
local RunLifecycleSpec = require("run_lifecycle_spec")
local CombatRuntimeIntegrationSpec = require("combat_runtime_integration_spec")
local GuideEquipmentSpec = require("guide_equipment_spec")
local AudioManagerSpec = require("audio_manager_spec")

local function assert_equal(left, right, message)
    assert(left == right, string.format("%s: expected %s, got %s", message, tostring(right), tostring(left)))
end

local function assert_true(value, message)
    assert(value == true, message)
end

CharacterLoadoutSpec(assert_equal, assert_true)
LoadoutOperationsSpec(assert_equal, assert_true)
StateAuthoritySpec(assert_equal, assert_true)
NativeSyncProtocolSpec(assert_equal, assert_true)
WeightRuntimeSpec(assert_equal, assert_true)
WeaponRuntimeSpec(assert_equal, assert_true)
SupportRuntimeSpec(assert_equal, assert_true)
ModifierRuntimeSpec(assert_equal, assert_true)
LoadoutCommitSpec(assert_equal, assert_true)
Gate0ValidationSpec(assert_equal, assert_true)
RewardRuntimeSpec(assert_equal, assert_true)
CapacityProgressionSpec(assert_equal, assert_true)
ShopSpec(assert_equal, assert_true)
RelicRuntimeSpec(assert_equal, assert_true)
RunLifecycleSpec(assert_equal, assert_true)
CombatRuntimeIntegrationSpec(assert_equal, assert_true)
GuideEquipmentSpec(assert_equal, assert_true)
AudioManagerSpec(assert_equal, assert_true)

local scroll = ScrollState.new(20, 8, 1)
assert_equal(scroll:update(1), 2, "scroll moves immediately on first key frame")
for _ = 1, 15 do
    local value = scroll:update(1)
    if value == 3 then break end
    assert_equal(value, 2, "scroll initial hold delay")
end
assert_equal(scroll:update(1), 3, "scroll repeats after initial hold delay")
scroll:update(0)
assert_equal(scroll:update(1), 4, "scroll release resets repeat timing")
assert_equal(scroll:first_visible(), 1, "scroll keeps early selection at top")
scroll:set_cursor(20)
assert_equal(scroll:first_visible(), 13, "scroll window follows last selection")
assert_equal(ScrollState.new(20, 8, 1):set_from_track(1), 20, "scrollbar bottom maps to last item")
assert_equal(ScrollState.new(20, 8, 1):set_from_track(0), 1, "scrollbar top maps to first item")

local function serialize_map(map)
    local parts = {}
    for id = 1, #map.nodes do
        local node = map.nodes[id]
        parts[#parts + 1] = string.format("%d:%s:%.5f:%.5f:%s", id, node.type, node.x, node.y, table.concat(node.links, ","))
    end
    return table.concat(parts, "|")
end

local keyboard_state = {}
local fake_keyboard = { GetKeyState = function(code) return keyboard_state[code] == true end }
for index, key in ipairs({ "Left", "Right", "Up", "Down", "Z", "LeftShift", "X", "Enter", "Escape", "Space", "Tab", "Back" }) do
    fake_keyboard[key] = index
end
local fake_mouse = { Primary = 1, GetKeyState = function() return false end }
local default_input_provider = LuaSTGInputProvider.new({ Input = { Keyboard = fake_keyboard, Mouse = fake_mouse } })
keyboard_state[fake_keyboard.Left] = true
keyboard_state[fake_keyboard.Z] = true
keyboard_state[fake_keyboard.LeftShift] = true
local matching_default_inputs = default_input_provider:poll_all({ 1, 2 })
assert_equal(matching_default_inputs[1].move_x, matching_default_inputs[2].move_x, "P1 and P2 default movement bindings must match")
assert_equal(matching_default_inputs[1].shoot, matching_default_inputs[2].shoot, "P1 and P2 default shoot bindings must match")
assert_equal(matching_default_inputs[1].focus, matching_default_inputs[2].focus, "P1 and P2 default focus bindings must match")

local mouse_down = true
local p2_mouse_provider = LuaSTGInputProvider.new({
    Input = {
        Keyboard = fake_keyboard,
        Mouse = {
            Primary = 1,
            GetKeyState = function() return mouse_down end,
        },
    },
})
local p2_mouse_input = p2_mouse_provider:poll(2)
assert_true(p2_mouse_input.mouse_primary_pressed, "LAN P2 must receive the local mouse click")
assert_true(p2_mouse_input.mouse_primary_down, "mouse hold state must be exposed for scrollbar dragging")
assert_equal(p2_mouse_provider:poll(2).mouse_primary_pressed, false, "holding the mouse must not repeat the click edge")
mouse_down = false
p2_mouse_provider:poll(2)
mouse_down = true
assert_true(p2_mouse_provider:poll(2).mouse_primary_pressed, "P2 mouse click should trigger again after release")

-- A Bomb key must be inert while the local resource is empty.  Holding the
-- key through a refill must not leak a charged/release event; the player has
-- to release and press again before Bomb input becomes active.
keyboard_state[fake_keyboard.X] = true
local bombs_available = false
local no_bomb_provider = LuaSTGInputProvider.new({
    Input = { Keyboard = fake_keyboard, Mouse = fake_mouse },
}, {
    bomb_available = function() return bombs_available end,
})
for _ = 1, 200 do
    local input = no_bomb_provider:poll(1)
    assert_equal(input.bomb_down, false, "empty Bomb inventory must suppress held Bomb input")
    assert_equal(input.bomb, false, "empty Bomb inventory must not emit a Bomb event")
    assert_equal(input.bomb_charged, false, "empty Bomb inventory must not charge")
end
bombs_available = true
local refilled_while_held = no_bomb_provider:poll(1)
assert_equal(refilled_while_held.bomb_down, false,
    "refilling a Bomb while the key is held must keep input blocked")
keyboard_state[fake_keyboard.X] = false
no_bomb_provider:poll(1)
keyboard_state[fake_keyboard.X] = true
local fresh_bomb_press = no_bomb_provider:poll(1)
assert_equal(fresh_bomb_press.bomb_down, true, "Bomb input resumes after a release and fresh press")
keyboard_state[fake_keyboard.X] = false
no_bomb_provider:poll(1)

local map_a = MapGenerator.generate(12345)
local map_b = MapGenerator.generate(12345)
local map_c = MapGenerator.generate(12346)
assert_equal(serialize_map(map_a), serialize_map(map_b), "same seed must reproduce the map")
assert_true(serialize_map(map_a) ~= serialize_map(map_c), "different seeds should produce a different map")
assert_true(map_a:find_path(map_a.start_node_id, map_a.boss_node_id) ~= nil, "boss must be reachable")
assert_true(#map_a:find_path(map_a.start_node_id, map_a.boss_node_id) - 1 >= 6, "boss path must have a minimum distance")
for id, node in pairs(map_a.nodes) do
    for _, linked_id in ipairs(node.links) do
        if linked_id > id then
            assert_true(node.x < map_a.nodes[linked_id].x, "route edges must travel from left to right")
        end
    end
end
local counts = map_a:count_types()
assert_equal(counts[Constants.node_types.START], 1, "map must have one start")
assert_equal(counts[Constants.node_types.BOSS], 1, "map must have one boss")
assert_true((counts[Constants.node_types.SHOP] or 0) > 0, "map must contain a shop")
assert_true((counts[Constants.node_types.EVENT] or 0) > 0, "map must contain an event")
assert_equal(StageDefinitions.ordinary_stage_01.kind, "ordinary", "ordinary stage spec kind")
assert_equal(#StageDefinitions.ordinary_stage_01.waves, 3, "ordinary stage wave count")
assert_equal(#StageDefinitions.ordinary_stage_01.mid_boss.cards, 1, "ordinary stage card count")
for index = 1, 6 do
    local stage = StageDefinitions[string.format("ordinary_stage_%02d", index)]
    assert_true(stage ~= nil, "ordinary stage variant must exist")
    assert_true(stage.waves[1].enemy ~= nil, "ordinary variant must select a small enemy")
    assert_true(stage.mid_boss.cards[1] ~= nil, "ordinary variant must select a nonspell")
end
assert_equal(#StageDefinitions.boss_stage_01.boss.cards, 4, "boss stage card count")
assert_true(ContentCatalog.cards.four_direction_formation.is_spell, "final boss card should be a spell")
assert_equal(ContentCatalog.cards.mushroom_growth.legacy_boss, "Marisa:Normal", "mushroom spell legacy boss")
assert_equal(ContentCatalog.cards.mushroom_growth.legacy_card_slot, 9, "mushroom spell must use the combat card slot")
assert_true(ContentCatalog.cards.mushroom_growth.legacy_expected_combat, "mushroom spell must require a combat card")
local enemy_wave_count = 0
local LegacyEnemyWaves = require("tnr.stages.legacy_enemy_waves")
for _, stage in ipairs(LegacyEnemyWaves) do
    assert_true(#(stage.waves or {}) <= 2, stage.source_stage .. " must expose at most two grouped waves")
end
for wave_id, wave in pairs(ContentCatalog.enemy_waves or {}) do
    enemy_wave_count = enemy_wave_count + 1
    assert_true(wave.legacy_exact == true, wave_id .. " must come from the reference stage")
    assert_true(#(wave.members or {}) > 0, wave_id .. " must retain its original spawn members")
    assert_true(#(wave.members or {}) > 0 and #(wave.members or {}) <= 200,
        wave_id .. " must keep a bounded stage wave")
    assert_true(wave.duration_frames and wave.duration_frames > 0, wave_id .. " must retain duration")
    assert_true(wave.duration_seconds and wave.duration_seconds > 10,
        wave_id .. " must not expose a ten-second-or-shorter practice wave")
    local previous_spawn_frame = -1
    for _, member in ipairs(wave.members or {}) do
        assert_true(type(member.spawn_frame) == "number" and member.spawn_frame >= 0,
            wave_id .. " members must retain original spawn timing")
        assert_true(member.spawn_frame >= previous_spawn_frame,
            wave_id .. " members must retain source order in the grouped timeline")
        previous_spawn_frame = member.spawn_frame
    end
    assert_true(wave.difficulty >= 1 and wave.difficulty <= 6, wave_id .. " difficulty must be 1-6")
    if wave.legacy_stage:match("@Normal$") then
        assert_true(wave.difficulty <= 3, wave_id .. " Normal wave must be difficulty 1-3")
    elseif wave.legacy_stage:match("@Lunatic$") then
        assert_true(wave.difficulty >= 4, wave_id .. " Lunatic wave must be difficulty 4-6")
    end
end
assert_true(enemy_wave_count >= 40, "reference enemy wave catalog should contain the grouped stage pool")
for _, id in ipairs({
    "reimu_nonspell", "spirit_seal", "yin_yang_jewel",
    "four_direction_formation", "marisa_nonspell", "anti_aircraft_fire",
    "mushroom_growth",
}) do
    assert_true(ContentCatalog.cards[id].legacy_expected_combat,
        id .. " must be marked as a combat card")
end
assert_true(ContentCatalog.cards.spirit_seal.pattern ~= ContentCatalog.cards.yin_yang_jewel.pattern, "boss cards should use different patterns")
assert_true(ContentCatalog.cards.yin_yang_jewel.pattern ~= ContentCatalog.cards.four_direction_formation.pattern, "final cards should use different patterns")
assert_equal(PlayerProfiles.reimu.normal_speed, 4.5, "Reimu normal speed")
assert_equal(PlayerProfiles.reimu.focused_speed, 2.25, "Reimu focused speed")
assert_equal(PlayerProfiles.reimu.bomb.duration, 90, "Reimu bomb duration")
assert_equal(PlayerProfiles.reimu.bomb.max_charge_frames, 180, "Reimu Bomb charge cap")
assert_equal(PlayerProfiles.reimu.bomb.charged_duration, 120, "Reimu charged Bomb duration")
assert_equal(PlayerProfiles.reimu.bomb.charged_invulnerability, 480, "Reimu charged Bomb invulnerability")

local aggro = Aggro.new(300)
assert_true(aggro:record(1, 25), "aggro records P1 damage")
assert_true(aggro:record(2, 10), "aggro records P2 damage")
assert_true(aggro:advance(299) == nil, "aggro does not close early")
local aggro_report = aggro:advance(1)
assert_equal(aggro_report.window_id, 1, "aggro closes at five seconds")
assert_equal(aggro_report.damage[1], 25, "aggro report keeps P1 total")
assert_equal(Aggro.compare(aggro_report, { window_id = 1, damage = { [2] = 20 } }, 2), 1,
    "host chooses the higher-damage focus")
assert_equal(Aggro.compare(aggro_report, { window_id = 1, damage = { [2] = 25 } }, 1), 1,
    "aggro ties retain the previous focus")

local tick_a = BattleTick.new(123)
local tick_b = BattleTick.new(123)
for _ = 1, 30 do
    tick_a:advance()
    tick_b:advance()
end
assert_equal(tick_a:hash(tick_a:snapshot()), tick_b:hash(tick_b:snapshot()), "same battle seed should produce same tick state")
tick_a:get_rng("boss"):next_int(1, 2)
local restored_tick = BattleTick.new(999):restore(tick_a:snapshot())
assert_equal(restored_tick:hash(restored_tick:snapshot()), tick_a:hash(tick_a:snapshot()), "battle tick restore must include every RNG stream")

local function create_pattern_simulation(seed)
    local pattern_session = GameSession.new({ run_seed = seed, player_count = 2 })
    pattern_session:start_new()
    local pattern_stage = StageAdapter.new(pattern_session)
    pattern_stage:start_training("spirit_seal")
    for player_id, player in pairs(pattern_stage.runtime.players) do
        player.x = player_id == 1 and 120 or 1160
        player.y = 60
        player.invulnerable = 100000
    end
    return pattern_stage
end

local pattern_a = create_pattern_simulation(424242)
local pattern_b = create_pattern_simulation(424242)
local pattern_other_seed = create_pattern_simulation(424243)
assert_equal(pattern_a.runtime.pattern_id, pattern_b.runtime.pattern_id, "pattern id must match")
assert_equal(pattern_a.runtime.pattern_seed, pattern_b.runtime.pattern_seed, "pattern seed must match")
assert_equal(pattern_a.runtime.pattern_start_tick, pattern_b.runtime.pattern_start_tick, "pattern start tick must match")
assert_true(pattern_a.runtime.pattern_phase ~= pattern_other_seed.runtime.pattern_phase, "pattern seed must affect gameplay phase")
local targeted_players = {}
for tick = 1, 900 do
    local inputs = {
        [1] = { player_id = 1, tick = tick },
        [2] = { player_id = 2, tick = tick },
    }
    pattern_a:update(inputs)
    pattern_b:update(inputs)
    pattern_other_seed:update(inputs)
    if pattern_a.runtime.pattern_target_player_id then
        targeted_players[pattern_a.runtime.pattern_target_player_id] = true
    end
    if tick % 30 == 0 then
        assert_equal(pattern_a:world_hash(), pattern_b:world_hash(), "same pattern simulation must not drift at tick " .. tick)
    end
end
assert_true(targeted_players[1] and targeted_players[2], "boss targeting must deterministically select both alive players")
assert_true(pattern_a:world_hash() ~= pattern_other_seed:world_hash(), "different pattern seeds should diverge")

local pattern_snapshot = pattern_a:get_world_snapshot()
pattern_b.runtime.players[1].x = pattern_b.runtime.players[1].x + 25
assert_true(pattern_a:world_hash() ~= pattern_b:world_hash(), "test mutation must cause a world mismatch")
assert_true(pattern_b:apply_snapshot(pattern_snapshot), "world snapshot should apply")
assert_equal(pattern_a:world_hash(), pattern_b:world_hash(), "snapshot must restore complete deterministic gameplay state")

local training_bootstrap = Bootstrap.create({})
training_bootstrap:init()
training_bootstrap.menu_cursor = 4
training_bootstrap.input:set_pending({ confirm = true })
training_bootstrap:update()
assert_equal(training_bootstrap.session.run_state, Constants.run_states.CARD_SELECT, "menu should open card training")
training_bootstrap.input:set_pending({ confirm = true })
training_bootstrap:update()
assert_equal(training_bootstrap.session.run_state, Constants.run_states.CARD_TRAINING, "card selection should start training")

local nonspell_bootstrap = Bootstrap.create({})
nonspell_bootstrap:init()
nonspell_bootstrap:open_training_selection("nonspell")
assert_equal(#nonspell_bootstrap.selection_catalog, #NonSpellCatalog, "nonspell catalog should be selected")
nonspell_bootstrap:start_selected_training(1)
assert_equal(nonspell_bootstrap.stage_adapter.training_kind, "card", "nonspell practice uses card runtime")
assert_equal(nonspell_bootstrap.stage_adapter.training_return_state, Constants.run_states.NON_SPELL_SELECT, "nonspell practice returns to nonspell list")

local enemy_bootstrap = Bootstrap.create({})
enemy_bootstrap:init()
enemy_bootstrap:open_training_selection("enemy")
assert_equal(#enemy_bootstrap.selection_catalog, #EnemyCatalog, "enemy catalog should be selected")
enemy_bootstrap:start_selected_training(1)
assert_equal(enemy_bootstrap.stage_adapter.training_kind, "enemy", "enemy practice uses enemy runtime")
assert_equal(enemy_bootstrap.stage_adapter.training_target_id, EnemyCatalog[1].id, "enemy practice target")

local join_menu = NetworkMenu.new():open("client")
assert_equal(join_menu.ip, "localhost", "join menu should support localhost by default")
assert_equal(join_menu:confirm(), nil, "confirming IP should focus the port field")
join_menu:append_text("28080")
local join_config = join_menu:confirm()
assert_equal(join_config.host, "localhost", "localhost must pass network menu validation")
assert_equal(join_config.port, 28080, "join menu should parse the entered port")
local host_menu = NetworkMenu.new():open("host")
host_menu:append_text("70000")
local _, invalid_port_error = host_menu:confirm()
assert_true(invalid_port_error ~= nil, "host menu must reject an invalid port")

local created_network_config
local function successful_lan_factory(config)
    created_network_config = config
    return {
        mode = config.mode,
        role = config.mode,
        player_id = config.player_id,
        attach_session = function(self, attached_session) self.session = attached_session return self end,
        connect = function() return true end,
        disconnect = function() end,
        submit_input = function() return true end,
        update = function() end,
        consume_inputs = function() return {} end,
        consume_events = function() return {} end,
        consume_snapshot = function() return nil end,
        broadcast = function() return true end,
        publish_snapshot = function() return true end,
        is_host = function(self) return self.mode == "host" end,
    }
end

local host_menu_bootstrap = Bootstrap.create({ lan_transport_factory = successful_lan_factory })
host_menu_bootstrap:init()
host_menu_bootstrap:open_network_menu("host")
host_menu_bootstrap.input:set_pending({ text = "28123" })
host_menu_bootstrap:update()
host_menu_bootstrap.input:set_pending({ confirm = true })
host_menu_bootstrap:update()
assert_equal(created_network_config.mode, "host", "host menu must create a host transport")
assert_equal(created_network_config.host, "0.0.0.0", "host menu should only require a port")
assert_equal(created_network_config.port, 28123, "host menu should forward its port")
assert_equal(host_menu_bootstrap.session.local_player_id, 1, "server should control P1")
assert_equal(host_menu_bootstrap.session.run_state, Constants.run_states.MAP, "server should enter the shared map")
assert_equal(host_menu_bootstrap.stage_adapter.runtime, nil, "server should wait for map consensus before entering a room")

local join_menu_bootstrap = Bootstrap.create({ lan_transport_factory = successful_lan_factory })
join_menu_bootstrap:init()
join_menu_bootstrap:open_network_menu("client")
join_menu_bootstrap.input:set_pending({ confirm = true })
join_menu_bootstrap:update()
join_menu_bootstrap.input:set_pending({ text = "28234" })
join_menu_bootstrap:update()
join_menu_bootstrap.input:set_pending({ confirm = true })
join_menu_bootstrap:update()
assert_equal(created_network_config.mode, "client", "join menu must create a client transport")
assert_equal(created_network_config.host, "localhost", "join menu must forward localhost")
assert_equal(created_network_config.port, 28234, "join menu should forward its port")
assert_equal(join_menu_bootstrap.session.local_player_id, 2, "client should control P2")
assert_equal(join_menu_bootstrap.session.run_state, Constants.run_states.MAP, "client should enter the shared map")

local coop_session = GameSession.new({ run_seed = 654, player_count = 2 })
coop_session:start_new()
assert_true(coop_session:get_player(1) ~= nil and coop_session:get_player(2) ~= nil, "co-op session should create two players")
assert_equal(#coop_session.party.player_ids, 2, "co-op party should contain two players")
local coop_node
for _, candidate in pairs(coop_session.map.nodes) do
    if candidate.type == Constants.node_types.ENEMY then
        coop_node = candidate
        break
    end
end
coop_session:debug_goto(coop_node.id)
local coop_stage = StageAdapter.new(coop_session)
coop_stage:start(coop_session.current_encounter)
assert_true(coop_stage:get_player_by_id(2) ~= nil, "co-op runtime should create player two")
local p1_x = coop_stage.runtime.players[1].x
local p2_x = coop_stage.runtime.players[2].x
coop_stage:update({
    [1] = { player_id = 1, move_x = 1, shoot = true },
    [2] = { player_id = 2, move_x = -1, shoot = true },
})
assert_true(coop_stage.runtime.players[1].x > p1_x and coop_stage.runtime.players[2].x < p2_x, "co-op inputs should move players independently")
assert_true(coop_stage:world_hash() ~= nil, "co-op runtime should expose a world hash")
coop_session:add_life(1, -3, "test")
coop_stage:update({ [2] = { player_id = 2 } })
assert_equal(coop_session.run_state, Constants.run_states.ENCOUNTER, "one player's death must not end the battle")

local fake_host, fake_client = FakeTransport.create_pair()
fake_host:send({ type = Command.ADD_SCORE, player_id = 1, amount = 5 })
local command_message = fake_client:poll()
assert_equal(command_message.kind, "command", "fake transport should carry commands")
local input_message = { player_id = 2, tick = 7, move_x = 1, move_y = 0, shoot = true, focus = false, bomb = false }
fake_client:submit_input(input_message)
fake_host:update()
assert_equal(fake_host:consume_inputs()[2].tick, 7, "fake host should receive remote input")
-- A Bomb is a one-frame edge.  Several packets can arrive before the host's
-- next update; coalescing must retain the edge instead of letting a later
-- release packet overwrite it.
fake_client:submit_input({ player_id = 2, tick = 8, move_x = 0, move_y = 0, shoot = false, focus = true, bomb = true })
fake_client:submit_input({ player_id = 2, tick = 9, move_x = 0, move_y = 0, shoot = false, focus = false, bomb = false })
fake_host:update()
local coalesced_input = fake_host:consume_inputs()[2]
assert_true(coalesced_input.bomb == true, "remote Bomb edge must survive input coalescing")
assert_equal(coalesced_input.tick, 9, "coalesced input should keep the newest movement tick")
assert_equal(coalesced_input.bomb_tick, 8, "coalesced input should preserve the Bomb action tick")
fake_host:publish_snapshot({ tick = 7, world_hash = "abc123" })
assert_equal(fake_client:poll().kind, "snapshot", "fake transport should carry snapshots")
fake_client:publish_peer_snapshot({ frame = 30, enemies = { [1] = { alive = true, x = 12, y = 18 } } })
fake_host:update()
assert_equal(fake_host:consume_peer_snapshot().frame, 30,
    "fake transport should carry bidirectional peer snapshots")
fake_client:ping()
fake_host:update()
assert_equal(fake_client:poll().kind, "pong", "fake transport should support ping/pong")

local room_host, room_clients = FakeTransport.create_room(2)
room_host:broadcast({ type = "ROOM_READY", tick = 1 })
room_clients[1]:update()
room_clients[2]:update()
assert_equal(room_clients[1]:consume_events()[1].type, "ROOM_READY", "fake client A should receive host events")
assert_equal(room_clients[2]:consume_events()[1].type, "ROOM_READY", "fake client B should receive host events")

local codec_payload = { text = "line one\nline two", tick = 17, flags = { true, false } }
local codec_round_trip = LANTransport.decode(LANTransport.encode(codec_payload))
assert_equal(codec_round_trip.text, codec_payload.text, "LAN codec must preserve embedded newlines")
assert_equal(codec_round_trip.flags[2], false, "LAN codec must preserve booleans")
local battle_events = {
    bomb_events = { { sequence = 4, owner = 1, focus = true, charged = true } },
    enemy_kill_events = { { sequence = 9, enemy_id = 3 } },
}
local battle_events_round_trip = LANTransport.decode(LANTransport.encode(battle_events))
assert_equal(battle_events_round_trip.bomb_events[1].owner, 1,
    "LAN codec must preserve compact Bomb events")
assert_true(battle_events_round_trip.bomb_events[1].charged == true,
    "LAN codec must preserve charged Bomb metadata")
assert_equal(battle_events_round_trip.enemy_kill_events[1].enemy_id, 3,
    "LAN codec must preserve compact enemy-kill events")
local frame_builder = LANTransport.new({ socket = {}, mode = "host" })
frame_builder:_queue("event", codec_payload)
local encoded_frame = frame_builder.outgoing[1]
local split_at = math.floor(#encoded_frame / 2)
local receive_chunks = { encoded_frame:sub(1, split_at), encoded_frame:sub(split_at + 1) }
local partial_socket = {
    receive = function()
        local chunk = table.remove(receive_chunks, 1)
        return nil, "timeout", chunk or ""
    end,
    close = function() end,
}
local frame_receiver = LANTransport.new({ socket = {}, mode = "client" })
frame_receiver.connected = true
frame_receiver.socket_handle = partial_socket
frame_receiver:_receive()
assert_equal(#frame_receiver.inbox, 0, "partial LAN frame must wait for the remaining bytes")
frame_receiver:_receive()
assert_equal(frame_receiver:poll().payload.text, codec_payload.text, "fragmented LAN frame must decode after reassembly")

local sync_host_transport, sync_client_transport = FakeTransport.create_pair()
local sync_host_session = GameSession.new({ run_seed = 20260826, player_count = 2, local_player_id = 1 }):start_new()
local sync_client_session = GameSession.new({ run_seed = 20260826, player_count = 2, local_player_id = 2 }):start_new()
sync_host_transport:attach_session(sync_host_session)
sync_client_transport:attach_session(sync_client_session)
local sync_host_stage = StageAdapter.new(sync_host_session)
local sync_client_stage = StageAdapter.new(sync_client_session)
sync_host_stage:start_empty_room()
sync_client_stage:start_empty_room()
local host_sync = BattleSync.new(sync_host_transport, { local_player_id = 1, snapshot_interval = 1 })
local client_sync = BattleSync.new(sync_client_transport, { local_player_id = 2, snapshot_interval = 1 })
for tick = 1, 120 do
    local client_bundle = client_sync:before_update({ [2] = { player_id = 2, move_x = -1 } }, sync_client_stage)
    assert_equal(client_bundle, nil, "client must wait for the authoritative input bundle")
    local host_bundle = host_sync:before_update({ [1] = { player_id = 1, move_x = 1 } }, sync_host_stage)
    assert_true(host_bundle ~= nil and host_bundle[1] ~= nil and host_bundle[2] ~= nil, "host must collect both player inputs at tick " .. tick)
    sync_host_stage:update(host_bundle)
    host_sync:after_update(sync_host_stage)

    client_bundle = client_sync:before_update({ [2] = { player_id = 2, move_x = -1 } }, sync_client_stage)
    assert_true(client_bundle ~= nil and client_bundle[1] ~= nil and client_bundle[2] ~= nil, "client must receive the same input bundle")
    sync_client_stage:update(client_bundle)
    client_sync:after_update(sync_client_stage)
    assert_equal(sync_host_stage:world_hash(), sync_client_stage:world_hash(), "empty-room lockstep must stay synchronized at tick " .. tick)
end
assert_true(sync_host_stage.runtime.players[1].x > 540, "host player should move in the empty room")
assert_true(sync_host_stage.runtime.players[2].x < 740, "client player should move in the empty room")
assert_equal(client_sync:get_status(), "SYNC OK", "matching host snapshots should report sync")

-- The equipment Runtime now applies the ultralight movement policy (9 px per
-- frame), so P1 reaches the right boundary during this long lockstep run.
-- Mutate the unconstrained vertical coordinate to keep the desync probe
-- independent of boundary clamping.
sync_client_stage.runtime.players[1].y = sync_client_stage.runtime.players[1].y + 9
client_sync:before_update({ [2] = { player_id = 2 } }, sync_client_stage)
local correction_bundle = host_sync:before_update({ [1] = { player_id = 1 } }, sync_host_stage)
sync_host_stage:update(correction_bundle)
host_sync:after_update(sync_host_stage)
local client_correction_bundle = client_sync:before_update({ [2] = { player_id = 2 } }, sync_client_stage)
sync_client_stage:update(client_correction_bundle)
client_sync:after_update(sync_client_stage)
local desync_status, first_mismatch_tick = client_sync:get_status()
assert_equal(desync_status, "DESYNC", "mutated client state must report desync")
assert_equal(first_mismatch_tick, 121, "desync detector must locate the first mismatching tick")
assert_equal(sync_host_stage:world_hash(), sync_client_stage:world_hash(), "authoritative snapshot must repair a mismatch")

local map_scene = MapScene.new(GameSession.new({ run_seed = 2345 }):start_new())
local map_view = map_scene:get_view()
for _, node in ipairs(map_view.nodes) do
    assert_true(node.revealed, "new map view must reveal every node")
end

local vote_session = GameSession.new({ run_seed = 2468, player_count = 2 }):start_new()
local vote_start_node_id = vote_session.current_node_id
local vote_links = vote_session.map:get_current_node().links
assert_true(#vote_links >= 2, "co-op map test needs two reachable choices")
local first_vote = vote_session:dispatch({ type = Command.VOTE_NODE, node_id = vote_links[1], player_id = 1 })
assert_true(first_vote ~= nil, "P1 should be able to submit a map vote")
assert_equal(vote_session.current_node_id, vote_start_node_id, "one map vote must not advance the party")
assert_equal(vote_session.run_state, Constants.run_states.MAP, "one map vote must keep the party on the map")
local vote_view = MapScene.new(vote_session):get_view()
assert_equal(vote_view.node_votes[1], vote_links[1], "map view should expose P1's vote")
assert_true(vote_view.message:find("P1", 1, true) ~= nil, "map view should say which player has voted")

vote_session:dispatch({ type = Command.VOTE_NODE, node_id = vote_links[2], player_id = 2 })
assert_equal(vote_session.current_node_id, vote_start_node_id, "different votes must not advance the party")
assert_equal(vote_session.run_state, Constants.run_states.MAP, "different votes must keep the party on the map")
assert_equal(vote_session.node_votes[2], vote_links[2], "P2 should be able to change the consensus target")
assert_true(vote_session:get_map_vote_message():find("不一致", 1, true) ~= nil, "different votes should show a disagreement message")

vote_session:dispatch({ type = Command.VOTE_NODE, node_id = vote_links[1], player_id = 2 })
assert_equal(vote_session.current_node_id, vote_links[1], "matching votes must advance the party")
assert_equal(next(vote_session.node_votes), nil, "votes must clear after entering the agreed node")

local invalid_vote_session = GameSession.new({ run_seed = 2468, player_count = 2 }):start_new()
local _, invalid_vote_error = invalid_vote_session:dispatch({ type = Command.VOTE_NODE, node_id = 9999, player_id = 1 })
assert_true(invalid_vote_error ~= nil, "an invalid map vote must be rejected")
assert_equal(next(invalid_vote_session.node_votes), nil, "a rejected vote must not be stored")

local vote_host_transport, vote_client_transport = FakeTransport.create_pair()
local vote_host_session = GameSession.new({ run_seed = 13579, player_count = 2, local_player_id = 1 }):start_new()
local vote_client_session = GameSession.new({ run_seed = 13579, player_count = 2, local_player_id = 2 }):start_new()
vote_host_transport:attach_session(vote_host_session)
vote_client_transport:attach_session(vote_client_session)
local network_vote_node_id = vote_host_session.map:get_current_node().links[1]
vote_host_transport:send({ type = Command.VOTE_NODE, node_id = network_vote_node_id, player_id = 1 })
vote_client_transport:update()
assert_equal(vote_client_session.node_votes[1], network_vote_node_id, "client should receive the host's map vote")
vote_client_transport:send({ type = Command.VOTE_NODE, node_id = network_vote_node_id, player_id = 2 })
vote_host_transport:update()
assert_equal(vote_host_session.current_node_id, network_vote_node_id, "host should enter the agreed network node")
-- The client no longer advances on its own vote; it must follow the host's
-- authoritative SYNC_NODE command (emitted by the host when the shared map
-- advances). Send that command and verify both peers land on the same node.
assert_equal(vote_client_session.current_node_id, vote_host_session.map.start_node_id, "client must wait for the host before advancing")
vote_host_transport:send({ type = Command.SYNC_NODE, node_id = network_vote_node_id, player_id = 1 })
vote_client_transport:update()
assert_equal(vote_client_session.current_node_id, network_vote_node_id, "client should enter the same agreed network node")
assert_equal(vote_host_session.run_state, vote_client_session.run_state, "map consensus must leave both peers in the same state")

-- A SYNC_NODE must repair a diverged client even when the node is no longer
-- adjacent to the client's stale current node. This is the exact deadlock the
-- authoritative command exists to prevent.
local diverge_host_session = GameSession.new({ run_seed = 13579, player_count = 2, local_player_id = 1 }):start_new()
local diverge_client_session = GameSession.new({ run_seed = 13579, player_count = 2, local_player_id = 2 }):start_new()
local diverge_links = diverge_host_session.map:get_current_node().links
local diverge_first = diverge_links[1]
local diverge_second = diverge_links[2]
-- Host advances two nodes ahead (first then a successor), client stays put.
diverge_host_session:dispatch({ type = Command.VOTE_NODE, node_id = diverge_first, player_id = 1 })
diverge_host_session:dispatch({ type = Command.VOTE_NODE, node_id = diverge_first, player_id = 2 })
local second_links = diverge_host_session.map:get_node(diverge_first).links
assert_true(second_links and #second_links > 0, "divergence test needs a deeper node to advance into")
local diverge_third = second_links[1]
diverge_host_session:dispatch({ type = Command.VOTE_NODE, node_id = diverge_third, player_id = 1 })
diverge_host_session:dispatch({ type = Command.VOTE_NODE, node_id = diverge_third, player_id = 2 })
assert_true(diverge_host_session.current_node_id ~= diverge_client_session.current_node_id,
    "host must be ahead of a client that has not received any sync")
-- Client is several nodes behind; force it to the host's current node even
-- though that node is not adjacent to the client's local current node.
diverge_client_session:dispatch({ type = Command.SYNC_NODE, node_id = diverge_host_session.current_node_id, player_id = 1 })
assert_equal(diverge_client_session.current_node_id, diverge_host_session.current_node_id,
    "authoritative sync must move a lagging client straight onto the host node")
assert_equal(diverge_client_session.run_state, diverge_host_session.run_state,
    "authoritative sync must align the run state as well")

local mouse_vote_host, mouse_vote_client = FakeTransport.create_pair()
local p2_mouse_bootstrap = Bootstrap.create({
    transport = mouse_vote_client,
    network_role = "client",
    local_player_id = 2,
    player_count = 2,
    run_seed = 97531,
})
p2_mouse_bootstrap:start_game(97531)
local p2_mouse_node = p2_mouse_bootstrap.session.map:get_node(p2_mouse_bootstrap.session.map:get_current_node().links[1])
p2_mouse_bootstrap.renderer = {
    screen_to_map = function()
        return p2_mouse_node.x, p2_mouse_node.y
    end,
}
p2_mouse_bootstrap.input = {
    poll_all = function()
        return {
            [2] = {
                player_id = 2,
                tick = 1,
                move_x = 0,
                move_y = 0,
                confirm = false,
                cancel = false,
                mouse_primary_pressed = true,
            },
        }
    end,
    get_mouse_position = function() return 640, 360 end,
}
p2_mouse_bootstrap:update()
local p2_mouse_command = mouse_vote_host:poll()
assert_equal(p2_mouse_command.kind, "command", "P2 mouse click should send a network command")
assert_equal(p2_mouse_command.payload.type, Command.VOTE_NODE, "P2 mouse click should send a map vote")
assert_equal(p2_mouse_command.payload.player_id, 2, "P2 mouse vote must retain the local player id")
assert_equal(p2_mouse_command.payload.node_id, p2_mouse_node.id, "P2 mouse vote should target the clicked node")

-- When the host's session advances a node, the bootstrap must broadcast a
-- SYNC_NODE command so the client follows the authoritative node.
local sync_host_transport, sync_client_transport = FakeTransport.create_pair()
local sync_bootstrap = Bootstrap.create({
    transport = sync_host_transport,
    network_role = "host",
    local_player_id = 1,
    player_count = 2,
    run_seed = 86420,
})
sync_bootstrap:start_game(86420)
local sync_target = sync_bootstrap.session.map:get_current_node().links[1]
sync_bootstrap.session:dispatch({ type = Command.SELECT_NODE, node_id = sync_target, player_id = 1 })
local sync_broadcast = sync_client_transport:poll()
assert_equal(sync_broadcast.kind, "command", "host node advance must broadcast a command")
assert_equal(sync_broadcast.payload.type, Command.SYNC_NODE, "host node advance must broadcast SYNC_NODE")
assert_equal(sync_broadcast.payload.node_id, sync_target, "SYNC_NODE must carry the authoritative node id")

local menu_session = GameSession.new({ run_seed = 4321 })
assert_equal(menu_session.run_state, Constants.run_states.MENU, "fresh session must open on menu")

local session = GameSession.new({ run_seed = 777 })
session:start_new()
assert_equal(session.run_state, Constants.run_states.MAP, "new session must start on map")
assert_equal(session.party.player_ids[1], 1, "party must contain player one")
local current = session.map:get_current_node()
assert_true(#current.links > 0, "start must have a move")
local next_node = session.map:get_node(current.links[1])
local selected = session:dispatch({ type = Command.SELECT_NODE, node_id = next_node.id, player_id = 1 })
assert_true(selected ~= nil, "adjacent node selection must work")
assert_equal(session.current_node_id, next_node.id, "session must update current node")
local _, invalid_error = session:dispatch({ type = Command.SELECT_NODE, node_id = 9999, player_id = 1 })
assert_true(invalid_error ~= nil, "invalid node must be rejected")

local transport = LocalTransport.new(session)
transport:send({ type = Command.ADD_MONEY, player_id = 1, amount = 25, source = "test" })
transport:update()
assert_equal(session:get_player(1).money, 25, "transport command must update player state")

local reward_service = RewardService.new()
local reward = reward_service:calculate({ battle_score = 100000, reward_eligible = true })
assert_equal(reward.money, 100, "reward money threshold")
assert_equal(reward.bomb, 1, "reward bomb threshold")
assert_equal(reward.life, 1, "reward life threshold")

local battle_session = GameSession.new({ run_seed = 888 })
battle_session:start_new()
local battle_node
for id, candidate in pairs(battle_session.map.nodes) do
    if candidate.type == Constants.node_types.ENEMY or candidate.type == Constants.node_types.BOSS then
        battle_node = candidate
        break
    end
end
assert_true(battle_node ~= nil, "test map must contain a battle node")
battle_session:debug_goto(battle_node.id)
local battle = BattleManager.new(battle_session)
battle:begin(battle_session.current_encounter)
battle:add_score(100000)
battle:collect_money(12)
assert_true(battle:use_bomb(1), "battle should consume a bomb")
local battle_result = battle:complete(true, { reward_eligible = true })
assert_true(battle_result.clear_state, "battle result should be clear")
assert_equal(battle_session:get_player(1).money, 112, "battle money and reward money")
assert_equal(battle_session:get_player(1).bomb, 3, "bomb spend and reward bomb")
if battle_session.run_state == Constants.run_states.REWARD then
    local reward_claim = battle_session:claim_reward(1, 1)
    assert_true(reward_claim ~= nil, "battle reward can be claimed")
elseif battle_session.run_state == Constants.run_states.RELIC_SELECT then
    local relic_choice = battle_session.relic_choices[1] and battle_session.relic_choices[1][1]
    assert_true(relic_choice and battle_session:choose_relic(1, relic_choice), "boss relic can be claimed")
end
assert_equal(battle_session.run_state, Constants.run_states.MAP, "normal battle should return to map")

local parsed_god = DebugCommand.parse("god")
assert_true(parsed_god.toggle, "god without argument should toggle")
local console = DebugConsole.new(battle_session)
console:write("god on")
assert_true(battle_session.god_mode[1], "god on command")
console:write("money 10")
assert_equal(battle_session:get_player(1).money, 122, "debug money command")
console:write("map_reveal")
assert_true(battle_session.map.revealed, "debug map reveal command")

local fallback_session = GameSession.new({ run_seed = 999 })
fallback_session:start_new()
local fallback_enemy
for _, candidate in pairs(fallback_session.map.nodes) do
    if candidate.type == Constants.node_types.ENEMY then
        fallback_enemy = candidate
        break
    end
end
assert_true(fallback_enemy ~= nil, "fallback battle needs an enemy node")
fallback_session:debug_goto(fallback_enemy.id)
local fallback_stage = StageAdapter.new(fallback_session)
fallback_stage:start(fallback_session.current_encounter)
for _ = 1, 12 do
    fallback_stage:kill_all()
    for _ = 1, 60 do
        fallback_stage:update({})
        if fallback_session.run_state == Constants.run_states.REWARD then
            fallback_session:claim_reward(1, 1)
        end
        if fallback_session.run_state == Constants.run_states.MAP then
            break
        end
    end
    if fallback_session.run_state == Constants.run_states.REWARD then
        fallback_session:claim_reward(1, 1)
    end
    if fallback_session.run_state == Constants.run_states.MAP then
        break
    end
end
assert_equal(fallback_session.run_state, Constants.run_states.MAP, "fallback stage should clear and return to map")
assert_true(fallback_session.battle_result ~= nil, "fallback stage should produce a battle result")

print("TouHouNightReign core tests passed")
