local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")
local RewardService = require("tnr.reward.reward_service")
local PerfectTracker = require("tnr.battle.perfect_tracker")

return function(assert_equal, assert_true)
    -- ---------------------------------------------------------------
    -- Additive reward thresholds
    -- ---------------------------------------------------------------
    local service = RewardService.new()
    local low = service:calculate({ reward_eligible = true, stage_score = 10000 })
    assert_equal(low.money, 100, "10k pays the first money tier")
    assert_equal(low.bomb, 0, "10k does not pay the bomb tier")

    local mid = service:calculate({ reward_eligible = true, stage_score = 50000 })
    assert_equal(mid.money, 100, "50k still pays the money tier")
    assert_equal(mid.bomb, 1, "50k adds the bomb tier")

    local high = service:calculate({ reward_eligible = true, stage_score = 100000 })
    assert_equal(high.money, 100, "100k still pays the money tier")
    assert_equal(high.bomb, 1, "100k still pays the bomb tier")
    assert_equal(high.life, 1, "100k adds the life tier")

    local none = service:calculate({ reward_eligible = true, stage_score = 9999 })
    assert_equal(none.money, 0, "below the first tier pays nothing")

    -- The battle score is used when no separate stage score is reported.
    local fallback = service:calculate({ reward_eligible = true, battle_score = 100000 })
    assert_equal(fallback.life, 1, "battle score fallback reaches the top tier")

    -- ---------------------------------------------------------------
    -- Perfect tracker: per-player, per-card
    -- ---------------------------------------------------------------
    local tracker = PerfectTracker.new()
    local totals = {
        [1] = { bombs = 0, deaths = 0 },
        [2] = { bombs = 0, deaths = 0 },
    }
    -- Card 1: nobody bombs or dies -> both perfect.
    tracker:begin_card(1, totals, { 1, 2 })
    local card1 = tracker:end_card(totals, { 1, 2 })
    assert_true(card1[1] == true and card1[2] == true, "a clean card is perfect for both")
    -- Card 2: player 2 bombs -> only player 1 is perfect.
    tracker:begin_card(2, totals, { 1, 2 })
    totals[2] = { bombs = 1, deaths = 0 }
    local card2 = tracker:end_card(totals, { 1, 2 })
    assert_true(card2[1] == true, "player 1 stays perfect on the second card")
    assert_true(card2[2] == false, "a bomb breaks player 2's perfect")
    -- Card 3: player 1 dies -> only player 2 is perfect.
    tracker:begin_card(3, totals, { 1, 2 })
    totals[1] = { bombs = 0, deaths = 1 }
    local card3 = tracker:end_card(totals, { 1, 2 })
    assert_true(card3[1] == false, "a miss breaks player 1's perfect")
    assert_true(card3[2] == true, "player 2 recovers a perfect on the third card")
    assert_equal(tracker:perfect_player_count({ 1, 2 }), 2,
        "both players perfect at least one card")
    assert_equal(tracker:full_perfect_player_count({ 1, 2 }), 0,
        "neither player perfects every card")

    local counts = tracker:get_counts()
    assert_equal(counts[1], 2, "player 1 perfects two cards")
    assert_equal(counts[2], 2, "player 2 perfects two cards")

    -- A fully clean run perfects every card.
    local clean = PerfectTracker.new()
    local clean_totals = { [1] = { bombs = 0, deaths = 0 } }
    clean:begin_card(1, clean_totals, { 1 })
    clean:end_card(clean_totals, { 1 })
    clean:begin_card(2, clean_totals, { 1 })
    clean:end_card(clean_totals, { 1 })
    assert_equal(clean:full_perfect_player_count({ 1 }), 1,
        "a clean player perfects every card")

    -- ---------------------------------------------------------------
    -- Perfect bonus grants equipment on boss/elite clears
    -- ---------------------------------------------------------------
    local session = GameSession.new({ run_seed = 777, player_count = 1 })
    session:start_new()
    local boss
    for _, node in ipairs(session.map.nodes) do
        if node.type == Constants.node_types.BOSS then boss = node break end
    end
    assert_true(boss ~= nil, "run must expose a boss node")
    session:debug_goto(boss.id)
    local player = session:get_player(1)
    local before = #player.loadout.inventory.items
    -- One card, perfectly cleared -> one bonus equipment in addition to the
    -- normal reward flow.
    session:complete_battle({
        clear_state = true, reward_eligible = true, stage_score = 0,
        perfect_counts = { [1] = 1 }, perfect_total_cards = 1,
    })
    local after = #player.loadout.inventory.items
    assert_true(after >= before + 1,
        "a perfect boss clear grants at least one bonus equipment")

    -- A non-perfect clear grants no bonus equipment.
    local session2 = GameSession.new({ run_seed = 778, player_count = 1 })
    session2:start_new()
    local boss2
    for _, node in ipairs(session2.map.nodes) do
        if node.type == Constants.node_types.BOSS then boss2 = node break end
    end
    session2:debug_goto(boss2.id)
    local player2 = session2:get_player(1)
    local before2 = #player2.loadout.inventory.items
    session2:complete_battle({
        clear_state = true, reward_eligible = true, stage_score = 0,
        perfect_counts = { [1] = 0 }, perfect_total_cards = 1,
    })
    assert_equal(#player2.loadout.inventory.items, before2,
        "a non-perfect boss clear grants no bonus equipment")

    -- ---------------------------------------------------------------
    -- Reward card availability: elite always, ordinary sometimes
    -- ---------------------------------------------------------------
    local elite_offered = false
    for seed = 1, 20 do
        local elite_session = GameSession.new({ run_seed = seed, player_count = 1 })
        elite_session:start_new()
        local elite
        for _, node in ipairs(elite_session.map.nodes) do
            if node.type == Constants.node_types.ELITE then elite = node break end
        end
        if elite then
            elite_session:debug_goto(elite.id)
            elite_session:complete_battle({ clear_state = true, reward_eligible = true })
            if elite_session.run_state == Constants.run_states.REWARD then
                elite_offered = true
                assert_equal(#elite_session.reward_choices, 3,
                    "an elite reward always offers three cards")
                assert_equal(elite_session.reward_required, 1,
                    "an elite reward picks a single card")
                break
            end
        end
    end
    assert_true(elite_offered, "an elite room always offers a reward card")

    -- Count how often ordinary rooms offer a card: it must be neither always
    -- nor never, matching the intended one-in-three chance.
    local offered, total = 0, 0
    for seed = 1, 60 do
        local enemy_session = GameSession.new({ run_seed = seed, player_count = 1 })
        enemy_session:start_new()
        for _, node in ipairs(enemy_session.map.nodes) do
            if node.type == Constants.node_types.ENEMY then
                enemy_session:debug_goto(node.id)
                enemy_session:complete_battle({ clear_state = true, reward_eligible = true })
                total = total + 1
                if enemy_session.run_state == Constants.run_states.REWARD then offered = offered + 1 end
                break
            end
        end
    end
    assert_true(total >= 50, "the ordinary-room sample must be large enough")
    assert_true(offered > 0, "some ordinary rooms offer a reward card")
    assert_true(offered < total, "some ordinary rooms offer no reward card")
end
