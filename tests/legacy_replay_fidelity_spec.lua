-- Fidelity checks for the legacy replay rendering.
--
-- These verify the invariants the reference capture established: the playfield
-- geometry, the background layer stack, the per-stage fog tint and the sprite
-- resolution. They do not pixel-compare against the capture (that needs the
-- engine), but they pin every number the comparison relies on, so a regression
-- that would move the field or drop the tint fails here.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local BossUi = require("tnr.legacy_replay.boss_ui")
    local StageBackground = require("tnr.legacy_replay.stage_background")
    local StageRuntime = require("tnr.legacy_replay.stage_runtime")
    local anm = require("tnr.legacy_replay.data.th15_anm")
    local std = require("tnr.legacy_replay.data.th15_std")

    local function close(a, b, tolerance, message)
        assert_true(math.abs(a - b) <= (tolerance or 0.5),
            string.format("%s: expected %.2f got %.2f", message, b, a))
    end

    -- Playfield geometry measured from the original capture. The field is
    -- 384x448 units at (37.2, 17.8)-(499.2, 556.8) in the 1280x720 canvas.
    close(BossUi.PLAYFIELD_LEFT, 37.2, 0.1, "playfield left")
    close(BossUi.PLAYFIELD_RIGHT, 499.2, 0.1, "playfield right")
    close(BossUi.PLAYFIELD_BOTTOM, 17.8, 0.1, "playfield bottom")
    close(BossUi.PLAYFIELD_TOP, 556.8, 0.1, "playfield top")
    -- The field must keep the reference 384:448 aspect ratio exactly.
    local width = BossUi.PLAYFIELD_RIGHT - BossUi.PLAYFIELD_LEFT
    local height = BossUi.PLAYFIELD_TOP - BossUi.PLAYFIELD_BOTTOM
    close(width / height, 384 / 448, 0.001, "playfield aspect ratio")
    close(width / 384, BossUi.PLAYFIELD_SCALE, 0.0001, "px per game unit")

    -- Projection round trip: the field centre and the top left corner.
    local cx, cy = BossUi.project(0, 0)
    close(cx, BossUi.PLAYFIELD_LEFT + 192 * BossUi.PLAYFIELD_SCALE, 0.1, "field centre x")
    close(cy, BossUi.PLAYFIELD_TOP, 0.1, "field centre y sits at the top edge")

    -- Reference sprite sizes carried by the archive.
    local entry = anm.st01enm and anm.st01enm[1]
    assert_true(entry ~= nil, "stage 1 enemy archive compiles")
    assert_equal(entry.sprites[1].w, 64, "enemy sprite width from the reference")
    assert_equal(entry.sprites[1].h, 96, "enemy sprite height from the reference")

    -- Background layers: stage 1 has seven std entries, the first being the
    -- opaque forest base and the rest scrolling cloud detail.
    assert_true(#std.st01 == 7, "stage 1 exposes seven background entries")
    local background = StageBackground.new({
        lstg = {}, anm = anm, std = std,
        image_for = function(path) return path end,
        -- The reference st01a texture is 512x512 even though the anm header
        -- claims 1024x512; the renderer must use the real size.
        texture_sizes = { ["background/stage01/st01a.png"] = { 512, 512 },
                          ["background/stage01/st01d.png"] = { 256, 256 } },
    })
    background:set_stage("st01")
    assert_equal(#background.layers, 7, "every background entry becomes a layer")
    assert_true(background.layers[1].base, "the first layer is the base")
    assert_true(not background.layers[2].base, "the rest are detail layers")
    -- The base is opaque; the detail layers are translucent.
    assert_equal(background.layers[1].alpha, 255, "the base layer is opaque")
    assert_true(background.layers[2].alpha < 255, "detail layers are translucent")
    -- Stage 1 must carry the violet fog measured from the capture.
    assert_true(background.tint ~= nil, "stage 1 has a fog tint")
    assert_equal(background.tint[1], 203, "fog tint red")
    assert_equal(background.tint[2], 78, "fog tint green")
    assert_equal(background.tint[3], 199, "fog tint blue")

    -- Image naming: the loader and the renderer must agree on the pattern.
    assert_equal(StageRuntime.image_name("st01enm", 1, 3), "tnr-th15-st01enm-1-3",
        "sprite image naming")

    -- Every stage must expose a background layout.
    for _, stage in ipairs({ "st01", "st02", "st03", "st04", "st05", "st06", "st07" }) do
        assert_true(std[stage] ~= nil, stage .. " must have a background config")
        local bg = StageBackground.new({
            lstg = {}, anm = anm, std = std,
            image_for = function(path) return path end,
            texture_sizes = {},
        })
        bg:set_stage(stage)
        assert_true(#bg.layers > 0, stage .. " must build at least one layer")
    end
end
