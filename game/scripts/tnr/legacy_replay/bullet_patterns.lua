-- Reference bullet pattern geometry.
--
-- The original games do not store a bullet's angle and speed per bullet. They
-- store one small block of parameters and generate the whole volley from it:
-- a count pair, a speed pair, an angle pair and an aim mode. The mode decides
-- the geometry of the ring or fan, and the counts decide how many rings and how
-- many bullets per ring.
--
-- Modes 0..10 follow TH15's native generator at 0x41a600. Mode 11 remains
-- an approximation and is not used by the regular six-stage scripts.
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
    -- TH15's paired-spoke ring variants (9/10), then the unused mode 11.
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
    local count1 = math.max(0, math.floor(tonumber(options.count1) or 1))
    local count2 = math.max(0, math.floor(tonumber(options.count2) or 1))
    local speed1 = tonumber(options.speed1) or 0
    local speed2 = tonumber(options.speed2) or speed1
    local angle1 = tonumber(options.angle1) or 0
    local angle2 = tonumber(options.angle2) or 0
    local mode = math.floor(tonumber(options.mode) or Patterns.MODE.CIRCLE)
    -- Modes above the reference range behave as an aimed ring with the per-ring
    -- offset the ECL supplies.
    if mode == Patterns.MODE.EXTRA_RING_D then
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
        -- TH15 41a683..41a6c4 includes both speed endpoints.
        local speed = count2>1 and speed1+(speed2-speed1)*ring/(count2-1) or speed1
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
                angle = angle + ring*angle2 + angle1
            elseif mode == Patterns.MODE.RANDOM_ANGLE then
                angle = random(angle1-angle2,angle1+angle2)
            elseif mode == Patterns.MODE.RANDOM_SPEED then
                speed = random(speed1,speed1+speed2)
                angle = angle + index * TWO_PI / count1
                angle = angle + ring * angle2 + angle1
            elseif mode == Patterns.MODE.RANDOM then
                angle = random(angle1-angle2,angle1+angle2)
                speed = random(speed1,speed1+speed2)
            elseif mode==9 or mode==10 then
                -- TH15 41ab55..41ac65: count2 forms alternating spokes at
                -- every point of the count1 ring, not successively rotated rings.
                local pair=math.floor((ring+(count2%2))/2)
                angle=index*TWO_PI/count1+(pair+(count2%2==0 and .5 or 0))*angle2
                if ring%2==1 then angle=-angle end
                angle=angle+angle1+(mode==9 and aim or 0)
                speed=count2>1 and speed1+(speed2-speed1)*pair*2/(count2-1) or speed1
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
