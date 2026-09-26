-- Tests for the etEx bullet effects block.
--
-- The reference stores an effects block on each bullet. The flags choose the
-- behaviour and the other fields parameterise it, so a wrong flag leaves a
-- bullet flying straight when the original bent it into a curve. These tests
-- pin the two behaviours the stage data actually asks for.

return function(assert_equal, assert_true, assert_false)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local Adapter = require("tnr.legacy_replay.adapter")

    -- The adapter advances bullets through advance_shots, which applies the
    -- effects first. Drive a recording that holds only the shots.
    local function make_adapter()
        local fake = { New = function() end }
        local adapter = Adapter.new({ lstg = fake, anm = {}, chunks = {} })
        return adapter
    end

    -- A bullet with no effects block keeps the straight path it was fired on.
    local adapter = make_adapter()
    adapter.shots = { { x = 0, y = 0, vx = 0, vy = -3, speed = 3, angle = -math.pi / 2 } }
    for _ = 1, 5 do adapter:advance_shots() end
    local straight = adapter.shots[1]
    assert_true(straight ~= nil, "a plain bullet survives")
    assert_equal(straight.x, 0, "a plain bullet does not drift sideways")
    assert_equal(straight.y, -15, "a plain bullet travels on its heading")

    -- Acceleration adds speed along the bullet's own heading.
    local accelerating = make_adapter()
    accelerating.shots = { {
        x = 0, y = 0, vx = 0, vy = -3, speed = 3, angle = -math.pi / 2,
        ex = { flags = 0x10, float1 = 1, float2 = -999999 },
    } }
    for _ = 1, 3 do accelerating:advance_shots() end
    local faster = accelerating.shots[1]
    assert_true(faster ~= nil, "an accelerating bullet survives")
    assert_true(faster.speed > 3, "acceleration raises the speed")

    -- The direction-change family turns the bullet on an interval.
    local turning = make_adapter()
    turning.shots = { {
        x = 0, y = 0, vx = 0, vy = -3, speed = 3, angle = -math.pi / 2,
        ex = { flags = 0x40, float1 = 0.25, int1 = 2, int2 = -1 },
    } }
    local first_angle = turning.shots[1].angle
    for _ = 1, 2 do turning:advance_shots() end
    local turned = turning.shots[1]
    assert_true(turned ~= nil, "a turning bullet survives")
    assert_true(math.abs(turned.angle - first_angle) > 1e-6,
        "the direction change turns the bullet")

    -- A rotation of zero on a turning bullet must not move it.
    local still = make_adapter()
    still.shots = { {
        x = 0, y = 0, vx = 0, vy = -3, speed = 3, angle = -math.pi / 2,
        ex = { flags = 0x40, float1 = 0, int1 = 1, int2 = -1 },
    } }
    local still_angle = still.shots[1].angle
    for _ = 1, 4 do still:advance_shots() end
    assert_true(math.abs(still.shots[1].angle - still_angle) < 1e-6,
        "a zero rotation leaves the heading alone")

    -- A flag of zero is inert even when the rest of the block is filled in.
    local inert = make_adapter()
    inert.shots = { {
        x = 0, y = 0, vx = 0, vy = -3, speed = 3, angle = -math.pi / 2,
        ex = { flags = 0, float1 = 9, int1 = 1, int2 = 1 },
    } }
    for _ = 1, 4 do inert:advance_shots() end
    assert_equal(inert.shots[1].x, 0, "flag zero does not accelerate")
    assert_equal(inert.shots[1].y, -12, "flag zero does not turn")

    -- A block whose fields are the sentinel leaves the bullet alone.
    local sentinel = make_adapter()
    sentinel.shots = { {
        x = 0, y = 0, vx = 0, vy = -3, speed = 3, angle = -math.pi / 2,
        ex = { flags = 0x10, float1 = -999999, float2 = -999999 },
    } }
    for _ = 1, 4 do sentinel:advance_shots() end
    assert_equal(sentinel.shots[1].speed, 3, "a sentinel rate does not accelerate")
end
