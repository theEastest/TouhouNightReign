local Constants = require("tnr.core.constants")
local TrainingCatalog = require("tnr.training.card_training_catalog")
local Phase1Catalog = require("tnr.equipment.phase1_catalog")
local ScrollState = require("tnr.ui.scroll_state")

local MapRenderer = {}
MapRenderer.__index = MapRenderer

local TYPE_META = {
    ELITE = { label = "Elite", glyph = "A", color = { 255, 220, 126, 58 } },
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
    active_line = { 255, 245, 216, 190 },
    visited_line = { 235, 155, 154, 170 },
    dim_line = { 220, 112, 132, 170 },
    p1_vote = { 255, 105, 190, 255 },
    p2_vote = { 255, 105, 235, 150 },
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
    -- Small rectangles are supported by the engine's fallback renderer.
    local steps = math.max(1, math.ceil(length / 3))
    for index = 0, steps do
        local t = index / steps
        local x = x1 + dx * t
        local y = y1 + dy * t
        draw_rect(lstg, image, values, x - thickness * 0.5, x + thickness * 0.5, y - thickness * 0.5, y + thickness * 0.5)
    end
end

local function draw_diamond(lstg, image, values, x, y, radius)
    draw_rect(lstg, image, values, x - radius, x + radius, y - radius, y + radius)
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
    -- Use the PNG loaded by game/scripts/main.lua. RenderTarget-backed
    -- sprites are not visible on all LuaSTG Sub graphics backends.
    self.white = "tnr-white"
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

function MapRenderer:list_window(cursor, count, visible)
    local state = ScrollState.new(count, visible, cursor)
    return state:first_visible(), math.min(count or 0, state:first_visible() + (visible or 1) - 1)
end

-- Draw a compact, high-contrast scrollbar only when a list exceeds its
-- viewport. The thumb position is derived from the selected item, keeping it
-- synchronized with keyboard navigation and mouse dragging.
function MapRenderer:draw_scrollbar(left, right, bottom, top, count, visible, cursor, mouse_x, mouse_y, mouse_down)
    count, visible = tonumber(count) or 0, math.max(1, tonumber(visible) or 1)
    if count <= visible then return end
    local track_left, track_right = right - 12, right - 4
    local track_height = top - bottom
    local thumb_height = math.max(28, track_height * visible / count)
    local state = ScrollState.new(count, visible, cursor)
    local fraction = (state:first_visible() - 1) / math.max(1, count - visible)
    -- LuaSTG uses a bottom-left origin, so increasing the selected index moves
    -- the thumb toward the visual bottom of the track.
    local thumb_bottom = bottom + (track_height - thumb_height) * (1 - fraction)
    local hovered = mouse_x and mouse_y and mouse_x >= track_left - 6 and mouse_x <= track_right + 6 and mouse_y >= bottom and mouse_y <= top
    local track_color = hovered and { 180, 115, 130, 180 } or { 120, 90, 102, 125 }
    local thumb_color = mouse_down and hovered and { 255, 255, 185, 155 }
        or (hovered and { 255, 255, 145, 125 } or COLORS.accent)
    draw_rect(self.lstg, self.white, track_color, track_left, track_right, bottom, top)
    draw_rect(self.lstg, self.white, thumb_color, track_left - 2, track_right + 2, thumb_bottom, thumb_bottom + thumb_height)
end

function MapRenderer:scrollbar_index(x, y, left, right, bottom, top, count, visible)
    count, visible = tonumber(count) or 0, math.max(1, tonumber(visible) or 1)
    if not x or not y or count <= visible or x < right - 28 or x > right + 4 then return nil end
    local normalized = math.max(0, math.min(1, (y - bottom) / math.max(1, top - bottom)))
    return ScrollState.new(count, visible, 1):set_from_track(1 - normalized)
end

function MapRenderer:draw_legend()
    local left, right, bottom, top = 24, 205, 185, 595
    self:draw_panel(left, right, bottom, top)
    self:draw_text("节点图例", left + 18, top - 20, 1.15, COLORS.text, 0)
    self:draw_text("当前路线", left + 18, top - 58, 0.72, COLORS.muted, 0)
    local rows = {
        { "Elite", "A", TYPE_META.ELITE.color },
        { "当前节点", "●", { 255, 255, 255, 255 } },
        { "未访问", "◆", { 190, 170, 175, 190 } },
        { "战斗", "E", TYPE_META.ENEMY.color },
        { "Boss", "B", TYPE_META.BOSS.color },
        { "商店", "$", TYPE_META.SHOP.color },
        { "事件", "?", TYPE_META.EVENT.color },
    }
    for index, row in ipairs(rows) do
        local y = top - 96 - (index - 1) * 38
        draw_diamond(self.lstg, self.white, row[3], left + 28, y, 9)
        self:draw_text(row[2], left + 28, y + 1, 0.78, COLORS.text, 1 + 4)
        self:draw_text(row[1], left + 52, y + 1, 0.82, COLORS.text, 0)
    end
    self:draw_text("鼠标悬停节点查看可达路线", left + 18, bottom + 26, 0.95, COLORS.muted, 0)
end

function MapRenderer:draw_header(session)
    local player = session:get_player(1)
    self:draw_panel(24, self.width - 24, self.height - 86, self.height - 20)
    self:draw_text("探索地图", 48, self.height - 68, 1.4, COLORS.text, 0)
    self:draw_text("TouHouNightReign", self.width * 0.5, self.height - 62, 1.0, COLORS.accent, 1 + 4)
    local hud = string.format("生命 %d   炸弹 %d   金钱 %d   总分 %d", player.life, player.bomb, player.money, player.score)
    -- Leave the top-right equipment button clear of the status HUD.
    self:draw_text(hud, self.width - 170, self.height - 62, 0.82, COLORS.text, 2)
end

function MapRenderer:draw_footer(message)
    self:draw_panel(220, self.width - 24, 22, 74)
    self:draw_text(message or "选择一个相邻节点前进", self.width * 0.5, 56, 0.88, COLORS.text, 1 + 4)
    self:draw_text("方向键移动    Enter 确认    鼠标点击选择", self.width - 48, 56, 0.68, COLORS.muted, 2)
end

function MapRenderer:draw_map(view)
    local left, right = 245, self.width - 48
    local bottom, top = 125, self.height - 120
    local node_positions = {}
    local node_vote_labels = {}
    for player_id, node_id in pairs(view.node_votes or {}) do
        node_vote_labels[node_id] = node_vote_labels[node_id] or {}
        node_vote_labels[node_id][#node_vote_labels[node_id] + 1] = player_id
    end
    for _, player_ids in pairs(node_vote_labels) do
        table.sort(player_ids)
    end
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
                draw_line(self.lstg, self.white, values, source.x, source.y, target.x, target.y, node.id == view.current_node_id and 5 or 4)
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
        local voters = node_vote_labels[node.id]
        if voters and #voters > 0 then
            local labels = {}
            for _, player_id in ipairs(voters) do
                labels[#labels + 1] = "P" .. tostring(player_id)
            end
            local vote_color = #voters > 1 and COLORS.accent or (voters[1] == 1 and COLORS.p1_vote or COLORS.p2_vote)
            self:draw_text(table.concat(labels, " + "), position.x, position.y + 32, 0.8, vote_color, 1 + 4)
        end
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

function MapRenderer:map_equipment_hit_test(x, y)
    if not x or not y then return false end
    local left, right = self.width - 154, self.width - 74
    local bottom, top = self.height - 76, self.height - 30
    return x >= left and x <= right and y >= bottom and y <= top
end

function MapRenderer:render_map(view, session, mouse_x, mouse_y)
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, COLORS.map_panel, 214, self.width - 24, 92, self.height - 96)
    self:draw_header(session)
    local button_left, button_right = self.width - 154, self.width - 74
    local button_bottom, button_top = self.height - 76, self.height - 30
    local locked = session.preparation and session.preparation.selected_node_id ~= nil
    local hovered = self:map_equipment_hit_test(mouse_x, mouse_y)
    local button_color = locked and { 100, 80, 86, 100 } or (hovered and { 255, 235, 105, 105 } or { 210, 24, 29, 62 })
    draw_rect(lstg, self.white, button_color, button_left, button_right, button_bottom, button_top)
    draw_line(lstg, self.white, hovered and COLORS.text or COLORS.panel_border, button_left, button_bottom, button_right, button_bottom, hovered and 2 or 1)
    draw_line(lstg, self.white, hovered and COLORS.text or COLORS.panel_border, button_left, button_top, button_right, button_top, hovered and 2 or 1)
    self:draw_text("i", (button_left + button_right) * 0.5, button_bottom + 23, 0.9, locked and COLORS.muted or COLORS.text, 1 + 4)
    self:draw_text("Seed: " .. tostring(session.run_seed or "-"), 48, 96, 0.72, COLORS.muted, 0)
    self:draw_legend()
    self:draw_map(view)
    self:draw_footer(view.message ~= "" and view.message or nil)
    lstg.EndScene()
end

function MapRenderer:preparation_hit_test(x, y, row_count, cursor)
    if not x or not y then return nil end
    local groups = {
        { key = "high_weapons", x = 100, y = 525, count = 3 },
        { key = "low_weapons", x = 100, y = 375, count = 3 },
        { key = "supports", x = 100, y = 225, count = 1 },
        { key = "self_modifiers", x = 300, y = 225, count = 2 },
        { key = "support_modifiers", x = 300, y = 75, count = 2 },
    }
    local row_base = { high_weapons = 4, low_weapons = 8, supports = 12, self_modifiers = 14, support_modifiers = 17 }
    local slot_w, slot_h, gap = 145, 105, 18
    for _, group in ipairs(groups) do
        for index = 1, group.count do
            local left = group.x + (index - 1) * (slot_w + gap)
            if x >= left and x <= left + slot_w and y >= group.y and y <= group.y + slot_h then
                local row = row_base[group.key] + index - 1
                if row <= (row_count or row) then return row end
            end
        end
    end
    if x >= 850 and x <= self.width - 80 and y >= 90 and y <= 360 then
        local col = x < 1035 and 0 or 1
        local line = math.floor((360 - y) / 78)
        local row = 20 + line * 2 + col
        if row <= (row_count or row) then return row end
    end
    if x >= 70 and x <= 300 and y >= 38 and y <= 86 then return 1 end
    return nil
end

function MapRenderer:render_preparation_legacy(session, cursor, message, mouse_x, mouse_y, mouse_down, edit_only)
    local lstg = self.lstg
    local player = session:get_player(session.local_player_id or 1) or session:get_player(1)
    local loadout = player and player.loadout
    local registry = session.equipment_registry
    local rows = { { label = player and (player.map_ready and "取消 Ready" or "Ready") or "Ready", kind = "action" } }
    if edit_only then rows[1].label = "Save" end
    local groups = {
        { key = "high_weapons", label = "HIGH" },
        { key = "low_weapons", label = "LOW" },
        { key = "supports", label = "SUPPORT" },
        { key = "self_modifiers", label = "SELF MODIFIER" },
        { key = "support_modifiers", label = "SUPPORT MODIFIER" },
    }
    if loadout then
        local relic = Phase1Catalog.relics[loadout.character_relic]
        rows[#rows + 1] = { label = "RELIC  " .. tostring(relic and relic.display_name or loadout.character_relic or "--"), kind = "relic" }
        for _, group in ipairs(groups) do
            rows[#rows + 1] = { label = "-- " .. group.label .. " --", kind = "header" }
            for index, instance in ipairs(loadout[group.key]) do
                local definition = instance and registry and registry:get(instance.definition_id)
                local name = instance and (definition and definition.display_name or instance.definition_id) or "Empty"
                local identity = instance and (" [" .. instance.instance_id .. "]") or ""
                rows[#rows + 1] = { label = string.format("%d  %s%s", index, name, identity), kind = "equipped", group = group.key, index = index, instance = instance, definition = definition }
            end
        end
        rows[#rows + 1] = { label = string.format("-- INVENTORY %d/%d --", loadout.inventory:count(), loadout.inventory.capacity), kind = "header" }
        for index, instance in ipairs(loadout.inventory.items) do
            local definition = registry and registry:get(instance.definition_id)
            rows[#rows + 1] = { label = string.format("%d  %s [%s]", index, definition and definition.display_name or instance.definition_id, instance.instance_id), kind = "inventory", index = index, instance = instance, definition = definition }
        end
    end
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, { 255, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
    self:draw_panel(70, self.width * 0.68, 70, self.height - 90)
    self:draw_panel(self.width * 0.7, self.width - 70, 70, self.height - 90)
    self:draw_text("地图整备", 98, self.height - 130, 1.4, COLORS.accent, 0)
    local capacity = player and player.current_capacity or 0
    local weight = loadout and loadout:get_total_weight(registry) or 0
    self:draw_text(string.format("Capacity %d    Weight %.1f", capacity, weight), 100, self.height - 165, 0.75, COLORS.muted, 0)
    local max_rows = math.max(1, math.floor((self.height - 245) / 38))
    local first, last = self:list_window(cursor or 1, #rows, max_rows)
    for index = first, last do
        local row = rows[index]
        local y = self.height - 205 - (index - first) * 38
        local selected = index == (cursor or 1)
        if row.kind ~= "header" then
            draw_rect(lstg, self.white, selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 }, 92, self.width * 0.65, y - 13, y + 19)
            self:draw_text(selected and ">" or "", 106, y + 2, 0.7, COLORS.accent, 1 + 4)
        end
        self:draw_text(row.label, row.kind == "header" and 105 or 132, y + 2, row.kind == "header" and 0.72 or 0.68, row.kind == "header" and COLORS.accent or (selected and COLORS.text or COLORS.muted), 0)
    end
    self:draw_scrollbar(92, self.width * 0.65, 88, self.height - 188, #rows, max_rows, cursor or 1, mouse_x, mouse_y, mouse_down)
    local selected_row = rows[cursor or 1]
    if selected_row and selected_row.instance then
        local definition = selected_row.definition or (registry and registry:get(selected_row.instance.definition_id))
        local equipment_type = definition and definition.equipment_type or selected_row.instance.equipment_type or "UNKNOWN"
        local legal_slots = "--"
        if equipment_type == "WEAPON" then
            local allowed = definition and definition.allowed_slots
            if allowed then
                local names = {}
                if allowed.HIGH_WEAPON then names[#names + 1] = "HIGH" end
                if allowed.LOW_WEAPON then names[#names + 1] = "LOW" end
                legal_slots = table.concat(names, "/")
            else
                legal_slots = "HIGH/LOW"
            end
        elseif equipment_type == "SUPPORT" then legal_slots = "SUPPORT"
        elseif equipment_type == "SELF_MODIFIER" then legal_slots = "SELF MODIFIER"
        elseif equipment_type == "SUPPORT_MODIFIER" then legal_slots = "SUPPORT MODIFIER"
        elseif equipment_type == "RELIC" then legal_slots = "FIXED RELIC"
        end
        self:draw_text("SELECTED ITEM", self.width * 0.73, self.height - 350, 0.82, COLORS.accent, 0)
        self:draw_text("Name: " .. tostring(definition and definition.display_name or selected_row.instance.definition_id), self.width * 0.73, self.height - 382, 0.68, COLORS.text, 0)
        self:draw_text("Type: " .. tostring(equipment_type) .. "   Weight: " .. tostring(definition and definition.weight or selected_row.instance.weight or 0), self.width * 0.73, self.height - 412, 0.64, COLORS.muted, 0)
        self:draw_text("Legal slots: " .. legal_slots, self.width * 0.73, self.height - 442, 0.64, COLORS.muted, 0)
        self:draw_text("Definition: " .. tostring(selected_row.instance.definition_id), self.width * 0.73, self.height - 472, 0.58, COLORS.muted, 0)
        self:draw_text("Instance: " .. tostring(selected_row.instance.instance_id), self.width * 0.73, self.height - 500, 0.58, COLORS.muted, 0)
    end
    if player then
        self:draw_text("装备操作", self.width * 0.73, self.height - 145, 1.0, COLORS.text, 0)
        if edit_only then
            self:draw_text("Save saves equipment and returns to map", self.width * 0.73, self.height - 295, 0.65, COLORS.muted, 0)
        end
        self:draw_text("选中仓库物品后确认：自动放入第一个合法槽位", self.width * 0.73, self.height - 190, 0.65, COLORS.muted, 0)
        self:draw_text("选中已装备物品后确认：卸下到仓库", self.width * 0.73, self.height - 225, 0.65, COLORS.muted, 0)
        self:draw_text("Backspace：丢弃选中的仓库物品", self.width * 0.73, self.height - 260, 0.65, COLORS.muted, 0)
        self:draw_text("Ready 后配装锁定；Tab/Esc 返回地图", self.width * 0.73, self.height - 295, 0.65, COLORS.muted, 0)
        if session.preparation and session.preparation:has_pending() then
            self:draw_text("等待处理的新装备：请接受或放弃", self.width * 0.73, self.height - 350, 0.75, { 255, 255, 120, 100 }, 0)
        end
    end
    self:draw_text(message or "方向键选择   Enter 操作/Ready   Tab/Esc 返回地图", self.width * 0.5, 58, 0.72, COLORS.muted, 1 + 4)
    lstg.EndScene()
    return #rows
end

function MapRenderer:render_preparation(session, cursor, message, mouse_x, mouse_y, mouse_down, edit_only)
    local lstg = self.lstg
    local player = session:get_player(session.local_player_id or 1) or session:get_player(1)
    local loadout = player and player.loadout
    local registry = session.equipment_registry
    local rows = { { kind = "action" } }
    if edit_only then rows[1].label = "Save" end
    local row_refs = {}
    local groups = {
        { key = "high_weapons", label = "HIGH-SPEED WEAPONS", x = 100, y = 525, count = 3 },
        { key = "low_weapons", label = "LOW-SPEED WEAPONS", x = 100, y = 375, count = 3 },
        { key = "supports", label = "SUPPORT", x = 100, y = 225, count = 1 },
        { key = "self_modifiers", label = "SELF BUFFS", x = 300, y = 225, count = 2 },
        { key = "support_modifiers", label = "SUPPORT BUFFS", x = 300, y = 75, count = 2 },
    }
    if loadout then
        rows[#rows + 1] = { kind = "relic" }
        for _, group in ipairs(groups) do
            rows[#rows + 1] = { kind = "header" }
            row_refs[group.key] = {}
            for index, instance in ipairs(loadout[group.key] or {}) do
                rows[#rows + 1] = { kind = "equipped", group = group.key, index = index, instance = instance,
                    definition = instance and registry and registry:get(instance.definition_id) }
                row_refs[group.key][index] = #rows
            end
        end
        rows[#rows + 1] = { kind = "header" }
        for index, instance in ipairs(loadout.inventory and loadout.inventory.items or {}) do
            rows[#rows + 1] = { kind = "inventory", index = index, instance = instance,
                definition = registry and registry:get(instance.definition_id) }
        end
    end
    local function name_of(instance)
        if not instance or instance == false then return "EMPTY" end
        local definition = registry and registry:get(instance.definition_id)
        return tostring(definition and (definition.display_name_zh or definition.display_name or definition.name) or instance.definition_id)
    end
    local function selected(group, index)
        return row_refs[group] and row_refs[group][index] == (cursor or 1)
    end
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, { 255, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
    self:draw_panel(62, 810, 48, self.height - 82)
    self:draw_panel(828, self.width - 62, 48, self.height - 82)
    self:draw_text("EQUIPMENT LOADOUT", 88, self.height - 116, 1.18, COLORS.accent, 0)
    self:draw_text(string.format("Capacity %d   Weight %.1f", player and player.current_capacity or 0,
        loadout and loadout:get_total_weight(registry) or 0), 88, self.height - 148, 0.68, COLORS.muted, 0)
    local slot_w, slot_h, gap = 145, 105, 18
    for _, group in ipairs(groups) do
        self:draw_text(group.label, group.x, group.y + slot_h + 13, 0.64, COLORS.muted, 0)
        for index = 1, group.count do
            local left = group.x + (index - 1) * (slot_w + gap)
            local instance = loadout and loadout[group.key] and loadout[group.key][index]
            local active = instance and instance ~= false
            draw_rect(lstg, self.white, selected(group.key, index) and { 255, 95, 80, 78 } or { 205, 31, 40, 42 },
                left, left + slot_w, group.y, group.y + slot_h)
            draw_rect(lstg, self.white, active and { 220, 78, 88, 82 } or { 150, 80, 90, 45 },
                left + 4, left + slot_w - 4, group.y + 4, group.y + slot_h - 4)
            self:draw_text(tostring(index), left + 9, group.y + slot_h - 17, 0.58, COLORS.accent, 0)
            self:draw_text(name_of(instance), left + slot_w * 0.5, group.y + slot_h * 0.5, 0.58,
                active and COLORS.text or COLORS.muted, 1 + 4)
        end
    end
    draw_rect(lstg, self.white, (cursor or 1) == 1 and { 255, 95, 80, 78 } or { 205, 31, 40, 55 }, 70, 300, 53, 86)
    self:draw_text(edit_only and "SAVE" or (player and player.map_ready and "CANCEL READY" or "READY"), 185, 69, 0.72, COLORS.text, 1 + 4)
    self:draw_text("INVENTORY", 850, 395, 0.82, COLORS.accent, 0)
    self:draw_text(string.format("%d/%d", loadout and loadout.inventory:count() or 0, loadout and loadout.inventory.capacity or 0), self.width - 88, 395, 0.62, COLORS.muted, 2)
    for index, instance in ipairs(loadout and loadout.inventory.items or {}) do
        local col, line = (index - 1) % 2, math.floor((index - 1) / 2)
        local left, bottom = 850 + col * 190, 335 - line * 78
        local row = rows[cursor or 1]
        local active = row and row.kind == "inventory" and row.index == index
        draw_rect(lstg, self.white, active and { 255, 95, 80, 76 } or { 205, 31, 40, 42 }, left, left + 175, bottom, bottom + 62)
        self:draw_text(string.format("%d  %s", index, name_of(instance)), left + 8, bottom + 31, 0.58,
            active and COLORS.text or COLORS.muted, 0)
    end
    local row = rows[cursor or 1]
    self:draw_text("SELECTED ITEM", 850, 650, 0.82, COLORS.accent, 0)
    if row and row.instance and row.instance ~= false then
        local definition = row.definition or (registry and registry:get(row.instance.definition_id))
        self:draw_text("Name: " .. name_of(row.instance), 850, 612, 0.68, COLORS.text, 0)
        self:draw_text("Type: " .. tostring(definition and definition.equipment_type or "EQUIPMENT"), 850, 582, 0.64, COLORS.muted, 0)
        self:draw_text("Weight: " .. tostring(definition and definition.weight or row.instance.weight or 0), 850, 554, 0.64, COLORS.muted, 0)
        self:draw_text("ID: " .. tostring(row.instance.definition_id), 850, 526, 0.58, COLORS.muted, 0)
    elseif row and row.kind == "equipped" then
        self:draw_text("Empty slot: " .. tostring(row.group) .. " / " .. tostring(row.index), 850, 612, 0.66, COLORS.muted, 0)
    else
        self:draw_text("Move the cursor to inspect an item", 850, 612, 0.66, COLORS.muted, 0)
    end
    self:draw_text(edit_only and "Enter saves and returns to map" or "Enter equips/unequips   Backspace discards", 850, 84, 0.60, COLORS.muted, 0)
    self:draw_text(message or "Arrow keys select   Enter confirm   Tab/Esc return", self.width * 0.5, 58, 0.68, COLORS.muted, 1 + 4)
    lstg.EndScene()
    return #rows
end

function MapRenderer:menu_hit_test(x, y)
    if not x or not y then
        return nil
    end
    if x < 90 or x > 470 then return nil end
    for index = 1, 8 do
        local bottom = 466 - (index - 1) * 52
        if y >= bottom and y <= bottom + 42 then return index end
    end
    return nil
end

function MapRenderer:network_menu_hit_test(x, y, item_count)
    if not x or not y or x < 330 or x > self.width - 330 then return nil end
    local field_count = math.max(1, (item_count or 2) - 1)
    for index = 1, field_count do
        local top = 450 - (index - 1) * 90
        if y >= top - 58 and y <= top then return index end
    end
    local action_top = 450 - field_count * 90
    if y >= action_top - 58 and y <= action_top then return field_count + 1 end
    return nil
end

function MapRenderer:card_training_hit_test(x, y, count, cursor)
    if not x or not y or x < 100 or x > self.width - 100 then
        return nil
    end
    local page_size = 8
    local first = self:list_window(cursor or 1, count, page_size)
    local top = 580
    local row_height = 58
    local page_index = math.floor((top - y) / row_height)
    local index = first + page_index
    if y <= top and page_index >= 0 and page_index < page_size and index <= (count or #TrainingCatalog) then
        return index
    end
    return nil
end

function MapRenderer:training_failed_hit_test(x, y)
    if not x or not y or x < 470 or x > self.width - 470 then
        return nil
    end
    if y >= 360 and y <= 414 then return 1 end
    if y >= 284 and y <= 338 then return 2 end
    return nil
end

function MapRenderer:battle_failed_hit_test(x, y, option_count)
    if not x or not y or x < 390 or x > self.width - 390 then
        return nil
    end
    option_count = option_count or 2
    local top = 360
    for index = 1, option_count do
        local bottom = top - (index - 1) * 68
        if y >= bottom and y <= bottom + 50 then
            return index
        end
    end
    return nil
end

function MapRenderer:render_practice_select(cursor, catalog, title, mouse_x, mouse_y, mouse_down)
    catalog = catalog or TrainingCatalog
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, { 255, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
    self:draw_text(title or "练习", 90, self.height - 115, 1.45, COLORS.accent, 0)
    self:draw_text("选择目标开始练习", 90, self.height - 155, 0.8, COLORS.muted, 0)
    local page_size = 8
    local first, last = self:list_window(cursor or 1, #catalog, page_size)
    for index = first, last do
        local card = catalog[index]
        local page_index = index - first + 1
        local top = 580 - (page_index - 1) * 58
        local bottom = top - 46
        local selected = index == (cursor or 1)
        draw_rect(lstg, self.white, selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 }, 100, self.width - 100, bottom, top)
        draw_line(lstg, self.white, selected and COLORS.accent or COLORS.panel_border, 100, bottom, self.width - 100, bottom, selected and 3 or 1)
        self:draw_text(selected and ">" or "", 124, bottom + 23, 0.8, COLORS.accent, 1 + 4)
        self:draw_text(card.display_name, 155, bottom + 23, 0.9, selected and COLORS.text or COLORS.muted, 0)
        local detail
        if card.difficulty then
            local duration = card.duration_seconds and string.format("%.1fs", card.duration_seconds) or "--"
            detail = string.format("Lv.%d   %s   %s", card.difficulty, duration, card.legacy_stage or "")
        elseif card.hp then
            detail = card.duration_seconds and string.format("HP %d   %ds", card.hp, card.duration_seconds) or string.format("HP %d", card.hp)
        else
            detail = "--"
        end
        self:draw_text(detail, self.width - 125, bottom + 23, 0.7, COLORS.muted, 2)
    end
    self:draw_scrollbar(100, self.width - 100, 105, 610, #catalog, page_size, cursor or 1, mouse_x, mouse_y, mouse_down)
    self:draw_text(string.format("%d / %d", cursor or 1, #catalog), self.width - 110, self.height - 115, 0.75, COLORS.muted, 2)
    self:draw_text("方向键选择   Enter 确认   Esc 返回", self.width * 0.5, 64, 0.75, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

function MapRenderer:render_card_select(cursor, catalog, title)
    self:render_practice_select(cursor, catalog, title or "符卡训练")
end

function MapRenderer:render_training_failed(card_id, cursor, catalog, title, display_name)
    local lstg = self.lstg
    local card
    for _, candidate in ipairs(catalog or TrainingCatalog) do
        if candidate.id == card_id then card = candidate break end
    end
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, { 255, 12, 15, 29 }, 300, self.width - 300, 170, self.height - 170)
    self:draw_text((title or "练习") .. "结束", self.width * 0.5, self.height - 230, 1.5, COLORS.text, 1 + 4)
    self:draw_text(display_name or (card and card.display_name) or "当前目标", self.width * 0.5, self.height - 280, 0.9, COLORS.accent, 1 + 4)
    local options = { "重新开始本张卡", "返回主界面" }
    for index, label in ipairs(options) do
        local bottom = 360 - (index - 1) * 76
        local selected = index == (cursor or 1)
        draw_rect(lstg, self.white, selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 }, 470, self.width - 470, bottom, bottom + 54)
        self:draw_text(selected and ">" or "", 500, bottom + 27, 0.8, COLORS.accent, 1 + 4)
        self:draw_text(label, self.width * 0.5, bottom + 27, 0.95, selected and COLORS.text or COLORS.muted, 1 + 4)
    end
    self:draw_text("方向键选择   Enter 确认   Esc 返回主界面", self.width * 0.5, 64, 0.75, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

function MapRenderer:render_battle_failed(session, cursor)
    local lstg = self.lstg
    local multiplayer = (session.player_count or 1) > 1
    local options = { "重试本关" }
    if multiplayer then
        options[#options + 1] = "重新开始联机游玩"
    end
    options[#options + 1] = "返回主菜单"
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, { 255, 12, 15, 29 }, 280, self.width - 280, 145, self.height - 145)
    self:draw_text("战斗失败", self.width * 0.5, self.height - 210, 1.5, COLORS.text, 1 + 4)
    self:draw_text(multiplayer and "P1/P2 请选择相同的处理方式" or "请选择下一步操作", self.width * 0.5, self.height - 255, 0.85, COLORS.muted, 1 + 4)
    for index, label in ipairs(options) do
        local bottom = 360 - (index - 1) * 68
        local selected = index == (cursor or 1)
        draw_rect(lstg, self.white, selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 }, 390, self.width - 390, bottom, bottom + 50)
        self:draw_text(selected and ">" or "", 420, bottom + 25, 0.8, COLORS.accent, 1 + 4)
        self:draw_text(label, self.width * 0.5, bottom + 25, 0.92, selected and COLORS.text or COLORS.muted, 1 + 4)
    end
    self:draw_text("方向键选择   Enter 确认   Esc 返回主菜单", self.width * 0.5, 64, 0.75, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

function MapRenderer:render_menu(menu_cursor, session)
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)

    draw_rect(lstg, self.white, { 255, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
    self:draw_panel(70, 515, 80, self.height - 116)
    self:draw_text("TouHouNightReign", 105, self.height - 164, 1.45, COLORS.accent, 0)
    self:draw_text("幻想乡夜行录", 108, self.height - 220, 0.92, COLORS.text, 0)
    self:draw_text("探索地图 · 战斗 · 奖励", 108, self.height - 251, 0.72, COLORS.muted, 0)

    local options = { "单人游戏", "局域网主机", "加入局域网", "符卡训练", "非符练习", "小怪练习", "音乐鉴赏", "退出游戏" }
    for index, label in ipairs(options) do
        local bottom = 466 - (index - 1) * 52
        local top = bottom + 42
        local selected = index == (menu_cursor or 1)
        local fill = selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 }
        draw_rect(lstg, self.white, fill, 90, 470, bottom, top)
        draw_line(lstg, self.white, selected and COLORS.accent or COLORS.panel_border, 90, bottom, 470, bottom, selected and 3 or 1)
        draw_line(lstg, self.white, selected and COLORS.accent or COLORS.panel_border, 90, top, 470, top, selected and 3 or 1)
        self:draw_text(selected and ">" or "", 116, bottom + 20, 0.72, COLORS.accent, 1 + 4)
        self:draw_text(label, 150, bottom + 20, 0.82, selected and COLORS.text or COLORS.muted, 0)
    end

    self:draw_panel(self.width - 420, self.width - 90, 170, self.height - 150)
    self:draw_text("RUN PREVIEW", self.width - 385, self.height - 205, 0.95, COLORS.accent, 0)
    self:draw_text("地图路线", self.width - 385, self.height - 260, 1.0, COLORS.text, 0)
    self:draw_text("战斗节点     事件节点", self.width - 385, self.height - 294, 0.85, COLORS.muted, 0)
    self:draw_text("鼠标可选择菜单与地图节点", self.width - 385, self.height - 360, 0.85, COLORS.muted, 0)
    self:draw_text("方向键移动   Enter 确认", self.width - 385, 212, 0.76, COLORS.muted, 0)
    lstg.EndScene()
end

function MapRenderer:render_music_player(cursor, catalog)
    local lstg = self.lstg
    catalog = catalog or {}
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, { 255, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
    self:draw_panel(120, self.width - 120, 105, self.height - 90)
    self:draw_text("音乐鉴赏", self.width * 0.5, self.height - 125, 1.45, COLORS.accent, 1 + 4)
    self:draw_text("原版关卡 BGM · Enter 播放 · Esc 返回主界面", self.width * 0.5, self.height - 165, 0.78, COLORS.muted, 1 + 4)
    local visible = 10
    local state = ScrollState.new(#catalog, visible, cursor or 1)
    local first = state:first_visible()
    local last = math.min(#catalog, first + visible - 1)
    for index = first, last do
        local entry = catalog[index]
        local row = index - first
        local bottom = self.height - 225 - row * 42
        local selected = index == (cursor or 1)
        draw_rect(lstg, self.white, selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 }, 190, self.width - 190, bottom, bottom + 32)
        self:draw_text(selected and ">" or "", 212, bottom + 16, 0.72, COLORS.accent, 1 + 4)
        self:draw_text(string.format("%02d", index), 244, bottom + 16, 0.68, COLORS.muted, 1 + 4)
        self:draw_text(entry.title or entry.key, 280, bottom + 16, 0.82, selected and COLORS.text or COLORS.muted, 0)
        self:draw_text(entry.key, self.width - 220, bottom + 16, 0.62, COLORS.muted, 2)
    end
    self:draw_text(string.format("%d / %d", cursor or 1, #catalog), self.width * 0.5, 72, 0.75, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

function MapRenderer:render_network_menu(menu)
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, { 255, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
    self:draw_panel(290, self.width - 290, 130, self.height - 120)
    local title = menu.mode == "host" and "开设局域网服务器" or "加入局域网服务器"
    local subtitle = menu.mode == "host" and "设置监听端口，等待另一位玩家加入" or "支持 localhost 或局域网 IPv4 地址"
    self:draw_text(title, self.width * 0.5, self.height - 175, 1.35, COLORS.accent, 1 + 4)
    self:draw_text(subtitle, self.width * 0.5, self.height - 215, 0.76, COLORS.muted, 1 + 4)

    local fields = menu:get_fields()
    for index, field in ipairs(fields) do
        local top = 450 - (index - 1) * 90
        local bottom = top - 58
        local selected = menu.cursor == index
        draw_rect(lstg, self.white, selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 }, 330, self.width - 330, bottom, top)
        draw_line(lstg, self.white, selected and COLORS.accent or COLORS.panel_border, 330, bottom, self.width - 330, bottom, selected and 3 or 1)
        self:draw_text(field.label, 360, top + 22, 0.72, COLORS.muted, 0)
        local value = field.value ~= "" and field.value or field.placeholder
        if selected and field.value ~= "" then value = value .. "_" end
        self:draw_text(value, 370, bottom + 27, 0.95, field.value ~= "" and COLORS.text or COLORS.muted, 0)
    end

    local action_index = #fields + 1
    local action_top = 450 - #fields * 90
    local action_bottom = action_top - 58
    local action_selected = menu.cursor == action_index
    draw_rect(lstg, self.white, action_selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 }, 430, self.width - 430, action_bottom, action_top)
    self:draw_text(menu:get_action_label(), self.width * 0.5, action_bottom + 28, 0.95, action_selected and COLORS.text or COLORS.muted, 1 + 4)
    if menu.status then
        self:draw_text(menu.status, self.width * 0.5, 155, 0.72, menu.status_is_error and { 255, 255, 105, 105 } or COLORS.accent, 1 + 4)
    end
    self:draw_text("输入内容   ↑↓/Tab 切换   Enter 确认   Esc 返回", self.width * 0.5, 82, 0.72, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

function MapRenderer:render(view, session, menu_cursor, training_cursor, training_card_id, training_catalog, training_title, training_display_name, network_menu, preparation_cursor, preparation_message, shop_cursor, relic_cursor, reward_cursor, mouse_x, mouse_y, mouse_down, preparation_edit_only, music_cursor, music_catalog)
    if not self.lstg then
        return
    end
    self:init()
    if session.run_state == Constants.run_states.MENU then
        if network_menu and network_menu:is_open() then
            self:render_network_menu(network_menu)
        else
            self:render_menu(menu_cursor, session)
        end
        return
    end
    if session.run_state == Constants.run_states.MUSIC_PLAYER then
        self:render_music_player(music_cursor, music_catalog)
        return
    end
    if session.run_state == Constants.run_states.CARD_SELECT or session.run_state == Constants.run_states.NON_SPELL_SELECT or session.run_state == Constants.run_states.ENEMY_SELECT then
        self:render_practice_select(training_cursor, training_catalog, training_title, mouse_x, mouse_y, mouse_down)
        return
    end
    if session.run_state == Constants.run_states.CARD_TRAINING_FAILED then
        self:render_training_failed(training_card_id, training_cursor, training_catalog, training_title, training_display_name)
        return
    end
    if session.run_state == Constants.run_states.RUN_FAILED then
        self:render_battle_failed(session, training_cursor)
        return
    end
    if session.run_state == Constants.run_states.MAP then
        self:render_map(view, session, mouse_x, mouse_y)
        return
    end
    if session.run_state == Constants.run_states.MAP_PREPARATION then
        self:render_preparation(session, preparation_cursor, preparation_message, mouse_x, mouse_y, mouse_down, preparation_edit_only)
        return
    end
    if session.run_state == Constants.run_states.SHOP then
        self:render_shop(session, shop_cursor or 1, mouse_x, mouse_y, mouse_down)
        return
    end
    if session.run_state == Constants.run_states.RELIC_SELECT then
        self:render_relic_select(session, relic_cursor or 1, mouse_x, mouse_y, mouse_down)
        return
    end
    if session.run_state == Constants.run_states.REWARD then
        self:render_reward(session, reward_cursor or 1, mouse_x, mouse_y, mouse_down)
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

local function shop_geometry(width, height)
    local list_left = 85
    local list_right = width - 85
    local gap = 12
    local card_width = (list_right - list_left - gap * 4) / 5
    local detail_top = math.max(190, height - 350)
    local card_bottom = detail_top + 20
    return {
        list_left = list_left,
        list_right = list_right,
        gap = gap,
        card_width = card_width,
        card_bottom = card_bottom,
        card_top = card_bottom + 120,
        detail_left = list_left,
        detail_right = list_right,
        detail_bottom = 105,
        detail_top = detail_top,
        ready_bottom = 55,
        ready_top = 90,
    }
end

function MapRenderer:render_shop(session, cursor, mouse_x, mouse_y, mouse_down)
    local lstg = self.lstg
    lstg.BeginScene(); lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height); lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_panel(55, self.width - 55, 55, self.height - 70)
    self:draw_text("SHOP", self.width * 0.5, self.height - 110, 2.0, COLORS.accent, 1 + 4)
    local offers = session.shop_service and session.shop_service:get_offers() or {}
    local item_count = #offers
    local local_player = session:get_player(session.local_player_id or 1)
    self:draw_text(string.format("MONEY %dG", local_player and local_player.money or 0),
        self.width - 120, self.height - 110, 0.78, COLORS.active_line, 1 + 4)
    local geometry = shop_geometry(self.width, self.height)
    local purchases = session.shop_service and session.shop_service.purchases
        and session.shop_service.purchases[session.local_player_id or 1] or {}
    for index = 1, item_count do
        local offer = offers[index]
        local x1 = geometry.list_left + (index - 1) * (geometry.card_width + geometry.gap)
        local x2 = x1 + geometry.card_width
        local selected = index == cursor
        local purchased = purchases[index] == true
        local fill = purchased and { 180, 45, 55, 150 } or (selected and COLORS.accent or COLORS.map_panel)
        draw_rect(lstg, self.white, fill, x1, x2, geometry.card_bottom, geometry.card_top)
        if not purchased then
            local offered_definition = offer and offer.kind == "EQUIPMENT"
                and session.equipment_registry:get(offer.definition_id) or nil
            local label = offer and offer.kind == "EQUIPMENT"
                and tostring(offered_definition and (offered_definition.display_name_zh or offered_definition.display_name) or offer.definition_id)
                or (offer and offer.kind == "LIFE" and "Team Life"
                    or (offer and offer.kind == "LIFE_FRAGMENT" and "Life Fragment" or "Bomb"))
            self:draw_text(string.format("%d", index), x1 + 16, geometry.card_top - 22, 0.7, COLORS.muted, 0)
            self:draw_text(label, (x1 + x2) * 0.5, geometry.card_top - 58, 0.72, COLORS.text, 1 + 4)
            self:draw_text(string.format("%dG", offer and offer.price or 0), (x1 + x2) * 0.5,
                geometry.card_bottom + 24, 0.7, COLORS.active_line, 1 + 4)
        end
    end

    local ready_selected = cursor == item_count + 1
    draw_rect(lstg, self.white, ready_selected and COLORS.accent or COLORS.map_panel,
        geometry.list_left, geometry.list_right, geometry.ready_bottom, geometry.ready_top)
    self:draw_text("READY / LEAVE SHOP", self.width * 0.5, (geometry.ready_bottom + geometry.ready_top) * 0.5,
        0.8, COLORS.text, 1 + 4)

    self:draw_panel(geometry.detail_left, geometry.detail_right, geometry.detail_bottom, geometry.detail_top)
    self:draw_text("ITEM INFO", geometry.detail_left + 20, geometry.detail_top - 28, 0.95, COLORS.accent, 0)
    local selected_offer = offers[cursor]
    local detail_lines = {}
    if cursor == item_count + 1 then
        detail_lines = { "Ready / Leave Shop", "All purchases are local to this player.", "Press Enter to continue." }
    elseif selected_offer then
        if purchases[cursor] then
            detail_lines = { "SOLD", "Already purchased by this player." }
        elseif selected_offer.kind == "EQUIPMENT" then
            local definition = session.equipment_registry:get(selected_offer.definition_id)
            detail_lines[#detail_lines + 1] = tostring(definition and (definition.display_name_zh or definition.display_name) or selected_offer.definition_id)
            detail_lines[#detail_lines + 1] = "Type: " .. tostring(definition and definition.equipment_type or "EQUIPMENT")
            detail_lines[#detail_lines + 1] = "Rarity: " .. tostring(definition and definition.rarity or "COMMON")
            if definition and definition.damage then detail_lines[#detail_lines + 1] = "Damage: " .. tostring(definition.damage) end
            if definition and definition.entity_count then detail_lines[#detail_lines + 1] = "Units: " .. tostring(definition.entity_count) end
            detail_lines[#detail_lines + 1] = "Price: " .. tostring(selected_offer.price or 0) .. "G"
        elseif selected_offer.kind == "LIFE" then
            detail_lines = { "Team Life", "Adds 1 team life.", "Price: " .. tostring(selected_offer.price or 0) .. "G" }
        elseif selected_offer.kind == "BOMB" then
            detail_lines = { "Bomb", "Adds " .. tostring(selected_offer.amount or 1) .. " bomb(s) to this player.", "Price: " .. tostring(selected_offer.price or 0) .. "G" }
        else
            detail_lines = { tostring(selected_offer.kind), "Price: " .. tostring(selected_offer.price or 0) .. "G" }
        end
        local selected_price = tonumber(selected_offer.price) or 0
        if local_player and local_player.money < selected_price then
            detail_lines[#detail_lines + 1] = "INSUFFICIENT MONEY"
        end
    else
        detail_lines = { "Move the cursor over an item", "to inspect its information." }
    end
    for index, line in ipairs(detail_lines) do
        self:draw_text(line, geometry.detail_left + 20, geometry.detail_top - 68 - (index - 1) * 28, 0.7, COLORS.text, 0)
    end
    self:draw_text("Left/Right select   Enter buy/ready   Esc return", self.width * 0.5, 25, 0.75, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

function MapRenderer:render_relic_select(session, cursor)
    local lstg = self.lstg
    lstg.BeginScene(); lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height); lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_panel(250, self.width - 250, 115, self.height - 115)
    self:draw_text("BOSS RELIC", self.width * 0.5, self.height - 165, 2.1, COLORS.accent, 1 + 4)
    local player_id = session.local_player_id or 1
    local choices = session.relic_choices[player_id] or {}
    local visible = 5
    local first, last = self:list_window(cursor or 1, #choices, visible)
    for index = first, last do
        local relic_id = choices[index]
        local y = self.height - 255 - (index - first) * 100
        local selected = index == cursor
        draw_rect(lstg, self.white, selected and COLORS.accent or COLORS.map_panel, 330, self.width - 330, y - 30, y + 30)
        self:draw_text(string.format("%d. %s", index, tostring(relic_id)), 370, y, 1.15, COLORS.text, 0)
    end
    self:draw_scrollbar(330, self.width - 330, 145, self.height - 220, #choices, visible, cursor or 1)
    self:draw_text("Choose one relic", self.width * 0.5, 70, 0.85, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

local function reward_label(session, choice)
    if not choice then return "Unknown reward" end
    if choice.kind == "RESOURCE" then return choice.resource == "life" and "1 Team Life" or "1 Bomb" end
    local definition = session.equipment_registry and session.equipment_registry:get(choice.definition_id)
    return definition and (definition.display_name_zh or definition.display_name) or tostring(choice.definition_id or "Unknown equipment")
end

local function reward_geometry(width, height)
    local cards_left = 90
    local cards_right = width * 0.61
    local gap = 16
    local card_width = (cards_right - cards_left - gap * 2) / 3
    return {
        cards_left = cards_left,
        card_width = card_width,
        gap = gap,
        card_bottom = 245,
        card_top = 475,
        detail_left = width * 0.65,
        detail_right = width - 105,
        detail_bottom = 245,
        detail_top = 475,
    }
end

function MapRenderer:render_reward(session, cursor, mouse_x, mouse_y, mouse_down)
    local lstg = self.lstg
    lstg.BeginScene(); lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height); lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_panel(55, self.width - 55, 95, self.height - 70)
    local player_id = session.local_player_id or 1
    local choices = session.reward_choices or {}
    local claims = session.reward_claims and session.reward_claims[player_id] or {}
    local required = session.reward_required or 1
    self:draw_text("REWARDS", self.width * 0.5, self.height - 155, 2.2, COLORS.accent, 1 + 4)
    self:draw_text(string.format("Choose %d   Selected %d", required, #claims), self.width * 0.5, self.height - 200, 1.0, COLORS.muted, 1 + 4)
    if session.reward_guaranteed_definition_id then
        local guaranteed = session.equipment_registry:get(session.reward_guaranteed_definition_id)
        self:draw_text("Guaranteed: " .. tostring(guaranteed and (guaranteed.display_name_zh or guaranteed.display_name) or session.reward_guaranteed_definition_id), self.width * 0.5, self.height - 235, 0.9, COLORS.active_line, 1 + 4)
    end
    local geometry = reward_geometry(self.width, self.height)
    for index = 1, 3 do
        local x1 = geometry.cards_left + (index - 1) * (geometry.card_width + geometry.gap)
        local x2 = x1 + geometry.card_width
        local selected = index == (cursor or 1)
        local claimed = false
        for _, claim in ipairs(claims) do if claim.choice_index == index then claimed = true break end end
        draw_rect(lstg, self.white, claimed and { 255, 95, 180, 125 } or (selected and COLORS.accent or COLORS.map_panel),
            x1, x2, geometry.card_bottom, geometry.card_top)
        local choice = choices[index]
        self:draw_text(string.format("%d. %s", index, choice and choice.kind or "-"), (x1 + x2) * 0.5, 435, 0.85, COLORS.text, 1 + 4)
        self:draw_text(reward_label(session, choice), (x1 + x2) * 0.5, 355, 0.8, COLORS.text, 1 + 4)
        if claimed then self:draw_text("SELECTED", (x1 + x2) * 0.5, 280, 0.72, COLORS.active_line, 1 + 4) end
    end
    self:draw_panel(geometry.detail_left, geometry.detail_right, geometry.detail_bottom, geometry.detail_top)
    self:draw_text("ITEM INFO", geometry.detail_left + 20, geometry.detail_top - 28, 0.95, COLORS.accent, 0)
    local choice = choices[cursor]
    local info = {}
    if choice and choice.kind == "RESOURCE" then
        info = { choice.resource == "life" and "Team Life" or "Bomb", "Amount: " .. tostring(choice.amount or 1), "No equipment slot required." }
    elseif choice then
        local definition = session.equipment_registry and session.equipment_registry:get(choice.definition_id)
        info[#info + 1] = tostring(definition and (definition.display_name_zh or definition.display_name) or choice.definition_id)
        info[#info + 1] = "Type: " .. tostring(definition and definition.equipment_type or choice.kind)
        info[#info + 1] = "Rarity: " .. tostring(definition and definition.rarity or "COMMON")
        if definition and definition.damage then info[#info + 1] = "Damage: " .. tostring(definition.damage) end
        if definition and definition.entity_count then info[#info + 1] = "Units: " .. tostring(definition.entity_count) end
    else
        info = { "Move the cursor over a reward", "to inspect its information." }
    end
    for index, line in ipairs(info) do
        self:draw_text(line, geometry.detail_left + 20, geometry.detail_top - 68 - (index - 1) * 28, 0.7, COLORS.text, 0)
    end
    self:draw_text("Left/Right select   Enter claim", self.width * 0.5, 145, 0.8, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

function MapRenderer:shop_hit_test(x, y)
    local geometry = shop_geometry(self.width, self.height)
    if not x or not y then return nil end
    if x >= geometry.list_left and x <= geometry.list_right
            and y >= geometry.card_bottom and y <= geometry.card_top then
        local index = math.floor((x - geometry.list_left) / (geometry.card_width + geometry.gap)) + 1
        local local_x = x - (geometry.list_left + (index - 1) * (geometry.card_width + geometry.gap))
        if index >= 1 and index <= 5 and local_x <= geometry.card_width then return index end
    end
    if x >= geometry.list_left and x <= geometry.list_right
            and y >= geometry.ready_bottom and y <= geometry.ready_top then
        return 6
    end
    return nil
end

function MapRenderer:relic_hit_test(session, x, y)
    local choices = session.relic_choices[session.local_player_id or 1] or {}
    local row = math.floor(((self.height - 255) - y) / 100) + 1
    if row >= 1 and row <= #choices then return row end
    return nil
end

function MapRenderer:reward_hit_test(x, y, count)
    local geometry = reward_geometry(self.width, self.height)
    if not x or not y or y < geometry.card_bottom or y > geometry.card_top then return nil end
    for index = 1, math.min(3, count or 3) do
        local x1 = geometry.cards_left + (index - 1) * (geometry.card_width + geometry.gap)
        if x >= x1 and x <= x1 + geometry.card_width then return index end
    end
    return nil
end

return MapRenderer
