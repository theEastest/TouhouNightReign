local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")

return function(assert_equal, assert_true)
    local session = GameSession.new({ run_seed = 101, player_count = 1 })
    session:start_new()
    -- Ordinary enemy rooms now offer a reward card only one third of the time.
    -- Find an enemy node that does offer one so the reward path is exercised.
    local enemy
    for _, node in ipairs(session.map.nodes) do
        if node.type == Constants.node_types.ENEMY then
            session:debug_goto(node.id)
            local result = session:complete_battle({
                clear_state = true, reward_eligible = true, battle_score = 100,
                encounter_id = session.current_encounter.id,
                encounter_type = session.current_encounter.type, player_id = 1,
            })
            if session.run_state == Constants.run_states.REWARD then
                enemy = node
                break
            end
            -- No reward this time: the run returns straight to the map.
            assert_equal(session.run_state, Constants.run_states.MAP,
                "an enemy room without a reward card returns to the map")
        end
    end
    assert_true(enemy ~= nil, "at least one enemy room must offer a reward card")
    local player = session:get_player(1)
    local before = #player.loadout.inventory.items
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
        -- Elite rooms now offer a single pick from three cards (the guaranteed
        -- legendary weapon is still granted separately).
        assert_equal(session.reward_required, 1, "elite reward picks one card")
        assert_equal(#session.reward_choices, 3, "elite reward offers three cards")
        assert_true(session.reward_guaranteed_definition_id ~= nil, "elite reward has guaranteed weapon")
        assert_true(session:claim_reward(1, 1) ~= nil, "elite choice can be claimed")
        assert_equal(session.run_state, Constants.run_states.MAP, "elite reward returns to map")
    end
end
