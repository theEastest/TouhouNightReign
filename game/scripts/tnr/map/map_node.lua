local MapNode = {}
MapNode.__index = MapNode

function MapNode.new(id, node_type, x, y, encounter_id)
    return setmetatable({
        id = id,
        type = node_type,
        x = x,
        y = y,
        links = {},
        visited = false,
        corrupted = false,
        encounter_id = encounter_id,
    }, MapNode)
end

function MapNode:add_link(node_id)
    if node_id == self.id then
        return false
    end
    for _, linked_id in ipairs(self.links) do
        if linked_id == node_id then
            return false
        end
    end
    self.links[#self.links + 1] = node_id
    table.sort(self.links)
    return true
end

function MapNode:is_linked(node_id)
    for _, linked_id in ipairs(self.links) do
        if linked_id == node_id then
            return true
        end
    end
    return false
end

function MapNode:remove_link(node_id)
    for index, linked_id in ipairs(self.links) do
        if linked_id == node_id then
            table.remove(self.links, index)
            return true
        end
    end
    return false
end

return MapNode
