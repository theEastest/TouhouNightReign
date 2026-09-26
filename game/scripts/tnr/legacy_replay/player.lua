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

Player.__index = Player

-- Reference playfield dimensions, in game units.
local FIELD_HALF_WIDTH = 192
local FIELD_TOP = 0
local FIELD_BOTTOM = 448

---@param options table { definition, x, y, power }
function Player.new(options)
    options = options or {}
    local definition = options.definition or {}
    return setmetatable({
        definition = definition,
        x = options.x or 0,
        y = options.y or (FIELD_BOTTOM - 64),
        -- Power drives which shooter set fires. The reference stores it as a
        -- continuous value and picks a level from it.
        power = options.power or 0,
        focus = false,
        alive = true,
        invulnerable = 0,
        fire_timer = 0,
        -- Boxes come straight from the sht data.
        hitbox = definition.hitbox or 2,
        grazebox = definition.grazebox or 6,
        itembox = definition.itembox or 28,
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
    local level = math.floor((self.power or 0) / 100 * levels) + 1
    return math.max(1, math.min(levels, level))
end

--- Apply a movement input for one frame.
function Player:move(move_x, move_y, focus)
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
    self.x = self.x + dx * speed
    self.y = self.y - dy * speed
    -- Clamp to the field. The reference allows the ship a small margin against
    -- the walls, which the sprite half-width provides.
    local margin = 8
    self.x = math.max(-FIELD_HALF_WIDTH + margin, math.min(FIELD_HALF_WIDTH - margin, self.x))
    self.y = math.max(FIELD_TOP + margin, math.min(FIELD_BOTTOM - margin, self.y))
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

--- Option positions for the current focus state and power level.
--- Option positions for the current focus state and power level.
-- The reference does not snap the options between their unfocused and focused
-- layouts; it slides them over eight frames. Holding the button pops the
-- options forward and inwards, releasing lets them fall back out. Interpolating
-- is what makes the ship read as focusing rather than flickering between two
-- poses.
function Player:option_positions()
    local options = self.definition.options
    if not options then return {} end
    local focused = self.focus and options.focused or nil
    local unfocused = options.unfocused
    local level = self:power_level()
    local target = (focused and focused[level]) or (unfocused and unfocused[level]) or {}
    -- No smooth state recorded, or no discrete layouts to blend between them.
    local blend = self.focus_blend
    if blend == nil or blend <= 0 then return target end
    local other = (self.focus and unfocused) or focused
    local previous = other and other[level]
    if not previous or #previous == 0 then return target end
    -- blend is 0 at the previous layout and 1 at the target layout.
    local result = {}
    for index, entry in ipairs(target) do
        local from = previous[index] or entry
        result[index] = {
            (from[1] or 0) + ((entry[1] or 0) - (from[1] or 0)) * blend,
            (from[2] or 0) + ((entry[2] or 0) - (from[2] or 0)) * blend,
        }
    end
    return result
end

--- Advance the focus transition by one frame.
-- The reference moves the options over eight frames, so the blend runs from
-- zero to one across that span.
function Player:advance_focus_transition()
    local target = self.focus and 1 or 0
    local current = self.focus_blend or target
    if current == target then return end
    local step = 1 / 8
    if current < target then
        current = math.min(target, current + step)
    else
        current = math.max(target, current - step)
    end
    self.focus_blend = current
end

--- Fire one volley. Returns a list of bullet spawn descriptors.
-- The caller decides how to instantiate them, which keeps this module free of
-- the renderer and lets the adapter feed the engine directly.
function Player:fire()
    local set = self:current_shooters()
    if not set then return {} end
    local bullets = {}
    for _, source in ipairs(set.sources or {}) do
        bullets[#bullets + 1] = {
            x = self.x + (source.offset_x or 0),
            y = self.y + (source.offset_y or 0),
            -- The reference angles are already in radians with -pi/2 meaning
            -- straight up.
            angle = source.angle or -math.pi / 2,
            speed = source.speed or 24,
            damage = source.damage or 16,
            animation = source.animation,
        }
    end
    self.shots_fired = self.shots_fired + 1
    return bullets
end

--- Distance from a point to the player's hit box.
function Player:distance_to_hitbox(x, y)
    return math.sqrt((x - self.x) ^ 2 + (y - self.y) ^ 2)
end

--- True when a point is inside the graze box but outside the hit box.
function Player:grazes(x, y)
    if self.invulnerable > 0 then return false end
    local distance = self:distance_to_hitbox(x, y)
    return distance <= self.grazebox and distance > self.hitbox
end

--- True when a point hits the player.
function Player:hits(x, y)
    if self.invulnerable > 0 or not self.alive then return false end
    return self:distance_to_hitbox(x, y) <= self.hitbox
end

--- True when a point is within item collection range.
function Player:collects(x, y)
    return self:distance_to_hitbox(x, y) <= self.itembox
end

function Player:update()
    if self.invulnerable > 0 then self.invulnerable = self.invulnerable - 1 end
    self:advance_focus_transition()
end

--- Put the player into the post-hit state.
function Player:hit()
    self.alive = false
    self.invulnerable = 120
end

function Player:respawn(x, y)
    self.x = x or 0
    self.y = y or (FIELD_BOTTOM - 64)
    self.alive = true
    self.invulnerable = 180
end

Player.FIELD_HALF_WIDTH = FIELD_HALF_WIDTH
Player.FIELD_TOP = FIELD_TOP
Player.FIELD_BOTTOM = FIELD_BOTTOM

return Player
