local Immutable = require("tnr.core.immutable")
local EquipmentDefinition = require("tnr.equipment.equipment_definition")

local WeaponDefinition = {}
local methods = {}

function WeaponDefinition.new(spec)
    spec = spec or {}
    local data = {
        equipment_id = spec.weapon_id,
        display_name = spec.name or spec.display_name_zh or spec.display_name or spec.weapon_id,
        display_name_zh = spec.display_name_zh or spec.name or spec.display_name or spec.weapon_id,
        display_name_en = spec.display_name_en or spec.display_name or spec.weapon_id,
        equipment_type = "WEAPON",
        rarity = spec.rarity,
        weight = spec.weight,
        unique = spec.unique,
        test_only = spec.test_only == true,
        tags = spec.tags,
        metadata = spec.metadata,
    }
    local definition = EquipmentDefinition.new(data)
    -- LuaJIT 5.1 does not invoke the __pairs metamethod used by the
    -- immutable proxy, so copy through its explicit stable API.
    local result = definition:to_table()
    -- Immutable proxies do not expose __pairs under Lua 5.1/LuaJIT, so
    -- preserve metadata from the source spec explicitly.
    result.metadata = Immutable.copy(spec.metadata or {})
    result.weapon_id = spec.weapon_id
    result.name = data.display_name
    result.type = spec.type or (spec.slot == "LOW" and "LOW_WEAPON" or "HIGH_WEAPON")
    result.display_name_zh = data.display_name_zh
    result.display_name_en = data.display_name_en
    result.rarity = data.rarity
    result.fire_interval = tonumber(spec.fire_interval) or 0
    result.damage = tonumber(spec.damage) or 0
    result.projectile_type = spec.projectile_type
    result.projectile_speed = tonumber(spec.projectile_speed) or 0
    result.speed = tonumber(spec.speed) or result.projectile_speed
    result.count = tonumber(spec.count)
    result.pattern = spec.pattern
    result.penetration = tonumber(spec.penetration) or 0
    result.targeting = spec.targeting
    result.status_type = spec.status_type
    result.status_buildup = tonumber(spec.status_buildup) or 0
    result.active_modes = spec.active_modes and Immutable.copy(spec.active_modes) or {}
    result.allowed_slots = spec.allowed_slots and Immutable.copy(spec.allowed_slots)
    result.dual_mode = spec.dual_mode == true
    result.test_only = spec.test_only == true
    return Immutable.freeze(result, methods)
end

function methods:to_table()
    return Immutable.copy(self)
end

return WeaponDefinition
