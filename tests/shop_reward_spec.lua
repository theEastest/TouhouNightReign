local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")
local ShopService = require("tnr.shop.shop_service")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local Command = require("tnr.core.command")

return function(assert_equal, assert_true)
    -- Full-inventory shop purchases wait for a replacement decision.
    local session = GameSession.new({ run_seed = 4242, player_count = 1 }):start_new()
    session.run_state = Constants.run_states.SHOP
    session.shop_service = ShopService.new(session)
    session.shop_service:open({ id = 1, content_seed = 1 })
    local player = session:get_player(1)
    local inventory = player.loadout.inventory
    while inventory:count() < inventory.capacity do
        inventory:add(EquipmentInstance.new(session.equipment_registry:get("hakurei_sealing_needle"), 1))
    end
    local equipment_slot
    for index, offer in ipairs(session.shop_service:get_offers()) do
        if offer.kind == "EQUIPMENT" then equipment_slot = index break end
    end
    assert_true(equipment_slot ~= nil, "shop must offer at least one equipment item")
    player.money = 100
    session.shop_service.offers[equipment_slot].price = 10
    local purchased = session.shop_service:purchase(1, equipment_slot)
    assert_true(purchased and purchased.pending, "a full purchase requests a replacement decision")
    assert_equal(player.money, 100, "pending purchase is not charged")
    local ready, ready_err = session.shop_service:set_ready(1, true)
    assert_equal(ready, nil, "shop cannot close with an unresolved item")
    assert_equal(ready_err, "PENDING_ACQUISITION", "shop reports pending acquisition")
    assert_true(session:dispatch({type = Command.REJECT_PENDING_ITEM, player_id = 1}) ~= nil, "player can reject the shop item")
    assert_equal(player.money, 100, "rejecting the item does not charge")
    assert_equal(inventory:count(), 12, "rejecting preserves the warehouse")
    local second = session.shop_service:purchase(1, equipment_slot)
    assert_true(second and second.pending, "the rejected offer remains available")
    assert_true(session:dispatch({type = Command.ACCEPT_PENDING_ITEM, player_id = 1, discard_index = 12}) ~= nil,
        "player can replace a selected item")
    assert_equal(player.money, 90, "accepting charges exactly once")
    assert_equal(inventory.items[12].instance_id, second.instance.instance_id, "the selected warehouse item is replaced")
    local repeat_purchase, repeat_err = session.shop_service:purchase(1, equipment_slot)
    assert_equal(repeat_purchase, nil, "accepted offer cannot be purchased twice")
    assert_equal(repeat_err, "ALREADY_PURCHASED", "accepted purchase is recorded")
    ready, ready_err = session.shop_service:set_ready(1, true)
    assert_true(ready ~= nil, "the shop remains leavable after resolution: " .. tostring(ready_err))
    assert_equal(session.run_state, Constants.run_states.MAP, "leaving the shop returns to the map")

    -- Rewards can be toggled: claiming then unclaiming must exactly undo the
    -- grant so a mis-click is recoverable before confirming.
    local reward_session = GameSession.new({ run_seed = 99, player_count = 1 }):start_new()
    reward_session.run_state = Constants.run_states.REWARD
    reward_session.reward_required = 2
    reward_session.reward_choices = {
        { kind = "RESOURCE", resource = "bomb", amount = 1 },
        { kind = "RESOURCE", resource = "life", amount = 1 },
    }
    reward_session.reward_claims = {}
    local bombs_before = reward_session:get_player(1).bomb
    assert_true(reward_session:claim_reward(1, 1) ~= nil, "a reward can be claimed")
    assert_equal(reward_session:get_player(1).bomb, bombs_before + 1, "claiming a bomb reward grants a bomb")
    assert_true(reward_session:unclaim_reward(1, 1), "a claimed reward can be unclaimed")
    assert_equal(reward_session:get_player(1).bomb, bombs_before, "unclaiming a bomb reward removes it again")
    assert_equal(#(reward_session.reward_claims[1] or {}), 0, "the claim list is empty after unclaiming")

    local inventory = reward_session:get_player(1).loadout.inventory
    local inventory_before = inventory:count()
    reward_session.reward_choices = {
        { kind = "EQUIPMENT", definition_id = "hakurei_sealing_needle" },
        { kind = "RESOURCE", resource = "bomb", amount = 1 },
    }
    assert_true(reward_session:claim_reward(1, 1) ~= nil, "an equipment reward can be claimed")
    assert_equal(inventory:count(), inventory_before + 1, "claiming equipment adds it to the inventory")
    assert_true(reward_session:unclaim_reward(1, 1), "a claimed equipment reward can be unclaimed")
    assert_equal(inventory:count(), inventory_before, "unclaiming equipment removes it from the inventory")

    -- A full inventory turns an equipment reward into a pending acquisition
    -- (resolved later through the acquisition flow) instead of a hang.
    local full_session = GameSession.new({ run_seed = 5, player_count = 1 }):start_new()
    full_session.run_state = Constants.run_states.REWARD
    full_session.reward_required = 1
    full_session.reward_choices = { { kind = "EQUIPMENT", definition_id = "hakurei_sealing_needle" } }
    full_session.reward_claims = {}
    local full_player = full_session:get_player(1)
    while full_player.loadout.inventory:count() < full_player.loadout.inventory.capacity do
        full_player.loadout.inventory:add(EquipmentInstance.new(full_session.equipment_registry:get("hakurei_sealing_needle"), 1))
    end
    local claim_result, claim_err = full_session:claim_reward(1, 1)
    assert_true(claim_result ~= nil or claim_err ~= nil,
        "a full-inventory equipment reward must resolve to a claim or an error, never a hang")
    if claim_result then
        assert_true(claim_result.pending == true or claim_result.acquired == true,
            "a full-inventory equipment reward is recorded as pending or acquired")
    end

    -- The loadout screen opened from the shop runs while the run state is
    -- SHOP, so equipping and unequipping must be accepted there. This used to
    -- report NOT_MAP and silently did nothing.
    local Command = require("tnr.core.command")
    local shop_session = GameSession.new({ run_seed = 31, player_count = 1 }):start_new()
    shop_session.run_state = Constants.run_states.SHOP
    local shop_player = shop_session:get_player(1)
    local shop_inventory = shop_player.loadout.inventory
    shop_inventory:add(EquipmentInstance.new(shop_session.equipment_registry:get("hakurei_sealing_needle"), 1))
    local inventory_before = shop_inventory:count()
    local equipped, equip_err = shop_session:dispatch({
        type = Command.EQUIP_ITEM, player_id = 1, inventory_index = 1,
        slot_type = "high_weapons", slot_index = 2,
    })
    assert_true(equipped ~= nil, "equipping from the shop must succeed: " .. tostring(equip_err))
    assert_equal(shop_inventory:count(), inventory_before - 1,
        "equipping from the shop removes the item from the inventory")
    local removed, unequip_err = shop_session:dispatch({
        type = Command.UNEQUIP_ITEM, player_id = 1, slot_type = "high_weapons", slot_index = 2,
    })
    assert_true(removed ~= nil, "unequipping from the shop must succeed: " .. tostring(unequip_err))
    assert_equal(shop_inventory:count(), inventory_before,
        "unequipping from the shop returns the item to the inventory")
end
