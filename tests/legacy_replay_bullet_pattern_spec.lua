-- Tests for the reference bullet pattern geometry.
--
-- The original games do not store a per-bullet angle. They store one parameter
-- block and generate the volley from it, and the aim mode decides the shape.
-- These tests pin that generator against the reference formulas, because a
-- wrong fan or ring is exactly the kind of error that makes imported danmaku
-- look nothing like the original.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local Patterns = require("tnr.legacy_replay.bullet_patterns")

    local function close(a, b, message)
        assert_true(math.abs(a - b) <= 1e-5,
            string.format("%s: expected %.5f got %.5f", message, b, a))
    end

    -- Fan with an odd count: the centre bullet points straight ahead and each
    -- pair widens by one step, alternating sides.
    local odd = Patterns.expand({ count1 = 5, count2 = 1, speed1 = 3, speed2 = 3,
        angle1 = 0, angle2 = 0.2, mode = Patterns.MODE.FAN })
    assert_equal(#odd, 5, "the fan fires its count")
    local expected_odd = { 0.0, -0.2, 0.2, -0.4, 0.4 }
    for index, value in ipairs(expected_odd) do
        close(odd[index].angle, value, "odd fan bullet " .. index)
    end

    -- Fan with an even count: no centre bullet, the pair straddles the line.
    local even = Patterns.expand({ count1 = 4, count2 = 1, speed1 = 3, speed2 = 3,
        angle1 = 0, angle2 = 0.2, mode = Patterns.MODE.FAN })
    local expected_even = { 0.1, -0.1, 0.3, -0.3 }
    for index, value in ipairs(expected_even) do
        close(even[index].angle, value, "even fan bullet " .. index)
    end

    -- A ring spreads its bullets evenly around a full turn.
    local ring = Patterns.expand({ count1 = 4, count2 = 1, speed1 = 3, speed2 = 3,
        angle1 = 0, angle2 = 0, mode = Patterns.MODE.CIRCLE })
    for index = 1, 4 do
        close(ring[index].angle, (index - 1) * math.pi / 2, "ring bullet " .. index)
    end

    -- An offset ring is shifted half a bullet, so two rings interleave.
    local offset = Patterns.expand({ count1 = 4, count2 = 1, speed1 = 3, speed2 = 3,
        angle1 = 0, angle2 = 0, mode = Patterns.MODE.OFFSET_CIRCLE })
    close(offset[1].angle, math.pi / 4, "the offset ring starts half a bullet along")

    -- Speed steps linearly from the first ring to the last, which is what makes
    -- an expanding or contracting spiral.
    local spiral = Patterns.expand({ count1 = 1, count2 = 3, speed1 = 6, speed2 = 0,
        angle1 = 0, angle2 = 0, mode = Patterns.MODE.CIRCLE })
    close(spiral[1].speed, 6, "the first ring uses the outer speed")
    close(spiral[2].speed, 4, "the middle ring is halfway")
    close(spiral[3].speed, 2, "the last ring approaches the inner speed")

    -- The ring offset advances each ring by the angle step.
    local stacked = Patterns.expand({ count1 = 1, count2 = 2, speed1 = 3, speed2 = 3,
        angle1 = 0.5, angle2 = 0.25, mode = Patterns.MODE.CIRCLE })
    close(stacked[1].angle, 0.5, "the first ring uses the base angle")
    close(stacked[2].angle, 0.75, "the second ring is one step further")

    -- The aimed modes add the angle to the player.
    local aimed = Patterns.expand({ count1 = 1, count2 = 1, speed1 = 3, speed2 = 3,
        angle1 = 0, angle2 = 0, mode = Patterns.MODE.CIRCLE_AIMED, aim_angle = 1.0 })
    close(aimed[1].angle, 1.0, "the aimed ring faces the player")

    -- An empty volley is impossible: a zero count is clamped to one.
    local single = Patterns.expand({ count1 = 0, count2 = 0, speed1 = 3, speed2 = 3,
        angle1 = 0, angle2 = 0, mode = Patterns.MODE.CIRCLE })
    assert_equal(#single, 1, "a zero count still fires one bullet")

    -- The th15 modes above the reference range still form a ring.
    for _, mode in ipairs({ 9, 10, 11 }) do
        local extra = Patterns.expand({ count1 = 4, count2 = 1, speed1 = 3, speed2 = 3,
            angle1 = 0, angle2 = 0, mode = mode })
        assert_equal(#extra, 4, "mode " .. mode .. " fires its count")
        local seen = {}
        for _, bullet in ipairs(extra) do seen[math.floor(bullet.angle * 1000)] = true end
        local distinct = 0
        for _ in pairs(seen) do distinct = distinct + 1 end
        assert_equal(distinct, 4, "mode " .. mode .. " spreads its bullets")
    end
end
