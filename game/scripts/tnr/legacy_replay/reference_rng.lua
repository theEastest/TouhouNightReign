-- TH15 1.00b, 0x403630 and 0x4036a0. The 32-bit draw concatenates the two
-- mixed words before rotation, even though each rotation updates the state.
local Rng = {}
Rng.__index = Rng
local float32 = require("tnr.legacy_replay.reference_rules").float32

local WORD = 0x10000
local DWORD = 0x100000000
local XOR_BITS = {0x8000, 0x1000, 0x0400, 0x0200, 0x0020, 0x0010}

function Rng.new(seed)
    return setmetatable({state = math.floor(tonumber(seed) or 151) % WORD, draws = 0}, Rng)
end

local function step(rng)
    local state = rng.state
    local mixed = state
    -- XOR with the constant 0x9630, including on Lua builds without bit32.
    for _, bit in ipairs(XOR_BITS) do
        mixed = mixed + (1 - 2 * (math.floor(state / bit) % 2)) * bit
    end
    mixed = (mixed - 0x6553) % WORD
    rng.state = (mixed * 4 + math.floor(mixed / 0x4000)) % WORD
    rng.draws = rng.draws + 1
    return mixed
end

function Rng:next_u16()
    step(self)
    return self.state
end

function Rng:next_u32()
    local high = step(self)
    return high * WORD + step(self)
end

function Rng:next_float()
    return float32(self:next_u32()) / DWORD
end

function Rng:range(low, high)
    local value = self:next_float()
    if low == -high then
        -- 0x403840 rounds the signed draw before the caller scales it.
        return float32(float32(value * 2 - 1) * float32(high))
    end
    return low + (high - low) * value
end

return Rng
