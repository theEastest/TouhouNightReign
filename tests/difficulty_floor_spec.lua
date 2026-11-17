local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")
local WaveDifficulty = require("tnr.stages.wave_difficulty")
local BossPools = require("tnr.stages.boss_pools")
local FloorBonus = require("tnr.battle.floor_bonus")
local Waves = require("tnr.stages.legacy_enemy_waves")
local MapGenerator = require("tnr.map.map_generator")

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
    local normal_waves, lunatic_waves = 0, 0
    for _, stage in ipairs(Waves) do
        for _, wave in ipairs(stage.waves or {}) do
            if tostring(stage.source_stage):match("@Normal$") then
                normal_waves = normal_waves + 1
                assert_true(WaveDifficulty.wave_allowed_on_floor(wave, 1), "floor 1 may select only source Normal waves")
                assert_true(not WaveDifficulty.wave_allowed_on_floor(wave, 3), "floor 3 may not select source Normal waves")
            elseif tostring(stage.source_stage):match("@Lunatic$") then
                lunatic_waves = lunatic_waves + 1
                assert_true(not WaveDifficulty.wave_allowed_on_floor(wave, 1), "floor 1 may not select source Lunatic waves")
                assert_true(WaveDifficulty.wave_allowed_on_floor(wave, 3), "floor 3 may select source Lunatic waves")
            end
        end
    end
    assert_true(normal_waves > 0 and lunatic_waves > 0, "source difficulty fixtures exist")

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
    assert_equal(FloorBonus.boss_multiplier(3), 1.40, "floor 3 applies the boss HP bonus")
    assert_equal(FloorBonus.enemy_multiplier(3), 1.30, "floor 3 applies the small-enemy HP bonus")

    -- apply() scales maxhp and keeps hp proportional.
    local boss = { maxhp = 1000, hp = 1000 }
    FloorBonus.apply(boss, 1, true)
    assert_true(boss.maxhp < 1000 and boss.hp == boss.maxhp,
        "attenuated boss must start at full scaled HP")
    local enemy = { maxhp = 100, hp = 100 }
    FloorBonus.apply(enemy, 3, false)
    assert_true(enemy.maxhp > 100, "floor-3 small enemy must be amplified")

    -- The route gains three decision columns without changing the three-floor
    -- boss progression. Category ratios are applied to one shared pool.
    local long_map = MapGenerator.generate(20261117)
    local columns = {}
    for _, node in ipairs(long_map.nodes) do
        columns[string.format("%.4f", node.x)] = true
    end
    local column_count = 0
    for _ in pairs(columns) do column_count = column_count + 1 end
    assert_equal(#long_map.nodes, 35, "extended map keeps the previous route-node density")
    assert_equal(column_count, 11, "extended map has three more route columns")
    assert_equal(#long_map:find_path(long_map.start_node_id, long_map.boss_node_id), 11,
        "start-to-boss route visits nine intermediate rooms")
    local counts = long_map:count_types()
    assert_equal(counts[Constants.node_types.ENEMY], 22, "enemy-room share increases")
    assert_equal(counts[Constants.node_types.ELITE], 6, "elite-room share increases")
    assert_equal(counts[Constants.node_types.EVENT], 3, "event-room share is reduced")
    assert_equal(counts[Constants.node_types.SHOP], 2, "shop share remains available")

    local nav_map = MapGenerator.generate(884422)
    local nav_start = nav_map:get_current_node()
    local first_forward_id = nav_map:get_forward_links()[1]
    assert_true(first_forward_id ~= nil, "start offers a forward route")
    assert_true(nav_map:select_node(first_forward_id) ~= nil, "map accepts a forward move")
    assert_true(nav_map:get_node(first_forward_id):is_linked(nav_start.id),
        "the route graph retains its visual connection to the previous layer")
    assert_true(not nav_map:is_adjacent(nav_start.id), "map rejects a link back to the previous layer")
    local rejected_backtrack, backtrack_error = nav_map:select_node(nav_start.id)
    assert_equal(rejected_backtrack, nil, "map cannot return to the previous node")
    assert_true(backtrack_error ~= nil, "backtracking has an explanatory error")
    assert_equal(nav_map.current_node_id, first_forward_id, "rejected backtracking leaves the player in place")

    local nav_session = GameSession.new({ run_seed = 884422 }):start_new()
    local session_start_id = nav_session.current_node_id
    local session_forward_id = nav_session.map:get_forward_links()[1]
    assert_true(nav_session:select_node(session_forward_id) ~= nil, "game session accepts forward travel")
    nav_session:return_to_map()
    local session_backtrack = nav_session:select_node(session_start_id)
    assert_equal(session_backtrack, nil, "game session rejects return travel after a room")
    assert_equal(nav_session.current_node_id, session_forward_id, "game session remains on the later layer")

    local MapScene = require("tnr.map.map_scene")
    local route_scene = MapScene.new({ map = nav_map, node_votes = {} })
    for _, selectable_node in ipairs(route_scene:get_selectable_nodes()) do
        assert_true(selectable_node.x > nav_map:get_current_node().x,
            "keyboard and mouse choices expose only the next layer")
    end
    for _, view_node in ipairs(route_scene:get_view().nodes) do
        if view_node.x < nav_map:get_current_node().x then
            assert_true(not view_node.selectable, "previous-layer nodes are visually unavailable")
        end
    end

    local function forward_reaches(map, start_id, goal_id)
        local queue = { start_id }
        local seen = { [start_id] = true }
        local head = 1
        while queue[head] do
            local node = map.nodes[queue[head]]
            head = head + 1
            if node.id == goal_id then return true end
            for _, linked_id in ipairs(node.links) do
                local target = map.nodes[linked_id]
                if target.x > node.x and not seen[target.id] then
                    seen[target.id] = true
                    queue[#queue + 1] = target.id
                end
            end
        end
        return false
    end

    local outgoing, incoming = {}, {}
    for _, node in ipairs(long_map.nodes) do
        outgoing[node.id], incoming[node.id] = 0, 0
        for _, linked_id in ipairs(node.links) do
            local linked = long_map.nodes[linked_id]
            if linked.x > node.x then outgoing[node.id] = outgoing[node.id] + 1 end
            if linked.x < node.x then incoming[node.id] = incoming[node.id] + 1 end
        end
    end
    local branch_nodes, merge_nodes = 0, 0
    for _, node in ipairs(long_map.nodes) do
        assert_true(forward_reaches(long_map, long_map.start_node_id, node.id),
            "every room is reachable from the start through forward links")
        assert_true(forward_reaches(long_map, node.id, long_map.boss_node_id),
            "every room has a forward route to the boss")
        assert_true(#node.links <= 4, "map node degree stays within the route cap")
        if outgoing[node.id] >= 2 then branch_nodes = branch_nodes + 1 end
        if incoming[node.id] >= 2 then merge_nodes = merge_nodes + 1 end
    end
    assert_true(branch_nodes >= 8, "map contains multiple branching choices")
    assert_true(merge_nodes >= 6, "map contains multiple route merges")

    -- Adjacent-layer edges must preserve vertical order, so two routes never
    -- cross between the same pair of columns.
    for _, source in ipairs(long_map.nodes) do
        for _, source_other in ipairs(long_map.nodes) do
            if source.x == source_other.x and source.id < source_other.id then
                for _, target_id in ipairs(source.links) do
                    local target = long_map.nodes[target_id]
                    if target.x > source.x then
                        for _, target_other_id in ipairs(source_other.links) do
                            local target_other = long_map.nodes[target_other_id]
                            if target_other.x > source_other.x and target_other.x == target.x then
                                assert_true((source.y - source_other.y) * (target.y - target_other.y) >= 0,
                                    "route lines must not cross")
                            end
                        end
                    end
                end
            end
        end
    end
    -- Randomized layer sizes and branch orientations must keep the same
    -- reachability guarantees across different run seeds.
    for seed = 20261118, 20261149 do
        local variant = MapGenerator.generate(seed)
        local variant_branches = 0
        local variant_merges = 0
        for _, node in ipairs(variant.nodes) do
            assert_true(forward_reaches(variant, variant.start_node_id, node.id),
                "randomized route seed " .. seed .. " reaches every room from the start")
            assert_true(forward_reaches(variant, node.id, variant.boss_node_id),
                "randomized route seed " .. seed .. " lets every room progress to the boss")
            assert_true(#node.links <= 4, "randomized route respects the link cap")
            local in_count, out_count = 0, 0
            for _, linked_id in ipairs(node.links) do
                local linked = variant.nodes[linked_id]
                if linked.x < node.x then in_count = in_count + 1 end
                if linked.x > node.x then out_count = out_count + 1 end
            end
            if in_count >= 2 then variant_merges = variant_merges + 1 end
            if out_count >= 2 then variant_branches = variant_branches + 1 end
        end
        assert_true(variant_branches >= 8, "randomized route has multiple branch decisions")
        assert_true(variant_merges >= 6, "randomized route has multiple merges")
    end

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
