-- Area difficulty bonus.
--
-- Each floor scales enemy durability to build a difficulty curve independent
-- of the content tier of a wave:
--
--   floor 1: boss/elite attenuated, small enemies untouched
--   floor 2: neutral
--   floor 3: everything amplified
--
-- Small enemies are never attenuated (a lower floor removes only boss/elite
-- pressure); they are only amplified on the last floor.

local FloorBonus = {}

FloorBonus.boss = {
    [1] = 0.80,
    [2] = 1.00,
    [3] = 1.30,
}

FloorBonus.enemy = {
    [1] = 1.00,
    [2] = 1.00,
    [3] = 1.20,
}

local function clamp_floor(floor)
    floor = math.floor(tonumber(floor) or 1)
    if floor < 1 then return 1 end
    if floor > 3 then return 3 end
    return floor
end

--- HP multiplier for a boss or elite on the given floor.
function FloorBonus.boss_multiplier(floor)
    return FloorBonus.boss[clamp_floor(floor)] or 1.0
end

--- HP multiplier for a small enemy on the given floor.
function FloorBonus.enemy_multiplier(floor)
    return FloorBonus.enemy[clamp_floor(floor)] or 1.0
end

--- Apply the area bonus to an object's hp/maxhp in place.
--- Returns the applied multiplier (1.0 when nothing changed).
function FloorBonus.apply(object, floor, is_boss)
    if type(object) ~= "table" then return 1.0 end
    local multiplier = is_boss and FloorBonus.boss_multiplier(floor) or FloorBonus.enemy_multiplier(floor)
    if multiplier == 1.0 then return 1.0 end
    local maxhp = tonumber(object.maxhp)
    local hp = tonumber(object.hp)
    if maxhp and maxhp > 0 and maxhp < 100000000 then
        local scaled = math.max(1, math.floor(maxhp * multiplier + 0.5))
        -- Keep hp consistent with maxhp so the boss bar starts full.
        local ratio = (hp and maxhp > 0) and (hp / maxhp) or 1
        object.maxhp = scaled
        object.hp = math.max(1, math.floor(scaled * ratio + 0.5))
    elseif hp and hp > 0 and hp < 100000000 then
        object.hp = math.max(1, math.floor(hp * multiplier + 0.5))
    else
        return 1.0
    end
    return multiplier
end

return FloorBonus
