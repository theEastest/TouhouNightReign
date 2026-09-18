local GameSession = require("tnr.core.game_session")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local Catalog = require("tnr.equipment.phase1_catalog")
local Bridge = require("tnr.character.runtime.character_runtime_bridge")
local StageAdapter = require("tnr.battle.stage_adapter")

return function(assert_equal, assert_true)
    local session = GameSession.new({ run_seed = 2201 })
    session:start_new()
    local player = session:get_player(1)

    for index = 1, #player.loadout.high_weapons do player.loadout:set_slot("high_weapons", index, false) end
    for index = 1, #player.loadout.low_weapons do player.loadout:set_slot("low_weapons", index, false) end
    for index = 1, #player.loadout.supports do player.loadout:set_slot("supports", index, false) end
    local empty_bridge = Bridge.new(session, 1, Catalog.registry)
    local empty_runtime = empty_bridge:create_runtime()
    local empty_shots, empty_supports = empty_bridge:update(empty_runtime, "HIGH", true,
        { x = 0, y = 0, angle = 90 })
    assert_equal(#empty_shots, 0, "empty loadout must not emit player or support projectiles")
    assert_equal(#empty_supports, 0, "empty support loadout must not create support entities")

    player.loadout:set_slot("high_weapons", 1,
        EquipmentInstance.new(Catalog.definitions.test_high_weapon, 1))
    player.loadout:set_slot("supports", 1,
        EquipmentInstance.new(Catalog.definitions.reimu_initial_support, 1))
    local bridge = Bridge.new(session, 1, Catalog.registry)
    local runtime = bridge:create_runtime()
    local first, supports = bridge:update(runtime, "HIGH", true, { x = 100, y = 50, angle = 90 })
    assert_equal(#first, 6, "weapon and four support entities must emit one descriptor each")
    assert_equal(#supports, 4, "support runtime entity count comes from the equipped definition")
    assert_equal(first[1].owner_player_id, 1, "projectile descriptor keeps its player owner")
    assert_true(first[1].source_type == "weapon", "weapon descriptor identifies its source")
    local support_descriptor
    for _, shot in ipairs(first) do
        if shot.source_type == "support" then support_descriptor = shot break end
    end
    assert_true(support_descriptor ~= nil, "support descriptor identifies its source")
    local second = bridge:update(runtime, "HIGH", true, { x = 100, y = 50, angle = 90 })
    assert_equal(#second, 0, "each runtime instance enforces its own fire interval")

    player.loadout:set_slot("self_modifiers", 1,
        EquipmentInstance.new(Catalog.definitions.test_self_modifier_alt, 1))
    local modified_runtime = Bridge.new(session, 1, Catalog.registry):create_runtime()
    local volley = Bridge.new(session, 1, Catalog.registry):update(modified_runtime, "HIGH", true,
        { x = 100, y = 50, angle = 90 })
    assert_true(#volley > #first, "volley modifier must affect the actual projectile pipeline")

    local fallback_session = GameSession.new({ run_seed = 2202 })
    fallback_session:start_new()
    local fallback_player = fallback_session:get_player(1)
    for index = 1, #fallback_player.loadout.high_weapons do fallback_player.loadout:set_slot("high_weapons", index, false) end
    for index = 1, #fallback_player.loadout.low_weapons do fallback_player.loadout:set_slot("low_weapons", index, false) end
    for index = 1, #fallback_player.loadout.supports do fallback_player.loadout:set_slot("supports", index, false) end
    local fallback = StageAdapter.new(fallback_session)
    fallback:start({ id = "runtime_empty", type = "ELITE", stage_id = "ordinary_stage_01" })
    fallback:update({ player_id = 1, shoot = true })
    assert_equal(#fallback.runtime.player_bullets, 0,
        "fallback battle must also honor an empty loadout")

    local remote_session = GameSession.new({ run_seed = 2203, player_count = 2 })
    remote_session:start_new()
    local remote_player = remote_session:get_player(2)
    remote_player.loadout:set_slot("high_weapons", 1,
        EquipmentInstance.new(Catalog.definitions.test_dual_weapon, 2))
    local remote_descriptor = Bridge.new(remote_session, 2, Catalog.registry):build_descriptor()
    local remote_runtime = Bridge.new(remote_session, 2, Catalog.registry)
        :create_runtime_from_descriptor(remote_descriptor)
    assert_equal(remote_runtime.weapon_manager:to_table()[1].definition_id,
        "test_dual_weapon", "remote runtime must consume the committed weapon descriptor")

    -- A charged Bomb converts a collision into a local safety release.  The
    -- hit itself must not spend a life; releasing within the short window
    -- upgrades the pending release to the charged variant.
    local charge_stage = StageAdapter.new(GameSession.new({ run_seed = 9919 }):start_new())
    charge_stage:start_empty_room("charge_hit_regression")
    local charge_player = charge_stage.runtime.players[1]
    charge_player.bomb_charging = true
    charge_player.bomb_charge = 30
    charge_stage.runtime.bullets = {{
        x = charge_player.x, y = charge_player.y, vx = 0, vy = 0, radius = 3, grazed_by = {},
    }}
    charge_stage:update({ [1] = { player_id = 1, bomb_down = true } })
    assert_equal(charge_stage.session:get_player(1).life, 3,
        "charge hit must not consume a player life")
    assert_equal(charge_stage.session:get_player(1).bomb, 3,
        "charge hit defers Bomb consumption until release")
    charge_stage:update({ [1] = { player_id = 1, bomb = true } })
    assert_equal(charge_stage.session:get_player(1).bomb, 2,
        "manual release in the charge-hit window consumes one Bomb")
    assert_equal(charge_player.bomb_timer, 119,
        "manual release in the charge-hit window uses charged duration")

    -- An empty Bomb inventory must clear stale charge state immediately and
    -- must not spend or arm a Bomb while the key remains held.
    local no_bomb_stage = StageAdapter.new(GameSession.new({ run_seed = 9920 }):start_new())
    no_bomb_stage:start_empty_room("empty_bomb_charge_regression")
    local no_bomb_player = no_bomb_stage.runtime.players[1]
    local no_bomb_session_player = no_bomb_stage.session:get_player(1)
    no_bomb_session_player.bomb = 0
    no_bomb_player.bomb_charging = true
    no_bomb_player.bomb_charge = 45
    no_bomb_stage:update({ [1] = { player_id = 1, bomb_down = true } })
    assert_equal(no_bomb_player.bomb_charging, false,
        "empty Bomb inventory must clear stale charging state")
    assert_equal(no_bomb_player.bomb_charge, 0,
        "empty Bomb inventory must clear the charge meter")
    assert_equal(no_bomb_session_player.bomb, 0,
        "empty Bomb inventory must never spend a Bomb")

    fallback:reset_for_new_run()
    assert_equal(next(fallback.character_runtimes), nil,
        "leaving a room must destroy all character runtimes")
end
