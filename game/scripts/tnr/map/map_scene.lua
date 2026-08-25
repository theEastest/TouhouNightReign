local Constants = require("tnr.core.constants")
local Command = require("tnr.core.command")

local MapScene = {}
MapScene.__index = MapScene

function MapScene.new(session)
    return setmetatable({ session = session, message = "" }, MapScene)
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
            revealed = map.revealed or node.visited or (current and current:is_linked(id)) or false,
        }
    end
    table.sort(nodes, function(a, b) return a.id < b.id end)
    return {
        nodes = nodes,
        current_node_id = map.current_node_id,
        message = self.message,
    }
end

function MapScene:select_node(node_id)
    local result, err = self.session:dispatch({ type = Command.SELECT_NODE, node_id = node_id, player_id = 1 })
    if not result then
        self.message = err or "无法前往该节点"
        return nil, self.message
    end
    self.message = ""
    return result
end

function MapScene:select_with_mouse(x, y, radius)
    radius = radius or 0.035
    local view = self:get_view()
    local best_id
    local best_distance
    for _, node in ipairs(view.nodes) do
        if node.selectable or node.id == view.current_node_id then
            local dx = node.x - x
            local dy = node.y - y
            local squared = dx * dx + dy * dy
            if squared <= radius * radius and (not best_distance or squared < best_distance) then
                best_id = node.id
                best_distance = squared
            end
        end
    end
    if not best_id or best_id == view.current_node_id then
        return nil, "没有可选择的节点"
    end
    return self:select_node(best_id)
end

return MapScene

