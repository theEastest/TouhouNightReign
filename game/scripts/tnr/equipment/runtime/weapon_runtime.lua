local WeaponRuntime = {}
local RNG = require("tnr.core.rng")
WeaponRuntime.__index = WeaponRuntime

local function copy_table(value)
    if type(value) ~= "table" then return value end
    local raw = value.__immutable_raw
    if type(raw) == "table" then value = raw end
    local result = {}
    for key, item in pairs(value) do result[key] = copy_table(item) end
    return result
end

local function append_values(target, values)
    if type(values) ~= "table" then return end
    -- Definition metadata is immutable-proxied in LuaJIT; ipairs/raw length
    -- therefore cannot see its numeric keys. Read the bounded angle list by
    -- index so both plain and immutable tables work.
    for index = 1, 64 do
        local value = values[index]
        if value == nil then break end
        target[#target + 1] = value
    end
end

function WeaponRuntime.new(instance, definition, slot_type, slot_index)
    assert(instance and definition, "weapon runtime requires instance and definition")
    return setmetatable({
        instance_id = instance.instance_id,
        definition_id = instance.definition_id,
        slot_type = slot_type,
        slot_index = slot_index,
        definition = definition,
        fire_count = 0,
        cooldown = 0,
        afterglow_pending = {},
        invulnerability_frames = 0,
        mini_next = false,
        mini_roll_count = 0,
        streaks = {},
        frame = 0,
    }, WeaponRuntime)
end

function WeaponRuntime:is_active(mode)
    mode = tostring(mode or "HIGH"):upper()
    if self.definition.dual_mode then return true end
    return (self.slot_type == "high_weapons" and mode == "HIGH")
        or (self.slot_type == "low_weapons" and mode == "LOW")
end

function WeaponRuntime:update(mode, firing, context)
    context = context or {}
    if context.paused then return {} end
    self.frame = self.frame + 1
    self.rng_seed = tostring(context.room_generation or 0) .. ":" .. tostring(context.player_id or 1)
        .. ":" .. tostring(self.slot_type) .. ":" .. tostring(self.slot_index)
        .. ":" .. tostring(self.definition_id)
    for target, state in pairs(self.streaks) do
        if self.frame - state.frame >= (tonumber((self.definition.metadata or {}).streak_timeout_frames) or 120) then
            self.streaks[target] = nil
        end
    end
    if self.cooldown > 0 then self.cooldown = self.cooldown - 1 end
    self.invulnerability_frames = math.max(0, (self.invulnerability_frames or 0) - 1)
    local result = {}
    for index = #self.afterglow_pending, 1, -1 do
        local pending = self.afterglow_pending[index]
        if context.attack_allowed ~= false then pending.delay = pending.delay - 1 end
        if pending.delay <= 0 then
            for _, shot in ipairs(pending.shots) do
                local copied = copy_table(shot)
                copied.x = (tonumber(context.x) or 0) + (copied.spawn_dx or 0)
                copied.y = (tonumber(context.y) or 0) + (copied.spawn_dy or 0)
                if context.attack_allowed ~= false then result[#result + 1] = copied end
            end
            table.remove(self.afterglow_pending, index)
        end
    end
    if context.attack_allowed == false or not firing or not self:is_active(mode) or self.cooldown > 0 then return result end
    local definition = self.definition
    local metadata = definition.metadata or {}
    local form = mode == "LOW" and metadata.low_form or metadata.high_form
    form = form or metadata.pattern or definition.pattern or definition.projectile_type or "default"
    local base_count = tonumber(metadata.projectile_count) or tonumber(definition.count) or 1
    local count = base_count + math.max(0, math.floor(tonumber(context and context.extra_projectiles) or 0))
    local spread = tonumber(metadata.spread) or 0
    local speed = (tonumber(definition.speed or definition.projectile_speed) or 0)
        * (tonumber(context.speed_multiplier) or 1)
    local damage = (tonumber(definition.damage) or 0)
        * (tonumber(context and context.damage_multiplier) or 1)
    -- `pattern` describes how a volley is laid out; it is not the projectile
    -- class.  The previous implementation used the pattern ("beam",
    -- "spread", ...) as the projectile type, so the native bridge silently
    -- fell back to a red needle for every custom weapon.  Keep the authored
    -- projectile type authoritative and only use the form as a last resort
    -- for legacy definitions that do not provide one.
    local projectile_type = definition.projectile_type or metadata.projectile_type or form
    local origin_x = tonumber(context and context.x) or 0
    local origin_y = tonumber(context and context.y) or 0
    local aim = tonumber(context and context.angle) or 90
    local mini_for_volley = self.mini_next == true
    if mini_for_volley then self.mini_next = false end
    local offsets = {}
    if type(metadata.spread_angles) == "table" then
        append_values(offsets, metadata.spread_angles)
    else
        for index = 1, math.max(1, math.floor(count)) do
            offsets[#offsets + 1] = (index - (count + 1) * 0.5) * spread
        end
    end
    append_values(offsets, context and context.extra_projectile_offsets)
    while #offsets < math.max(1, math.floor(count)) do offsets[#offsets + 1] = 0 end
    for index, offset in ipairs(offsets) do
        local shot_metadata = copy_table(metadata)
        if context and context.homing_turn_multiplier then
            shot_metadata.homing_turn_multiplier = tonumber(context.homing_turn_multiplier) or 1
        end
        if context and context.force_homing and not metadata.homing and definition.targeting ~= "NEAREST_ENEMY" then
            shot_metadata.homing = true
            shot_metadata.homing_strength = context.homing_strength or "WEAK"
            shot_metadata.homing_turn_ratio = tonumber(context.homing_turn_ratio) or 0.5
        end
        local shot_damage = damage
        if index > count then shot_damage = shot_damage * 0.1 end
        local shot_penetration = math.max(0, (tonumber(definition.penetration) or 0)
            + (tonumber(context and context.penetration_bonus) or 0))
        if metadata.penetration == "INFINITE" then shot_penetration = 999999 end
        if mini_for_volley and metadata.alternate_fire == "mini_master_spark"
                and metadata.beam == true then
            shot_metadata.mini_master_spark = true
            shot_metadata.beam_duration_frames = tonumber(metadata.mini_duration_frames) or 30
            shot_metadata.tick_interval = 1
            shot_metadata.persistent_collision = metadata.mini_persistent_collision == true
            shot_damage = shot_damage * (tonumber(metadata.mini_damage_multiplier) or 1)
            shot_penetration = 999999
            shot_metadata.penetration = metadata.mini_penetration or "INFINITE"
        end
        -- Pixel-top muzzle pairs for Reimu's three slots: 1/8+7/8,
        -- 2/8+6/8, 3/8+5/8 of its 32px frame. A pair keeps its own anchor.
        local half_width = (4 - math.min(3, self.slot_index or 1)) * 4
        local dx = count == 2 and (index % 2 == 1 and -half_width or half_width)
            or ((self.slot_index or 2) - 2) * 8
        local dy = 20
        result[#result + 1] = {
            weapon_id = self.definition_id,
            instance_id = self.instance_id,
            source_type = "weapon",
            source_instance_id = self.instance_id,
            projectile_type = projectile_type,
            x = origin_x + dx,
            y = origin_y + dy,
            spawn_dx = dx, spawn_dy = dy,
            angle = aim + (tonumber(offset) or 0),
            speed = speed,
            damage = shot_damage,
            scale = tonumber(context and context.scale) or 1,
            hitbox_scale = tonumber(context and context.hitbox_scale) or 1,
            penetration = shot_penetration,
            targeting = context and context.targeting_override
                or definition.targeting or metadata.targeting,
            metadata = shot_metadata,
            mode = mode,
            slot_type = self.slot_type,
            slot_index = self.slot_index,
        }
    end
    self.fire_count = self.fire_count + 1
    local interval = tonumber(definition.fire_interval) or 1
    interval = interval * (tonumber(context and context.fire_interval_multiplier) or 1)
    self.cooldown = math.max(1, math.floor(interval))
    local afterglow = context.afterglow
    if afterglow and self.fire_count % math.max(1, math.floor(afterglow.fire_threshold or 10)) == 0 then
        local copies = copy_table(result)
        local multiplier = tonumber(afterglow.copied_damage_multiplier) or 1
        for _, shot in ipairs(copies) do
            shot.damage = (tonumber(shot.damage) or 0) * multiplier
            shot.metadata = shot.metadata or {}
            shot.metadata.afterglow_copy = true
        end
        self.afterglow_pending[#self.afterglow_pending + 1] = {
            delay = math.max(1, math.floor(afterglow.delay_frames or 10)),
            shots = copies,
        }
        if afterglow.player_invincibility then
            self.invulnerability_frames = math.max(self.invulnerability_frames, 10)
        end
    end
    return result
end

function WeaponRuntime:notify_projectile_hit(frame)
    local metadata = self.definition.metadata or {}
    if metadata.alternate_fire ~= "mini_master_spark" then return false end
    self.mini_roll_count = (self.mini_roll_count or 0) + 1
    local seed = 1
    for index = 1, #(self.rng_seed or self.instance_id) do
        seed = (seed * 31 + (self.rng_seed or self.instance_id):byte(index)) % 4294967296
    end
    local rng = RNG.new((seed + self.mini_roll_count * 97) % 4294967296)
    if rng:next_float()
            < (tonumber(metadata.transform_chance) or 0) then
        self.mini_next = true
        return true
    end
    return false
end

function WeaponRuntime:damage_bonus(target)
    local state = self.streaks[target]
    local metadata = self.definition.metadata or {}
    if not state or self.frame - state.frame >= (metadata.streak_timeout_frames or 120) then return 0 end
    return math.min(metadata.streak_max_bonus or 1,
        math.floor(state.hits / (metadata.streak_step_hits or 10)) * (metadata.streak_damage_step or 0.01))
end

function WeaponRuntime:record_hit(target)
    if (self.definition.metadata or {}).legendary_effect ~= "sealing_streak" then return end
    local state = self.streaks[target] or { hits = 0 }
    state.hits, state.frame = state.hits + 1, self.frame
    self.streaks[target] = state
end

function WeaponRuntime:to_table()
    return {
        instance_id = self.instance_id,
        definition_id = self.definition_id,
        slot_type = self.slot_type,
        slot_index = self.slot_index,
        fire_count = self.fire_count,
        cooldown = self.cooldown,
        afterglow_pending = #self.afterglow_pending,
        invulnerability_frames = self.invulnerability_frames,
        definition = copy_table(self.definition),
    }
end

return WeaponRuntime
