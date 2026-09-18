local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")

return function(assert_equal, assert_true)
    local session = GameSession.new({ run_seed = 101, player_count = 1 })
    session:start_new()
    local enemy
    for _, node in ipairs(session.map.nodes) do
        if node.type == Constants.node_types.ENEMY then enemy = node break end
    end
    assert_true(enemy ~= nil, "reward test needs an enemy node")
    session:debug_goto(enemy.id)
    local player = session:get_player(1)
    local before = #player.loadout.inventory.items
    session:complete_battle({
        clear_state = true, reward_eligible = true, battle_score = 100,
        encounter_id = session.current_encounter.id,
        encounter_type = session.current_encounter.type, player_id = 1,
    })
    assert_equal(session.run_state, Constants.run_states.REWARD, "enemy clear opens reward choice")
    assert_equal(#session.reward_choices, 3, "enemy reward has three choices")
    assert_true(session:claim_reward(1, 1) ~= nil, "enemy reward can be claimed")
    assert_equal(session.run_state, Constants.run_states.MAP, "claiming enemy reward returns to map")
    assert_true(#player.loadout.inventory.items >= before,
        "enemy reward is acquired or queued in inventory")

    local elite
    for _, node in ipairs(session.map.nodes) do
        if node.type == Constants.node_types.ELITE then elite = node break end
    end
    if elite then
        session:debug_goto(elite.id)
        session:complete_battle({ clear_state = true, reward_eligible = true, player_id = 1 })
        assert_equal(session.run_state, Constants.run_states.REWARD, "elite clear opens reward choice")
        assert_equal(session.reward_required, 2, "elite reward requires two choices")
        assert_true(session.reward_guaranteed_definition_id ~= nil, "elite reward has guaranteed weapon")
        assert_true(session:claim_reward(1, 1) ~= nil, "elite first choice can be claimed")
        assert_true(session:claim_reward(1, 2) ~= nil, "elite second choice can be claimed")
        assert_equal(session.run_state, Constants.run_states.MAP, "elite reward returns to map")
    end
end
