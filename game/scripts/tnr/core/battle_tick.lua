local RNG = require("tnr.core.rng")

local BattleTick = {}
BattleTick.__index = BattleTick

local STREAM_OFFSETS = {
    battle = 11,
    enemy = 23,
    boss = 37,
    pattern = 53,
    reward = 71,
    visual = 97,
}

local function stable_value(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "number" or value_type == "string" then
        return tostring(value)
    end
    if value_type ~= "table" then
        return "<" .. value_type .. ">"
    end
    seen = seen or {}
    if seen[value] then
        return "<cycle>"
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = stable_value(key, seen) .. "=" .. stable_value(value[key], seen)
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ";") .. "}"
end

local function hash_string(value)
    local hash = 2166136261
    for index = 1, #value do
        hash = (hash * 16777619 + string.byte(value, index)) % 4294967296
    end
    return string.format("%08x", hash)
end

function BattleTick.new(seed)
    seed = tonumber(seed) or 1
    local streams = {}
    for name, offset in pairs(STREAM_OFFSETS) do
        streams[name] = RNG.new(seed + offset)
    end
    return setmetatable({ tick = 0, seed = math.floor(seed), streams = streams }, BattleTick)
end

function BattleTick:advance()
    self.tick = self.tick + 1
    return self.tick
end

function BattleTick:get_rng(name)
    return assert(self.streams[name], "unknown battle RNG stream: " .. tostring(name))
end

function BattleTick:snapshot()
    local result = { tick = self.tick, seed = self.seed, streams = {} }
    for name, rng in pairs(self.streams) do
        result.streams[name] = rng.state
    end
    return result
end

function BattleTick:restore(snapshot)
    assert(type(snapshot) == "table", "battle tick snapshot is required")
    assert(type(snapshot.streams) == "table", "battle tick RNG streams are required")
    self.tick = math.max(0, math.floor(tonumber(snapshot.tick) or 0))
    self.seed = math.floor(tonumber(snapshot.seed) or self.seed)
    for name, rng in pairs(self.streams) do
        local state = snapshot.streams[name]
        assert(state ~= nil, "missing battle RNG stream: " .. tostring(name))
        rng.state = math.floor(tonumber(state) or 1) % 4294967296
        if rng.state == 0 then
            rng.state = 1
        end
    end
    return self
end

function BattleTick:hash(value)
    return hash_string(stable_value(value))
end

return BattleTick
