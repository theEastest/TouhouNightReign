-- Legacy replay items.
--
-- The reference drops power, point, big power and life items. Each falls, then
-- is attracted to the player along a curve, then is collected. The item sheet
-- carries a sprite per kind, and the item scripts animate the spin.
--
-- The kinds and their sprite indices come from the `bullet/item.png` entry of
-- the bullet archive; the animation scripts there are 124 and up.

local Items = {}
local Rules = require("tnr.legacy_replay.reference_rules")
local float32 = Rules.float32
local atan2 = math.atan2 or math.atan

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
    power = 112, point = 113, power_large = 114,
    life_piece = 115, life = 116, bomb_piece = 117, bomb = 118,
    full_power = 119, graze = 123, cancel = 124,
}

Items.ITEM_ANIMATION = ITEM_ANIMATION

-- Fall and attract behaviour, in game units per frame.
local FALL_START = float32(2.2) -- native ordinary enemy drop: 428d39 / 424f7b
local DOWN_ANGLE = float32(math.pi / 2)
local FALL_ACCEL = float32(Rules.fall_accel)
local ATTRACT_ACCEL = float32(Rules.attract_accel)
local COLLECT_LINE = 128

---@param options table { player, field_bottom }
function Items.new(options)
    options = options or {}
    return setmetatable({
        player = options.player,
        field_bottom = options.field_bottom or 448,
        list = {},
        collected = {},
        slowdown = 1,
        spawn_serial = 0,
        random = options.random,
        visual_rng = require("tnr.core.rng").new(151),
    }, Items)
end

