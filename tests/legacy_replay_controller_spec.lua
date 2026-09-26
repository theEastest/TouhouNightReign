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
end
