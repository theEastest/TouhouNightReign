-- Legacy replay player ship.
--
-- The reference player is defined by the stage's `.sht` data: a hit box, a
-- graze box, an item box, movement speeds for focused and unfocused states, and
-- a set of shooter sets — one per focus state and power level — that name every
-- bullet source with its offset, angle, speed and damage.
--
-- This module implements that model. It is deliberately independent of the
-- project's own roguelike ships so the replay keeps the original handling, and
-- it exposes the same three seams the mode interfaces expect: a position, a
-- fire method and a hit test.

local Player = {}
local Rules = require("tnr.legacy_replay.reference_rules")

Player.__index = Player

-- Reference playfield dimensions, in game units.
local FIELD_HALF_WIDTH = 192
local FIELD_TOP = 0
local FIELD_BOTTOM = 448

---@param options table { definition, x, y, power }
function Player.new(options)
    options = options or {}
    local definition = require("tnr.core.immutable").copy(options.definition or {})
    local native = Rules.players[definition.id] or Rules.players.reimu
    return setmetatable({
        definition = definition,
        x = options.x or 0,
        -- TH15 Player::initialize calls the position setter with (0, 400)
        -- at 0x453461. The field coordinate is measured downward from the top.
        y = options.y or 400,
        -- Power drives which shooter set fires. The reference stores it as a
        -- continuous value and picks a level from it.
        power = options.power or 0,
        focus = false,
        option_anchors = {},
        alive = true,
        invulnerable = 0,
        fire_timer = -1,
        long_fire_timer = -1,
        -- Player::initialize overwrites these SHT fields in the original.
        hitbox = native.hitbox,
        grazebox = Rules.graze_range,
        itembox = Rules.attract_half,
        pickup_half = Rules.pickup_half,
        attract_speed = native.attract_speed,
        collect_line = native.collect_line,
        graze = 0,
        shots_fired = 0,
    }, Player)
end

--- Movement speed for the current focus state, in units per frame.
function Player:speed()
    local definition = self.definition
    if self.focus then
        return definition.move_focused or 2.0
    end
    return definition.move_unfocused or 4.5
end

--- Power level, one-based, clamped to the definition's level count.
function Player:power_level()
    local levels = self.definition.power_levels or 4
    -- The reference divides power into four steps for the fire pattern.
    local level = math.floor((self.power or 0) / 100) + 1
    return math.max(1, math.min(levels + 1, level))
end

--- Apply a movement input for one frame.
function Player:move(move_x, move_y, focus, speed_scale)
    self.focus = focus == true
    -- Movement diagonals are stored as the per-axis speed for a diagonal input,
    -- so a diagonal move uses them directly on each axis. That keeps a diagonal
    -- the same total speed as a straight move, as the reference does.
    local speed = self:speed()
    local dx, dy = tonumber(move_x) or 0, tonumber(move_y) or 0
    if dx ~= 0 and dy ~= 0 then
        speed = self.focus
            and (self.definition.move_focused_diagonal or speed * 0.7071)
            or (self.definition.move_unfocused_diagonal or speed * 0.7071)
    end
    -- 453483..4534c9 truncates the SHT speed to 1/128 units.
    speed = math.modf(math.modf(speed * 128) * (speed_scale or 1)) / 128
    self.move_velocity_x = dx * speed
    self.x = self.x + dx * speed
    self.y = self.y - dy * speed
    -- 454583..4545d7 clamps x to [-184,184] and y to [32,432].
    self.x = math.max(-FIELD_HALF_WIDTH + 8, math.min(FIELD_HALF_WIDTH - 8, self.x))
    self.y = math.max(FIELD_TOP + 32, math.min(FIELD_BOTTOM - 16, self.y))
end

--- The shooter set for the current focus state and power level.
function Player:current_shooters()
    local sets = self.definition.shooters
    if not sets then return nil end
    local wanted = self.focus and "focused" or "unfocused"
    local level = self:power_level()
    -- Sets are ordered unfocused 1..N then focused 1..N.
    local seen = 0
    for _, entry in ipairs(sets) do
        if entry.kind == wanted then
            seen = seen + 1
            if seen == level then return entry end
        end
    end
    -- Fall back to the first set of the wanted kind.
    for _, entry in ipairs(sets) do
        if entry.kind == wanted then return entry end
    end
    return nil
end

local function option_layout(player)
    local options = player.definition.options or {}
    local mode = player.focus and "focused" or "unfocused"
    local layouts = options[mode] or options.unfocused or {}
    return layouts[player:power_level() - 1] or {}
end

--- Current option offsets relative to the ship.
function Player:option_positions()
    local result = {}
    for index, offset in ipairs(option_layout(self)) do
        local anchor = self.option_anchors[index]
        result[index] = anchor and { anchor[1] / 128 - self.x, anchor[2] / 128 - self.y } or offset
    end
    return result
end

