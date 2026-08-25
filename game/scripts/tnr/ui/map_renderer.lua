local Constants = require("tnr.core.constants")

local MapRenderer = {}
MapRenderer.__index = MapRenderer

local TYPE_LABELS = {
    START = "起点",
    ENEMY = "战斗",
    BOSS = "Boss",
    SHOP = "商店",
    EVENT = "事件",
}

local TYPE_COLORS = {
    START = { 255, 90, 210, 125 },
    ENEMY = { 255, 220, 100, 100 },
    BOSS = { 255, 240, 80, 80 },
    SHOP = { 255, 100, 180, 240 },
    EVENT = { 255, 170, 120, 230 },
}

local function color(lstg, values)
    return lstg.Color(values[1], values[2], values[3], values[4])
end

local function screen_x(node, width)
    return 80 + node.x * (width - 160)
end

local function screen_y(node, height)
    return 60 + node.y * (height - 150)
end

local function draw_segment(lstg, image, x1, y1, x2, y2, thickness)
    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0 then
        return
    end
    local nx = -dy / length * thickness * 0.5
    local ny = dx / length * thickness * 0.5
    lstg.Render4V(image, x1 + nx, y1 + ny, 0.5, x2 + nx, y2 + ny, 0.5, x2 - nx, y2 - ny, 0.5, x1 - nx, y1 - ny, 0.5)
end

function MapRenderer.new(lstg, width, height)
    return setmetatable({ lstg = lstg, width = width or 1280, height = height or 720, white = nil }, MapRenderer)
end

function MapRenderer:init()
    if self.white or not self.lstg then
        return
    end
    self.lstg.CreateRenderTarget("rt:tnr-white", 16, 16)
    self.lstg.LoadImage("img:tnr-white", "rt:tnr-white", 0, 0, 16, 16)
    self.white = "img:tnr-white"
end

function MapRenderer:draw_text(text, x, y, size, draw_color, align)
    self.lstg.RenderTTF("Sans", text, x, x, y, y, align or 0, draw_color, size or 2)
end

function MapRenderer:render(view, session)
    if not self.lstg then
        return
    end
    self:init()
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(lstg.Color(255, 12, 16, 28))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)

    if session.run_state ~= Constants.run_states.MAP then
        local title = ""
        local detail = ""
        if session.run_state == Constants.run_states.PLACEHOLDER then
            title = session.map:get_current_node().type == Constants.node_types.SHOP and "商店" or "事件"
            detail = "第一版占位界面，按 Enter 返回地图"
        elseif session.run_state == Constants.run_states.ENCOUNTER then
            title = "战斗准备中"
            detail = session.current_encounter and ("Stage: " .. session.current_encounter.stage_id) or "等待 Encounter"
        elseif session.run_state == Constants.run_states.RUN_CLEAR then
            title = "本局完成"
            detail = "Boss 已击破"
        else
            title = "战斗失败"
            detail = "请重新开始"
        end
        self:draw_text(title, self.width * 0.5, self.height * 0.58, 3, lstg.Color(255, 245, 245, 255), 1 + 4)
        self:draw_text(detail, self.width * 0.5, self.height * 0.45, 1.8, lstg.Color(255, 220, 220, 220), 1 + 4)
        lstg.EndScene()
        return
    end

    local white = self.white
    for _, node in ipairs(view.nodes) do
        if node.revealed then
            for _, linked_id in ipairs(node.links) do
                if linked_id > node.id then
                    local linked = view.nodes[linked_id]
                    if linked and linked.revealed then
                        lstg.SetImageState(white, "", lstg.Color(120, 90, 100, 125))
                        draw_segment(lstg, white, screen_x(node, self.width), screen_y(node, self.height), screen_x(linked, self.width), screen_y(linked, self.height), 3)
                    end
                end
            end
        end
    end

    for _, node in ipairs(view.nodes) do
        if node.revealed then
            local x = screen_x(node, self.width)
            local y = screen_y(node, self.height)
            local node_color = TYPE_COLORS[node.type] or { 255, 200, 200, 200 }
            if node.id == view.current_node_id then
                node_color = { 255, 255, 255, 255 }
            elseif node.id == view.cursor_node_id then
                node_color = { 255, 110, 230, 255 }
            elseif not node.selectable and not node.visited then
                node_color = { 120, 100, 100, 100 }
            end
            lstg.SetImageState(white, "", color(lstg, node_color))
            local radius = node.id == view.current_node_id and 15 or 10
            lstg.RenderRect(white, x - radius, x + radius, y - radius, y + radius)
            self:draw_text(TYPE_LABELS[node.type] or node.type, x, y - 28, 1.2, color(lstg, node_color), 1 + 4)
        end
    end

    self:draw_text("TouHouNightReign", 40, self.height - 40, 2.5, lstg.Color(255, 245, 245, 255), 0)
    local player = session:get_player(1)
    local hud = string.format("Money %d   Score %d   Life %d   Bomb %d", player.money, player.score, player.life, player.bomb)
    self:draw_text(hud, self.width - 40, self.height - 40, 1.5, lstg.Color(255, 235, 235, 235), 2)
    self:draw_text(view.message ~= "" and view.message or "方向键选择节点，Enter 确认，鼠标点击节点", 40, 24, 1.3, lstg.Color(255, 220, 220, 220), 0)
    lstg.EndScene()
end

return MapRenderer
