-- Floor-aware boss / elite pools.
--
-- The auto-generated `boss_floor_pools.lua` assigns every full boss to one of
-- three floors (1 = lightest, 3 = heaviest) by measured card count and card
-- HP, and every short "elite" boss likewise. This module turns those sets into
-- a query the native room selector can use.

local Pools = require("tnr.stages.boss_floor_pools")

local BossPools = {}

BossPools.MIN_FLOOR = 1
BossPools.MAX_FLOOR = 3

local function clamp_floor(floor)
    floor = math.floor(tonumber(floor) or 1)
    if floor < BossPools.MIN_FLOOR then return BossPools.MIN_FLOOR end
    if floor > BossPools.MAX_FLOOR then return BossPools.MAX_FLOOR end
    return floor
end

--- Is this legacy boss class part of the given floor's boss pool?
function BossPools.is_floor_boss(legacy_boss, floor)
    local set = Pools.bosses and Pools.bosses[clamp_floor(floor)]
    return set ~= nil and set[legacy_boss] == true
end

--- Is this legacy boss class part of the given floor's elite pool?
function BossPools.is_floor_elite(legacy_boss, floor)
    local set = Pools.elites and Pools.elites[clamp_floor(floor)]
    return set ~= nil and set[legacy_boss] == true
end

--- Every legacy boss class in the given floor's boss pool (sorted).
function BossPools.boss_list(floor)
    local set = Pools.bosses and Pools.bosses[clamp_floor(floor)] or {}
    local result = {}
    for name in pairs(set) do result[#result + 1] = name end
    table.sort(result)
    return result
end

--- Every legacy boss class in the given floor's elite pool (sorted).
function BossPools.elite_list(floor)
    local set = Pools.elites and Pools.elites[clamp_floor(floor)] or {}
    local result = {}
    for name in pairs(set) do result[#result + 1] = name end
    table.sort(result)
    return result
end

return BossPools
