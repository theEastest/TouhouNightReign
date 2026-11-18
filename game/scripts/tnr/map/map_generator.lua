local Constants = require("tnr.core.constants")
local RNG = require("tnr.core.rng")
local MapNode = require("tnr.map.map_node")
local MapState = require("tnr.map.map_state")
local WaveDifficulty = require("tnr.stages.wave_difficulty")

local Generator = {}

local DEFAULTS = {
    -- Keep roughly the previous node density after adding three route
    -- columns, so the map still offers several meaningful paths per column.
    node_count = 35,
    min_boss_hops = 10,
    min_node_spacing = 0.06,
    max_links = 4,
    enemy_ratio = 0.64,
    elite_ratio = 0.18,
    event_ratio = 0.06,
    shop_ratio = 0.07,
    shrine_ratio = 0.05,
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
    local layer_count = math.min(11, count)
    layer_count = math.max(7, layer_count)
    local layers = { { 1 } }
    local remaining = count - 2
    local middle_layers = layer_count - 2
    local base = math.floor(remaining / middle_layers)
    local extra = remaining % middle_layers
    local extra_layers = {}
    for layer_index = 1, middle_layers do
        extra_layers[#extra_layers + 1] = layer_index
    end
    rng:shuffle(extra_layers)
    local layer_sizes = {}
    for layer_index = 1, middle_layers do
        layer_sizes[layer_index] = base
    end
    for index = 1, extra do
        local layer_index = extra_layers[index]
        layer_sizes[layer_index] = layer_sizes[layer_index] + 1
    end
    local next_id = 2
    for layer_index = 1, middle_layers do
        local layer_size = layer_sizes[layer_index]
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
    local incoming_count = {}
    local max_incoming = target_count == 1 and max_links or math.min(2, max_links - 1)
    for _, target_id in ipairs(target_ids) do incoming_count[target_id] = 0 end
    local function mapped_index(index, from_count, to_count)
        if from_count <= 1 or to_count <= 1 then
            return 1
        end
        return math.floor((index - 1) * (to_count - 1) / (from_count - 1)) + 1
    end
    local function connect(source_index, target_index)
        if target_index < 1 or target_index > target_count then
            return false
        end
        local source = nodes[source_ids[source_index]]
        local target = nodes[target_ids[target_index]]
        -- Keep at most two incoming routes per room. That leaves room for a
        -- forward exit under the four-link cap, including when a 3-node layer
        -- fans out into a 4-node layer.
        if incoming_count[target.id] < max_incoming
                and #source.links < max_links and #target.links < max_links then
            if add_edge(nodes, source.id, target.id) then
                incoming_count[target.id] = incoming_count[target.id] + 1
                return true
            end
        end
        return false
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
    -- If a reverse edge hit a saturated source in a custom map config, attach
    -- any still-unserved destination to the nearest source that has capacity.
    -- With the default 3/4-node layers this is normally a no-op.
    for target_index, target_id in ipairs(target_ids) do
        if incoming_count[target_id] == 0 then
            local preferred = mapped_index(target_index, target_count, source_count)
            local connected = connect(preferred, target_index)
            local distance = 1
            while not connected and distance < source_count do
                for _, source_index in ipairs({ preferred - distance, preferred + distance }) do
                    if source_index >= 1 and source_index <= source_count then
                        connected = connect(source_index, target_index)
                        if connected then break end
                    end
                end
                distance = distance + 1
            end
        end
    end
    -- StS/FTL maps tend to offer one or two forward choices per room. Give
    -- each layer pair a randomized branch direction, then add optional
    -- adjacent choices on that side. A shared direction preserves vertical
    -- order, so lines stay non-crossing while the graph forms varied fans,
    -- joins and splits instead of repeating the same diagonal motif.
    local branch_direction = rng:chance(0.5) and 1 or -1
    for source_index = 1, source_count do
        local primary = mapped_index(source_index, source_count, target_count)
        local alternate = primary + branch_direction
        if alternate >= 1 and alternate <= target_count and rng:chance(0.62) then
            connect(source_index, alternate)
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

    -- Ratios are shares of the same interior-node pool. The previous code
    -- assigned events/shops/elites first, then split the remainder only
    -- between enemies and events, making events appear far more often than
    -- their configured 20% weight.
    local entries = {
        { type = Constants.node_types.ENEMY, weight = math.max(0, tonumber(config.enemy_ratio) or 0) },
        { type = Constants.node_types.ELITE, weight = math.max(0, tonumber(config.elite_ratio) or 0) },
        { type = Constants.node_types.EVENT, weight = math.max(0, tonumber(config.event_ratio) or 0) },
        { type = Constants.node_types.SHOP, weight = math.max(0, tonumber(config.shop_ratio) or 0) },
        { type = Constants.node_types.SHRINE, weight = math.max(0, tonumber(config.shrine_ratio) or 0) },
    }
    local total_weight = 0
    for _, entry in ipairs(entries) do total_weight = total_weight + entry.weight end
    if total_weight <= 0 then
        entries[1].weight, entries[2].weight, entries[3].weight, entries[4].weight, entries[5].weight = 0.64, 0.18, 0.06, 0.07, 0.05
        total_weight = 1
    end
    local counts, remainders, assigned = {}, {}, 0
    for index, entry in ipairs(entries) do
        local exact = #candidates * entry.weight / total_weight
        counts[index] = math.floor(exact)
        assigned = assigned + counts[index]
        remainders[#remainders + 1] = { index = index, fraction = exact - counts[index] }
    end
    table.sort(remainders, function(left, right)
        if left.fraction ~= right.fraction then return left.fraction > right.fraction end
        return left.index < right.index
    end)
    for index = 1, #candidates - assigned do
        local entry_index = remainders[((index - 1) % #remainders) + 1].index
        counts[entry_index] = counts[entry_index] + 1
    end
    local assigned_types = {}
    for index, entry in ipairs(entries) do
        for _ = 1, counts[index] do assigned_types[#assigned_types + 1] = entry.type end
    end
    rng:shuffle(assigned_types)
    for index, node_id in ipairs(candidates) do
        nodes[node_id].type = assigned_types[index]
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
