local ModifierRuntime = {}
ModifierRuntime.__index = ModifierRuntime

local function modifier_kind(definition)
    local metadata = definition and definition.metadata or {}
    return metadata.runtime_effect or definition and definition.modifier_id
end

local function append_indexed(target, values)
    if type(values) ~= "table" then return end
    for index = 1, 64 do
        local value = values[index]
        if value == nil then break end
        target[#target + 1] = value
    end
end

function ModifierRuntime.new(loadout, registry)
    local self = setmetatable({ self_modifiers = {}, support_modifiers = {} }, ModifierRuntime)
    for _, group in ipairs({ "self_modifiers", "support_modifiers" }) do
        for _, instance in ipairs(loadout and loadout[group] or {}) do
            if instance and instance ~= false then
                local definition = registry and registry.get and registry:get(instance.definition_id)
                if definition then
                    local target = group == "self_modifiers" and self.self_modifiers or self.support_modifiers
                    target[#target + 1] = { instance = instance, definition = definition, kind = modifier_kind(definition) }
                end
            end
        end
    end
    return self
end

function ModifierRuntime:apply_hook(hook, context)
    context = context or {}
    if hook == "on_projectile_create" then
        for _, modifier in ipairs(self.self_modifiers) do
            if modifier.kind == "projectile_scale" then
                local metadata = modifier.definition.metadata or {}
                context.scale = (context.scale or 1) * (tonumber(metadata.projectile_scale) or 1.35)
                context.hitbox_scale = (context.hitbox_scale or 1) * (tonumber(metadata.hitbox_scale) or 1)
                if context.damage ~= nil then
                    context.damage = (tonumber(context.damage) or 0)
                        * (tonumber(metadata.damage_multiplier) or 1)
                end
                if context.speed ~= nil then
                    context.speed = (tonumber(context.speed) or 0)
                        * (tonumber(metadata.speed_multiplier) or 1)
                end
            end
        end
        context.scale = math.min(3, context.scale or 1)
        context.hitbox_scale = math.min(2, context.hitbox_scale or 1)
    elseif hook == "on_weapon_fire" then
        local volley_stack = 0
        for _, modifier in ipairs(self.self_modifiers) do
            if modifier.kind == "volley" then
                volley_stack = volley_stack + 1
                local offsets = (modifier.definition.metadata or {}).extra_projectile_offsets
                if type(offsets) == "table" then
                    context.extra_projectile_offsets = context.extra_projectile_offsets or {}
                    local indexed = {}
                    append_indexed(indexed, offsets)
                    for _, offset in ipairs(indexed) do
                        context.extra_projectile_offsets[#context.extra_projectile_offsets + 1] = (tonumber(offset) or 0) * volley_stack
                    end
                else
                    context.extra_projectiles = (context.extra_projectiles or 0) + 1
                end
            elseif modifier.kind == "cast_speed_damage" then
                local metadata = modifier.definition.metadata or {}
                local multiplier = tonumber(metadata.fire_interval_multiplier) or 1
                context.fire_interval_multiplier = (context.fire_interval_multiplier or 1) * multiplier
                context.damage_multiplier = (context.damage_multiplier or 1)
                    * (tonumber(metadata.damage_multiplier) or 1)
            elseif modifier.kind == "penetration_bonus" then
                local metadata = modifier.definition.metadata or {}
                context.penetration_bonus = (context.penetration_bonus or 0)
                    + (tonumber(metadata.penetration_bonus) or 0)
                context.damage_multiplier = (context.damage_multiplier or 1)
                    * (tonumber(metadata.damage_multiplier) or 1)
            elseif modifier.kind == "homing_formula" then
                local metadata = modifier.definition.metadata or {}
                context.targeting_override = metadata.direct_targeting or "NEAREST_ENEMY"
                context.homing_turn_multiplier = (context.homing_turn_multiplier or 1)
                    * (tonumber(metadata.already_homing_turn_multiplier) or 1)
                context.force_homing = true
                context.homing_strength = "WEAK"
                context.homing_turn_ratio = 0.5
            elseif modifier.kind == "afterglow" then
                local metadata = modifier.definition.metadata or {}
                context.afterglow = {
                    fire_threshold = tonumber(metadata.fire_threshold) or 10,
                    delay_frames = tonumber(metadata.delay_frames) or 10,
                    copied_damage_multiplier = tonumber(metadata.copied_damage_multiplier) or 1,
                    player_invincibility = metadata.player_invincibility == true,
                }
            end
        end
    elseif hook == "on_support_formation" then
        for _, modifier in ipairs(self.support_modifiers) do
            if modifier.kind == "front_concentration" then context.support_formation = "front_concentration" end
            if modifier.kind == "orbit_formation" then
                context.support_formation = "orbit"
                local metadata = modifier.definition.metadata or {}
                context.high_radius = tonumber(metadata.high_radius) or 42
                context.low_radius = tonumber(metadata.low_radius) or 28
            end
            if modifier.kind == "auto_target" then
                local metadata = modifier.definition.metadata or {}
                local active_mode = tostring(metadata.active_mode or ""):upper()
                if active_mode == "" or active_mode == tostring(context.mode or "HIGH"):upper() then
                    context.support_auto_target = metadata.target or "NEAREST_ENEMY"
                    context.support_auto_target_mode = active_mode
                end
            end
        end
    elseif hook == "on_support_update" then
        for _, modifier in ipairs(self.support_modifiers) do
            if modifier.kind == "periodic_bullet_clear" or modifier.kind == "support_bullet_clear"
                    or modifier.kind == "staggered_bullet_clear" then
                local metadata = modifier.definition.metadata or {}
                local interval = tonumber(metadata.clear_interval_frames or metadata.cycle_frames or 180) or 180
                context.clear_bullets = context.clear_bullets == true
                    or (tonumber(context.frame) or 0) % math.max(1, interval) == 0
                context.clear_radius_ratio = tonumber(metadata.clear_radius_ratio) or context.clear_radius_ratio or 2
                if modifier.kind == "staggered_bullet_clear" then
                    context.staggered_bullet_clear = true
                    context.staggered_cycle_frames = math.max(1, math.floor(interval))
                end
            end
        end
    elseif hook == "on_support_projectile_create" then
        for _, modifier in ipairs(self.support_modifiers) do
            if modifier.kind == "support_projectile_scale" then
                local metadata = modifier.definition.metadata or {}
                context.scale = (context.scale or 1) * (tonumber(metadata.support_projectile_scale) or 1.25)
            end
        end
    end
    return context
end

function ModifierRuntime:to_table()
    local result = { self_modifiers = {}, support_modifiers = {} }
    for index, item in ipairs(self.self_modifiers) do result.self_modifiers[index] = item.instance.instance_id end
    for index, item in ipairs(self.support_modifiers) do result.support_modifiers[index] = item.instance.instance_id end
    return result
end

return ModifierRuntime
