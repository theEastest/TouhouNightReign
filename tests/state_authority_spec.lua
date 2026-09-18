local LegacyStateAdapter = require("tnr.core.legacy_state_adapter")
local GameSession = require("tnr.core.game_session")

return function(assert_equal, assert_true)
    local players = {
        [1] = { bomb = 3, score = 0, graze = 0, life = 3, alive = true },
        [2] = { bomb = 3, score = 0, graze = 0, life = 3, alive = true },
    }
    local session = {
        party = { team_life = 3 },
        get_player = function(_, player_id) return players[player_id] end,
    }
    local adapter = LegacyStateAdapter.new(session)
    assert_true(adapter ~= nil, "session must expose a legacy state adapter")
    assert_equal(adapter:team_life(), 3, "party state owns initial team life")
    assert_true(adapter:record_bomb_use(1), "owner can consume one bomb")
    assert_equal(players[1].bomb, 2, "bomb decrement is applied once to the owner")
    assert_true(adapter:record_bomb_use(1), "second owner-local bomb can be consumed")
    assert_equal(players[1].bomb, 1, "second bomb decrement is not duplicated")
    adapter:apply_player_snapshot(2, { alive = false, respawning = true, respawn_timer = 60 })
    assert_true(players[2].respawning, "native lifecycle snapshot maps to PlayerState")
    adapter:set_team_life(2)
    assert_equal(session.party.team_life, 2, "team life writes through PartyState")

    local real_session = GameSession.new({ run_seed = 17, player_count = 1 })
    real_session:start_new(17)
    assert_true(real_session.legacy_state_adapter ~= nil, "GameSession must install LegacyStateAdapter")
    local node
    for _, candidate in ipairs(real_session.map.nodes or {}) do
        if real_session.map:is_adjacent(candidate.id) then node = candidate; break end
    end
    if node then
        real_session:select_node(node.id, 1)
        assert_true(real_session.current_encounter == nil or real_session.current_encounter.room_generation ~= nil,
            "encounters must carry a deterministic room generation")
    end
end
