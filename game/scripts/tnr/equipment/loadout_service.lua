local ModifierDefinition = require("tnr.equipment.modifier_definition")
local Constants = require("tnr.core.constants")

local LoadoutService = {}
LoadoutService.__index = LoadoutService

-- States in which the player may edit their loadout. The shop exposes the
-- loadout screen as an overlay and the reward flow also grants equipment, so
-- both are accepted alongside the map and preparation screens.
local function loadout_editable(run_state)
    return run_state == Constants.run_states.MAP
        or run_state == Constants.run_states.MAP_PREPARATION
        or run_state == Constants.run_states.SHOP
        or run_state == Constants.run_states.REWARD
end

local SLOT_TYPES = {
    high_weapons = "HIGH_WEAPON",
    low_weapons = "LOW_WEAPON",
    supports = "SUPPORT",
    self_modifiers = "SELF_MODIFIER",
    support_modifiers = "SUPPORT_MODIFIER",
}

function LoadoutService.new(session, equipment_registry)
    return setmetatable({ session = session, registry = equipment_registry }, LoadoutService)
end

function LoadoutService:_definition(instance)
    return instance and self.registry and self.registry:get(instance.definition_id) or nil
end

function LoadoutService:can_equip(instance, slot_type, slot_index, player_id, ignore_lock)
    if not instance then return false, "MISSING_INSTANCE" end
    local player = self.session:get_player(player_id)
    if not player or not player.loadout then return false, "UNKNOWN_PLAYER" end
    if not loadout_editable(self.session.run_state) then
        return false, "NOT_MAP"
    end
    if not ignore_lock and self.session.preparation and not self.session.preparation:can_edit(player_id) then
        return false, "LOADOUT_LOCKED"
    end
    if instance.owner_player_id ~= player_id then return false, "WRONG_OWNER" end
    if instance.equipment_type == "RELIC" then return false, "NOT_EQUIPPABLE" end
    local slots = player.loadout[slot_type]
    if not slots or type(slot_index) ~= "number" or slot_index < 1 or slot_index > #slots then
        return false, "INVALID_SLOT"
    end
    local definition = self:_definition(instance)
    if not definition then return false, "UNKNOWN_DEFINITION" end
    -- A non-dual weapon instance has one slot identity.  Reject attempts to
    -- place the same instance in the other weapon collection; moving it must
    -- go through an explicit unequip first.
    if definition.equipment_type == "WEAPON" and not definition.dual_mode then
        local current = player.loadout:get_slot(slot_type, slot_index)
        for equipped_group, equipped_index, equipped in player.loadout:iter_equipped() do
            if equipped ~= current and equipped.instance_id == instance.instance_id
                    and (equipped_group == "high_weapons" or equipped_group == "low_weapons") then
                return false, "ALREADY_EQUIPPED"
            end
        end
    end
    local expected = SLOT_TYPES[slot_type]
    if definition.equipment_type == "WEAPON" then
        if expected ~= "HIGH_WEAPON" and expected ~= "LOW_WEAPON" then return false, "ILLEGAL_SLOT_TYPE" end
        local allowed = definition.allowed_slots or { HIGH_WEAPON = true, LOW_WEAPON = true }
        if not allowed[expected] then return false, "ILLEGAL_SLOT_TYPE" end
    elseif definition.equipment_type == "SUPPORT" then
        if expected ~= "SUPPORT" then return false, "ILLEGAL_SLOT_TYPE" end
    elseif definition.equipment_type == "SELF_MODIFIER" then
        if expected ~= "SELF_MODIFIER" then return false, "ILLEGAL_SLOT_TYPE" end
    elseif definition.equipment_type == "SUPPORT_MODIFIER" then
        if expected ~= "SUPPORT_MODIFIER" then return false, "ILLEGAL_SLOT_TYPE" end
    else
        return false, "NOT_EQUIPPABLE"
    end
    return true
end

local function find_instance(inventory, instance_id)
    return inventory and inventory:find(instance_id)
end

