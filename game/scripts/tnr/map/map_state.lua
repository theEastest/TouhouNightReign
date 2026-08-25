local Constants = require("tnr.core.constants")

local MapState = {}
MapState.__index = MapState

function MapState.new(nodes, start_node_id, boss_node_id)
    return setmetatable({
        nodes = nodes or {},
        start_node_id = start_node_id,
        boss_node_id = boss_node_id,
        current_node_id = start_node_id,
        revealed = false,
    }, MapState)
end

function MapState:get_node(node_id)
    return self.nodes[node_id]
end

function MapState:get_current_node()
    return self.nodes[self.current_node_id]
end

function MapState:is_adjacent(node_id)
    local current = self:get_current_node()
    return current ~= nil and current:is_linked(node_id)
end

function MapState:select_node(node_id)
    local node = self.nodes[node_id]
    if not node then
        return nil, "unknown node"
    end
    if node_id == self.current_node_id then
        return nil, "already at node"
    end
    if not self:is_adjacent(node_id) then
        return nil, "node is not adjacent"
    end
    self.current_node_id = node_id
    node.visited = true
    return node
end

function MapState:find_path(start_id, goal_id)
    if not self.nodes[start_id] or not self.nodes[goal_id] then
        return nil
    end
    local queue = { start_id }
    local head = 1
    local parent = { [start_id] = false }
    while queue[head] do
        local node_id = queue[head]
        head = head + 1
        if node_id == goal_id then
            local path = {}
            while node_id do
                table.insert(path, 1, node_id)
                node_id = parent[node_id]
            end
            return path
        end
        for _, linked_id in ipairs(self.nodes[node_id].links) do
            if parent[linked_id] == nil then
                parent[linked_id] = node_id
                queue[#queue + 1] = linked_id
            end
        end
    end
    return nil
end

function MapState:count_types()
    local counts = {}
    for _, node in pairs(self.nodes) do
        counts[node.type] = (counts[node.type] or 0) + 1
    end
    return counts
end

function MapState:reveal()
    self.revealed = true
end

return MapState

