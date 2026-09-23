local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")
local WaveDifficulty = require("tnr.stages.wave_difficulty")
local BossPools = require("tnr.stages.boss_pools")
local FloorBonus = require("tnr.battle.floor_bonus")
local Waves = require("tnr.stages.legacy_enemy_waves")

return function(assert_equal, assert_true)
    -- Every selectable wave carries a 1..6 content tier.
    local tier_counts = {}
    for _, stage in ipairs(Waves) do
        for _, wave in ipairs(stage.waves or {}) do
            local tier = WaveDifficulty.tier_of(wave)
            assert_true(tier >= 1 and tier <= 6, "wave tier must be 1..6: " .. tostring(wave.id))
            tier_counts[tier] = (tier_counts[tier] or 0) + 1
        end
    end
    for tier = 1, 6 do
        assert_true((tier_counts[tier] or 0) > 0, "every tier must own at least one wave: " .. tier)
    end

    -- The score must be monotonic with real content: the wave with the most
    -- enemies must outrank the wave with the fewest.
    local lightest, heaviest
    for _, stage in ipairs(Waves) do
        for _, wave in ipairs(stage.waves or {}) do
            if not lightest or #wave.members < #lightest.members then lightest = wave end
            if not heaviest or #wave.members > #heaviest.members then heaviest = wave end
        end
    end
    assert_true(lightest ~= nil and heaviest ~= nil, "difficulty fixtures must exist")
    assert_true(WaveDifficulty.score(heaviest) > WaveDifficulty.score(lightest),
        "the largest wave must score above the smallest wave")

    -- Six progression bands map floor + progress deterministically.
    assert_equal(WaveDifficulty.band_for(1, 0.25), 1, "floor 1 first half is band 1")
    assert_equal(WaveDifficulty.band_for(1, 0.75), 2, "floor 1 second half is band 2")
    assert_equal(WaveDifficulty.band_for(2, 0.25), 3, "floor 2 first half is band 3")
    assert_equal(WaveDifficulty.band_for(2, 0.75), 4, "floor 2 second half is band 4")
    assert_equal(WaveDifficulty.band_for(3, 0.25), 5, "floor 3 first half is band 5")
    assert_equal(WaveDifficulty.band_for(3, 0.75), 6, "floor 3 second half is band 6")

    -- Boss and elite pools are fixed per floor and non-empty.
    for floor = 1, 3 do
        assert_true(#BossPools.boss_list(floor) > 0, "floor " .. floor .. " must own a boss pool")
        assert_true(#BossPools.elite_list(floor) > 0, "floor " .. floor .. " must own an elite pool")
    end
    -- A boss belongs to exactly one floor.
    local cirno_floors = 0
    for floor = 1, 3 do
        if BossPools.is_floor_boss("Cirno:Normal", floor) then cirno_floors = cirno_floors + 1 end
    end
    assert_equal(cirno_floors, 1, "a boss must belong to exactly one floor pool")

    -- Area bonus: floor 1 attenuates bosses but never small enemies.
    assert_true(FloorBonus.boss_multiplier(1) < 1.0, "floor 1 must attenuate boss HP")
    assert_equal(FloorBonus.enemy_multiplier(1), 1.0, "floor 1 must not attenuate small-enemy HP")
    assert_equal(FloorBonus.boss_multiplier(2), 1.0, "floor 2 boss HP is neutral")
    assert_equal(FloorBonus.enemy_multiplier(2), 1.0, "floor 2 small-enemy HP is neutral")
    assert_true(FloorBonus.boss_multiplier(3) > 1.0, "floor 3 must amplify boss HP")
    assert_true(FloorBonus.enemy_multiplier(3) > 1.0, "floor 3 must amplify small-enemy HP")

    -- apply() scales maxhp and keeps hp proportional.
    local boss = { maxhp = 1000, hp = 1000 }
    FloorBonus.apply(boss, 1, true)
    assert_true(boss.maxhp < 1000 and boss.hp == boss.maxhp,
        "attenuated boss must start at full scaled HP")
    local enemy = { maxhp = 100, hp = 100 }
    FloorBonus.apply(enemy, 3, false)
    assert_true(enemy.maxhp > 100, "floor-3 small enemy must be amplified")

    -- A run is split into three floors; the map carries floor and band.
    local session = GameSession.new({ run_seed = 20260101, player_count = 1 })
    session:start_new()
    assert_equal(session.floor, 1, "a fresh run starts on floor 1")
    assert_equal(session.floor_count, 3, "a run has three floors")
    for _, node in ipairs(session.map.nodes) do
        assert_equal(node.floor, 1, "floor-1 map nodes carry floor 1")
    end
    local enemy_seen, elite_seen, boss_seen = false, false, false
    for _, node in ipairs(session.map.nodes) do
        if node.type == Constants.node_types.ENEMY then
            enemy_seen = true
            assert_true(node.band == 1 or node.band == 2, "floor-1 enemy bands are 1 or 2")
        elseif node.type == Constants.node_types.ELITE then
            elite_seen = true
            assert_equal(node.band, 2, "floor-1 elite band is 2")
        elseif node.type == Constants.node_types.BOSS then
            boss_seen = true
            assert_equal(node.band, 2, "floor-1 boss band is 2")
        end
    end
    assert_true(enemy_seen and elite_seen and boss_seen, "the map must contain every room type")
end
