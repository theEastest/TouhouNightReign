local Constants = require("tnr.core.constants")
local RNG = require("tnr.core.rng")
local MapNode = require("tnr.map.map_node")
local MapState = require("tnr.map.map_state")

local Generator = {}

local DEFAULTS = {
    node_count = 24,
    min_boss_hops = 6,
    min_node_spacing = 0.06,
    max_links = 4,
    enemy_ratio = 0.55,
    event_ratio = 0.20,
    shop_ratio = 0.10,
}

local function merged_config(config)
    local result = {}
    for key, value in pairs(DEFAULTS) do
        result[key] = value
    end
    for key, value in pairs(config or {}) do
        result[key] = value
    end
    result.node_count = math.max(8, math.floor(result.node_count))
    result.min_boss_hops = math.min(result.min_boss_hops, result.node_count - 1)
    return result
end

local function distance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function make_positions(rng, count, spacing)
    local positions = {
        { x = 0.08, y = 0.50 },
        { x = 0.92, y = 0.50 },
    }
    for index = 3, count do
        local position
        for _ = 1, 80 do
            local candidate = { x = 0.10 + rng:next_float() * 0.80, y = 0.10 + rng:next_float() * 0.80 }
            local valid = true
            for _, other in ipairs(positions) do
                if distance(candidate, other) < spacing then
                    valid = false
                    break
                end
            end
            if valid then
                position = candidate
                break
            end
        end
        position = position or { x = 0.10 + rng:next_float() * 0.80, y = 0.10 + rng:next_float() * 0.80 }
        positions[index] = position
    end
    return positions
end

local function add_edge(nodes, left, right)
    if nodes[left]:add_link(right) then
        nodes[right]:add_link(left)
        return true
    end
    return false
end

local function shortest_hops(nodes, start_id, goal_id)
    local queue = { { id = start_id, hops = 0 } }
    local head = 1
    local seen = { [start_id] = true }
    while queue[head] do
        local current = queue[head]
        head = head + 1
        if current.id == goal_id then
            return current.hops
        end
        for _, linked_id in ipairs(nodes[current.id].links) do
            if not seen[linked_id] then
                seen[linked_id] = true
                queue[#queue + 1] = { id = linked_id, hops = current.hops + 1 }
            end
        end
    end
    return math.huge
end

local function add_edge_preserving_distance(nodes, left, right, minimum_hops, goal_id)
    if not add_edge(nodes, left, right) then
        return false
    end
    if shortest_hops(nodes, 1, goal_id) < minimum_hops then
        nodes[left]:remove_link(right)
        nodes[right]:remove_link(left)
        return false
    end
    return true
end

local function assign_types(rng, nodes, config)
    local candidates = {}
    for id = 2, config.node_count - 1 do
        candidates[#candidates + 1] = id
    end
    rng:shuffle(candidates)

    local event_count = math.max(1, math.floor(#candidates * config.event_ratio + 0.5))
    local shop_count = math.max(1, math.floor(#candidates * config.shop_ratio + 0.5))
    local cursor = 1
    for _ = 1, event_count do
        nodes[candidates[cursor]].type = Constants.node_types.EVENT
        cursor = cursor + 1
    end
    for _ = 1, shop_count do
        nodes[candidates[cursor]].type = Constants.node_types.SHOP
        cursor = cursor + 1
    end
    for index = cursor, #candidates do
        nodes[candidates[index]].type = rng:chance(config.enemy_ratio) and Constants.node_types.ENEMY or Constants.node_types.EVENT
    end
end

function Generator.generate(run_seed, config)
    config = merged_config(config)
    local seed = tonumber(run_seed) or 1
    local rng = RNG.new(seed)
    local positions = make_positions(rng, config.node_count, config.min_node_spacing)
    local nodes = {}

    for id = 1, config.node_count do
        local node_type = Constants.node_types.ENEMY
        if id == 1 then
            node_type = Constants.node_types.START
        elseif id == config.node_count then
            node_type = Constants.node_types.BOSS
        end
        nodes[id] = MapNode.new(id, node_type, positions[id].x, positions[id].y)
    end
    nodes[1].visited = true
    nodes[1].encounter_id = nil
    nodes[config.node_count].encounter_id = "boss_test_01"
    assign_types(rng, nodes, config)

    -- A chain is the guaranteed connected backbone and gives the boss a safe minimum distance.
    for id = 1, config.node_count - 1 do
        add_edge(nodes, id, id + 1)
    end

    local edge_pairs = {}
    for left = 1, config.node_count do
        for right = left + 1, config.node_count do
            if not nodes[left]:is_linked(right) then
                edge_pairs[#edge_pairs + 1] = { left = left, right = right, weight = distance(nodes[left], nodes[right]) }
            end
        end
    end
    table.sort(edge_pairs, function(a, b)
        if a.weight == b.weight then
            return (a.left * 1000 + a.right) < (b.left * 1000 + b.right)
        end
        return a.weight < b.weight
    end)
    for _, pair in ipairs(edge_pairs) do
        local left_node = nodes[pair.left]
        local right_node = nodes[pair.right]
        if #left_node.links < config.max_links and #right_node.links < config.max_links and rng:chance(0.38) then
            add_edge_preserving_distance(nodes, pair.left, pair.right, config.min_boss_hops, config.node_count)
        end
    end

    -- Add a few long links only when they preserve the minimum start-to-boss distance.
    for _, pair in ipairs(edge_pairs) do
        if #nodes[pair.left].links < config.max_links and #nodes[pair.right].links < config.max_links and rng:chance(0.12) then
            add_edge_preserving_distance(nodes, pair.left, pair.right, config.min_boss_hops, config.node_count)
        end
    end

    for id, node in pairs(nodes) do
        if node.type == Constants.node_types.ENEMY then
            node.encounter_id = "enemy_test_01"
        elseif node.type == Constants.node_types.BOSS then
            node.encounter_id = "boss_test_01"
        end
    end
    return MapState.new(nodes, 1, config.node_count)
end

return Generator
