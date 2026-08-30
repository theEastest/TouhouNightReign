local ModifierRuntime = {}
ModifierRuntime.__index = ModifierRuntime

local function modifier_kind(definition)
    local metadata = definition and definition.metadata or {}
    return metadata.runtime_effect or definition and definition.modifier_id
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
            if modifier.kind == "projectile_scale" then context.scale = (context.scale or 1) * 1.35 end
        end
    elseif hook == "on_weapon_fire" then
        for _, modifier in ipairs(self.self_modifiers) do
            if modifier.kind == "volley" then
                context.extra_projectiles = (context.extra_projectiles or 0) + 1
            end
        end
    elseif hook == "on_support_formation" then
        for _, modifier in ipairs(self.support_modifiers) do
            if modifier.kind == "front_concentration" then context.support_formation = "front_concentration" end
        end
    elseif hook == "on_support_update" then
        for _, modifier in ipairs(self.support_modifiers) do
            if modifier.kind == "periodic_bullet_clear" then context.clear_bullets = context.clear_bullets == true or (tonumber(context.frame) or 0) % 180 == 0 end
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