--- Spawn an item at a position.
function Items:spawn(kind, x, y, owner_id)
    if self.players and not owner_id then
        local first
        for id=1,2 do
            local item=self:spawn(kind,x,y,id)
            first=first or item
        end
        return first
    end
    if kind ~= "money" then self.spawn_serial = self.spawn_serial + 1 end
    local launched = kind == "graze" or kind == "cancel"
    local item = {
        kind = kind or Items.KIND.POWER,
        owner_player_id=owner_id,
        x = float32(launched and x or math.max(-192,math.min(192,x))), y = float32(y),
        vy = -FALL_START,
        vx = float32(math.cos(-DOWN_ANGLE) * FALL_START),
        timer = 0,
        attracted = false,
        animation = ITEM_ANIMATION[kind] or ITEM_ANIMATION.power,
        animation_frame = 0,
        -- Native state 5 counts down the low two bits of the spawn serial.
        -- The activation tick creates its sprite before motion starts.
        launch_delay = launched and self.spawn_serial % 4 + 1 or nil,
    }
    self.list[#self.list + 1] = item
    return item
end

-- TH15 stores the slowdown on ItemManager, shared by every item and player.
function Items:on_graze(owner_id)
    self.slowdown=float32(Rules.graze_slowdown)
end

function Items:spawn_launched(kind,x,y,owner_id,angle)
    -- TH15 419db0..419ddd and 41e5e0..41e616: signed +/-10 degrees.
    if not angle then
        local spread=math.pi/18
        local offset=self.random and self.random(-spread,spread) or (math.random()*2-1)*spread
        angle=float32(offset - DOWN_ANGLE)
    end
    if self.players and not owner_id then
        local first=self:spawn_launched(kind,x,y,1,angle)
        self:spawn_launched(kind,x,y,2,angle)
        return first
    end
    local item=self:spawn(kind,x,y,owner_id)
    angle=float32(angle)
    item.vx,item.vy=float32(math.cos(angle)*FALL_START),float32(math.sin(angle)*FALL_START)
    item.rising_graze=true
    return item
end

function Items:spawn_graze(x,y,owner_id,angle)
    return self:spawn_launched("graze",x,y,owner_id,angle)
end

function Items:spawn_miss_drops(x,y,owner_id)
    -- 454bef..454c98 aims the seven small P items at (0, y - 224).
    local dx,dy=-x,-224
    local scale=3/math.sqrt(dx*dx+dy*dy)
    for index=0,6 do
        local angle=index*math.pi/28-math.pi/8
        local cos,sin=math.cos(angle),math.sin(angle)
        local item=self:spawn("power",x,y,owner_id)
        item.vx=(dx*cos-dy*sin)*scale
        item.vy=(dx*sin+dy*cos)*scale
    end
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

local function attract(item,player,full)
    item.attracted=true
    item.auto_collect=full
    item.attract_speed=float32(player.attract_speed/(full and 1 or 3))
end

local function advance_attraction(item,player)
    local dx,dy=float32(player.x-item.x),float32(player.y-item.y)
    local angle=dx==0 and dy==0 and DOWN_ANGLE or float32(atan2(dy,dx))
    local speed=item.attract_speed or player.attract_speed
    item.vx=float32(math.cos(angle)*speed)
    item.vy=float32(math.sin(angle)*speed)
    item.x,item.y=float32(item.x+item.vx),float32(item.y+item.vy)
    -- 43fc9f/43fe0a compare the old speed before adding 0.2. At 5.0
    -- the last float32 increment takes the speed just above 12.
    if speed<Rules.attract_max then
        item.attract_speed=float32(speed+ATTRACT_ACCEL)
    end
end

local function advance_item(self, item, auto_collect)
    local player=self.players and self.players[item.owner_player_id] or self.player
    local collected = false
    local alive=player and player.alive~=false and not player.deathbomb_frames and not player.respawn_frames
    if not alive and item.attracted then
        item.attracted=false;item.auto_collect=false;item.vx=0;item.vy=0
    end
    item.slowed_visual=false;item.draw_offset_x=0;item.draw_offset_y=0
    if alive and not item.rising_graze and not item.auto_collect
            and (player.y<(player.collect_line or COLLECT_LINE) or (auto_collect and auto_collect[player.player_id])) then
        attract(item,player,true)
    end
    if item.attracted then
        advance_attraction(item,player)
    elseif item.rising_graze then
        -- 43fae9..43fb6d advances the launched graze item at full speed.
        -- Crossing the apex enters auto-collection in this same tick.
        item.x,item.y=float32(item.x+item.vx),float32(item.y+item.vy)
        item.vy=math.min(Rules.fall_max,float32(item.vy+FALL_ACCEL))
        if item.vy>=0 then
            item.vx=0
            if alive then
                item.rising_graze=false
                attract(item,player,true)
                advance_attraction(item,player)
            end
        end
    else
        local slow=self.slowdown or 1
        -- Native 43f9ee..43fa93: after 32 frames, slowed free-falling
        -- items turn pink and jitter by at most one pixel. This is a
        -- drawing offset only, and uses no gameplay/drop random numbers.
        if item.timer>=32 and slow<1 then
            item.slowed_visual=true
            item.draw_offset_x=self.visual_rng:next_float()*2-1
            item.draw_offset_y=self.visual_rng:next_float()*2-1
        end
        item.x=float32(item.x+float32(item.vx*slow))
        item.y=float32(item.y+float32(item.vy*slow))
        item.vy=math.min(Rules.fall_max,float32(item.vy+float32(FALL_ACCEL*slow)))
        if item.vy>=0 then item.vx=0 end
    end
    -- The original checks pickup after motion, then arms proximity homing
    -- for the next tick. Graze rewards complete their upward flight first.
    if alive and not item.rising_graze then
        collected=player:collects(item.x,item.y)
        if not collected and not item.attracted and item.kind~="graze" and item.kind~="cancel"
                and player:attracts(item.x,item.y) then
            attract(item,player,false)
        end
    end
    item.timer = item.timer + 1
    item.animation_frame = item.animation_frame + 1
    return collected
end

--- Advance every item: fall, then curve toward the player, then be collected.
function Items:update(auto_collect)
    local remaining = {}
    for _, item in ipairs(self.list) do
        if item.launch_delay then
            local delay = item.launch_delay - 1
            item.launch_delay = delay > 0 and delay or nil
            remaining[#remaining + 1] = item
        elseif advance_item(self, item, auto_collect) then
            self.collected[#self.collected + 1] = item
        elseif item.y <= self.field_bottom + 24 then
            remaining[#remaining + 1] = item
        end
    end
    self.list = remaining
    if self.slowdown<1 then
        self.slowdown=float32(self.slowdown+float32(Rules.slowdown_recovery))
    end
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
