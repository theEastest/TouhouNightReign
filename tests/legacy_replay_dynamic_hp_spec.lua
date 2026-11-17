return function(assert_equal, assert_true)
    local DynamicEnemyHp = require("tnr.legacy_replay.dynamic_enemy_hp")
    local definitions = {
        light = { damage = 2, count = 1, fire_interval = 6 },
        heavy = { damage = 4, count = 2, fire_interval = 6 },
    }
    local players = {
        { player_id = 1, loadout = { high_weapons = { { definition_id = "light" }, false },
            low_weapons = { { definition_id = "heavy" } } } },
        { player_id = 2, loadout = { high_weapons = { { definition_id = "light" } },
            low_weapons = { false, false } } },
    }
    local session = {
        equipment_registry = { get = function(_, id) return definitions[id] end },
        players = { get_players = function() return players end },
    }
    local measured = DynamicEnemyHp.measure(session)
    assert_equal(measured.total_dps, 120, "co-op DPS combines both equipped loadouts")
    assert_equal(measured.max_weapon_dps, 80, "the highest equipped weapon DPS is used")
    assert_equal(measured.weapon_slots, 6, "the cap counts every high and low weapon slot")
    assert_equal(measured.cap_dps, 480, "DPS cap is best weapon DPS times combined slots")
    assert_equal(DynamicEnemyHp.multiplier(measured, measured.total_dps), 0.5,
        "the stage-start DPS baseline maps to half enemy health")
    assert_equal(DynamicEnemyHp.multiplier({ total_dps = 480, cap_dps = 480 }, 100), 2,
        "the upper DPS cap maps to double enemy health")
    local midpoint = DynamicEnemyHp.multiplier({ total_dps = 290, cap_dps = 480 }, 100)
    assert_true(midpoint > 0.5 and midpoint < 2, "the sine curve stays within its endpoints")

    session.character_registry = { get = function(_, id)
        return id == "marisa" and { high_weapon_slots = 4, low_weapon_slots = 2 }
            or { high_weapon_slots = 1, low_weapon_slots = 3 }
    end }
    local network = DynamicEnemyHp.measure(session, {
        [1] = { high_weapons = { { definition = definitions.heavy } }, low_weapons = {} },
        [2] = { high_weapons = { { definition = definitions.light } }, low_weapons = {} },
    }, { [1] = "marisa", [2] = "sanae" })
    assert_equal(network.total_dps, 100, "LAN HP scaling uses both peers' committed loadout DPS")
    assert_equal(network.weapon_slots, 10, "LAN HP scaling counts each selected character's weapon slots")
    assert_equal(network.cap_dps, 800, "LAN HP scaling shares one party DPS cap")
end
