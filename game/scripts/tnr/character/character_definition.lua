local Immutable = require("tnr.core.immutable")

local CharacterDefinition = {}
local methods = {}

local function positive_integer(value, field)
    value = tonumber(value)
    assert(value and value >= 0 and value % 1 == 0, field .. " must be a non-negative integer")
    return value
end

function CharacterDefinition.new(spec)
    spec = spec or {}
    assert(type(spec.character_id) == "string" and spec.character_id ~= "", "character_id is required")
    assert(type(spec.name) == "string" and spec.name ~= "", "name is required")
    local data = {
        character_id = spec.character_id,
        name = spec.name,
        base_high_speed = tonumber(spec.base_high_speed) or 0,
        base_low_speed = tonumber(spec.base_low_speed) or 0,
        base_capacity = tonumber(spec.base_capacity) or 0,
        high_weapon_slots = positive_integer(spec.high_weapon_slots or 0, "high_weapon_slots"),
        low_weapon_slots = positive_integer(spec.low_weapon_slots or 0, "low_weapon_slots"),
        support_slots = positive_integer(spec.support_slots or 0, "support_slots"),
        self_modifier_slots = positive_integer(spec.self_modifier_slots or 0, "self_modifier_slots"),
        support_modifier_slots = positive_integer(spec.support_modifier_slots or 0, "support_modifier_slots"),
        inventory_slots = positive_integer(spec.inventory_slots or 0, "inventory_slots"),
    }
    assert(data.base_high_speed >= 0 and data.base_low_speed >= 0, "base speeds must be non-negative")
    assert(data.base_capacity >= 0, "base_capacity must be non-negative")
    return Immutable.freeze(data, methods)
end

function methods:to_table()
    return Immutable.copy({
        character_id = self.character_id,
        name = self.name,
        base_high_speed = self.base_high_speed,
        base_low_speed = self.base_low_speed,
        base_capacity = self.base_capacity,
        high_weapon_slots = self.high_weapon_slots,
        low_weapon_slots = self.low_weapon_slots,
        support_slots = self.support_slots,
        self_modifier_slots = self.self_modifier_slots,
        support_modifier_slots = self.support_modifier_slots,
        inventory_slots = self.inventory_slots,
    })
end

return CharacterDefinition
