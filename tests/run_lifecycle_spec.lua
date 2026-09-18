local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")

return function(assert_equal, assert_true)
    local session = GameSession.new({ run_seed = 12345, player_count = 1 })
    session:start_new()
    local enemy, shop
    for _, node in ipairs(session.map.nodes) do
        if node.type == Constants.node_types.ENEMY and not enemy then enemy = node end
        if node.type == Constants.node_types.SHOP and not shop then shop = node end
    end
    assert_true(enemy ~= nil and shop ~= nil, "lifecycle needs enemy and shop nodes")
    session:debug_goto(enemy.id)
    session:complete_battle({ clear_state = true, reward_eligible = true, battle_score = 150, player_id = 1 })
    assert_equal(session.run_state, Constants.run_states.REWARD, "enemy clear opens reward choice")
    local reward_claim = session:claim_reward(1, 1)
    assert_true(reward_claim ~= nil, "enemy reward can be claimed")
    assert_equal(session.run_state, Constants.run_states.MAP, "enemy reward returns to map")
    session:get_player(1):add_money(100)
    session:debug_goto(shop.id)
    assert_equal(session.run_state, Constants.run_states.SHOP, "shop node opens shop state")
    assert_true(session:shop_purchase(1, 1), "shop purchase succeeds")
    assert_true(session:shop_ready(1), "single player leaves shop")
    assert_equal(session.run_state, Constants.run_states.MAP, "shop ready returns to map")
    local boss = session.map:get_node(session.map.boss_node_id)
    session:debug_goto(boss.id)
    session:complete_battle({ clear_state = true, reward_eligible = false, player_id = 1 })
    assert_equal(session.run_state, Constants.run_states.RELIC_SELECT, "boss clear opens relic choice")
    assert_true(session:choose_relic(1, session.relic_choices[1][2]), "boss relic choice succeeds")
    assert_equal(session.run_state, Constants.run_states.RUN_CLEAR, "relic choice completes run")
end
