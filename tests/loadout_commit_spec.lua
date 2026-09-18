local GameSession = require("tnr.core.game_session")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local Catalog = require("tnr.equipment.phase1_catalog")
local Commit = require("tnr.multiplayer.loadout_commit")

return function(assert_equal, assert_true)
    local session = GameSession.new({ run_seed = 1004, player_count = 2 })
    session:start_new()
    local first = session:build_loadout_commit(1)
    local second = session:build_loadout_commit(2)
    assert_true(Commit.validate(first), "local descriptor validates")
    assert_true(Commit.validate(second), "remote descriptor validates")
    assert_true(type(first.definition_registry_hash) == "string"
        and first.definition_registry_hash ~= "", "commit includes a definition registry hash")
    assert_equal(first.definition_registry_hash, second.definition_registry_hash,
        "identical registries hash equally")
    assert_true(first.loadout_hash == second.loadout_hash, "identical default loadouts hash equally")
    session:get_player(2).loadout:set_slot("high_weapons", 1,
        EquipmentInstance.new(Catalog.definitions.test_high_weapon, 2))
    local changed = session:build_loadout_commit(2)
    assert_true(changed.loadout_hash ~= first.loadout_hash, "loadout hash changes after equipment edit")
    assert_equal(changed.definition_registry_hash, first.definition_registry_hash,
        "different loadouts still share the room definition registry hash")
    local mismatched = {}
    for key, value in pairs(changed) do mismatched[key] = value end
    mismatched.definition_registry_hash = "00000000"
    local rejected, mismatch_reason = session:commit_loadout(2, mismatched)
    assert_equal(rejected, nil, "a peer with different equipment definitions is rejected")
    assert_equal(mismatch_reason, "DEFINITION_REGISTRY_MISMATCH",
        "definition mismatch has an explicit error")
    assert_true(session:commit_loadout(1, first) ~= nil, "host loadout commit accepted")
    assert_true(session:commit_loadout(2, changed) ~= nil, "peer loadout commit accepted")
    assert_true(session:all_loadouts_committed(), "room starts only after every player commits")
    assert_true(Commit.same_room(changed, session.room_generation), "commit accepts current room")
end
