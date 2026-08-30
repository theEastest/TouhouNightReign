-- Centralized movement policy for equipment weight.  This module is pure
-- data/math so both native and fallback runtimes can use the same result.
local Policy = {}

function Policy.classify(weight, capacity)
    weight = math.max(0, tonumber(weight) or 0)
    capacity = math.max(0, tonumber(capacity) or 0)
    if capacity <= 0 then
        return weight > 0 and "OVERLOAD" or "NORMAL"
    end
    if weight < capacity * 0.5 then return "ULTRALIGHT" end
    if weight <= capacity then return "NORMAL" end
    return "OVERLOAD"
end

function Policy.high_speed(base_speed, capacity, weight)
    base_speed = math.max(0, tonumber(base_speed) or 0)
    capacity = math.max(0, tonumber(capacity) or 0)
    weight = math.max(0, tonumber(weight) or 0)
    if capacity <= 0 then
        return weight > 0 and 0 or base_speed
    end
    if weight < capacity * 0.5 then return base_speed * 2 end
    if weight <= capacity then return base_speed end
    return base_speed * capacity / weight
end

function Policy.resolve(base_high_speed, base_low_speed, capacity, weight)
    return {
        weight = math.max(0, tonumber(weight) or 0),
        capacity = math.max(0, tonumber(capacity) or 0),
        high_speed = Policy.high_speed(base_high_speed, capacity, weight),
        low_speed = math.max(0, tonumber(base_low_speed) or 0),
        class = Policy.classify(weight, capacity),
    }
end

return Policy
