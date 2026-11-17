local Bootstrap = require("tnr.bootstrap")
local GameSession = require("tnr.core.game_session")
local PlayerState = require("tnr.core.player_state")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local Bridge = require("tnr.character.runtime.character_runtime_bridge")
local MapRenderer = require("tnr.ui.map_renderer")
local FakeTransport = require("tnr.multiplayer.fake_transport")
local Command = require("tnr.core.command")

return function(assert_equal, assert_true)
    local app = Bootstrap.create({run_seed = 1387, player_count = 1})
    app:start_game(1387)
    assert_true(app.session:enter_preparation() ~= nil, "preparation opens")
    local session, player = app.session, app.session:get_player(1)
    local support = player.loadout.supports[1]
    local previous_weight = player.loadout:get_total_weight(session.equipment_registry)
    local old_commit = session:build_loadout_commit(1)
    local target
    for index, row in ipairs(app:_preparation_rows()) do
        if row.kind == "equipped" and row.group == "supports" and row.index == 1 then target = index break end
    end
    app.input = {get_mouse_position = function() return 100, 100 end}
    app.renderer = {width = 1280, height = 720,
        scrollbar_index = function() return nil end,
        preparation_hit_test = function() return target end}
    app:_update_preparation({move_y = 0, mouse_primary_pressed = true}, false)
    assert_equal(player.loadout.supports[1], support, "left click keeps support equipped")
    assert_equal(support.runtime_data.enabled, false, "left click disables support")
    local labels = {}
    local mock = { Color = function() return {} end, SetImageState = function() end, RenderRect = function() end,
        RenderTTF = function(_, text) labels[#labels + 1] = text end,
        BeginScene = function() end, EndScene = function() end, RenderClear = function() end,
        SetViewport = function() end, SetScissorRect = function() end, SetOrtho = function() end, Render = function() end }
    local renderer = MapRenderer.new(mock, 1280, 720); renderer.white = "white"
    renderer:render_preparation(session, target, "", nil, nil, false, false, false)
    local found_disabled = false
    for _, text in ipairs(labels) do if text == "[停用]" then found_disabled = true end end
    assert_true(found_disabled, "preparation screen shows the disabled status")
    assert_equal(player.loadout:get_total_weight(session.equipment_registry), previous_weight, "disabled support retains weight")
    local commit = session:build_loadout_commit(1)
    assert_equal(commit.supports[1].runtime_data.enabled, false, "commit carries support state")
    assert_true(commit.loadout_hash ~= old_commit.loadout_hash, "support toggle changes loadout hash")
    local restored = PlayerState.from_table(player:to_table(), session.character_registry:get("reimu"))
    assert_equal(restored.loadout.supports[1].runtime_data.enabled, false, "player snapshot retains support state")
    local bridge = Bridge.new(session, 1)
    local local_runtime = bridge:create_runtime()
    local remote_runtime = bridge:create_runtime_from_descriptor(commit)
    assert_equal(local_runtime.support_manager:entity_count(), 0, "disabled support creates no local entities")
    assert_equal(remote_runtime.support_manager:entity_count(), 0, "disabled support creates no remote entities")
    assert_equal(#local_runtime.support_manager:fire("HIGH", true, {player_id = 1}), 0, "disabled support does not fire")
    assert_equal(#local_runtime.support_manager:update(0, 0, "HIGH"), 0, "disabled support does not render or pulse")
    assert_equal(#remote_runtime.support_manager.supports, 0, "remote disabled support contributes no P regeneration or cost")
    for _, weapon in ipairs(local_runtime.weapon_manager.weapons) do weapon.enabled = false end
    local disabled_rates
    local_runtime.p_gauge:on("rates", function(rates) disabled_rates = rates; return rates end)
    bridge:update(local_runtime, "HIGH", true, {x = 0, y = 0, moving = true})
    assert_equal(disabled_rates.regeneration, 0, "disabled support adds no regeneration")
    assert_equal(disabled_rates.consumption, 0, "disabled support adds no firing cost")
    app:_update_preparation({move_y = 0, mouse_primary_pressed = true}, false)
    assert_equal(support.runtime_data.enabled, true, "another click re-enables support")
    local enabled = bridge:create_runtime()
    assert_true(enabled.support_manager:entity_count() > 0, "re-enabled support creates entities")
    enabled.support_manager:update(0, 0, "HIGH")
    assert_true(#enabled.support_manager:fire("HIGH", true, {player_id = 1}) > 0, "re-enabled support fires")
    for _, weapon in ipairs(enabled.weapon_manager.weapons) do weapon.enabled = false end
    local enabled_rates
    enabled.p_gauge:on("rates", function(rates) enabled_rates = rates; return rates end)
    bridge:update(enabled, "HIGH", true, {x = 0, y = 0, moving = true})
    assert_true(enabled_rates.regeneration > 0, "enabled support restores P")
    assert_true(enabled_rates.consumption > 0, "enabled support contributes firing cost")
    session.preparation.loadout_locked[1] = true
    local changed, reason = session.loadout_service:toggle_support(1, 1)
    assert_equal(changed, nil, "ready-locked support cannot be toggled")
    assert_equal(reason, "LOADOUT_LOCKED", "locked reason is explicit")
    assert_equal(support.runtime_data.enabled, true, "failed toggle leaves state unchanged")

    local sanae = GameSession.new({run_seed = 99, player_count = 1})
    sanae:set_local_character("sanae"); sanae:start_new()
    local sanae_player = sanae:get_player(1)
    local second = EquipmentInstance.new(sanae.equipment_registry:get("test_support_alt"), 1)
    sanae_player.loadout:set_slot("supports", 2, second)
    assert_true(sanae.loadout_service:toggle_support(1, 1), "one of multiple supports can be disabled")
    local sanae_bridge = Bridge.new(sanae, 1)
    local mixed = sanae_bridge:create_runtime()
    assert_equal(#mixed.support_manager.supports, 1, "other support remains enabled")
    assert_equal(mixed.support_manager:entity_count(), 2, "enabled support keeps its own entity count")
    assert_equal(mixed.support_manager.supports[1].instance_id, second.instance_id, "correct support remains active")

    local host_link, client_link = FakeTransport.create_pair()
    local host = GameSession.new({run_seed = 142, player_count = 2}):start_new()
    local client = GameSession.new({run_seed = 142, player_count = 2, local_player_id = 2}):start_new()
    host_link:attach_session(host); client_link:attach_session(client)
    assert_true(client.loadout_service:toggle_support(2, 1), "P2 disables their support locally")
    local client_commit = client:build_loadout_commit(2)
    client_link:send({type = Command.SET_READY, player_id = 2, commit = client_commit})
    host_link:update(); client_link:update()
    local peer_commit = host.loadout_commits[2]
    assert_true(peer_commit ~= nil, "host receives P2 loadout commit")
    assert_equal(peer_commit.supports[1].runtime_data.enabled, false, "P2 support toggle reaches host")
    local peer_runtime = Bridge.new(host, 2):create_runtime_from_descriptor(peer_commit)
    assert_equal(peer_runtime.support_manager:entity_count(), 0, "host respects disabled P2 support")
    assert_true(Bridge.new(host, 1):create_runtime().support_manager:entity_count() > 0, "P1 support remains enabled")
end
