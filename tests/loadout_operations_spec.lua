local GameSession = require("tnr.core.game_session")
local Command = require("tnr.core.command")
local EquipmentInstance = require("tnr.equipment.equipment_instance")

return function(assert_equal, assert_true)
    local function new_session(seed)
        local session = GameSession.new({ run_seed = seed or 7001, player_count = 1 })
        session:start_new(seed or 7001)
        return session
    end

    local session = new_session()
    local player = session:get_player(1)
    local registry = session.equipment_registry
    local high = registry:get("test_high_weapon")
    local low = registry:get("test_low_weapon")
    local support = registry:get("test_support")
    local modifier = registry:get("test_self_modifier")
    assert_true(registry:get("test_dual_weapon") ~= nil, "catalog includes a third weapon")
    assert_true(registry:get("test_support_alt") ~= nil, "catalog includes a second support")
    assert_true(registry:get("test_self_modifier_alt") ~= nil, "catalog includes a second self modifier")
    assert_true(registry:get("test_support_modifier_alt") ~= nil, "catalog includes a second support modifier")
    local function instance(definition)
        return EquipmentInstance.new(definition, 1)
    end

    local first = instance(high)
    assert_true(session:dispatch({ type = Command.ACQUIRE_ITEM, player_id = 1, instance = first }) ~= nil, "acquisition should enter inventory")
    assert_equal(player.loadout.inventory:count(), 1, "acquisition never auto-equips")
    local equipped = session:dispatch({ type = Command.EQUIP_ITEM, player_id = 1, inventory_index = 1, slot_type = "high_weapons", slot_index = 2 })
    assert_equal(equipped.instance_id, first.instance_id, "inventory item equips into empty slot")
    assert_equal(player.loadout.inventory:count(), 0, "equipped item leaves inventory")

    local removed = session:dispatch({ type = Command.UNEQUIP_ITEM, player_id = 1, slot_type = "high_weapons", slot_index = 2 })
    assert_equal(removed.instance_id, first.instance_id, "unequip returns instance")
    assert_equal(player.loadout.inventory:count(), 1, "unequipped item enters inventory")

    local second = instance(low)
    session:dispatch({ type = Command.ACQUIRE_ITEM, player_id = 1, instance = second })
    session:dispatch({ type = Command.EQUIP_ITEM, player_id = 1, inventory_index = 2, slot_type = "low_weapons", slot_index = 2 })
    assert_equal(player.loadout.low_weapons[2].instance_id, second.instance_id, "low weapon equips into low slot")
    local bad, bad_reason = session:dispatch({ type = Command.EQUIP_ITEM, player_id = 1, inventory_index = 1, slot_type = "supports", slot_index = 1 })
    assert_equal(bad, nil, "weapon cannot enter support slot")
    assert_equal(bad_reason, "ILLEGAL_SLOT_TYPE", "illegal slot has explicit reason")
    local relic_bad, relic_reason = session.loadout_service:can_equip({ definition_id = "test_relic", equipment_type = "RELIC", owner_player_id = 1 }, "high_weapons", 1, 1)
    assert_equal(relic_bad, false, "relic cannot enter an equipment slot")
    assert_equal(relic_reason, "NOT_EQUIPPABLE", "relic is not an equipment definition")
    local relic_instance = EquipmentInstance.new(registry and session.equipment_registry and require("tnr.equipment.phase1_catalog").relics.test_relic or "test_relic", 1)
    local relic_acquired, relic_acquire_reason = session.acquisition_service:acquire(1, relic_instance)
    assert_equal(relic_acquired, nil, "relic cannot enter inventory")
    assert_equal(relic_acquire_reason, "NOT_EQUIPPABLE", "relic acquisition is rejected")

    local swap_session = new_session(7006)
    local swap_player = swap_session:get_player(1)
    local swap_a, swap_b = instance(high), instance(registry:get("test_dual_weapon"))
    swap_session.acquisition_service:acquire(1, swap_a)
    swap_session:dispatch({ type = Command.EQUIP_ITEM, player_id = 1, inventory_index = 1, slot_type = "high_weapons", slot_index = 2 })
    swap_session.acquisition_service:acquire(1, swap_b)
    local swap_result = swap_session:dispatch({ type = Command.EQUIP_ITEM, player_id = 1, inventory_index = 1, slot_type = "high_weapons", slot_index = 2 })
    assert_equal(swap_result.instance_id, swap_b.instance_id, "occupied slot accepts an inventory replacement")
    assert_equal(swap_player.loadout.inventory.items[1].instance_id, swap_a.instance_id, "occupied-slot swap returns old item atomically")

    local middle_session = new_session(7013)
    local middle_player = middle_session:get_player(1)
    local middle_a, middle_b, middle_c = instance(high), instance(high), instance(high)
    middle_session.acquisition_service:acquire(1, middle_a)
    middle_session.acquisition_service:acquire(1, middle_b)
    middle_session.acquisition_service:acquire(1, middle_c)
    local middle_result = middle_session:dispatch({
        type = Command.EQUIP_ITEM, player_id = 1, inventory_index = 2,
        slot_type = "high_weapons", slot_index = 2,
    })
    assert_equal(middle_result.instance_id, middle_b.instance_id, "middle inventory item equips")
    assert_equal(middle_player.loadout.inventory:count(), 2, "middle equip removes exactly one inventory item")
    assert_equal(middle_player.loadout.inventory.items[1].instance_id, middle_a.instance_id,
        "middle equip preserves the preceding inventory item")
    assert_equal(middle_player.loadout.inventory.items[2].instance_id, middle_c.instance_id,
        "middle equip preserves the following inventory item")
    assert_equal(middle_player.loadout.high_weapons[2].instance_id, middle_b.instance_id,
        "middle equip preserves the selected instance")
    assert_true(middle_session.loadout_service:validate(1), "middle equip leaves a valid loadout")

    local full_session = new_session(7002)
    local full_player = full_session:get_player(1)
    for _ = 1, 6 do full_session.acquisition_service:acquire(1, instance(registry:get("test_high_weapon"))) end
    assert_equal(full_player.loadout.inventory:count(), 6, "inventory reaches configured capacity")
    local pending = instance(registry:get("test_support"))
    local acquired, pending_reason = full_session.acquisition_service:acquire(1, pending)
    assert_equal(acquired, nil, "full inventory does not accept silently")
    assert_equal(pending_reason, "INVENTORY_FULL", "full inventory returns overflow")
    assert_equal(full_session.preparation.pending_acquisition[1].instance_id, pending.instance_id, "pending item is retained")
    local ready, ready_reason = full_session:set_player_ready(1, true)
    assert_equal(ready, nil, "pending acquisition blocks Ready")
    assert_equal(ready_reason, "当前不在地图整备状态", "Ready requires preparation state")
    full_session:enter_preparation()
    ready, ready_reason = full_session:set_player_ready(1, true)
    assert_equal(ready, nil, "pending acquisition still blocks Ready")
    assert_equal(ready_reason, "PENDING_ACQUISITION", "pending reason is explicit")
    local accepted, discarded = full_session.acquisition_service:accept_pending(1, 1)
    assert_equal(accepted.instance_id, pending.instance_id, "overflow accepts new item after discard")
    assert_true(discarded ~= nil, "overflow reports discarded item")
    assert_equal(full_player.loadout.inventory:count(), 6, "overflow replacement preserves capacity")
    assert_true(full_session:set_player_ready(1, true), "Ready succeeds after overflow resolution")
    assert_true(not full_session.loadout_service:unequip(1, "high_weapons", 1), "locked loadout cannot be edited")
    local locked_acquire, locked_acquire_reason = full_session.acquisition_service:acquire(1, instance(high))
    assert_equal(locked_acquire, nil, "locked player cannot acquire into inventory")
    assert_equal(locked_acquire_reason, "LOADOUT_LOCKED", "locked acquisition has explicit reason")
    full_session:set_player_ready(1, false)
    assert_true(full_session.loadout_service:discard_inventory(1, 1) ~= nil, "cancel Ready unlocks inventory editing")

    local reject_session = new_session(7007)
    for _ = 1, 6 do reject_session.acquisition_service:acquire(1, instance(high)) end
    reject_session.acquisition_service:acquire(1, instance(support))
    assert_true(reject_session.acquisition_service:reject_pending(1), "pending item can be rejected")
    assert_equal(reject_session.acquisition_service:get_pending(1), nil, "rejected item is destroyed")

    local full_unequip = new_session(7008)
    for _ = 1, 5 do full_unequip.acquisition_service:acquire(1, instance(high)) end
    full_unequip.acquisition_service:acquire(1, instance(high))
    local unequip_result, unequip_reason = full_unequip.loadout_service:unequip(1, "high_weapons", 1)
    assert_equal(unequip_result, nil, "full inventory blocks unequip")
    assert_equal(unequip_reason, "INVENTORY_FULL", "unequip reports full inventory")

    local conflict_session = new_session(7003)
    local conflict_player = conflict_session:get_player(1)
    local mod_a = instance(modifier)
    local mod_b = instance(modifier)
    conflict_session.acquisition_service:acquire(1, mod_a)
    conflict_session:dispatch({ type = Command.EQUIP_ITEM, player_id = 1, inventory_index = 1, slot_type = "self_modifiers", slot_index = 1 })
    conflict_session.acquisition_service:acquire(1, mod_b)
    conflict_session:dispatch({ type = Command.EQUIP_ITEM, player_id = 1, inventory_index = 1, slot_type = "self_modifiers", slot_index = 2 })
    assert_equal(conflict_player.loadout.self_modifiers[2].instance_id, mod_b.instance_id, "conflicting modifier replaces old module")
    assert_equal(conflict_player.loadout.inventory.items[1].instance_id, mod_a.instance_id, "replaced modifier returns to inventory")

    local multi_session = new_session(7009)
    local multi_player = multi_session:get_player(1)
    local multi_a, multi_b, multi_c = instance(modifier), instance(modifier), instance(modifier)
    multi_player.loadout:set_slot("self_modifiers", 1, multi_a)
    multi_player.loadout:set_slot("self_modifiers", 2, multi_b)
    multi_session.acquisition_service:acquire(1, multi_c)
    local valid, valid_reason = multi_session.loadout_service:validate(1)
    assert_equal(valid, nil, "invalid duplicate modifier groups block node entry")
    assert_equal(valid_reason, "CONFLICTING_MODIFIERS", "validation reports conflicting modifiers")

    local move_session = new_session(7004)
    local move_player = move_session:get_player(1)
    local move_a, move_b = instance(high), instance(low)
    move_session.acquisition_service:acquire(1, move_a)
    move_session.acquisition_service:acquire(1, move_b)
    assert_true(move_session.loadout_service:move_inventory(1, 1, 2), "inventory move/swap succeeds")
    assert_equal(move_player.loadout.inventory.items[1].instance_id, move_b.instance_id, "inventory swap preserves identity")
    assert_equal(move_player.loadout.inventory.items[2].instance_id, move_a.instance_id, "inventory swap preserves order")
    assert_true(move_session.loadout_service:move_inventory(1, 1, 6), "move to an empty inventory slot stays compact")
    assert_equal(move_player.loadout.inventory:count(), 2, "empty-slot move does not create sparse inventory")
    assert_true(move_session.loadout_service:discard_inventory(1, 2) ~= nil, "inventory discard succeeds")
    assert_equal(move_player.loadout.inventory:count(), 1, "discard removes exactly one item")

    local combat_session = new_session(7012)
    local combat_target
    for _, candidate_id in ipairs(combat_session.map:get_current_node().links) do
        local candidate = combat_session.map:get_node(candidate_id)
        if candidate and (candidate.type == "ENEMY" or candidate.type == "ELITE" or candidate.type == "BOSS") then
            combat_target = candidate_id
            break
        end
    end
    assert_true(combat_target ~= nil, "combat lock test has a combat node")
    assert_true(combat_session:select_node(combat_target, 1) ~= nil, "combat lock test enters encounter")
    local combat_discard, combat_discard_reason = combat_session.loadout_service:discard_inventory(1, 1)
    assert_equal(combat_discard, nil, "combat cannot mutate inventory")
    assert_equal(combat_discard_reason, "NOT_MAP", "combat inventory mutation has explicit reason")

    local ready_session = new_session(7005)
    local target
    for _, candidate_id in ipairs(ready_session.map:get_current_node().links) do
        local candidate = ready_session.map:get_node(candidate_id)
        if candidate and (candidate.type == "ENEMY" or candidate.type == "ELITE" or candidate.type == "BOSS") then
            target = candidate_id
            break
        end
    end
    assert_true(target ~= nil, "test map has an adjacent combat node")
    assert_true(ready_session:enter_preparation(target) ~= nil, "preparation accepts adjacent target")
    assert_true(ready_session:set_player_ready(1, true), "single player can Ready")
    assert_true(ready_session:commit_prepared_node() ~= nil, "all Ready commits selected node")
    assert_equal(ready_session.run_state, "ENCOUNTER", "committed preparation enters encounter")

    local gated_session = GameSession.new({ run_seed = 7011, player_count = 1, preparation_required = true })
    gated_session:start_new(7011)
    local gated_target
    for _, candidate_id in ipairs(gated_session.map:get_current_node().links) do
        local candidate = gated_session.map:get_node(candidate_id)
        if candidate and (candidate.type == "ENEMY" or candidate.type == "ELITE" or candidate.type == "BOSS") then
            gated_target = candidate_id
            break
        end
    end
    assert_true(gated_target ~= nil, "gated map has an adjacent combat node")
    assert_true(gated_session:select_node(gated_target, 1) ~= nil, "gated node selection opens preparation")
    assert_equal(gated_session.run_state, "MAP_PREPARATION", "single-player map selection uses preparation state")
    assert_true(gated_session:set_player_ready(1, true), "gated single player can Ready")
    assert_true(gated_session:commit_prepared_node() ~= nil, "gated preparation commits after Ready")
    assert_equal(gated_session.run_state, "ENCOUNTER", "gated preparation enters encounter")

    local party_session = GameSession.new({ run_seed = 7010, player_count = 2 })
    party_session:start_new(7010)
    assert_true(party_session:enter_preparation() ~= nil, "two-player preparation opens")
    assert_true(party_session:set_player_ready(1, true), "P1 can Ready independently")
    assert_true(not party_session.preparation:is_party_ready(party_session.party.player_ids), "one Ready player cannot start the party")
    assert_true(party_session:set_player_ready(2, true), "P2 can Ready independently")
    assert_true(party_session.preparation:is_party_ready(party_session.party.player_ids), "both Ready players can start the party")
end
