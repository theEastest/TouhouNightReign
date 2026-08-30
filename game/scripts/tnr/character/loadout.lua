local Immutable = require("tnr.core.immutable")

local Loadout = {}
Loadout.__index = Loadout

local function slots(count)
    local result = {}
    for index = 1, count or 0 do
        result[index] = false
    end
    return result
end

local function copy_slots(values, count)
    local result = slots(count)
    for index = 1, math.min(#(values or {}), count or 0) do
        result[index] = values[index]
    end
    return result
end

function Loadout.new(character_definition, options)
    assert(character_definition, "character_definition is required")
    options = options or {}
    local self = setmetatable({
        character_id = character_definition.character_id,
        high_weapons = copy_slots(options.high_weapons, character_definition.high_weapon_slots),
        low_weapons = copy_slots(options.low_weapons, character_definition.low_weapon_slots),
        supports = copy_slots(options.supports, character_definition.support_slots),
        self_modifiers = copy_slots(options.self_modifiers, character_definition.self_modifier_slots),
        support_modifiers = copy_slots(options.support_modifiers, character_definition.support_modifier_slots),
        inventory = options.inventory,
        relics = Immutable.copy(options.relics or {}),
        character_relic = options.character_relic,
        version = tonumber(options.version) or 1,
        _definition_lookup = options.definition_lookup,
    }, Loadout)
    return self
end

function Loadout:set_definition_lookup(lookup)
    assert(type(lookup) == "function" or type(lookup) == "table", "definition lookup must be callable or a registry")
    self._definition_lookup = lookup
end

function Loadout:set_slot(slot_type, index, instance)
    local collection = self[slot_type]
    assert(type(collection) == "table", "unknown loadout slot type: " .. tostring(slot_type))
    assert(type(index) == "number" and index >= 1 and index <= #collection and index % 1 == 0, "slot index out of range")
    local next_instance = instance or false
    if collection[index] ~= next_instance then
        collection[index] = next_instance
        self.version = (tonumber(self.version) or 1) + 1
    end
    return collection[index]
end

function Loadout:get_slot(slot_type, index)
    local collection = self[slot_type]
    return collection and collection[index] or nil
end

function Loadout:iter_equipped()
    local groups = { "high_weapons", "low_weapons", "supports", "self_modifiers", "support_modifiers" }
    local group_index, slot_index = 1, 0
    return function()
        while group_index <= #groups do
            local group = groups[group_index]
            slot_index = slot_index + 1
            if slot_index <= #self[group] then
                local instance = self[group][slot_index]
                if instance and instance ~= false then
                    return group, slot_index, instance
                end
            else
                group_index = group_index + 1
                slot_index = 0
            end
        end
    end
end

local function resolve_definition(lookup, instance)
    if not instance then
        return nil
    end
    if type(lookup) == "function" then
        return lookup(instance.definition_id)
    end
    if type(lookup) == "table" and lookup.get then
        return lookup:get(instance.definition_id)
    end
    return nil
end

function Loadout:get_total_weight(definition_lookup)
    local lookup = definition_lookup or self._definition_lookup
    local total = 0
    for group, _, instance in self:iter_equipped() do
        if group == "high_weapons" or group == "low_weapons" or group == "supports" then
            local definition = resolve_definition(lookup, instance)
            total = total + (definition and definition.weight or instance.weight or 0)
        end
    end
    return total
end

function Loadout:debug_summary()
    local function used(values)
        local count = 0
        for _, value in ipairs(values) do
            if value and value ~= false then count = count + 1 end
        end
        return count
    end
    local inventory_count = self.inventory and self.inventory.count and self.inventory:count() or 0
    local inventory_capacity = self.inventory and self.inventory.capacity or 0
    return {
        character_id = self.character_id,
        version = tonumber(self.version) or 1,
        high_slots = { used = used(self.high_weapons), total = #self.high_weapons },
        low_slots = { used = used(self.low_weapons), total = #self.low_weapons },
        support_slots = { used = used(self.supports), total = #self.supports },
        self_modifier_slots = { used = used(self.self_modifiers), total = #self.self_modifiers },
        support_modifier_slots = { used = used(self.support_modifiers), total = #self.support_modifiers },
        inventory = { used = inventory_count, total = inventory_capacity },
    }
end

function Loadout:to_table()
    return {
        character_id = self.character_id,
        high_weapons = Immutable.copy(self.high_weapons),
        low_weapons = Immutable.copy(self.low_weapons),
        supports = Immutable.copy(self.supports),
        self_modifiers = Immutable.copy(self.self_modifiers),
        support_modifiers = Immutable.copy(self.support_modifiers),
        inventory = self.inventory and self.inventory.to_table and self.inventory:to_table() or Immutable.copy(self.inventory),
        relics = Immutable.copy(self.relics),
        character_relic = Immutable.copy(self.character_relic),
        version = tonumber(self.version) or 1,
    }
end

function Loadout.from_table(data, character_definition, inventory)
    assert(type(data) == "table", "loadout data is required")
    local result = Loadout.new(character_definition, {
        high_weapons = data.high_weapons,
        low_weapons = data.low_weapons,
        supports = data.supports,
        self_modifiers = data.self_modifiers,
        support_modifiers = data.support_modifiers,
        inventory = inventory or data.inventory,
        relics = data.relics,
        character_relic = data.character_relic,
        version = data.version,
    })
    return result
end

return Loadout
