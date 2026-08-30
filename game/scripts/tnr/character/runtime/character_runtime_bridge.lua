local Immutable = require("tnr.core.immutable")
local ReimuDefinition = require("tnr.character.reimu_definition")
local WeightSpeedPolicy = require("tnr.character.runtime.weight_speed_policy")
local WeaponRuntimeManager = require("tnr.equipment.runtime.weapon_runtime_manager")
local SupportRuntimeManager = require("tnr.equipment.runtime.support_runtime_manager")
local ModifierRuntime = require("tnr.equipment.runtime.modifier_runtime")

local Bridge = {}
Bridge.__index = Bridge

local function stable_encode(value, seen)
    local kind = type(value)
    if value == nil then return "n" end
    if kind == "boolean" then return value and "b1" or "b0" end
    if kind == "number" then return "d" .. string.format("%.17g", value) .. ";" end
    if kind == "string" then return "s" .. #value .. ":" .. value end
    if kind ~= "table" then return "n" end
    seen = seen or {}
    if seen[value] then return "r" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = { "t", tostring(#keys), ":" }
    for _, key in ipairs(keys) do parts[#parts + 1] = stable_encode(key, seen); parts[#parts + 1] = stable_encode(value[key], seen) end
    seen[value] = nil
    return table.concat(parts)
end

local function hash_string(value)
    local hash = 2166136261
    for index = 1, #value do
        hash = (hash + string.byte(value, index) * 16777619) % 4294967291
    end
    return string.format("%08x", hash % 4294967296)
end

local function plain(value)
    if type(value) ~= "table" then return value end
    if type(value.to_table) == "function" then return plain(value:to_table()) end
    local result = {}
    for key, item in pairs(value) do result[key] = plain(item) end
    return result
end

local function definition_for(registry, instance)
    return registry and registry.get and registry:get(instance.definition_id) or nil
end

local function instance_descriptor(registry, instance)
    local definition = definition_for(registry, instance)
    return {
        instance_id = tostring(instance.instance_id),
        definition_id = tostring(instance.definition_id),
        owner_player_id = tonumber(instance.owner_player_id),
        equipment_type = instance.equipment_type,
        weight = tonumber(definition and definition.weight or instance.weight) or 0,
        runtime_data = plain(instance.runtime_data or {}),
        random_affixes = plain(instance.random_affixes or {}),
        definition = definition and plain(definition) or nil,
    }
end

local function hashable_group(descriptor, group_name)
    local result = {}
    for index, item in ipairs(descriptor[group_name] or {}) do
        result[index] = {
            -- Instance IDs are process-local and must not make equivalent
            -- loadouts disagree across LAN peers.
            definition_id = item.definition_id,
            weight = item.weight,
            runtime_data = item.runtime_data,
            random_affixes = item.random_affixes,
        }
    end
    return result
end

function Bridge.new(session, player_id, registry)
    assert(session, "session is required")
    return setmetatable({ session = session, player_id = tonumber(player_id) or 1, registry = registry or session.equipment_registry }, Bridge)
end

function Bridge:player()
    return self.session:get_player(self.player_id)
end

function Bridge:build_descriptor()
    local player = self:player()
    assert(player and player.loadout, "player loadout is required")
    local character = ReimuDefinition
    local loadout = player.loadout
    local descriptor = {
        player_id = self.player_id,
        character_id = player.character_id or loadout.character_id or character.character_id,
        capacity = tonumber(player.current_capacity or character.base_capacity) or 0,
        high_weapons = {}, low_weapons = {}, supports = {},
        self_modifiers = {}, support_modifiers = {},
        loadout_version = tonumber(loadout.version) or 1,
    }
    local definition = character
    if self.session.character_registry and self.session.character_registry.get then
        definition = self.session.character_registry:get(descriptor.character_id) or character
    end
    descriptor.base_high_speed = tonumber(definition.base_high_speed) or 0
    descriptor.base_low_speed = tonumber(definition.base_low_speed) or 0
    for _, group in ipairs({ "high_weapons", "low_weapons", "supports", "self_modifiers", "support_modifiers" }) do
        for _, instance in ipairs(loadout[group] or {}) do
            if instance and instance ~= false then descriptor[group][#descriptor[group] + 1] = instance_descriptor(self.registry, instance) end
        end
    end
    local weight = loadout:get_total_weight(self.registry)
    descriptor.weight = weight
    local policy = WeightSpeedPolicy.resolve(descriptor.base_high_speed, descriptor.base_low_speed, descriptor.capacity, weight)
    descriptor.speed = policy
    local hash_payload = {
        character_id = descriptor.character_id,
        capacity = descriptor.capacity,
        weight = descriptor.weight,
        base_high_speed = descriptor.base_high_speed,
        base_low_speed = descriptor.base_low_speed,
        loadout_version = descriptor.loadout_version,
        high_weapons = hashable_group(descriptor, "high_weapons"),
        low_weapons = hashable_group(descriptor, "low_weapons"),
        supports = hashable_group(descriptor, "supports"),
        self_modifiers = hashable_group(descriptor, "self_modifiers"),
        support_modifiers = hashable_group(descriptor, "support_modifiers"),
    }
    descriptor.loadout_hash = hash_string(stable_encode(hash_payload))
    return descriptor
end

function Bridge:create_runtime()
    local player = self:player()
    local descriptor = self:build_descriptor()
    local modifier_runtime = ModifierRuntime.new(player.loadout, self.registry)
    return {
        descriptor = descriptor,
        weapon_manager = WeaponRuntimeManager.new(player.loadout, self.registry, modifier_runtime),
        support_manager = SupportRuntimeManager.new(player.loadout, self.registry, modifier_runtime),
        modifier_runtime = modifier_runtime,
    }
end

function Bridge:to_table()
    return Immutable.copy(self:build_descriptor())
end

return Bridge
