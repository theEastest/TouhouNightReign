local Immutable = require("tnr.core.immutable")

local EquipmentInstance = {}
EquipmentInstance.__index = EquipmentInstance

local next_id = 0

local function new_id(definition_id)
    next_id = next_id + 1
    return string.format("%s-%06d", definition_id, next_id)
end

function EquipmentInstance.new(definition, owner_player_id, options)
    options = options or {}
    local definition_id = type(definition) == "table" and (definition.equipment_id or definition.weapon_id or definition.support_id or definition.modifier_id or definition.relic_id) or definition
    assert(type(definition_id) == "string" and definition_id ~= "", "definition_id is required")
    assert(owner_player_id ~= nil, "owner_player_id is required")
    local instance = setmetatable({
        instance_id = options.instance_id or new_id(definition_id),
        definition_id = definition_id,
        owner_player_id = owner_player_id,
        equipment_type = type(definition) == "table" and (definition.equipment_type or (definition.relic_id and "RELIC")) or options.equipment_type,
        runtime_data = Immutable.copy(options.runtime_data or {}),
        random_affixes = Immutable.copy(options.random_affixes or {}),
        weight = type(definition) == "table" and tonumber(definition.weight) or tonumber(options.weight) or 0,
    }, EquipmentInstance)
    assert(instance.instance_id ~= "", "instance_id is required")
    return instance
end

function EquipmentInstance:to_table()
    return {
        instance_id = self.instance_id,
        definition_id = self.definition_id,
        owner_player_id = self.owner_player_id,
        runtime_data = Immutable.copy(self.runtime_data),
        random_affixes = Immutable.copy(self.random_affixes),
        weight = self.weight,
        equipment_type = self.equipment_type,
    }
end

function EquipmentInstance.from_table(data)
    assert(type(data) == "table", "equipment instance data is required")
    return EquipmentInstance.new(data.definition_id, data.owner_player_id, {
        instance_id = data.instance_id,
        runtime_data = data.runtime_data,
        random_affixes = data.random_affixes,
        weight = data.weight,
        equipment_type = data.equipment_type,
    })
end

return EquipmentInstance
