-- Tests for the legacy replay mode controller.
--
-- This is the piece that makes the replay reachable from the game, so the tests
-- pin the stage and character tables the select screen shows, the cursor
-- wraparound, and that starting a stage builds a runtime wired to the selected
-- mode and character.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local Replay = require("tnr.legacy_replay.replay")
    local Constants = require("tnr.core.constants")

    -- The run states the game dispatches on must exist.
    assert_true(Constants.run_states.REPLAY_SELECT ~= nil, "the select state exists")
    assert_true(Constants.run_states.REPLAY_STAGE ~= nil, "the stage state exists")

    -- Every reference stage has a key that matches the compiled namespace.
    assert_equal(#Replay.STAGES, 7, "seven stages are offered")
    for index, stage in ipairs(Replay.STAGES) do
        assert_true(stage.key == string.format("st%02d", index),
            "stage " .. index .. " uses the compiled namespace key")
        assert_true(type(stage.name) == "string" and #stage.name > 0,
            "stage " .. index .. " has a display name")
    end

    -- Every reference character maps to a compiled sht entry and a sheet.
    assert_equal(#Replay.CHARACTERS, 4, "four characters are offered")
    local sht = require("tnr.legacy_replay.data.th15_sht")
    for _, character in ipairs(Replay.CHARACTERS) do
        assert_true(sht[character.key] ~= nil,
            character.key .. " has an sht definition")
        assert_equal(character.sheet,
            string.format("pl%02d", ({ reimu = 0, marisa = 1, sanae = 2, reisen = 3 })[character.key]),
            character.key .. " maps to its player sheet")
    end

    -- Two rulesets are offered.
    assert_equal(#Replay.MODES, 2, "two rulesets are offered")
    local keys = {}
    for _, mode in ipairs(Replay.MODES) do keys[mode.key] = true end
    assert_true(keys.modern, "the modern ruleset is offered")
    assert_true(keys.classic, "the classic ruleset is offered")

    -- Cursors wrap around in both directions.
    local replay = Replay.new({})
    replay:move_cursor("stage", -1, #Replay.STAGES)
    assert_equal(replay.stage_cursor, 7, "moving up from the first stage wraps to the last")
    replay:move_cursor("stage", 1, #Replay.STAGES)
    assert_equal(replay.stage_cursor, 1, "moving down from the last stage wraps to the first")
    assert_equal(replay:selected_stage().key, "st01", "the selection reads back")

    -- A selected mode and character read back.
    replay.mode_cursor = 2
    assert_equal(replay:selected_mode().key, "classic", "the classic mode reads back")
    replay.character_cursor = 2
    assert_equal(replay:selected_character().key, "marisa", "the character reads back")

    -- Effects: each kind resolves to an archive entry and plays its script.
    local Effects = require("tnr.legacy_replay.effects")
    local anm = require("tnr.legacy_replay.data.th15_anm")
    local effects = Effects.new({ anm = anm })
    local death = effects:spawn(Effects.KIND.ENEMY_DEATH, 0, 0)
    assert_true(death ~= nil, "the enemy death effect resolves")
    -- The reference's death effect runs for 81 frames and grows from half size
    -- to five and a half, so the ring expands instead of blinking out.
    assert_true(death.duration > 60, "the death effect lasts as long as the reference")
    assert_equal(effects:count(), 1, "the effect is tracked")
    local _, first_scale = effects:sprite_for(death)
    death.timer = 30
    local _, grown_scale = effects:sprite_for(death)
    assert_true(grown_scale > first_scale, "the death effect grows across its life")
    for _ = 1, death.duration + 2 do effects:update() end
    assert_equal(effects:count(), 0, "the effect expires")
    -- An unknown kind is refused rather than tracked.
    assert_true(effects:spawn("not_a_kind", 0, 0) == nil, "an unknown effect is refused")

    -- Rewards: the modern ruleset offers two rounds of three picks, and the
    -- classic ruleset none.
    assert_true(#Replay.REWARDS >= 3, "at least three reward kinds exist")
    local replay = Replay.new({})
    -- Without a cleared result there are no rewards.
    assert_true(replay:next_reward_round() == nil, "no rewards before a clear")
    replay.last_result = { outcome = "cleared" }
    replay.runtime = { session = { reward_rounds = function() return 2 end }, frames = 0,
        stats = {}, players = {} }
    local first = replay:next_reward_round()
    assert_true(first ~= nil, "the first reward round exists")
    assert_equal(#first, 3, "a round offers three choices")
    assert_equal(replay.reward_round, 1, "the round counter advances")
    local second = replay:next_reward_round()
    assert_true(second ~= nil, "the second reward round exists")
    assert_true(replay:next_reward_round() == nil, "there is no third round")
end
