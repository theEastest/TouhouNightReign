local Bootstrap = require("tnr.bootstrap")
local Constants = require("tnr.core.constants")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local MapRenderer = require("tnr.ui.map_renderer")
local PreparationState = require("tnr.preparation.preparation_state")
local GameSession = require("tnr.core.game_session")
local FakeTransport = require("tnr.multiplayer.fake_transport")
local Command = require("tnr.core.command")
local Immutable = require("tnr.core.immutable")
local Inventory = require("tnr.equipment.inventory")

return function(assert_equal, assert_true)
    local app = Bootstrap.create({ run_seed = 7821, player_count = 1 })
    app:start_game(7821)
    local session = app.session
    local inventory = session:get_player(1).loadout.inventory
    local definition = session.equipment_registry:get("test_high_weapon")
    for _ = 1, inventory.capacity do inventory:add(EquipmentInstance.new(definition, 1)) end
    assert_equal(inventory:count(), 12, "all twelve slots are filled")
    local old_first = inventory.items[1].instance_id
    local old_last = inventory.items[12].instance_id
    session.run_state = Constants.run_states.REWARD
    session.reward_required = 1
    session.reward_choices = {{ kind = "EQUIPMENT", definition_id = "test_high_weapon" }}
    session.reward_claims = {}
    local claim = session:claim_reward(1, 1)
    assert_true(claim and claim.pending and not claim.acquired, "full reward is recorded as pending")
    assert_equal(session.run_state, Constants.run_states.MAP, "reward flow returns to map")
    assert_equal(session.acquisition_service:get_pending(1).instance_id, claim.equipment.instance_id, "map reset preserves pending reward")
    local second = session.equipment_reward_service:grant("test_support", 1)
    assert_true(second and second.pending, "a second full reward is queued")
    local restored = PreparationState.from_table(session.preparation:to_table())
    assert_equal(restored.pending_acquisition[1].instance_id, claim.equipment.instance_id, "pending reward survives serialization")
    assert_equal(restored.pending_acquisition_queue[1][1].instance_id, second.instance.instance_id, "queued reward survives serialization")

    local renderer = MapRenderer.new(nil, 1280, 720)
    local rows = app:_preparation_rows()
    local last_row
    for i, row in ipairs(rows) do if row.kind == "inventory" and row.index == 12 then last_row = i end end
    assert_equal(renderer:preparation_hit_test(1050, 110, #rows, 1, session:get_player(1).loadout), last_row, "twelfth item is visible and clickable")
    assert_equal(renderer:preparation_hit_test(1030, 110, #rows, 1, session:get_player(1).loadout), nil, "gap between columns is not clickable")
    app.renderer = renderer
    app.input = { get_mouse_position = function() return 1050, 110 end }
    app:_update_pending_acquisition({ move_x = 0, move_y = 0, mouse_primary_pressed = true })
    assert_equal(app.preparation_cursor, last_row, "mouse selects the desired item before confirmation")
    assert_equal(inventory.items[12].instance_id, old_last, "selection does not discard before confirmation")
    app:_update_pending_acquisition({ move_x = 0, move_y = 0, confirm = true })
    app.transport:update()
    assert_equal(inventory:count(), 12, "replacement preserves capacity")
    assert_equal(inventory.items[12].instance_id, claim.equipment.instance_id, "confirmed item replaces the chosen slot")
    assert_equal(inventory.items[1].instance_id, old_first, "other inventory items are preserved")
    assert_equal(session.acquisition_service:get_pending(1).instance_id, second.instance.instance_id, "next queued item is presented")
    app:_update_pending_acquisition({ move_x = 0, move_y = 0, cancel = true })
    app.transport:update()
    assert_equal(session.acquisition_service:get_pending(1), nil, "cancel rejects only the new item")
    assert_equal(inventory:count(), 12, "rejecting does not discard inventory")
    assert_equal(inventory.items[12].instance_id, claim.equipment.instance_id, "rejecting leaves accepted item in place")

    session.perfect_bonus_pool = { "test_high_weapon" }
    session:_grant_perfect_bonus({ perfect_total_cards = 1, perfect_counts = { [1] = 1 } }, { id = 8 })
    assert_true(session.acquisition_service:get_pending(1) ~= nil, "first full-perfect reward is pending")
    assert_equal(#session.preparation.pending_acquisition_queue[1], 1, "second full-perfect reward is queued rather than overwritten")
    session.run_state = Constants.run_states.REWARD
    session.reward_required = 2
    session.reward_choices = { { kind = "EQUIPMENT", definition_id = "test_high_weapon" } }
    session.reward_claims = {}
    local queued_claim = session:claim_reward(1, 1)
    assert_true(queued_claim and queued_claim.pending and not queued_claim.acquired, "additional reward is queued")
    assert_equal(#session.preparation.pending_acquisition_queue[1], 2, "all pending rewards are retained")
    assert_true(session:unclaim_reward(1, 1), "a queued claim can be reversed")
    assert_equal(#session.preparation.pending_acquisition_queue[1], 1, "unclaim removes only the matching queued reward")

    -- In two-player rewards a player may replace inventory and change their
    -- mind while the other player is still selecting. Undo must restore the
    -- displaced item, including its metadata, before another choice is made.
    local reward = GameSession.new({run_seed = 19, player_count = 2}):start_new()
    local reward_inventory = reward:get_player(1).loadout.inventory
    local reward_def = reward.equipment_registry:get("test_high_weapon")
    for i = 1, reward_inventory.capacity do
        reward_inventory:add(EquipmentInstance.new(reward_def, 1, {
            instance_id = "replacement-old-" .. i, runtime_data = { enabled = false },
            random_affixes = { { id = "saved", value = i } },
        }))
    end
    reward.run_state = Constants.run_states.REWARD
    reward.reward_required = 1
    reward.reward_claims = {}
    reward.reward_choices = {
        { kind = "EQUIPMENT", definition_id = "test_high_weapon" },
        { kind = "RESOURCE", resource = "bomb", amount = 1 },
    }
    local reward_claim = assert(reward:claim_reward(1, 1))
    local reward_id = reward_claim.equipment.instance_id
    assert_true(reward:dispatch({type=Command.ACCEPT_PENDING_ITEM, player_id=1, discard_index=12}) ~= nil, "reward replacement accepted")
    assert_true(reward_claim.acquired and not reward_claim.pending, "claim tracks accepted pending reward")
    -- Model network/state serialization: claims and inventory contain plain
    -- tables after transport or persistence, rather than object identities.
    reward.reward_claims = Immutable.copy(reward.reward_claims)
    reward:get_player(1).loadout.inventory = Inventory.from_table(reward_inventory:to_table())
    reward_inventory = reward:get_player(1).loadout.inventory
    assert_true(reward:unclaim_reward(1, 1), "accepted replacement can be undone after serialization")
    assert_equal(reward_inventory:count(), 12, "undo retains inventory capacity")
    assert_equal(reward_inventory:find(reward_id), nil, "undo removes acquired reward")
    assert_equal(reward_inventory.items[12].instance_id, "replacement-old-12", "undo restores chosen item at its original index")
    assert_equal(reward_inventory.items[12].runtime_data.enabled, false, "undo restores item state")
    assert_equal(reward_inventory.items[12].random_affixes[1].value, 12, "undo restores item affixes")
    local bombs = reward:get_player(1).bomb
    assert_true(reward:claim_reward(1, 2) ~= nil, "player can select another reward after undo")
    assert_equal(reward:get_player(1).bomb, bombs + 1, "only the new resource reward is granted")
    assert_true(reward:claim_reward(2, 2) ~= nil, "second player can finish selection")
    assert_equal(reward.run_state, Constants.run_states.MAP, "second player closes the reward screen")
    assert_equal(reward_inventory:find(reward_id), nil, "first reward does not survive the screen transition")

    local late = GameSession.new({run_seed = 20, player_count = 2}):start_new()
    local late_inventory = late:get_player(1).loadout.inventory
    local late_def = late.equipment_registry:get("test_high_weapon")
    for i = 1, late_inventory.capacity do
        late_inventory:add(EquipmentInstance.new(late_def, 1, {instance_id = "late-old-" .. i}))
    end
    late.run_state = Constants.run_states.REWARD
    late.reward_required = 1
    late.reward_claims = {}
    late.reward_choices = {
        {kind="EQUIPMENT", definition_id="test_high_weapon"},
        {kind="RESOURCE", resource="bomb", amount=1},
    }
    assert_true(late:claim_reward(2, 2) ~= nil, "other player can select first")
    local late_claim = assert(late:claim_reward(1, 1))
    assert_equal(late.run_state, Constants.run_states.MAP, "last claim closes reward screen before replacement")
    assert_true(late:dispatch({type=Command.ACCEPT_PENDING_ITEM,player_id=1,discard_index=12}) ~= nil, "pending reward resolves on map")
    assert_true(late_inventory:find(late_claim.equipment.instance_id) ~= nil, "last selection remains acquired")

    local host_link, client_link = FakeTransport.create_pair()
    local host = GameSession.new({run_seed = 91, player_count = 2}):start_new()
    local client = GameSession.new({run_seed = 91, player_count = 2}):start_new()
    host_link:attach_session(host); client_link:attach_session(client)
    for _, peer in ipairs({host, client}) do
        local peer_inventory = peer:get_player(2).loadout.inventory
        local peer_definition = peer.equipment_registry:get("test_high_weapon")
        for i = 1, peer_inventory.capacity do
            peer_inventory:add(EquipmentInstance.new(peer_definition, 2, {instance_id = "old-" .. i}))
        end
        peer.acquisition_service:acquire(2, EquipmentInstance.new(peer_definition, 2, {instance_id = "new"}))
    end
    client_link:send({type = Command.ACCEPT_PENDING_ITEM, player_id = 2, discard_index = 12})
    host_link:update(); client_link:update()
    for _, peer in ipairs({host, client}) do
        assert_equal(peer:get_player(2).loadout.inventory.items[12].instance_id, "new", "replacement reaches both peers")
        assert_equal(peer.acquisition_service:get_pending(2), nil, "both peers resolve the pending item")
    end
end
