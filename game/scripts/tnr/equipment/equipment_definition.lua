local Immutable = require("tnr.core.immutable")

local EquipmentDefinition = {}
local methods = {}

function EquipmentDefinition.new(spec)
    spec = spec or {}
    assert(type(spec.equipment_id) == "string" and spec.equipment_id ~= "", "equipment_id is required")
    assert(type(spec.equipment_type) == "string" and spec.equipment_type ~= "", "equipment_type is required")
    -- `display_name` is the player-facing name. Prefer the localized Chinese
    -- name when one exists so all-English ids never leak into the UI, while
    -- `display_name_en` keeps the reference English name for compatibility.
    local localized_zh = spec.display_name_zh or (spec.display_name and spec.display_name:find("[\228-\233]") and spec.display_name) or nil
    local data = {
        equipment_id = spec.equipment_id,
        display_name = localized_zh or spec.display_name or spec.equipment_id,
        display_name_zh = spec.display_name_zh or spec.display_name or spec.equipment_id,
        display_name_en = spec.display_name_en or spec.display_name or spec.equipment_id,
        equipment_type = spec.equipment_type,
        rarity = spec.rarity,
        weight = tonumber(spec.weight) or 0,
        unique = spec.unique == true,
        description = spec.description,
        description_zh = spec.description_zh or spec.description,
        tags = Immutable.copy(spec.tags or {}),
        metadata = Immutable.copy(spec.metadata or {}),
    }
    assert(data.weight >= 0, "equipment weight must be non-negative")
    return Immutable.freeze(data, methods)
end

function methods:to_table()
    return Immutable.copy({
        equipment_id = self.equipment_id,
        display_name = self.display_name,
        display_name_zh = self.display_name_zh,
        display_name_en = self.display_name_en,
        equipment_type = self.equipment_type,
        rarity = self.rarity,
        weight = self.weight,
        unique = self.unique,
        description = self.description,
        description_zh = self.description_zh,
        tags = self.tags,
        metadata = self.metadata,
    })
end

return EquipmentDefinition
