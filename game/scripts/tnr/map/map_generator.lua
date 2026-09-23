local Constants = require("tnr.core.constants")
local RNG = require("tnr.core.rng")
local MapNode = require("tnr.map.map_node")
local MapState = require("tnr.map.map_state")
local WaveDifficulty = require("tnr.stages.wave_difficulty")

local Generator = {}

local DEFAULTS = {
    node_count = 24,
    min_boss_hops = 6,
    min_node_spacing = 0.06,
    max_links = 4,
    enemy_ratio = 0.55,
    elite_ratio = 0.12,
    event_ratio = 0.20,
    shop_ratio = 0.10,
    ordinary_stage_variants = 6,
    floor = 1,
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
    result.ordinary_stage_variants = math.min(6, math.max(1, math.floor(result.ordinary_stage_variants)))
    result.floor = math.max(1, math.min(3, math.floor(tonumber(result.floor) or 1)))
    return result
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

-- Build an FTL-style layout. Node IDs are assigned in layer order so the
-- graph itself has a stable left-to-right direction instead of relying on
-- random coordinates.
local function make_layout(rng, count)
    local layer_count = math.min(8, count)
    layer_count = math.max(7, layer_count)
    local layers = { { 1 } }
    local remaining = count - 2
    local middle_layers = layer_count - 2
    local base = math.floor(remaining / middle_layers)
    local extra = remaining % middle_layers
    local next_id = 2
    for layer_index = 1, middle_layers do
        local layer_size = base + (layer_index <= extra and 1 or 0)
        local layer = {}
        for _ = 1, layer_size do
            layer[#layer + 1] = next_id
            next_id = next_id + 1
        end
        layers[#layers + 1] = layer
    end
    layers[#layers + 1] = { count }

    local positions = {
        [1] = { x = 0.06, y = 0.50 },
        [count] = { x = 0.94, y = 0.50 },
    }
    for layer_index = 2, #layers - 1 do
        local layer = layers[layer_index]
        local x = 0.06 + (layer_index - 1) * 0.88 / (#layers - 1)
        local ys = {}
        for index = 1, #layer do
            local ideal = 0.12 + (index - 0.5) * 0.76 / #layer
            ys[index] = ideal + (rng:next_float() - 0.5) * 0.06
        end
        table.sort(ys)
        for index, node_id in ipairs(layer) do
            positions[node_id] = { x = x, y = clamp(ys[index], 0.08, 0.92) }
        end
    end
    return positions, layers
end

local function add_edge(nodes, left, right)
    if nodes[left]:add_link(right) then
        nodes[right]:add_link(left)
        return true
    end
    return false
end

local function connect_layers(rng, nodes, source_ids, target_ids, max_links)
    local source_count = #source_ids
    local target_count = #target_ids
    local function mapped_index(index, from_count, to_count)
        if from_count <= 1 or to_count <= 1 then
            return 1
        end
        return math.floor((index - 1) * (to_count - 1) / (from_count - 1)) + 1
    end
    local function connect(source_index, target_index)
        if target_index < 1 or target_index > target_count then
            return
        end
        local source = nodes[source_ids[source_index]]
        local target = nodes[target_ids[target_index]]
        if #source.links < max_links and #target.links < max_links then
            add_edge(nodes, source.id, target.id)
        end
    end

    -- Primary monotonic connections preserve vertical order and guarantee
    -- that every source can advance to the next layer.
    for source_index = 1, source_count do
        connect(source_index, mapped_index(source_index, source_count, target_count))
    end
    -- Reverse mapping ensures every node in the next layer has an entrance.
    for target_index = 1, target_count do
        connect(mapped_index(target_index, target_count, source_count), target_index)
    end
    -- Add sparse parallel choices. The +1 target remains monotonic, so it
    -- cannot introduce a crossing with the primary edges.
    for source_index = 1, source_count do
        local primary = mapped_index(source_index, source_count, target_count)
        if primary < target_count and rng:chance(0.45) then
            connect(source_index, primary + 1)
        end
    end
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

    local event_count = math.min(#candidates, math.max(1, math.floor(#candidates * config.event_ratio + 0.5)))
    local shop_count = math.min(#candidates - event_count, math.max(1, math.floor(#candidates * config.shop_ratio + 0.5)))
    local cursor = 1
    for _ = 1, event_count do
        nodes[candidates[cursor]].type = Constants.node_types.EVENT
        cursor = cursor + 1
    end
    for _ = 1, shop_count do
        nodes[candidates[cursor]].type = Constants.node_types.SHOP
        cursor = cursor + 1
    end
    local elite_count = math.max(1, math.floor(#candidates * config.elite_ratio + 0.5))
    for _ = 1, elite_count do
        if cursor <= #candidates then
            nodes[candidates[cursor]].type = Constants.node_types.ELITE
            cursor = cursor + 1
        end
    end
    for index = cursor, #candidates do
        nodes[candidates[index]].type = rng:chance(config.enemy_ratio) and Constants.node_types.ENEMY or Constants.node_types.EVENT
    end
end

function Generator.generate(run_seed, config)
    config = merged_config(config)
    local seed = tonumber(run_seed) or 1
    local rng = RNG.new(seed)
    local positions, layers = make_layout(rng, config.node_count)
    local nodes = {}

    for id = 1, config.node_count do
        local node_type = Constants.node_types.ENEMY
        if id == 1 then
            node_type = Constants.node_types.START
        elseif id == config.node_count then
            node_type = Constants.node_types.BOSS
        end
        nodes[id] = MapNode.new(id, node_type, positions[id].x, positions[id].y, nil, rng:next_int(1, 2147483646))
    end
    nodes[1].visited = true
    nodes[1].encounter_id = nil
    nodes[config.node_count].encounter_id = "boss_stage_01"
    assign_types(rng, nodes, config)

    -- Only connect adjacent layers. connect_layers preserves the vertical
    -- ordering, which keeps the rendered route lines free of crossings.
    for layer_index = 1, #layers - 1 do
        connect_layers(rng, nodes, layers[layer_index], layers[layer_index + 1], config.max_links)
    end

    -- Ordinary rooms carry the six-band difficulty of their floor and
    -- position. Boss/elite rooms carry the floor so the native layer can pick
    -- from the matching fixed pool.
    local floor = math.max(1, math.min(3, math.floor(tonumber(config.floor) or 1)))
    for id, node in pairs(nodes) do
        node.floor = floor
        if node.type == Constants.node_types.ENEMY then
            node.band = WaveDifficulty.band_for(floor, node.x)
            node.encounter_id = string.format("ordinary_stage_%02d", rng:next_int(1, config.ordinary_stage_variants))
        elseif node.type == Constants.node_types.ELITE then
            node.band = (floor - 1) * 2 + 2
            node.encounter_id = "elite_stage_01"
        elseif node.type == Constants.node_types.BOSS then
            node.band = floor * 2
            node.encounter_id = "boss_stage_01"
        end
    end
    return MapState.new(nodes, 1, config.node_count)
end

return Generator
