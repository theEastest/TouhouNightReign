local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")

return function(assert_equal, assert_true)
    local session = GameSession.new({ run_seed = Constants.validation_run_seed, player_count = 1 })
    session:start_new()
    local boss_node = session.map:get_node(session.map.boss_node_id)
    assert_true(boss_node ~= nil, "gate0 run must expose a boss node")
    session:debug_goto(boss_node.id)
    assert_true(session.current_encounter ~= nil, "gate0 boss encounter must start")
    assert_true(session.room_generation ~= nil, "gate0 encounter must have room generation")
    session:complete_battle({ clear_state = true, reward_eligible = false })
    assert_equal(session.run_state, Constants.run_states.RELIC_SELECT,
        "boss clear must enter relic selection")
    assert_true(session.current_encounter == nil, "boss clear must release encounter")
    assert_true(session.room_generation == nil, "boss clear must invalidate room generation")
    local cleared_before_choice = false
    for _, event in ipairs(session.event_log) do
        if event.type == "RUN_CLEARED" then cleared_before_choice = true end
    end
    assert_true(not cleared_before_choice, "boss clear must wait for relic choice before RUN_CLEAR")
    assert_true(session:choose_relic(1, session.relic_choices[1][1]),
        "gate0 single player relic choice must complete")
    assert_equal(session.run_state, Constants.run_states.RUN_CLEAR,
        "relic selection must enter terminal run state")
end
