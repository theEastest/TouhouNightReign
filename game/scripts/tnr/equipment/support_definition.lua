local Immutable = require("tnr.core.immutable")
local EquipmentDefinition = require("tnr.equipment.equipment_definition")

local SupportDefinition = {}
local methods = {}

function SupportDefinition.new(spec)
    spec = spec or {}
    local base = EquipmentDefinition.new({
        equipment_id = spec.support_id,
        display_name = spec.name or spec.display_name_zh or spec.display_name or spec.support_id,
        display_name_zh = spec.display_name_zh or spec.name or spec.display_name or spec.support_id,
        display_name_en = spec.display_name_en or spec.display_name or spec.support_id,
        equipment_type = "SUPPORT",
        rarity = spec.rarity,
        weight = spec.weight,
        unique = spec.unique,
        test_only = spec.test_only == true,
        tags = spec.tags,
        metadata = spec.metadata,
    })
    local data = base:to_table()
    data.metadata = Immutable.copy(spec.metadata or {})
    data.support_id = spec.support_id
    data.name = data.display_name
    data.entity_count = tonumber(spec.entity_count) or 0
    data.activation_mode = spec.activation_mode or "INDEPENDENT"
    data.formation = Immutable.copy(spec.formation or {})
    data.attack_mode = spec.attack_mode or "INDEPENDENT"
    data.weapon_definition_id = spec.weapon_definition_id
    data.high_weapon_definition_id = spec.high_weapon_definition_id
    data.low_weapon_definition_id = spec.low_weapon_definition_id
    data.test_only = spec.test_only == true
    return Immutable.freeze(data, methods)
end

function methods:to_table()
    return Immutable.copy(self)
end

return SupportDefinition
