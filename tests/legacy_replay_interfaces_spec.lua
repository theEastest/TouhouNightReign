-- Tests for the legacy replay player mode and roster interfaces.
--
-- These are the seams the single and co-operative, classic and modern
-- combinations are built from. A regression here would silently change how a
-- run is configured, so every combination is pinned.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local Interfaces = require("tnr.legacy_replay.interfaces")
    local BossUi = require("tnr.legacy_replay.boss_ui")

    -- Rosters describe who is playing.
    local solo = Interfaces.PlayerRoster.new({ player_ids = { 1 } })
    assert_equal(solo:count(), 1, "a solo roster has one player")
    assert_true(not solo:is_coop(), "a solo roster is not co-op")

    local duo = Interfaces.PlayerRoster.new({ player_ids = { 1, 2 } })
    assert_equal(duo:count(), 2, "a duo roster has two players")
    assert_true(duo:is_coop(), "a duo roster is co-op")

    -- Input sampling normalises whatever source is attached.
    duo:set_input(2, { move_x = 1, shoot = true })
    local sample = duo:sample(2)
    assert_equal(sample.move_x, 1, "input move axis is carried")
    assert_true(sample.shoot, "input shoot is carried")
    assert_true(not sample.focus, "a missing button defaults to false")
    -- A player with no source still yields a usable, neutral sample.
    local neutral = duo:sample(1)
    assert_equal(neutral.move_x, 0, "a missing source yields a neutral sample")
    assert_true(not neutral.shoot, "a missing source does not shoot")

    -- Modern mode: two reward rounds of three choices.
    local modern = Interfaces.modern_mode()
    assert_equal(modern.id, "modern", "the modern mode is identified")
    assert_equal(modern:rewards_per_stage(), 2, "modern offers two reward rounds")
    assert_equal(modern:reward_choice_count(), 3, "modern offers three choices per round")
    assert_equal(modern:score_extend_threshold(), nil, "modern has no score extend")

    -- Classic mode: no rewards, score extend at the reference threshold.
    local classic = Interfaces.classic_mode()
    assert_equal(classic.id, "classic", "the classic mode is identified")
    assert_equal(classic:rewards_per_stage(), 0, "classic offers no reward rounds")
    assert_equal(classic:score_extend_threshold(), 10000000, "classic extends at ten million")

    -- Sessions pair a roster with a mode.
    local solo_modern = Interfaces.ReplaySession.new({ roster = solo, mode = modern })
    assert_equal(solo_modern:reward_rounds(), 2, "solo modern runs two reward rounds")
    local duo_modern = Interfaces.ReplaySession.new({ roster = duo, mode = modern })
    assert_equal(duo_modern:reward_rounds(), 4, "co-op modern runs a round per player")
    local solo_classic = Interfaces.ReplaySession.new({ roster = solo, mode = classic })
    assert_equal(solo_classic:reward_rounds(), 0, "classic runs no reward rounds")

    -- finish_stage returns one entry per round and alternates players in co-op.
    local rewards = duo_modern:finish_stage("st01")
    assert_equal(#rewards, 4, "co-op finish_stage returns four picks")
    assert_equal(rewards[1].player_id, 1, "the first pick belongs to player one")
    assert_equal(rewards[2].player_id, 2, "the second pick belongs to player two")
    assert_equal(rewards[3].player_id, 1, "picks alternate back to player one")
    assert_equal(rewards[1].choices, 3, "each pick offers three choices")
    local classic_rewards = solo_classic:finish_stage("st01")
    assert_equal(#classic_rewards, 0, "classic finish_stage yields no picks")

    -- Classic mode tracks power on the session.
    solo_classic:add_power(1, 1.0)
    solo_classic:add_power(1, 0.5)
    assert_true(math.abs(solo_classic:get_power(1) - 1.5) < 1e-6, "power accumulates")

    -- HUD icon selection: six progressive frames, both rows present.
    assert_equal(BossUi.HEART_FIRST_SPRITE, 13, "the first heart sprite is index 13")
    assert_equal(BossUi.STAR_FIRST_SPRITE, 19, "the first star sprite is index 19")
    assert_equal(BossUi.icon_sprite(BossUi.HEART_FIRST_SPRITE, 0), 13, "an empty heart")
    assert_equal(BossUi.icon_sprite(BossUi.HEART_FIRST_SPRITE, 1), 18, "a full heart")
    assert_equal(BossUi.icon_sprite(BossUi.STAR_FIRST_SPRITE, 0), 19, "an empty star")
    assert_equal(BossUi.icon_sprite(BossUi.STAR_FIRST_SPRITE, 1), 24, "a full star")
    -- The heart and star ranges must not overlap.
    assert_true(BossUi.HEART_FIRST_SPRITE + BossUi.ICON_FILL_FRAMES - 1 < BossUi.STAR_FIRST_SPRITE,
        "the heart row ends before the star row begins")

    -- Movement easing curves, matching the reference formulas exactly.
    local Adapter = require("tnr.legacy_replay.adapter")
    assert_true(math.abs(Adapter.ease_fraction(0, 0.5) - 0.5) < 1e-6, "linear easing")
    assert_true(math.abs(Adapter.ease_fraction(1, 0.5) - 0.75) < 1e-6, "decelerate easing")
    assert_true(math.abs(Adapter.ease_fraction(2, 0.5) - (1 - 0.5 ^ 4)) < 1e-6, "decelerate fast easing")
    assert_true(math.abs(Adapter.ease_fraction(3, 0.5) - 0.25) < 1e-6, "accelerate easing")
    assert_true(math.abs(Adapter.ease_fraction(4, 0.5) - 0.5 ^ 4) < 1e-6, "accelerate fast easing")
    -- Every curve reaches the destination at the end of the move.
    for mode = 0, 4 do
        assert_true(math.abs(Adapter.ease_fraction(mode, 0) - 1.0) < 1e-6,
            "easing mode " .. mode .. " completes the move")
    end
end
