-- Source-data and rendering regressions. Passing these is not a visual acceptance test.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local BossUi = require("tnr.legacy_replay.boss_ui")
    local StageBackground = require("tnr.legacy_replay.stage_background")
    local StageRuntime = require("tnr.legacy_replay.stage_runtime")
    local anm = require("tnr.legacy_replay.data.th15_anm")
    local std = require("tnr.legacy_replay.data.th15_std")
    local face_entry
    for i, source in ipairs(anm.pl00) do
        if source.texture == "face/pl00/face_pl00pr.png" then face_entry = i end
    end
    local face_load
    StageRuntime.load_stage_assets({
        LoadTexture = function() end,
        GetTextureSize = function() return 2048, 2048 end,
        LoadImage = function(name, texture, x, y, w, h)
            if name == StageRuntime.image_name("pl00", face_entry, 1) then face_load = {x,y,w,h} end
        end,
    }, "st01", anm, {})
    assert_equal(face_load[1], 340, "portrait extraction canvas X offset is applied")
    assert_equal(face_load[2], 54, "portrait extraction canvas Y offset is applied")
    assert_equal(face_load[3], 236, "portrait rectangle keeps its unpadded width")

    local function close(a, b, tolerance, message)
        assert_true(math.abs(a - b) <= (tolerance or 0.5),
            string.format("%s: expected %.2f got %.2f", message, b, a))
    end

    -- Playfield geometry measured from the original capture. The field is
    -- Source front00 border strips: 64/768/448 px across a 1280x960 canvas.
    -- Fit at 0.75 scale, centred horizontally in the project's 1280x720.
    close(BossUi.PLAYFIELD_LEFT, 208, 0.1, "playfield left")
    close(BossUi.PLAYFIELD_RIGHT, 784, 0.1, "playfield right")
    close(BossUi.PLAYFIELD_BOTTOM, 24, 0.1, "playfield bottom")
    close(BossUi.PLAYFIELD_TOP, 696, 0.1, "playfield top")
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
    -- Source STD coordinates and camera transitions, not colours fitted to an
    -- unrelated screenshot. These checks do not certify visual fidelity.
    assert_equal(background.tint, nil, "no fixed violet overlay")
    assert_equal(std.st01[1].faces[1].x, 0, "instance x")
    assert_equal(std.st01[1].faces[1].y, -128, "instance y")
    assert_equal(std.st01[1].quads[1].position[3], 300, "quad depth")
    assert_equal(background.camera.position[3], -600, "opening camera depth")
    for _ = 1, 200 do background:update() end
    close(background.layers[5].alpha, 64, 0.001, "cloud alpha interpolates instead of moving")
    close(background.layers[2].position[1], 16 * 2 / 9, 0.001, "cloud uses mode 9 position interpolation")
    for _ = 201, 390 do background:update() end
    close(background.camera.position[2], 512, 0.001, "camera reset at frame 390")
    close(background.camera.position[3], -400, 0.001, "camera arrives at target depth")
    for _ = 391, 6230 do background:update() end
    assert_equal(background.camera.time, 5830, "STD jumps to its source timestamp")
    for _ = 1, 800 do background:update() end
    assert_equal(background.camera.time, 5830, "STD loop remains stable")

    -- Image naming: the loader and the renderer must agree on the pattern.
    assert_equal(StageRuntime.image_name("st01enm", 1, 3), "tnr-th15-st01enm-1-3",
        "sprite image naming")
    local renderer = setmetatable({anm = anm}, StageRuntime)
    local blue_ring, ring_w = renderer:bullet_image({sprite = 4, color_index = 6})
    assert_equal(blue_ring, "tnr-th15-bullet-1-71", "type 4 blue colour selects sprite 70, not script 4")
    assert_equal(ring_w, 16, "ring uses source sprite width")
    local big_ball = renderer:bullet_image({sprite = 18, color_index = 0})
    assert_equal(big_ball, "tnr-th15-bullet-2-1", "global sprite 368 resolves into second sheet")
    local spawning = {sprite = 4, color_index = 6, ex = {flags = 2, int1 = 1}, anim_frame = 8}
    local spawn_image = renderer:bullet_image(spawning)
    assert_true(spawn_image ~= blue_ring, "spawn effect uses its own descriptor sprite")
    close(spawning.legacy_bullet_animation.alpha, 136, 0.001, "spawn alpha follows ANM duration")
    spawning.anim_frame = 16
    assert_equal(renderer:bullet_image(spawning), blue_ring, "spawn jump reaches live bullet body")
    close(spawning.legacy_bullet_animation.alpha, 255, 0.001, "live bullet is opaque")

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