function Player:update_options()
    local level=self:power_level()
    if self.option_previous_level and self.option_previous_level~=level then
        self.option_anchors={}
    end
    self.option_previous_level=level
    local layout = option_layout(self)
    for index, offset in ipairs(layout) do
        local x = math.modf(self.x * 128) + math.modf(offset[1] * 128)
        local y = math.modf(self.y * 128) + math.modf(offset[2] * 128)
        local anchor = self.option_anchors[index]
        if anchor then
            -- 4546e3..4547c0 approaches the world-space target by 30% in
            -- 1/128 units, including while the player moves without focusing.
            local dx = math.modf((x - anchor[1]) * 30 / 100)
            local dy = math.modf((y - anchor[2]) * 30 / 100)
            if dx ~= 0 or dy ~= 0 then
                x, y = anchor[1] + dx, anchor[2] + dy
            end
        end
        self.option_anchors[index] = { x, y }
    end
    for index = #self.option_anchors, #layout + 1, -1 do
        self.option_anchors[index] = nil
    end
end

local function advance_fire_timer(timer, period, held)
    if timer < 0 then return timer end
    if timer + 1 < period then return timer + 1 end
    return held and 0 or -1
end

function Player:stop_firing()
    self.fire_timer, self.long_fire_timer = -1, -1
end

--- Advance the trigger and return this frame's bullet spawn descriptors.
-- The caller decides how to instantiate them, which keeps this module free of
-- the renderer and lets the adapter feed the engine directly.
function Player:fire(held)
    if held == nil then held = true end
    -- 458de0 advances both clocks to their cycle boundary before testing
    -- whether a released trigger should stop them.
    local timer, long_timer = self.fire_timer, self.long_fire_timer
    if held and timer < 0 then
        timer = 0
        if long_timer < 0 then long_timer = 0 end
    end
    self.fire_timer = advance_fire_timer(timer, 15, held)
    self.long_fire_timer = advance_fire_timer(long_timer, 120, held)
    if timer < 0 then return {} end
    local set = self:current_shooters()
    if not set then return {} end
    local bullets = {}
    local options = self:option_positions()
    for _, source in ipairs(set.sources or {}) do
        local phase = source.fire_long and long_timer or timer
        local interval = math.max(1, source.fire_long or source.fire or 1)
        local delay = source.fire_long and (source.delay_long or 0) or (source.delay or 0)
        local offset = options[source.option or 0] or {0,0}
        if phase >= 0 and phase % interval == delay then
            local coordinate = source.callback_tick == 1 and Rules.float32 or Rules.motion_coordinate
            bullets[#bullets + 1] = {
                x = coordinate(self.x + offset[1] + (source.offset_x or 0)),
                y = coordinate(self.y + offset[2] + (source.offset_y or 0)),
                -- The reference angles are in radians with -pi/2 straight up.
                angle = source.angle or -math.pi / 2,
                speed = source.speed or 24,
                damage = source.damage or 16,
                animation = source.animation,
                hitbox_x = source.hitbox_x,
                hitbox_y = source.hitbox_y,
                -- Zero-speed Marisa sources are beams, not stationary pellets.
                beam_length = self.definition.id == "marisa" and source.speed == 0 and 560 or nil,
                lifetime = source.speed == 0 and interval or nil,
                radius = source.option and source.option > 0 and 4 or 2,
                callback_tick = source.callback_tick,
                owner_player_id = self.player_id,
            }
        end
    end
    self.shots_fired = self.shots_fired + 1
    return bullets
end

--- Distance from a point to the player's hit box.
function Player:distance_to_hitbox(x, y)
    return math.sqrt((x - self.x) ^ 2 + (y - self.y) ^ 2)
end

--- True when a point is inside the graze box but outside the hit box.
function Player:grazes(x, y, bullet_radius)
    if not self.alive then return false end
    local distance2 = (x-self.x)^2+(y-self.y)^2
    local radius = bullet_radius or 0
    local reach = math.max(self.grazebox,radius/2.5)+self.hitbox
    return distance2 < reach^2+radius^2 and distance2 >= self.hitbox^2+radius^2
end

--- True when a point hits the player.
function Player:hits(x, y, bullet_radius)
    return self.alive and self.invulnerable <= 0 and self:bullet_contact(x, y, bullet_radius)
end

--- Geometry only. The stage handles Bomb protection and miss states.
function Player:bullet_contact(x, y, bullet_radius)
    return (x-self.x)^2+(y-self.y)^2 < self.hitbox^2+(bullet_radius or 0)^2
end

--- True when a point is within item collection range.
function Player:collects(x, y)
    return math.abs(x-self.x)<=self.pickup_half and math.abs(y-self.y)<=self.pickup_half
end

function Player:attracts(x,y)
    local half=self.itembox*(self.focus and Rules.focus_attract_half/Rules.attract_half or 1)
    return math.abs(x-self.x)<=half and math.abs(y-self.y)<=half
end

function Player:update()
    if self.invulnerable > 0 then self.invulnerable = self.invulnerable - 1 end
    self:update_options()
end

--- Put the player into the post-hit state.
function Player:hit()
    self.alive = false
    self.invulnerable = 120
    self.deathbomb_frames, self.respawn_frames = nil, nil
end

function Player:respawn(x, y)
    self.x = x or 0
    self.y = y or 400
    self.alive = true
    self.invulnerable = 180
    self.option_anchors = {}
    self.deathbomb_frames, self.respawn_frames = nil, nil
end

Player.FIELD_HALF_WIDTH = FIELD_HALF_WIDTH
Player.FIELD_TOP = FIELD_TOP
Player.FIELD_BOTTOM = FIELD_BOTTOM

return Player
