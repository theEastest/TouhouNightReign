local Constants = require("tnr.core.constants")

local MapRenderer = {}
MapRenderer.__index = MapRenderer

local TYPE_META = {
    START = { label = "起点", glyph = "S", color = { 255, 236, 236, 240 } },
    ENEMY = { label = "战斗", glyph = "E", color = { 255, 238, 92, 92 } },
    BOSS = { label = "Boss", glyph = "B", color = { 255, 247, 151, 58 } },
    SHOP = { label = "商店", glyph = "$", color = { 255, 112, 220, 145 } },
    EVENT = { label = "事件", glyph = "?", color = { 255, 86, 180, 238 } },
}

local COLORS = {
    background = { 255, 9, 13, 25 },
    map_panel = { 220, 20, 26, 43 },
    panel = { 242, 15, 19, 32 },
    panel_border = { 190, 110, 122, 154 },
    muted = { 190, 164, 172, 190 },
    text = { 255, 245, 241, 236 },
    accent = { 255, 235, 105, 110 },
    active_line = { 235, 245, 216, 190 },
    visited_line = { 210, 155, 154, 170 },
    dim_line = { 145, 96, 105, 105 },
}

local function color(lstg, values)
    return lstg.Color(values[1], values[2], values[3], values[4])
end

local function screen_x(node, left, right)
    return left + node.x * (right - left)
end

local function screen_y(node, bottom, top)
    return bottom + node.y * (top - bottom)
end

local function draw_rect(lstg, image, values, left, right, bottom, top)
    lstg.SetImageState(image, "", color(lstg, values))
    lstg.RenderRect(image, left, right, bottom, top)
end

local function draw_line(lstg, image, values, x1, y1, x2, y2, thickness)
    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0 then
        return
    end
    local nx = -dy / length * thickness * 0.5
    local ny = dx / length * thickness * 0.5
    lstg.SetImageState(image, "", color(lstg, values))
    lstg.Render4V(image, x1 + nx, y1 + ny, 0.7, x2 + nx, y2 + ny, 0.7, x2 - nx, y2 - ny, 0.7, x1 - nx, y1 - ny, 0.7)
end

local function draw_diamond(lstg, image, values, x, y, radius)
    lstg.SetImageState(image, "", color(lstg, values))
    lstg.Render4V(image, x, y + radius, 0.5, x + radius, y, 0.5, x, y - radius, 0.5, x - radius, y, 0.5)
end

function MapRenderer.new(lstg, width, height)
    return setmetatable({
        lstg = lstg,
        width = width or 1280,
        height = height or 720,
        white = nil,
    }, MapRenderer)
end

function MapRenderer:init()
    if self.white or not self.lstg then
        return
    end
    self.lstg.CreateRenderTarget("rt:tnr-white", 16, 16)
    self.lstg.LoadImage("img:tnr-white", "rt:tnr-white", 0, 0, 16, 16)
    self.white = "img:tnr-white"
end

function MapRenderer:draw_text(text, x, y, size, values, align)
    self.lstg.RenderTTF("Sans", text, x, x, y, y, align or 0, color(self.lstg, values or COLORS.text), size or 2)
end

function MapRenderer:draw_panel(left, right, bottom, top)
    local lstg = self.lstg
    local image = self.white
    draw_rect(lstg, image, { 180, 0, 0, 0 }, left + 4, right + 4, bottom - 4, top - 4)
    draw_rect(lstg, image, COLORS.panel, left, right, bottom, top)
    draw_line(lstg, image, COLORS.panel_border, left, bottom, right, bottom, 1)
    draw_line(lstg, image, COLORS.panel_border, right, bottom, right, top, 1)
    draw_line(lstg, image, COLORS.panel_border, right, top, left, top, 1)
    draw_line(lstg, image, COLORS.panel_border, left, top, left, bottom, 1)
end

function MapRenderer:draw_legend()
    local left, right, bottom, top = 24, 205, 185, 595
    self:draw_panel(left, right, bottom, top)
    self:draw_text("节点图例", left + 18, top - 30, 2.1, COLORS.text, 0)
    self:draw_text("当前路线", left + 18, top - 56, 1.1, COLORS.muted, 0)
    local rows = {
        { "当前节点", "●", { 255, 255, 255, 255 } },
        { "未访问", "◆", { 190, 170, 175, 190 } },
        { "战斗", "E", TYPE_META.ENEMY.color },
        { "Boss", "B", TYPE_META.BOSS.color },
        { "商店", "$", TYPE_META.SHOP.color },
        { "事件", "?", TYPE_META.EVENT.color },
    }
    for index, row in ipairs(rows) do
        local y = top - 92 - (index - 1) * 42
        draw_diamond(self.lstg, self.white, row[3], left + 28, y, 9)
        self:draw_text(row[2], left + 28, y - 4, 1.1, COLORS.text, 1 + 4)
        self:draw_text(row[1], left + 52, y - 4, 1.2, COLORS.text, 0)
    end
    self:draw_text("鼠标悬停节点查看可达路线", left + 18, bottom + 26, 0.95, COLORS.muted, 0)
