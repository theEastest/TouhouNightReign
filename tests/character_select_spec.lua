local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")
local Bootstrap = require("tnr.bootstrap")
local CharacterCatalog = require("tnr.character.character_catalog")
local Phase1Catalog = require("tnr.equipment.phase1_catalog")

return function(assert_equal, assert_true)
    -- Every catalog character must have a definition in the registry.
    local session = GameSession.new({ run_seed = 1 })
    assert_true(#CharacterCatalog >= 3, "the select screen must offer the three characters")
    for _, entry in ipairs(CharacterCatalog) do
        assert_true(session.character_registry:has(entry.id),
            "character catalog entry must be registered: " .. tostring(entry.id))
    end

    -- Every character must expose a complete starting kit.
    for _, character_id in ipairs({ "reimu", "marisa", "sanae" }) do
        local kit = Phase1Catalog.initial_by_character[character_id]
        assert_true(kit ~= nil, character_id .. " must have an initial kit")
        assert_true(Phase1Catalog.registry:get(kit.high_weapon.equipment_id) ~= nil,
            character_id .. " high weapon must be registered")
        assert_true(Phase1Catalog.registry:get(kit.low_weapon.equipment_id) ~= nil,
            character_id .. " low weapon must be registered")
        assert_true(Phase1Catalog.registry:get(kit.support.equipment_id) ~= nil,
            character_id .. " support must be registered")
        assert_true(Phase1Catalog.relics[kit.relic.relic_id] ~= nil,
            character_id .. " relic must be registered")
    end

    -- Selecting a character applies its kit and the chosen character id.
    for _, character_id in ipairs({ "marisa", "sanae" }) do
        local run = GameSession.new({ run_seed = 12345, player_count = 1 })
        local applied, err = run:set_local_character(character_id)
        assert_true(applied ~= nil, character_id .. " selection must apply: " .. tostring(err))
        run:start_new(12345)
        local player = run:get_player(1)
        assert_equal(player.character_id, character_id, "player keeps the chosen character")
        local kit = Phase1Catalog.initial_by_character[character_id]
        assert_equal(player.loadout.high_weapons[1].definition_id, kit.high_weapon.equipment_id,
            character_id .. " starts with its own high weapon")
        assert_equal(player.loadout.low_weapons[1].definition_id, kit.low_weapon.equipment_id,
            character_id .. " starts with its own low weapon")
        assert_equal(player.loadout.supports[1].definition_id, kit.support.equipment_id,
            character_id .. " starts with its own support")
        assert_equal(player.loadout.character_relic, kit.relic.relic_id,
            character_id .. " starts with its own relic")
    end

    -- An unknown character id is rejected.
    local guard = GameSession.new({ run_seed = 1 })
    local bad, bad_err = guard:set_local_character("nonexistent")
    assert_true(bad == nil and bad_err ~= nil, "an unknown character must be rejected")

    -- Single player: menu -> character select -> map.
    local bootstrap = Bootstrap.create({})
    bootstrap:init()
    bootstrap.menu_cursor = 1
    bootstrap.input:set_pending({ confirm = true })
    bootstrap:update()
    assert_equal(bootstrap.session.run_state, Constants.run_states.CHARACTER_SELECT,
        "single player must open the character select")
    -- Choose Marisa (catalog index 2) and confirm.
    bootstrap.character_cursor = 2
    bootstrap.input:set_pending({ confirm = true })
    bootstrap:update()
    assert_equal(bootstrap.session.run_state, Constants.run_states.MAP,
        "confirming a character must enter the map")
    assert_equal(bootstrap.session:get_player(1).character_id,
        CharacterCatalog[2].id, "the selected character reaches the run")

    -- Cancel returns to the menu without starting a run.
    local cancel_bootstrap = Bootstrap.create({})
    cancel_bootstrap:init()
    cancel_bootstrap.menu_cursor = 1
    cancel_bootstrap.input:set_pending({ confirm = true })
    cancel_bootstrap:update()
    assert_equal(cancel_bootstrap.session.run_state, Constants.run_states.CHARACTER_SELECT,
        "character select opens")
    cancel_bootstrap.input:set_pending({ cancel = true })
    cancel_bootstrap:update()
    assert_equal(cancel_bootstrap.session.run_state, Constants.run_states.MENU,
        "cancel returns to the main menu")
end
