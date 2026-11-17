-- Legacy replay visual effects.
--
-- The reference spawns short lived effect objects when an enemy dies or a
-- bullet breaks. Each is a real animation script on the effect sheet: it sets a
-- starting scale, ramps the scale up over a number of frames, steps through a
-- few sprites and then stops. Playing that script is what keeps an explosion
-- alive for as long as the original and lets it grow as wide.
--
-- The effect ids come from the stage's effect archive.

local Effects = {}

Effects.__index = Effects

-- Effect kinds, mapped to the archive texture and the script index the
-- reference plays for them.
Effects.KIND = {
    ENEMY_DEATH = "enemy_death",
    BULLET_BREAK = "bullet_break",
}

local EFFECT_TEXTURES = {
    enemy_death = "eff_deadcircle.png",
    bullet_break = "eff_breakwave2.png",
}

-- The reference's script indices for these two effects.
local EFFECT_SCRIPTS = {
    enemy_death = 28,
    bullet_break = 29,
}

-- Fallbacks for a sheet that does not carry the reference script.
local DEFAULT_DURATION = 81
local DEFAULT_GROWTH_FRAMES = 30
local DEFAULT_START_SCALE = 0.5
local DEFAULT_END_SCALE = 5.5
local ENEMY_DEATH_DURATION = 27
local ENEMY_DEATH_END_SCALE = 3.0

Effects.EFFECT_TEXTURES = EFFECT_TEXTURES
Effects.EFFECT_SCRIPTS = EFFECT_SCRIPTS

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
                result = {
                    entry = entry_index,
                    sprites = #entry.sprites,
                    script = entry.scripts and entry.scripts[EFFECT_SCRIPTS[kind]],
                }
                break
            end
        end
    end
    self.entry_cache[kind] = result
    return result
end

--- Read a script's timeline into the values the renderer needs.
-- The interesting instructions are the sprite steps (300 and 500), the scale
-- keys (402 sets it outright, 412 interpolates it) and the stop (1 and 81).
-- Reading them once at spawn keeps the per frame path cheap.
local function read_timeline(script)
    local timeline = {
        duration = DEFAULT_DURATION,
        start_scale = DEFAULT_START_SCALE,
        end_scale = DEFAULT_END_SCALE,
        growth_frames = DEFAULT_GROWTH_FRAMES,
        first_sprite = 1,
    }
    if not script then return timeline end
    local sprites = {}
    for _, instruction in ipairs(script) do
        local id = instruction.id
        local time = instruction.time or 0
        if id == 1 or id == 81 then
            -- Stop: the effect ends here.
            if time > 0 then timeline.duration = time end
        elseif id == 300 then
            sprites[#sprites + 1] = { time = time, sprite = (tonumber(instruction[1]) or 0) + 1 }
        elseif id == 500 then
            sprites[#sprites + 1] = { time = time, sprite = (tonumber(instruction[1]) or 0) + 1 }
        elseif id == 402 then
            local x = tonumber(instruction[1])
            if x then
                timeline.start_scale = x
                timeline.end_scale = tonumber(instruction[2]) or x
            end
        elseif id == 412 then
            -- 412 <frames> <ease> <end_x> <end_y>.
            local frames = tonumber(instruction[1])
            local end_x = tonumber(instruction[3])
            if frames and frames > 0 then timeline.growth_frames = frames end
            if end_x then timeline.end_scale = end_x end
        end
    end
    timeline.sprites = sprites
    if sprites[1] then timeline.first_sprite = sprites[1].sprite end
    return timeline
end

Effects.read_timeline = read_timeline

--- Spawn an effect at a position.
function Effects:spawn(kind, x, y, scale)
    local info = self:entry_for(kind)
    if not info then return nil end
    local timeline = read_timeline(info.script)
    if kind == Effects.KIND.ENEMY_DEATH then
        -- The archive's 64x64 ring was enlarged to an 88px radius and left on
        -- screen for 81 frames. Keep the imported animation, but cap both its
        -- lifetime and scale so the low-resolution source does not dominate.
        timeline.duration = math.min(timeline.duration, ENEMY_DEATH_DURATION)
        timeline.growth_frames = math.min(timeline.growth_frames, 18)
        timeline.end_scale = math.min(timeline.end_scale, ENEMY_DEATH_END_SCALE)
    end
    local effect = {
        kind = kind,
        x = x, y = y,
        timer = 0,
        duration = math.max(1, timeline.duration),
        entry = info.entry,
        timeline = timeline,
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

--- The sprite index and size an effect shows right now.
-- Returns the sprite, its scale and its alpha. The scale ramps from the
-- script's starting value to its ending value across the growth window, which
-- is the expanding ring the original draws.
function Effects:sprite_for(effect)
    local timeline = effect.timeline or {}
    local timer = effect.timer or 0
    -- The sprite is whichever step the timeline has reached.
    local sprite = timeline.first_sprite or 1
    for _, step in ipairs(timeline.sprites or {}) do
        if step.time <= timer then sprite = step.sprite else break end
    end
    local growth = math.max(1, timeline.growth_frames or DEFAULT_GROWTH_FRAMES)
    local progress = math.min(1, timer / growth)
    local from = timeline.start_scale or DEFAULT_START_SCALE
    local to = timeline.end_scale or DEFAULT_END_SCALE
    local scale = from + (to - from) * progress
    -- Fade out over the last third of the effect's life.
    local alpha = 255
    local duration = math.max(1, effect.duration or DEFAULT_DURATION)
    local fade_start = duration * 2 / 3
    if timer > fade_start then
        alpha = math.floor(255 * (duration - timer) / (duration - fade_start))
    end
    return sprite, scale, alpha
end

function Effects:count()
    return #self.list
end

Effects.DEFAULT_DURATION = DEFAULT_DURATION

return Effects
