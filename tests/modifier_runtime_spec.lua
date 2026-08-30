local GameSession = require("tnr.core.game_session")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local Catalog = require("tnr.equipment.phase1_catalog")
local ModifierRuntime = require("tnr.equipment.runtime.modifier_runtime")

return function(assert_equal, assert_true)
    local session = GameSession.new({ run_seed = 1003 })
    session:start_new()
    local player = session:get_player(1)
    player.loadout:set_slot("self_modifiers", 1, EquipmentInstance.new(Catalog.definitions.test_self_modifier, 1))
    player.loadout:set_slot("self_modifiers", 2, EquipmentInstance.new(Catalog.definitions.test_self_modifier_alt, 1))
    player.loadout:set_slot("support_modifiers", 1, EquipmentInstance.new(Catalog.definitions.test_support_modifier, 1))
    player.loadout:set_slot("support_modifiers", 2, EquipmentInstance.new(Catalog.definitions.test_support_modifier_alt, 1))
    local runtime = ModifierRuntime.new(player.loadout, Catalog.registry)
    assert_true(runtime:apply_hook("on_projectile_create", {}).scale > 1, "projectile modifier hook scales shots")
    assert_equal(runtime:apply_hook("on_weapon_fire", {}).extra_projectiles, 1, "volley modifier adds a projectile")
    assert_equal(runtime:apply_hook("on_support_formation", {}).support_formation,
        "front_concentration", "support modifier changes formation")
    assert_true(runtime:apply_hook("on_support_update", { frame = 180 }).clear_bullets,
        "support modifier can request periodic bullet clear")
end
