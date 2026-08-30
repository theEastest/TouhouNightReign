local Immutable = require("tnr.core.immutable")
local EquipmentDefinition = require("tnr.equipment.equipment_definition")

local ModifierDefinition = {}
local methods = {}

function ModifierDefinition.new(spec)
    spec = spec or {}
    local base = EquipmentDefinition.new({
        equipment_id = spec.modifier_id,
        display_name = spec.name or spec.display_name or spec.modifier_id,
        equipment_type = spec.modifier_type or "SELF_MODIFIER",
        weight = 0,
        unique = spec.unique,
        tags = spec.tags,
        metadata = spec.metadata,
    })
    local data = base:to_table()
    data.metadata = Immutable.copy(spec.metadata or {})
    data.modifier_id = spec.modifier_id
    data.modifier_type = spec.modifier_type or "SELF_MODIFIER"
    data.conflict_group = spec.conflict_group
    data.hook_definitions = Immutable.copy(spec.hook_definitions or {})
    return Immutable.freeze(data, methods)
end

function methods:to_table()
    return Immutable.copy(self)
end

function ModifierDefinition.is_conflicting(left, right)
    return left ~= nil and right ~= nil and left.conflict_group ~= nil and left.conflict_group ~= "" and left.conflict_group == right.conflict_group
end

return ModifierDefinition
