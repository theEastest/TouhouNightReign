local root = (...)
package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path

local Constants = require("tnr.core.constants")
local Command = require("tnr.core.command")
local GameSession = require("tnr.core.game_session")
local MapGenerator = require("tnr.map.map_generator")
local RewardService = require("tnr.reward.reward_service")
local LocalTransport = require("tnr.multiplayer.local_transport")
local BattleManager = require("tnr.battle.battle_manager")
local StageAdapter = require("tnr.battle.stage_adapter")
local MapScene = require("tnr.map.map_scene")
local DebugCommand = require("tnr.debug.debug_command")
local DebugConsole = require("tnr.debug.console")

local function assert_equal(left, right, message)
    assert(left == right, string.format("%s: expected %s, got %s", message, tostring(right), tostring(left)))
end

local function assert_true(value, message)
    assert(value == true, message)
end

local function serialize_map(map)
    local parts = {}
    for id = 1, #map.nodes do
        local node = map.nodes[id]
        parts[#parts + 1] = string.format("%d:%s:%.5f:%.5f:%s", id, node.type, node.x, node.y, table.concat(node.links, ","))
    end
    return table.concat(parts, "|")
end

local map_a = MapGenerator.generate(12345)
local map_b = MapGenerator.generate(12345)
local map_c = MapGenerator.generate(12346)
assert_equal(serialize_map(map_a), serialize_map(map_b), "same seed must reproduce the map")
assert_true(serialize_map(map_a) ~= serialize_map(map_c), "different seeds should produce a different map")
assert_true(map_a:find_path(map_a.start_node_id, map_a.boss_node_id) ~= nil, "boss must be reachable")
assert_true(#map_a:find_path(map_a.start_node_id, map_a.boss_node_id) - 1 >= 6, "boss path must have a minimum distance")
local counts = map_a:count_types()
assert_equal(counts[Constants.node_types.START], 1, "map must have one start")
assert_equal(counts[Constants.node_types.BOSS], 1, "map must have one boss")
assert_true((counts[Constants.node_types.SHOP] or 0) > 0, "map must contain a shop")
assert_true((counts[Constants.node_types.EVENT] or 0) > 0, "map must contain an event")

local map_scene = MapScene.new(GameSession.new({ run_seed = 2345 }):start_new())
local map_view = map_scene:get_view()
for _, node in ipairs(map_view.nodes) do
    assert_true(node.revealed, "new map view must reveal every node")
end

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
        if fallback_session.run_state == Constants.run_states.MAP then
            break
        end
    end
    if fallback_session.run_state == Constants.run_states.MAP then
        break
    end
end
assert_equal(fallback_session.run_state, Constants.run_states.MAP, "fallback stage should clear and return to map")
assert_true(fallback_session.battle_result ~= nil, "fallback stage should produce a battle result")

print("TouHouNightReign core tests passed")
