local SupportRuntime = require("tnr.equipment.runtime.support_runtime")

local Manager = {}
Manager.__index = Manager

function Manager.new(loadout, registry, modifiers)
    local self = setmetatable({ supports = {}, registry = registry, modifiers = modifiers, frame = 0 }, Manager)
    for index, instance in ipairs(loadout and loadout.supports or {}) do
        if instance and instance ~= false then
            local definition = registry and registry.get and registry:get(instance.definition_id)
            if definition then self.supports[#self.supports + 1] = SupportRuntime.new(instance, definition, index) end
        end
    end
    return self
end

function Manager:entity_count()
    local count = 0
    for _, support in ipairs(self.supports) do count = count + support:entity_count() end
    return count
end

function Manager:update(player_x, player_y, mode, modifiers)
    modifiers = modifiers or self.modifiers
    local modifier_context = { frame = self.frame or 0 }
    if modifiers then
        modifier_context = modifiers:apply_hook("on_support_formation", modifier_context)
        modifier_context = modifiers:apply_hook("on_support_update", modifier_context)
    end
    self.frame = self.frame + 1
    local result = {}
    for _, support in ipairs(self.supports) do
        local entities = support:update(player_x, player_y, mode, modifier_context)
        for _, entity in ipairs(entities) do result[#result + 1] = entity end
    end
    return result
end

function Manager:to_table()
    local result = { entity_count = self:entity_count(), supports = {} }
    for index, support in ipairs(self.supports) do result.supports[index] = support:to_table() end
    return result
end

return Manager
