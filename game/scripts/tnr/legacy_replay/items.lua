-- Legacy replay items.
--
-- The reference drops power, point, big power and life items. Each falls, then
-- is attracted to the player along a curve, then is collected. The item sheet
-- carries a sprite per kind, and the item scripts animate the spin.
--
-- The kinds and their sprite indices come from the `bullet/item.png` entry of
-- the bullet archive; the animation scripts there are 124 and up.

local Items = {}

Items.__index = Items

-- Item kinds, matching the reference drop table.
--   power        small power, worth a fraction of a level
--   power_large  a full power level
--   point        score by the point rate
--   life         an extra life fragment
--   full_power   the F card, fills the meter
Items.KIND = {
    POWER = "power",
    POWER_LARGE = "power_large",
    POINT = "point",
    LIFE = "life",
    FULL_POWER = "full_power",
}

-- Animation ids in the item sheet for each kind.
local ITEM_ANIMATION = {
    power = 124,
    power_large = 125,
    point = 126,
    life = 127,
    full_power = 128,
}

Items.ITEM_ANIMATION = ITEM_ANIMATION

-- Fall and attract behaviour, in game units per frame.
local FALL_START = 1.6
local FALL_ACCEL = 0.05
local ATTRACT_SPEED_START = 4.0
local ATTRACT_SPEED_MAX = 12.0
local ATTRACT_DELAY = 30
local COLLECT_LINE = 128

---@param options table { player, field_bottom }
function Items.new(options)
    options = options or {}
    return setmetatable({
        player = options.player,
        field_bottom = options.field_bottom or 448,
        list = {},
        collected = {},
    }, Items)
end

--- Spawn an item at a position.
function Items:spawn(kind, x, y)
    local item = {
        kind = kind or Items.KIND.POWER,
        x = x, y = y,
        vy = -FALL_START,
        vx = 0,
        timer = 0,
        attracted = false,
        animation = ITEM_ANIMATION[kind] or ITEM_ANIMATION.power,
        animation_frame = 0,
    }
    self.list[#self.list + 1] = item
    return item
end

--- Spawn a reference drop from an ECL drop table.
-- The table is { power, faith, point }: the faith count becomes points and the
-- power count becomes power items, matching the reference distribution.
function Items:spawn_drop(drop, x, y)
    local power = tonumber(drop and drop[1]) or 0
    local faith = tonumber(drop and drop[2]) or 0
    local point = tonumber(drop and drop[3]) or 0
    local spawned = {}
    if power >= 400 then
        spawned[#spawned + 1] = self:spawn(Items.KIND.FULL_POWER, x, y)
    elseif power > 0 then
        local large = math.floor(power / 100)
        local small = power % 100
        for _ = 1, large do spawned[#spawned + 1] = self:spawn(Items.KIND.POWER_LARGE, x, y) end
        for _ = 1, small do spawned[#spawned + 1] = self:spawn(Items.KIND.POWER, x, y) end
    end
    for _ = 1, point + faith do
        spawned[#spawned + 1] = self:spawn(Items.KIND.POINT, x, y)
    end
    return spawned
end

--- Advance every item: fall, then curve toward the player, then be collected.
function Items:update()
    local player = self.player
    local remaining = {}
    for _, item in ipairs(self.list) do
        item.timer = item.timer + 1
        item.animation_frame = item.animation_frame + 1
        local collected = false
        if player then
            -- The reference attracts once the player is above the collect line
            -- or has been near the item for a while.
            local above_line = player.y <= COLLECT_LINE
            local close = math.abs(player.x - item.x) < player.itembox * 2
                and math.abs(player.y - item.y) < player.itembox * 2
            if above_line or close or item.attracted then
                item.attracted = true
            end
            if item.attracted and item.timer > ATTRACT_DELAY then
                local dx = player.x - item.x
                local dy = player.y - item.y
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance < 1 then
                    collected = true
                else
                    local speed = math.min(ATTRACT_SPEED_MAX,
                        ATTRACT_SPEED_START + item.timer * 0.1)
                    item.x = item.x + dx / distance * speed
                    item.y = item.y + dy / distance * speed
                end
                if player:collects(item.x, item.y) then collected = true end
            end
        end
        if not collected then
            -- Free fall with gravity.
            item.vy = item.vy - FALL_ACCEL
            item.y = item.y + item.vy
            if item.y < -16 then collected = true end
        end
        if collected then
            self.collected[#self.collected + 1] = item
        else
            remaining[#remaining + 1] = item
        end
    end
    self.list = remaining
end

--- Take the items collected since the last call.
function Items:drain_collected()
    local result = self.collected
    self.collected = {}
    return result
end

function Items:count()
    return #self.list
end

Items.FALL_START = FALL_START
Items.COLLECT_LINE = COLLECT_LINE

return Items
