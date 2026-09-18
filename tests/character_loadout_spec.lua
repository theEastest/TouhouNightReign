local CharacterRegistry = require("tnr.character.character_registry")
local ReimuDefinition = require("tnr.character.reimu_definition")
local Loadout = require("tnr.character.loadout")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local EquipmentRegistry = require("tnr.equipment.equipment_registry")
local EquipmentDefinition = require("tnr.equipment.equipment_definition")
local WeaponDefinition = require("tnr.equipment.weapon_definition")
local SupportDefinition = require("tnr.equipment.support_definition")
local ModifierDefinition = require("tnr.equipment.modifier_definition")
local RelicDefinition = require("tnr.equipment.relic_definition")
local Inventory = require("tnr.equipment.inventory")
local PlayerState = require("tnr.core.player_state")
local PartyState = require("tnr.core.party_state")

local function same_table(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not same_table(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

return function(assert_equal, assert_true)
    local characters = CharacterRegistry.new({ ReimuDefinition })
    assert_true(characters:has("reimu"), "Reimu must be registered")
    assert_equal(ReimuDefinition.high_weapon_slots, 3, "Reimu high weapon slots")
    assert_equal(ReimuDefinition.low_weapon_slots, 3, "Reimu low weapon slots")
    assert_equal(ReimuDefinition.support_slots, 1, "Reimu support slots")
    assert_equal(ReimuDefinition.self_modifier_slots, 2, "Reimu self modifier slots")
    assert_equal(ReimuDefinition.support_modifier_slots, 2, "Reimu support modifier slots")
    assert_equal(ReimuDefinition.inventory_slots, 6, "Reimu inventory slots")

    local registry = EquipmentRegistry.new()
    local high = registry:register(WeaponDefinition.new({
        weapon_id = "test_high_weapon", name = "Test High", weight = 2,
        fire_interval = 4, damage = 2, projectile_type = "test", projectile_speed = 20,
        active_modes = { HIGH = true },
    }))
    local low = registry:register(WeaponDefinition.new({
        weapon_id = "test_low_weapon", name = "Test Low", weight = 3,
        fire_interval = 5, damage = 3, projectile_type = "test", projectile_speed = 18,
        active_modes = { LOW = true },
    }))
    local support = registry:register(SupportDefinition.new({
        support_id = "test_support", name = "Test Support", weight = 4,
        entity_count = 4, activation_mode = "INDEPENDENT", attack_mode = "INDEPENDENT",
    }))
    local self_modifier = registry:register(ModifierDefinition.new({
        modifier_id = "test_self_modifier", name = "Test Self", modifier_type = "SELF_MODIFIER",
        conflict_group = "projectile_size",
    }))
    local support_modifier = registry:register(ModifierDefinition.new({
        modifier_id = "test_support_modifier", name = "Test Support Mod", modifier_type = "SUPPORT_MODIFIER",
        conflict_group = "formation",
    }))
    local plain = registry:register(EquipmentDefinition.new({
        equipment_id = "test_plain", equipment_type = "WEAPON", weight = 9,
    }))
    local relic = RelicDefinition.new({ relic_id = "test_relic", name = "Test Relic", character_relic = true })
    assert_true(plain ~= nil and relic ~= nil, "all definition types must construct")

    local high_instance_a = EquipmentInstance.new(high, 1)
    local high_instance_b = EquipmentInstance.new(high, 1)
    assert_true(high_instance_a.instance_id ~= high_instance_b.instance_id, "instances need unique ids")
    assert_equal(high_instance_a.definition_id, high_instance_b.definition_id, "duplicate definitions are allowed")
    local low_instance = EquipmentInstance.new(low, 1)
    local support_instance = EquipmentInstance.new(support, 1)
    local self_instance = EquipmentInstance.new(self_modifier, 1)
    local support_modifier_instance = EquipmentInstance.new(support_modifier, 1)

    local inventory = Inventory.new(ReimuDefinition.inventory_slots)
    local loadout = Loadout.new(ReimuDefinition, { inventory = inventory, definition_lookup = registry })
    loadout:set_slot("high_weapons", 1, high_instance_a)
    loadout:set_slot("low_weapons", 1, low_instance)
    loadout:set_slot("supports", 1, support_instance)
    loadout:set_slot("self_modifiers", 1, self_instance)
    loadout:set_slot("support_modifiers", 1, support_modifier_instance)
    assert_equal(loadout:get_total_weight(), 9, "only weapons and supports count toward weight")
    assert_equal(loadout:debug_summary().high_slots.total, 3, "debug summary exposes dynamic slots")

    for index = 1, 6 do
        local item = EquipmentInstance.new(plain, 1)
        assert_true(inventory:add(item) ~= nil, "inventory accepts item " .. index)
    end
    local overflow = inventory:add(EquipmentInstance.new(plain, 1))
    assert_equal(overflow, nil, "seventh inventory item must not be accepted")
    local _, overflow_reason = inventory:add(EquipmentInstance.new(plain, 1))
    assert_equal(overflow_reason, "INVENTORY_FULL", "inventory returns explicit overflow status")
    assert_equal(inventory:count(), 6, "inventory cannot silently exceed capacity")
    assert_equal(loadout:get_total_weight(), 9, "inventory items do not add weight")

    assert_true(ModifierDefinition.is_conflicting(self_modifier, ModifierDefinition.new({
        modifier_id = "other_size", modifier_type = "SELF_MODIFIER", conflict_group = "projectile_size",
    })), "same modifier group conflicts")
    assert_true(not ModifierDefinition.is_conflicting(self_modifier, support_modifier), "different modifier groups do not conflict")

    local party = PartyState.new({ 1, 2 }, 10, { team_life = 0 })
    assert_equal(party:add_life_fragments(1), 0, "fragment threshold not reached")
    assert_equal(party:add_life_fragments(2), 1, "three fragments grant one team life")
    assert_equal(party.team_life, 1, "team life belongs to party")
    assert_equal(party.life_fragments, 0, "fragments roll over after conversion")

    local player = PlayerState.new(1, { loadout = loadout, inventory = inventory, map_ready = true })
    assert_equal(player.current_capacity, ReimuDefinition.base_capacity, "player capacity starts at base")
    local state_data = player:to_table()
    local restored = PlayerState.from_table(state_data, ReimuDefinition)
    assert_equal(restored.player_id, player.player_id, "player id serializes")
    assert_equal(restored.loadout.high_weapons[1].instance_id, high_instance_a.instance_id, "loadout instance serializes")
    assert_equal(restored.loadout.high_weapons[1].definition_id, high_instance_a.definition_id, "loadout definition serializes")
    assert_equal(restored.loadout.character_id, "reimu", "loadout character serializes")
    assert_equal(restored.map_ready, true, "player ready state serializes")
    assert_true(same_table(party:to_table(), PartyState.from_table(party:to_table()):to_table()), "party state is serializable")

    local players = { [1] = player, [2] = PlayerState.new(2) }
    assert_true(not party:is_ready(players), "party is not ready until every player is ready")
    players[2]:set_map_ready(true)
    assert_true(party:is_ready(players), "party becomes ready when every player is ready")

    local ok = pcall(function() ReimuDefinition.inventory_slots = 99 end)
    assert_true(not ok, "definitions are immutable")
end
