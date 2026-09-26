-- Reference bullet pattern geometry.
--
-- The original games do not store a bullet's angle and speed per bullet. They
-- store one small block of parameters and generate the whole volley from it:
-- a count pair, a speed pair, an angle pair and an aim mode. The mode decides
-- the geometry of the ring or fan, and the counts decide how many rings and how
-- many bullets per ring.
--
-- This is the exact generator, transcribed from the reference bullet manager,
-- so a volley lands where the original put it rather than near it.
--
-- The aim mode is the second argument of the etAim ECL instruction.

local Patterns = {}

-- Aim modes, in the order the reference enumerates them. The number is what an
-- etAim call passes.
Patterns.MODE = {
    FAN_AIMED = 0,
    FAN = 1,
    CIRCLE_AIMED = 2,
    CIRCLE = 3,
    OFFSET_CIRCLE_AIMED = 4,
    OFFSET_CIRCLE = 5,
    RANDOM_ANGLE = 6,
    RANDOM_SPEED = 7,
    RANDOM = 8,
    -- th15 adds three modes above the reference range. They are ring variants
    -- with an extra per-ring offset; the closest reference behaviour is used so
    -- a volley still forms a ring instead of collapsing.
    EXTRA_RING_AIMED = 9,
    EXTRA_RING_C = 10,
    EXTRA_RING_D = 11,
}

local TWO_PI = math.pi * 2

--- Expand one volley into the bullets it fires.
--
-- Parameters mirror the reference shooter block:
--   count1, count2   bullets per ring and number of rings
--   speed1, speed2   the speed at the first ring and the last
--   angle1, angle2   the base angle and the step between bullets
--   mode             one of Patterns.MODE
--   aim_angle        the angle to the player, used by the aimed modes
--   random           a function returning a float in [min, max); injectable so
--                    tests and network peers stay deterministic
--
-- Returns a list of { angle = radians, speed = units_per_frame }.
function Patterns.expand(options)
    local count1 = math.max(1, math.floor(tonumber(options.count1) or 1))
    local count2 = math.max(1, math.floor(tonumber(options.count2) or 1))
    local speed1 = tonumber(options.speed1) or 0
    local speed2 = tonumber(options.speed2) or speed1
    local angle1 = tonumber(options.angle1) or 0
    local angle2 = tonumber(options.angle2) or 0
    local mode = math.floor(tonumber(options.mode) or Patterns.MODE.CIRCLE)
    -- Modes above the reference range behave as an aimed ring with the per-ring
    -- offset the ECL supplies.
    if mode == Patterns.MODE.EXTRA_RING_AIMED or mode == Patterns.MODE.EXTRA_RING_C
            or mode == Patterns.MODE.EXTRA_RING_D then
        mode = Patterns.MODE.CIRCLE_AIMED
    end
    local aim = tonumber(options.aim_angle) or 0
    local random = options.random or function(minimum, maximum)
        return minimum + math.random() * (maximum - minimum)
    end

    local bullets = {}
    for ring = 0, count2 - 1 do
        -- The speed steps linearly from the first ring to the last, which is
        -- what makes an expanding or contracting spiral.
        local speed = speed1 - (speed1 - speed2) * ring / count2
        for index = 0, count1 - 1 do
            local angle = 0
            if mode == Patterns.MODE.FAN or mode == Patterns.MODE.FAN_AIMED then
                -- A fan spreads outward from the centre in alternating
                -- directions, so an odd count puts a bullet straight ahead and
                -- an even count straddles the centre line. The index pairs are
                -- integer divisions: two bullets share each step.
                if count1 % 2 == 1 then
                    angle = (math.floor((index + 1) / 2)) * angle2
                else
                    angle = math.floor(index / 2) * angle2 + angle2 * 0.5
                end
                if index % 2 == 1 then angle = -angle end
                if mode == Patterns.MODE.FAN_AIMED then angle = angle + aim end
                angle = angle + angle1
            elseif mode == Patterns.MODE.CIRCLE or mode == Patterns.MODE.CIRCLE_AIMED then
                if mode == Patterns.MODE.CIRCLE_AIMED then angle = angle + aim end
                angle = angle + index * TWO_PI / count1
                angle = angle + ring * angle2 + angle1
            elseif mode == Patterns.MODE.OFFSET_CIRCLE
                or mode == Patterns.MODE.OFFSET_CIRCLE_AIMED then
                if mode == Patterns.MODE.OFFSET_CIRCLE_AIMED then angle = angle + aim end
                -- Half a bullet of offset makes the ring interleave with the
                -- previous one instead of overlapping it.
                angle = angle + math.pi / count1
                angle = angle + index * TWO_PI / count1
                angle = angle + angle1
            elseif mode == Patterns.MODE.RANDOM_ANGLE then
                angle = random(angle1 - angle2, angle1 - angle2 + angle2)
            elseif mode == Patterns.MODE.RANDOM_SPEED then
                speed = random(speed1 - speed2, speed1 - speed2 + speed2)
                angle = angle + index * TWO_PI / count1
                angle = angle + ring * angle2 + angle1
            elseif mode == Patterns.MODE.RANDOM then
                angle = random(angle1 - angle2, angle1 - angle2 + angle2)
                speed = random(speed1 - speed2, speed1 - speed2 + speed2)
            end
            bullets[#bullets + 1] = { angle = angle, speed = speed, ring = ring }
        end
    end
    return bullets
end

--- Normalize an angle into [0, 2pi).
function Patterns.normalize(angle)
    angle = angle % TWO_PI
    if angle < 0 then angle = angle + TWO_PI end
    return angle
end

return Patterns
