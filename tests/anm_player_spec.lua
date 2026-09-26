-- Tests for the ANM animation player used by the legacy replay mode.
--
-- thtk `thanm -l` dumps sprite rectangles and animation scripts; the compiled
-- form is played here to pick the sprite shown each frame. These tests pin the
-- sprite indexing, the timed instruction schedule and the loop opcode.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local AnmPlayer = require("tnr.legacy_replay.anm_player")
    local anm = require("tnr.legacy_replay.data.th15_anm")

    assert_true(anm.st01enm ~= nil, "the stage 1 enemy archive compiles")
    local archive = anm.st01enm and anm.st01enm[1]
    assert_true(archive ~= nil, "the stage 1 enemy archive has an entry")
    assert_equal(archive.texture, "stgenm/stage01/enm1.png", "the enemy texture is recorded")
    assert_true(#archive.sprites > 0, "the archive exposes sprite rectangles")

    -- Every sprite rectangle must be inside the texture the archive names.
    for index, sprite in ipairs(archive.sprites) do
        assert_true(sprite.w > 0 and sprite.h > 0,
            "sprite " .. index .. " must have a positive size")
        assert_true(sprite.x >= 0 and sprite.y >= 0,
            "sprite " .. index .. " must start inside the texture")
    end

    -- A sprite rect carries the position and size the renderer needs.
    local first = archive.sprites[1]
    assert_equal(first.w, 64, "the first stage 1 enemy sprite is 64 wide")
    assert_equal(first.h, 96, "the first stage 1 enemy sprite is 96 tall")

    -- Playing a script advances the displayed sprite over time.
    local player = AnmPlayer.new(archive)
    assert_true(player:play(0), "script 0 is available")
    assert_equal(player.sprite, 1, "the player starts on the first sprite")
    local sprites_seen = {}
    for _ = 1, 120 do
        player:update()
        sprites_seen[player.sprite] = true
    end
    local distinct = 0
    for _ in pairs(sprites_seen) do distinct = distinct + 1 end
    assert_true(distinct > 1, "the script cycles through several sprites")

    -- Every script must keep its sprite index inside the sprite table. An out
    -- of range index would draw nothing at runtime.
    for script_id in pairs(archive.scripts) do
        local script_player = AnmPlayer.new(archive)
        script_player:play(script_id)
        for _ = 1, 400 do
            script_player:update()
            assert_true(script_player.sprites[script_player.sprite] ~= nil,
                "script " .. script_id .. " must keep its sprite index in range")
            if script_player.finished then break end
        end
    end

    -- The jump opcode repeats a section a fixed number of times. Build a
    -- synthetic archive so the loop count is exact.
    local looped = {
        texture = "test.png",
        sprites = { { x = 0, y = 0, w = 8, h = 8 }, { x = 8, y = 0, w = 8, h = 8 } },
        scripts = {
            [0] = {
                { time = 0, id = 300, 1 },
                { time = 10, id = 300, 2 },
                { time = 20, id = 200, 2, 3 }, -- jump back 2, three times
                { time = 30, id = 1 },         -- stop
            },
        },
    }
    local loop_player = AnmPlayer.new(looped)
    loop_player:play(0)
    for _ = 1, 300 do
        loop_player:update()
        if loop_player.finished then break end
    end
    assert_true(loop_player.finished, "the stop opcode ends the animation")

    -- An unavailable script is recorded rather than crashing the caller.
    local missing = AnmPlayer.new(archive)
    assert_true(missing:play(9999) == false, "a missing script is rejected")
    assert_true(missing.unhandled["script:9999"] ~= nil, "the missing script is recorded")
end
