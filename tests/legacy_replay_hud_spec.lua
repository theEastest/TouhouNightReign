-- Tests for the reference HUD font and the boss presentation timings.
--
-- The HUD numbers are drawn from the ascii sheet, whose glyph grid is what
-- makes a digit line up. The spell cut-in and name plate follow fixed frame
-- counts taken from the reference portrait script. Both are pinned here.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local HudFont = require("tnr.legacy_replay.hud_font")
    local BossUi = require("tnr.legacy_replay.boss_ui")
    local PlayerAnimation = require("tnr.legacy_replay.player_animation")
    local anm = require("tnr.legacy_replay.data.th15_anm")

    -- The ascii sheet lays its glyphs out from code 33, so a character's sprite
    -- index is its code minus 32.
    -- The sheet has blank slots, so the map is derived from the image.
    assert_equal(HudFont.sprite_for("!"), 2, "the exclamation mark follows a blank slot")
    assert_equal(HudFont.sprite_for("/"), 16, "the slash precedes the digits")
    assert_equal(HudFont.sprite_for("0"), 17, "zero is sprite seventeen")
    assert_equal(HudFont.sprite_for("9"), 26, "nine is sprite twenty six")
    assert_equal(HudFont.sprite_for("A"), 34, "the capital A follows the digits")
    assert_equal(HudFont.sprite_for(" "), nil, "a space has no glyph")
    assert_equal(HudFont.sprite_for("\t"), nil, "a control character has no glyph")

    -- Layout advances one glyph per character and reports the total width.
    local draws, width = HudFont.layout("123456")
    assert_equal(#draws, 6, "six characters lay out six glyphs")
    assert_equal(width, 6 * HudFont.GLYPH_SIZE, "the width is six advances")
    assert_equal(draws[1].x, 0, "the first glyph sits at the origin")
    assert_equal(draws[2].x, HudFont.GLYPH_SIZE, "the second is one advance along")
    -- A space advances the pen without drawing.
    local spaced = HudFont.layout("1 2")
    assert_equal(#spaced, 2, "a space draws nothing")
    assert_equal(spaced[2].x, HudFont.GLYPH_SIZE * 2, "but still advances the pen")

    -- The cut-in timing constants match the reference portrait script.
    local ui = BossUi.new({ lstg = {} })
    ui:show_card("test")
    -- Fade plus slide plus hold.
    assert_equal(ui.card_timer, 15 + 15 + 120, "the cut-in lasts the scripted time")
    assert_equal(ui.card_elapsed, 0, "the cut-in starts at frame zero")
    -- The name plate bar length is fifteen half pixels per character plus 16.
    assert_true(math.abs(ui.card_bar_length - (#"test" * 15 / 2 + 16)) < 1e-6,
        "the name plate bar follows the reference formula")

    -- The player animation cycles through poses.
    local animation = PlayerAnimation.new(anm.pl00[1], "pl00")
    animation:update({ move_x = 0 })
    assert_equal(animation.script, PlayerAnimation.POSE.IDLE, "standing still idles")
    animation:update({ move_x = 0, shoot = true })
    assert_equal(animation.script, PlayerAnimation.POSE.FIRE, "shooting fires")
    animation:update({ move_x = 1 })
    assert_equal(animation.script, PlayerAnimation.POSE.SIDE_A, "moving sideways steps")
    -- Every pose keeps its sprite inside the sheet.
    for _, pose in ipairs({ 0, 1, 2, 3, 5 }) do
        local anim = PlayerAnimation.new(anm.pl00[1], "pl00")
        anim:play(pose)
        for _ = 1, 200 do
            anim:update(nil)
            assert_true(anm.pl00[1].sprites[anim.sprite] ~= nil,
                "pose " .. pose .. " keeps its sprite in range")
        end
    end
end
