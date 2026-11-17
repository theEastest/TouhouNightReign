local Bootstrap = require("tnr.bootstrap")
local LuaSTGInputProvider = require("tnr.input.luastg_input")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local Command = require("tnr.core.command")
local FakeTransport = require("tnr.multiplayer.fake_transport")

return function(assert_equal, assert_true)
    local button = 0
    local provider = LuaSTGInputProvider.new({ Input = { Keyboard = {}, Mouse = {
        Secondary = 2, GetKeyState = function(code) if code == 2 then return button end return false end,
    } } })
    assert_equal(provider:poll(2).mouse_secondary_pressed, false, "numeric zero means button released")
    button = 1
    assert_true(provider:poll(2).mouse_secondary_pressed, "right click belongs to the local P2")
    assert_equal(provider:poll(2).mouse_secondary_pressed, false, "holding right click does not repeat")
    button = 0; provider:poll(2); button = 1
    assert_true(provider:poll(2).mouse_secondary_pressed, "a new right click produces a new edge")

    local app = Bootstrap.create({ run_seed = 789, player_count = 1 })
    app:start_game(789)
    assert_true(app.session:enter_preparation() ~= nil, "preparation opens")
    local player = app.session:get_player(1)
    local target
    app.input = { get_mouse_position = function() return 100, 100 end }
    app.renderer = {
        height = 720, width = 1280,
        scrollbar_index = function() return nil end,
        preparation_hit_test = function() return target end,
    }
    local function find_row(group, index)
        for i, row in ipairs(app:_preparation_rows()) do
            if row.kind == "equipped" and row.group == group and row.index == index then return i end
        end
    end
    local function right_click()
        app:_update_preparation({ move_y = 0, mouse_secondary_pressed = true }, false)
    end
    target = find_row("high_weapons", 2)
    assert_equal(player.loadout.high_weapons[2], false, "second weapon slot starts empty")
    local ok = pcall(function()
        app:_update_preparation({move_y = 0, mouse_primary_pressed = true}, false)
    end)
    assert_true(ok, "left clicking an empty equipment slot is safe")
    app.preparation_cursor = target
    ok = pcall(function()
        app:_update_preparation({move_y = 0, confirm = true}, false)
    end)
    assert_true(ok, "confirming an empty equipment slot is safe")
    assert_equal(player.loadout.inventory:count(), 0, "empty-slot input does not change inventory")
    local weapon = player.loadout.high_weapons[1]
    assert_true(weapon and weapon ~= false, "initial weapon is equipped")
    target = find_row("high_weapons", 1)
    right_click()
    assert_equal(player.loadout.high_weapons[1], false, "right click empties the weapon slot")
    assert_equal(player.loadout.inventory.items[1].instance_id, weapon.instance_id, "right click returns the same weapon")
    right_click()
    assert_equal(player.loadout.inventory:count(), 1, "right click on an empty slot has no effect")

    local modifier = EquipmentInstance.new(app.session.equipment_registry:get("test_support_modifier"), 1)
    assert_true(app.session.acquisition_service:acquire(1, modifier) ~= nil, "modifier enters inventory")
    assert_true(app.session:dispatch({type = Command.EQUIP_ITEM, player_id = 1, inventory_index = 2,
        slot_type = "support_modifiers", slot_index = 1}) ~= nil, "modifier equips")
    target = find_row("support_modifiers", 1)
    right_click()
    assert_equal(player.loadout.support_modifiers[1], false, "right click empties a support modifier slot")
    assert_equal(player.loadout.inventory.items[2].instance_id, modifier.instance_id, "modifier returns to inventory")

    assert_true(app.session:dispatch({type = Command.EQUIP_ITEM, player_id = 1, inventory_index = 1,
        slot_type = "high_weapons", slot_index = 1}) ~= nil, "weapon can be re-equipped")
    while not player.loadout.inventory:is_full() do
        player.loadout.inventory:add(EquipmentInstance.new(app.session.equipment_registry:get("test_high_weapon"), 1))
    end
    target = find_row("high_weapons", 1)
    right_click()
    assert_equal(player.loadout.high_weapons[1].instance_id, weapon.instance_id, "full inventory preserves equipped weapon")
    assert_equal(app.preparation_message, "INVENTORY_FULL", "full inventory reports why unequip failed")
    local failed, fail_reason = app.session:dispatch({type=Command.DISCARD_EQUIPPED_ITEM,player_id=1,
        slot_type="high_weapons",slot_index=1,expected_instance_id=weapon.instance_id})
    assert_equal(failed, nil, "a full inventory rejects equipped-item discard atomically")
    assert_equal(fail_reason, "INVENTORY_FULL", "discard preserves the unequip capacity check")
    assert_equal(player.loadout.high_weapons[1].instance_id, weapon.instance_id, "failed discard keeps the slot")
    assert_equal(player.loadout.inventory:count(), player.loadout.inventory.capacity, "failed discard keeps the inventory")
    failed, fail_reason = app.session:dispatch({type=Command.DISCARD_EQUIPPED_ITEM,player_id=1,
        slot_type="high_weapons",slot_index=1,expected_instance_id="stale-id"})
    assert_equal(failed, nil, "stale equipment command is rejected")
    assert_equal(fail_reason, "STALE_ITEM", "stale identity is reported")

    local host_link, client_link = FakeTransport.create_pair()
    local host = Bootstrap.create({transport=host_link,network_role="host",player_count=2,local_player_id=1,run_seed=99})
    local client = Bootstrap.create({transport=client_link,network_role="client",player_count=2,local_player_id=2,run_seed=99})
    host.session:start_new(99); client.session:start_new(99)
    local peer_weapon_ids = {}
    for _, peer in ipairs({host, client}) do
        local loadout = peer.session:get_player(2).loadout
        peer_weapon_ids[peer] = loadout.high_weapons[1].instance_id
        local def = peer.session.equipment_registry:get("test_high_weapon")
        loadout.inventory:add(EquipmentInstance.new(def, 2, {instance_id="inventory-1"}))
        assert_true(peer.session:enter_preparation() ~= nil, "network preparation opens")
    end
    assert_true(peer_weapon_ids[host] ~= peer_weapon_ids[client], "process histories can produce different instance IDs")
    local net_target
    client.input = {get_mouse_position = function() return 100, 100 end}
    client.renderer = {height=720,width=1280,scrollbar_index=function() return nil end,
        preparation_hit_test=function() return net_target end}
    local function select_row(kind, group, index)
        for i, row in ipairs(client:_preparation_rows()) do
            if row.kind == kind and row.group == group and row.index == index then net_target = i; return end
        end
        error("missing network preparation row")
    end
    local function pump() host_link:update(); client_link:update() end
    local function input(values) values.move_y=0; client:_update_preparation(values, false) end
    select_row("equipped", "supports", 1)
    input({mouse_primary_pressed=true}); pump()
    for _, peer in ipairs({host, client}) do
        assert_equal(peer.session:get_player(2).loadout.supports[1].runtime_data.enabled, false, "support click synchronizes")
    end
    select_row("equipped", "high_weapons", 1)
    input({mouse_secondary_pressed=true}); pump()
    for _, peer in ipairs({host, client}) do
        assert_equal(peer.session:get_player(2).loadout.high_weapons[1], false, "right click synchronizes")
        assert_equal(peer.session:get_player(2).loadout.inventory.items[2].instance_id, peer_weapon_ids[peer], "same local weapon is returned")
    end
    select_row("inventory", nil, 2)
    input({mouse_primary_pressed=true}); pump()
    for _, peer in ipairs({host, client}) do
        assert_equal(peer.session:get_player(2).loadout.high_weapons[1].instance_id, peer_weapon_ids[peer], "equip click synchronizes")
    end
    select_row("inventory", nil, 1)
    client.preparation_cursor=net_target
    input({backspace=true}); pump()
    assert_equal(host.session:get_player(2).loadout.inventory:count(), 1, "first discard press only asks for confirmation")
    input({backspace=true}); pump()
    for _, peer in ipairs({host, client}) do
        assert_equal(peer.session:get_player(2).loadout.inventory:count(), 0, "inventory discard synchronizes")
    end
    select_row("equipped", "high_weapons", 1)
    client.preparation_cursor=net_target
    input({backspace=true}); input({backspace=true}); pump()
    for _, peer in ipairs({host, client}) do
        assert_equal(peer.session:get_player(2).loadout.high_weapons[1], false, "equipped discard synchronizes")
        assert_equal(peer.session:get_player(2).loadout.inventory:count(), 0, "discarded equipment is not left in inventory")
    end
end
