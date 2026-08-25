local RNG = {}
RNG.__index = RNG

local UINT32 = 4294967296

local function normalize_seed(seed)
    seed = math.floor(tonumber(seed) or 1) % UINT32
    if seed == 0 then
        seed = 1
    end
    return seed
end

function RNG.new(seed)
    return setmetatable({ state = normalize_seed(seed) }, RNG)
end

function RNG:next_u32()
    local x = self.state
    x = (1664525 * x + 1013904223) % UINT32
    self.state = x
    return x
end

function RNG:next_float()
    return self:next_u32() / UINT32
end

function RNG:next_int(minimum, maximum)
    assert(minimum <= maximum, "invalid RNG range")
    return minimum + (self:next_u32() % (maximum - minimum + 1))
end

function RNG:chance(probability)
    return self:next_float() < probability
end

function RNG:shuffle(values)
    for index = #values, 2, -1 do
        local swap_index = self:next_int(1, index)
        values[index], values[swap_index] = values[swap_index], values[index]
    end
    return values
end

return RNG

