local WeaponRuntime = require("tnr.equipment.runtime.weapon_runtime")

local Manager = {}
Manager.__index = Manager

local function definition_for(registry, instance)
    return registry and registry.get and registry:get(instance.definition_id) or nil
end

function Manager.new(loadout, registry, modifiers)
    local self = setmetatable({ weapons = {}, loadout = loadout, registry = registry, modifiers = modifiers }, Manager)
    for _, slot_type in ipairs({ "high_weapons", "low_weapons" }) do
        for index, instance in ipairs(loadout and loadout[slot_type] or {}) do
            if instance and instance ~= false then
                local definition = definition_for(registry, instance)
                if definition then
                    self.weapons[#self.weapons + 1] = WeaponRuntime.new(instance, definition, slot_type, index)
                end
            end
        end
    end
    return self
end

function Manager:update(mode, firing, context)
    context = context or {}
    if self.modifiers then context = self.modifiers:apply_hook("on_weapon_fire", context) end
    local result = {}
    for _, weapon in ipairs(self.weapons) do
        local shots = weapon:update(mode, firing, context)
        for _, shot in ipairs(shots) do
            if self.modifiers then
                local projectile_context = self.modifiers:apply_hook("on_projectile_create", shot)
                shot = projectile_context
            end
            result[#result + 1] = shot
        end
    end
    return result
end

function Manager:active_ids(mode)
    local result = {}
    for _, weapon in ipairs(self.weapons) do
        if weapon:is_active(mode) then result[#result + 1] = weapon.definition_id end
    end
    return result
end

function Manager:to_table()
    local result = {}
    for index, weapon in ipairs(self.weapons) do result[index] = weapon:to_table() end
    return result
end

return Manager