function LoadoutService:equip_from_inventory(player_id, inventory_index, slot_type, slot_index)
    local player = self.session:get_player(player_id)
    if not player then return nil, "UNKNOWN_PLAYER" end
    if not loadout_editable(self.session.run_state) then return nil, "NOT_MAP" end
    local inventory = player.loadout.inventory
    local instance = inventory and inventory.items[inventory_index]
    local ok, err = self:can_equip(instance, slot_type, slot_index, player_id)
    if not ok then return nil, err end
    local old = player.loadout:get_slot(slot_type, slot_index)
    local conflicts = {}
    local definition = self:_definition(instance)
    if definition and (definition.equipment_type == "SELF_MODIFIER" or definition.equipment_type == "SUPPORT_MODIFIER") then
        for group, equipped_index, equipped in player.loadout:iter_equipped() do
            local equipped_definition = self:_definition(equipped)
            if group == slot_type and equipped_definition and ModifierDefinition.is_conflicting(definition, equipped_definition) and equipped ~= old then
                conflicts[#conflicts + 1] = { instance = equipped, slot_index = equipped_index }
            end
        end
        if #conflicts > 1 then return nil, "MULTIPLE_CONFLICTS" end
    end

    -- Keep the inventory a compact sequence. Assigning nil before
    -- table.remove makes the length operator ambiguous when the selected item
    -- is in the middle, which can hide the following inventory item.
    local displaced = {}
    if old then displaced[#displaced + 1] = old end
    if conflicts[1] then displaced[#displaced + 1] = conflicts[1].instance end
    if #inventory.items - 1 + #displaced > inventory.capacity then
        return nil, "INVENTORY_FULL"
    end

    local removed = table.remove(inventory.items, inventory_index)
    if removed ~= instance then return nil, "INVENTORY_CORRUPT" end
    player.loadout:set_slot(slot_type, slot_index, instance)
    if conflicts[1] then
        player.loadout:set_slot(slot_type, conflicts[1].slot_index, false)
    end

    local insert_at = math.min(inventory_index, #inventory.items + 1)
    for _, displaced_instance in ipairs(displaced) do
        table.insert(inventory.items, insert_at, displaced_instance)
        insert_at = insert_at + 1
    end
    return instance
end

function LoadoutService:unequip(player_id, slot_type, slot_index)
    local player = self.session:get_player(player_id)
    if not player then return nil, "UNKNOWN_PLAYER" end
    if not loadout_editable(self.session.run_state) then return nil, "NOT_MAP" end
    if self.session.preparation and not self.session.preparation:can_edit(player_id) then return nil, "LOADOUT_LOCKED" end
    local instance = player.loadout:get_slot(slot_type, slot_index)
    if not instance then return nil, "EMPTY_SLOT" end
    local inventory = player.loadout.inventory
    local added, err = inventory:add(instance)
    if not added then return nil, err end
    player.loadout:set_slot(slot_type, slot_index, false)
    return instance
end

function LoadoutService:move_inventory(player_id, from_index, to_index)
    local player = self.session:get_player(player_id)
    if not player then return nil, "UNKNOWN_PLAYER" end
    if not loadout_editable(self.session.run_state) then return nil, "NOT_MAP" end
    if self.session.preparation and not self.session.preparation:can_edit(player_id) then return nil, "LOADOUT_LOCKED" end
    local inventory = player.loadout.inventory
    if not inventory.items[from_index] or to_index < 1 or to_index > inventory.capacity then return nil, "INVALID_SLOT" end
    if inventory.items[to_index] and from_index ~= to_index then
        inventory.items[from_index], inventory.items[to_index] = inventory.items[to_index], inventory.items[from_index]
    elseif from_index ~= to_index then
        -- Inventory is a compact list; an empty destination means append to
        -- the end rather than creating a sparse array and corrupting count().
        local item = table.remove(inventory.items, from_index)
        inventory.items[#inventory.items + 1] = item
    end
    return true
end

function LoadoutService:discard_inventory(player_id, inventory_index)
    local player = self.session:get_player(player_id)
    if not player then return nil, "UNKNOWN_PLAYER" end
    if not loadout_editable(self.session.run_state) then return nil, "NOT_MAP" end
    if self.session.preparation and not self.session.preparation:can_edit(player_id) then return nil, "LOADOUT_LOCKED" end
    return player.loadout.inventory:remove(inventory_index)
end

function LoadoutService:validate(player_id)
    local player = self.session:get_player(player_id)
    if not player or not player.loadout then return nil, "UNKNOWN_PLAYER" end
    local seen = {}
    local modifier_groups = {}
    for group, slot_index, instance in player.loadout:iter_equipped() do
        local ok, err = self:can_equip(instance, group, slot_index, player_id, true)
        if not ok and err ~= "INVALID_SLOT" then return nil, err end
        if instance.owner_player_id ~= player_id then return nil, "WRONG_OWNER" end
        if seen[instance.instance_id] then return nil, "DUPLICATE_INSTANCE" end
        seen[instance.instance_id] = true
        local definition = self:_definition(instance)
        if not definition then return nil, "UNKNOWN_DEFINITION" end
        if definition.equipment_type == "SELF_MODIFIER" or definition.equipment_type == "SUPPORT_MODIFIER" then
            local group_key = group .. ":" .. tostring(definition.conflict_group or "")
            if definition.conflict_group and modifier_groups[group_key] then return nil, "CONFLICTING_MODIFIERS" end
            modifier_groups[group_key] = true
        end
    end
    for _, instance in ipairs(player.loadout.inventory.items) do
        if seen[instance.instance_id] then return nil, "DUPLICATE_INSTANCE" end
        if instance.owner_player_id ~= player_id then return nil, "WRONG_OWNER" end
        if not self:_definition(instance) then return nil, "UNKNOWN_DEFINITION" end
        seen[instance.instance_id] = true
    end
    return true
end

return LoadoutService
