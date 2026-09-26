-- Legacy replay visual effects.
--
-- The reference spawns short lived effect objects when an enemy dies or a
-- bullet breaks. Each is a small animation on the effect sheet that plays once
-- and disappears. This module keeps a simple list of those so the renderer can
-- draw them without an object per effect.
--
-- Effect ids come from the stage effect archive.

local Effects = {}

Effects.__index = Effects

-- Effect kinds, mapped to the archive entry and the sprite range they play.
-- The entries are looked up by texture suffix so a different stage archive with
-- the same layout still resolves.
Effects.KIND = {
    ENEMY_DEATH = "enemy_death",
    BULLET_BREAK = "bullet_break",
}

local EFFECT_TEXTURES = {
    enemy_death = "eff_deadcircle.png",
    bullet_break = "eff_breakwave2.png",
}

Effects.EFFECT_TEXTURES = EFFECT_TEXTURES

-- How long an effect lasts, in frames, and how many frames each sprite shows.
local ENEMY_DEATH_FRAMES = 24
local BULLET_BREAK_FRAMES = 18
local FRAMES_PER_SPRITE = 4

---@param options table { anm }
function Effects.new(options)
    options = options or {}
    return setmetatable({
        anm = options.anm or {},
        list = {},
    }, Effects)
end

--- Resolve the effect archive entry for a kind.
function Effects:entry_for(kind)
    self.entry_cache = self.entry_cache or {}
    if self.entry_cache[kind] ~= nil then return self.entry_cache[kind] end
    local suffix = EFFECT_TEXTURES[kind]
    local result = nil
    if suffix then
        for entry_index, entry in ipairs(self.anm.effect or {}) do
            if entry.texture and entry.texture:sub(-#suffix) == suffix then
                result = { entry = entry_index, count = #entry.sprites }
                break
            end
        end
    end
    self.entry_cache[kind] = result
    return result
end

--- Spawn an effect at a position.
function Effects:spawn(kind, x, y, scale)
    local info = self:entry_for(kind)
    if not info then return nil end
    local total = kind == Effects.KIND.BULLET_BREAK and BULLET_BREAK_FRAMES or ENEMY_DEATH_FRAMES
    local effect = {
        kind = kind,
        x = x, y = y,
        timer = 0,
        duration = total,
        entry = info.entry,
        sprites = info.count,
        scale = scale or 1,
    }
    -- Cap the list so a busy frame cannot grow it without bound.
    if #self.list < 256 then self.list[#self.list + 1] = effect end
    return effect
end

--- Advance every effect and drop the finished ones.
function Effects:update()
    local remaining = {}
    for _, effect in ipairs(self.list) do
        effect.timer = effect.timer + 1
        if effect.timer < effect.duration then remaining[#remaining + 1] = effect end
    end
    self.list = remaining
end

--- The sprite index and alpha an effect shows right now.
function Effects:sprite_for(effect)
    local steps = math.max(1, math.floor(effect.duration / FRAMES_PER_SPRITE))
    local index = math.min(effect.sprites or 1, math.floor(effect.timer / FRAMES_PER_SPRITE) + 1)
    -- Fade out over the last third.
    local alpha = 255
    local fade_start = effect.duration * 2 / 3
    if effect.timer > fade_start then
        alpha = math.floor(255 * (effect.duration - effect.timer) / (effect.duration - fade_start))
    end
    return index, alpha
end

function Effects:count()
    return #self.list
end

Effects.ENEMY_DEATH_FRAMES = ENEMY_DEATH_FRAMES
Effects.BULLET_BREAK_FRAMES = BULLET_BREAK_FRAMES

return Effects