end

function MapRenderer:draw_header(session)
    local player = session:get_player(1)
    self:draw_panel(24, self.width - 24, self.height - 86, self.height - 20)
    self:draw_text("探索地图", 48, self.height - 55, 2.5, COLORS.text, 0)
    self:draw_text("TouHouNightReign", self.width * 0.5, self.height - 54, 1.8, COLORS.accent, 1 + 4)
    local hud = string.format("生命 %d     炸弹 %d     金钱 %d     总分 %d", player.life, player.bomb, player.money, player.score)
    self:draw_text(hud, self.width - 48, self.height - 54, 1.35, COLORS.text, 2)
end

function MapRenderer:draw_footer(message)
    self:draw_panel(220, self.width - 24, 22, 74)
    self:draw_text(message or "选择一个相邻节点前进", self.width * 0.5, 42, 1.35, COLORS.text, 1 + 4)
    self:draw_text("方向键移动    Enter 确认    鼠标点击选择", self.width - 48, 42, 1.05, COLORS.muted, 2)
end

function MapRenderer:draw_map(view)
    local left, right = 245, self.width - 48
    local bottom, top = 125, self.height - 120
    local node_positions = {}
    for _, node in ipairs(view.nodes) do
        node_positions[node.id] = {
            x = screen_x(node, left, right),
            y = screen_y(node, bottom, top),
        }
    end

    for _, node in ipairs(view.nodes) do
        local source = node_positions[node.id]
        for _, linked_id in ipairs(node.links) do
            if linked_id > node.id then
                local target = node_positions[linked_id]
                local linked = view.nodes[linked_id]
                local values = COLORS.dim_line
                if node.id == view.current_node_id or linked_id == view.current_node_id then
                    values = COLORS.active_line
                elseif node.visited and linked and linked.visited then
                    values = COLORS.visited_line
                end
                draw_line(self.lstg, self.white, values, source.x, source.y, target.x, target.y, node.id == view.current_node_id and 3 or 2)
            end
        end
    end

    for _, node in ipairs(view.nodes) do
        local position = node_positions[node.id]
        local meta = TYPE_META[node.type] or TYPE_META.EVENT
        local is_current = node.id == view.current_node_id
        local is_hovered = node.id == view.cursor_node_id
        local is_selectable = node.selectable
        local outer = meta.color
        if is_current then
            outer = { 255, 255, 255, 255 }
        elseif is_hovered then
            outer = { 255, 255, 210, 115 }
        elseif not is_selectable and not node.visited then
            outer = { 130, meta.color[2], meta.color[3], meta.color[4] }
        end
        if is_current or is_hovered then
            draw_diamond(self.lstg, self.white, { 80, outer[2], outer[3], outer[4] }, position.x, position.y, is_current and 29 or 25)
        end
        draw_diamond(self.lstg, self.white, outer, position.x, position.y, is_current and 21 or 17)
        draw_diamond(self.lstg, self.white, { 255, 19, 23, 38 }, position.x, position.y, is_current and 14 or 11)
        self:draw_text(meta.glyph, position.x, position.y - 6, is_current and 1.4 or 1.1, outer, 1 + 4)
        self:draw_text(meta.label, position.x, position.y - 34, 1.05, is_current and COLORS.text or COLORS.muted, 1 + 4)
    end
end

function MapRenderer:screen_to_map(x, y)
    local left, right = 245, self.width - 48
    local bottom, top = 125, self.height - 120
    if x < left or x > right or y < bottom or y > top then
        return nil
    end
    return (x - left) / (right - left), (y - bottom) / (top - bottom)
end

function MapRenderer:render_map(view, session)
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, COLORS.map_panel, 214, self.width - 24, 92, self.height - 96)
    self:draw_header(session)
    self:draw_legend()
    self:draw_map(view)
    self:draw_footer(view.message ~= "" and view.message or nil)
    lstg.EndScene()
end

function MapRenderer:render(view, session)
    if not self.lstg then
        return
    end
    self:init()
    if session.run_state == Constants.run_states.MAP then
        self:render_map(view, session)
        return
    end
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_panel(270, self.width - 270, 240, 480)
    local title = "战斗准备中"
    local detail = session.current_encounter and ("Stage: " .. session.current_encounter.stage_id) or "等待 Encounter"
    if session.run_state == Constants.run_states.PLACEHOLDER then
        title = "占位区域"
        detail = "第一版占位界面，按 Enter 返回地图"
    elseif session.run_state == Constants.run_states.RUN_CLEAR then
        title = "本局完成"
        detail = "Boss 已击破"
    elseif session.run_state == Constants.run_states.RUN_FAILED then
        title = "战斗失败"
        detail = "请重新开始"
    end
    self:draw_text(title, self.width * 0.5, 400, 3.2, COLORS.text, 1 + 4)
    self:draw_text(detail, self.width * 0.5, 335, 1.6, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

return MapRenderer
