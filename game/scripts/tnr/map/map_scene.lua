local Constants = require("tnr.core.constants")
local Command = require("tnr.core.command")

local MapScene = {}
MapScene.__index = MapScene

function MapScene.new(session)
    return setmetatable({ session = session, message = "", cursor_node_id = nil }, MapScene)
end

function MapScene:get_view()
    local map = self.session.map
    local current = map and map:get_current_node()
    local nodes = {}
    if not map then
        return { nodes = nodes, current_node_id = nil, message = self.message }
    end
    for id, node in pairs(map.nodes) do
        nodes[#nodes + 1] = {
            id = id,
            type = node.type,
            x = node.x,
            y = node.y,
            links = node.links,
            visited = node.visited,
            selectable = current ~= nil and current:is_linked(id),
            -- The first prototype intentionally exposes the whole route graph.
            revealed = true,
        }
    end
    table.sort(nodes, function(a, b) return a.id < b.id end)
    return {
        nodes = nodes,
        current_node_id = map.current_node_id,
        message = self.message,
        cursor_node_id = self.cursor_node_id,
    }
end

function MapScene:get_selectable_nodes()
    local current = self.session.map and self.session.map:get_current_node()
    local result = {}
    if current then
        for _, node_id in ipairs(current.links) do
            result[#result + 1] = self.session.map:get_node(node_id)
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function MapScene:move_cursor(direction)
    local nodes = self:get_selectable_nodes()
    if #nodes == 0 then
        self.cursor_node_id = nil
        return nil
    end
    local current_index = 1
    for index, node in ipairs(nodes) do
        if node.id == self.cursor_node_id then
            current_index = index
            break
        end
    end
    local next_index = ((current_index - 1 + direction) % #nodes) + 1
    self.cursor_node_id = nodes[next_index].id
    return nodes[next_index]
end

function MapScene:select_cursor()
    if not self.cursor_node_id then
        self:move_cursor(1)
    end
    if not self.cursor_node_id then
        return nil, "没有可选择的节点"
    end
    return self:select_node(self.cursor_node_id)
end

function MapScene:select_node(node_id)
    local result, err = self.session:dispatch({ type = Command.SELECT_NODE, node_id = node_id, player_id = 1 })
    if not result then
        self.message = err or "无法前往该节点"
        return nil, self.message
    end
    self.message = ""
    self.cursor_node_id = nil
    return result
end

function MapScene:select_with_mouse(x, y, radius)
    local node = self:find_mouse_node(x, y, radius)
    if not node or node.id == self.session.map.current_node_id then
        return nil, "没有可选择的节点"
    end
    return self:select_node(node.id)
end

function MapScene:find_mouse_node(x, y, radius)
    radius = radius or 0.035
    local view = self:get_view()
    local best_id
    local best_distance
    for _, node in ipairs(view.nodes) do
        if node.selectable then
            local dx = node.x - x
            local dy = node.y - y
            local squared = dx * dx + dy * dy
            if squared <= radius * radius and (not best_distance or squared < best_distance) then
                best_id = node.id
                best_distance = squared
            end
        end
    end
    return best_id and self.session.map:get_node(best_id) or nil
end

function MapScene:hover_with_mouse(x, y, radius)
    local node = self:find_mouse_node(x, y, radius)
    self.cursor_node_id = node and node.id or nil
    return node
end

return MapScene
