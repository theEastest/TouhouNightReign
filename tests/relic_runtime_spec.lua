local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")

return function(assert_equal, assert_true)
    local session = GameSession.new({ run_seed = 303, player_count = 1 })
    session:start_new()
    local player = session:get_player(1)
    local fragments = session.party.life_fragments
    session.relic_runtime:emit("ON_BATTLE_START", 1)
    session.relic_runtime:emit("ON_BATTLE_CLEAR", 1)
    assert_equal(session.party.life_fragments, fragments + 1, "Reimu no-hit relic grants a fragment")
    session.relic_runtime:emit("ON_BATTLE_START", 1)
    session.relic_runtime:emit("ON_PLAYER_HIT", 1)
    local after_hit = session.party.life_fragments
    session.relic_runtime:emit("ON_BATTLE_CLEAR", 1)
    assert_equal(session.party.life_fragments, after_hit, "Reimu hit clear grants no fragment")
    session.run_state = Constants.run_states.RELIC_SELECT
    session.relic_choices[1] = { "test_relic", "test_relic_bonus", "test_relic_guard" }
    assert_true(session:choose_relic(1, "test_relic"), "ordinary relic can be selected")
    assert_true(player.relics[#player.relics] == "test_relic", "ordinary relic is permanent player state")
    assert_equal(session.run_state, Constants.run_states.RUN_CLEAR, "single player relic choice clears run")
end
