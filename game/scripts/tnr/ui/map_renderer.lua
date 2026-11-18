local Constants = require("tnr.core.constants")
local TrainingCatalog = require("tnr.training.card_training_catalog")
local Phase1Catalog = require("tnr.equipment.phase1_catalog")
local ScrollState = require("tnr.ui.scroll_state")
local EquipmentInfo = require("tnr.ui.equipment_info")
local TitleAssets = require("tnr.ui.title_assets")
local WeaponPreview = require("tnr.ui.weapon_preview")

local MapRenderer = {}
MapRenderer.__index = MapRenderer

local MAP_ICON_IMAGES = {
    START = "tnr-map-node-start",
    ENEMY = "tnr-map-node-enemy",
    ELITE = "tnr-map-node-elite",
    BOSS = "tnr-map-node-boss",
    SHOP = "tnr-map-node-shop",
    SHRINE = "tnr-map-node-shrine",
    EVENT = "tnr-map-node-event",
    CURRENT = "tnr-map-node-current",
    UNVISITED = "tnr-map-node-unvisited",
}

local TYPE_META = {
    ELITE = { label = "精英", icon = "ELITE", color = { 255, 231, 177, 91 } },
    START = { label = "起点", icon = "START", color = { 255, 236, 236, 240 } },
    ENEMY = { label = "战斗", icon = "ENEMY", color = { 255, 224, 91, 112 } },
    BOSS = { label = "首领", icon = "BOSS", color = { 255, 245, 174, 105 } },
    SHOP = { label = "商店", icon = "SHOP", color = { 255, 155, 211, 186 } },
    SHRINE = { label = "神社", icon = "SHRINE", color = { 255, 220, 142, 164 } },
    EVENT = { label = "事件", icon = "EVENT", color = { 255, 143, 191, 231 } },
}

local COLORS = {
    background = { 255, 9, 13, 25 },
    map_panel = { 152, 11, 15, 31 },
    panel = { 188, 10, 13, 28 },
    panel_border = { 168, 139, 78, 91 },
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
    radius = math.max(0.8, tonumber(radius) or 1)
    local bands = math.max(1, math.min(10, math.ceil(radius / 2.2)))
    for band = 0, bands - 1 do
        local low = -radius + 2 * radius * band / bands
        local high = -radius + 2 * radius * (band + 1) / bands
        local middle = (low + high) * 0.5
        local half_width = math.max(0.8, radius - math.abs(middle))
        draw_rect(lstg, image, values, x - half_width, x + half_width, y + low, y + high)
    end
end

local function utf8_char_count(text)
    local count = 0
    for _ in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
    end
    return count
end

local function draw_polygon(lstg, image, values, points)
    if not lstg.Render4V or #points < 3 then return end
    lstg.SetImageState(image, "", color(lstg, values))
    local origin = points[1]
    for index = 2, #points - 1 do
        local first, second = points[index], points[index + 1]
        lstg.Render4V(image,
            origin[1], origin[2], 0.5,
            first[1], first[2], 0.5,
            second[1], second[2], 0.5,
            second[1], second[2], 0.5)
    end
end

local function draw_circle(lstg, image, values, x, y, radius, segments)
    radius = math.max(0.5, tonumber(radius) or 1)
    local points = {}
    for index = 0, (segments or 24) - 1 do
        local angle = index * math.pi * 2 / (segments or 24)
        points[#points + 1] = { x + math.cos(angle) * radius, y + math.sin(angle) * radius }
    end
    draw_polygon(lstg, image, values, points)
end

local function draw_ring(lstg, image, values, x, y, inner, outer, segments)
    if not lstg.Render4V then return end
    segments = segments or 32
    lstg.SetImageState(image, "", color(lstg, values))
    for index = 0, segments - 1 do
        local a1, a2 = index * math.pi * 2 / segments, (index + 1) * math.pi * 2 / segments
        local c1, s1, c2, s2 = math.cos(a1), math.sin(a1), math.cos(a2), math.sin(a2)
        lstg.Render4V(image,
            x + c1 * outer, y + s1 * outer, 0.5,
            x + c2 * outer, y + s2 * outer, 0.5,
            x + c2 * inner, y + s2 * inner, 0.5,
            x + c1 * inner, y + s1 * inner, 0.5)
    end
end

local function draw_ellipse(lstg, image, values, x, y, rx, ry, angle)
    local points = {}
    angle = angle or 0
    for index = 0, 15 do
        local theta = index * math.pi * 2 / 16
        local px, py = math.cos(theta) * rx, math.sin(theta) * ry
        points[#points + 1] = {
            x + px * math.cos(angle) - py * math.sin(angle),
            y + px * math.sin(angle) + py * math.cos(angle),
        }
    end
    draw_polygon(lstg, image, values, points)
end

local function draw_medallion(lstg, image, x, y, radius, values, selected)
    draw_circle(lstg, image, { 238, 7, 10, 23 }, x, y, radius)
    draw_ring(lstg, image, values, x, y, radius - 1.8, radius, 32)
    draw_ring(lstg, image, { selected and 170 or 95, 255, 220, 178 }, x, y, radius - 4.2, radius - 3.6, 32)
    -- Tiny four-point ornaments bring the nodes closer to the title page seals.
    for index = 0, 3 do
        local angle = math.pi * 0.25 + index * math.pi * 0.5
        local ox, oy = math.cos(angle) * (radius - 2.1), math.sin(angle) * (radius - 2.1)
        draw_ellipse(lstg, image, { 195, 255, 220, 175 }, x + ox, y + oy, 1.25, 0.65, angle)
    end
end

-- Small, text-free pictograms keep route nodes legible and tie their shapes
-- to shrine, moon and festival motifs from the title illustration.
local function draw_map_glyph(lstg, image, kind, x, y, values, scale)
    scale = tonumber(scale) or 1
    local ink = { 255, 255, 235, 202 }
    local function bar(left, right, bottom, top, color_values)
        draw_rect(lstg, image, color_values or ink, left, right, bottom, top)
    end
    local function stroke(x1, y1, x2, y2, width, color_values)
        local dx, dy = x2 - x1, y2 - y1
        local length = math.sqrt(dx * dx + dy * dy)
        if length <= 0 then return end
        local half = (width or 2) * 0.5
        local nx, ny = -dy / length * half, dx / length * half
        draw_polygon(lstg, image, color_values or ink, {
            { x1 + nx, y1 + ny }, { x2 + nx, y2 + ny },
            { x2 - nx, y2 - ny }, { x1 - nx, y1 - ny },
        })
    end
    local function petal(px, py, radius, angle)
        draw_ellipse(lstg, image, ink, px, py, radius * 0.72, radius * 0.43, angle or 0)
    end

    if kind == "START" then
        -- Lacquered torii gate with a gently crowned lintel.
        stroke(x - 5.6 * scale, y + 3.3 * scale, x + 5.6 * scale, y + 3.3 * scale, 1.55 * scale)
        stroke(x - 5.5 * scale, y + 3.3 * scale, x - 4.3 * scale, y + 4.4 * scale, 1.15 * scale)
        stroke(x + 4.3 * scale, y + 4.4 * scale, x + 5.5 * scale, y + 3.3 * scale, 1.15 * scale)
        stroke(x - 3.5 * scale, y + 1.0 * scale, x + 3.5 * scale, y + 1.0 * scale, 1.2 * scale)
        stroke(x - 2.9 * scale, y - 4.1 * scale, x - 2.9 * scale, y + 2.4 * scale, 1.35 * scale)
        stroke(x + 2.9 * scale, y - 4.1 * scale, x + 2.9 * scale, y + 2.4 * scale, 1.35 * scale)
    elseif kind == "ENEMY" then
        -- Crossed spirit blades, complete with guards and bright pommels.
        stroke(x - 4.7 * scale, y - 4.8 * scale, x + 3.8 * scale, y + 3.7 * scale, 1.45 * scale)
        stroke(x - 3.8 * scale, y + 3.7 * scale, x + 4.7 * scale, y - 4.8 * scale, 1.45 * scale)
        stroke(x - 4.6 * scale, y - 1.5 * scale, x - 1.7 * scale, y - 4.4 * scale, 1.2 * scale)
        stroke(x + 1.7 * scale, y - 4.4 * scale, x + 4.6 * scale, y - 1.5 * scale, 1.2 * scale)
        draw_circle(lstg, image, { 255, 255, 165, 133 }, x, y, 1.25 * scale, 16)
    elseif kind == "ELITE" then
        -- Four-petal imperial seal, centered with a tiny lacquer bead.
        for index = 0, 3 do
            local angle = index * math.pi * 0.5
            petal(x + math.cos(angle) * 3.1 * scale,
                y + math.sin(angle) * 3.1 * scale, 2.8 * scale, angle)
        end
        draw_circle(lstg, image, { 255, 255, 198, 137 }, x, y, 1.45 * scale, 16)
    elseif kind == "BOSS" then
        -- Three-point crown over a crescent-shaped moon.
        stroke(x - 5 * scale, y - 2 * scale, x - 3.3 * scale, y + 4.2 * scale, 1.25 * scale)
        stroke(x - 3.3 * scale, y + 4.2 * scale, x, y + 0.8 * scale, 1.25 * scale)
        stroke(x, y + 0.8 * scale, x + 3.3 * scale, y + 4.2 * scale, 1.25 * scale)
        stroke(x + 3.3 * scale, y + 4.2 * scale, x + 5 * scale, y - 2 * scale, 1.25 * scale)
        stroke(x - 5 * scale, y - 2 * scale, x + 5 * scale, y - 2 * scale, 1.25 * scale)
        draw_ring(lstg, image, { 255, 255, 195, 128 }, x, y - 3.4 * scale, 1.0 * scale, 2.0 * scale, 16)
    elseif kind == "SHOP" then
        -- A warm paper lantern, with visible frame and a hanging tassel.
        stroke(x, y + 5 * scale, x, y + 3.8 * scale, 1.1 * scale)
        stroke(x - 3.8 * scale, y + 3.7 * scale, x + 3.8 * scale, y + 3.7 * scale, 1.1 * scale)
        draw_ellipse(lstg, image, { 255, 255, 192, 126 }, x, y, 2.8 * scale, 3.2 * scale, 0)
        stroke(x - 2.8 * scale, y + 2.4 * scale, x - 2.8 * scale, y - 2.2 * scale, 0.9 * scale)
        stroke(x + 2.8 * scale, y + 2.4 * scale, x + 2.8 * scale, y - 2.2 * scale, 0.9 * scale)
        stroke(x - 2.1 * scale, y - 3.2 * scale, x + 2.1 * scale, y - 3.2 * scale, 1.0 * scale)
        stroke(x, y - 3.2 * scale, x, y - 5 * scale, 1.0 * scale)
        stroke(x - 1.6 * scale, y + 1.0 * scale, x + 1.6 * scale, y + 1.0 * scale, 0.75 * scale)
    elseif kind == "EVENT" then
        -- Five rounded sakura petals and a warm seed at the center.
        for petal_index = 0, 4 do
            local angle = (petal_index - 0.5) * math.pi * 2 / 5 + math.pi * 0.5
            petal(x + math.cos(angle) * 3.0 * scale,
                y + math.sin(angle) * 3.0 * scale, 2.7 * scale, angle)
        end
        draw_circle(lstg, image, { 255, 255, 198, 137 }, x, y, 1.4 * scale, 16)
    elseif kind == "CURRENT" then
        draw_ring(lstg, image, ink, x, y, 2.8 * scale, 4.2 * scale, 20)
        draw_circle(lstg, image, { 255, 255, 198, 137 }, x, y, 1.25 * scale, 16)
        for petal_index = 0, 3 do
            local angle = petal_index * math.pi * 0.5
            petal(x + math.cos(angle) * 5 * scale,
                y + math.sin(angle) * 5 * scale, 1.7 * scale, angle)
        end
    elseif kind == "UNVISITED" then
        draw_ring(lstg, image, ink, x, y, 2.6 * scale, 3.8 * scale, 20)
        draw_circle(lstg, image, ink, x, y, 1.0 * scale, 16)
    end
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
    self.lstg.RenderTTF("Sans", tostring(text), x, x, y, y, align or 0, color(self.lstg, values or COLORS.text), size or 2)
end

--- Draw a loaded image stretched to the given rectangle.
-- LuaSTG Sub exposes RenderRect for the simple case; fall back to a textured
-- quad so the call also works on builds without it.
function MapRenderer:draw_image(image, left, right, bottom, top, values)
    local lstg = self.lstg
    if not image or not lstg then return end
    -- Always publish the tint before drawing. Image state persists between
    -- frames, so a sprite can inherit the color another draw left behind.
    if type(lstg.SetImageState) == "function" then
        pcall(lstg.SetImageState, image, "", color(lstg, values or { 255, 255, 255, 255 }))
    end
    if type(lstg.RenderRect) == "function" then
        lstg.RenderRect(image, left, right, bottom, top)
        return
    end
    if type(lstg.RenderTexture) ~= "function" then return end
    local size = _G["__tnr_" .. tostring(image) .. "_size"]
    local u1, v1, u2, v2 = 0, 0, 1, 1
    if size then u2, v2 = size[1], size[2] end
    local tint = color(lstg, values or { 255, 255, 255, 255 })
    pcall(lstg.RenderTexture, image, "",
        { left, top, 0, u1, v1, tint },
        { right, top, 0, u2, v1, tint },
        { right, bottom, 0, u2, v2, tint },
        { left, bottom, 0, u1, v2, tint })
end

function MapRenderer:draw_weapon_icon(definition, x, y, size)
    if not _G.__tnr_weapon_icon_loaded or not definition then return end
    local id = type(definition) == "table"
        and (definition.weapon_id or definition.equipment_id or definition.definition_id)
        or tostring(definition)
    id = tostring(id or "default")
    if not (_G.__tnr_weapon_icon_rows or {})[id] then id = "default" end
    local frame = math.floor(((self.ui_time or 0) * 8) % 8) + 1
    local image = "tnr-weapon-icon-" .. id .. "-" .. frame
    size = tonumber(size) or 24
    self:draw_image(image, x - size * 0.5, x + size * 0.5,
        y - size * 0.5, y + size * 0.5)
end

--- Draw a list of { text = string, color = string|table } lines inside a panel.
--- Returns the number of lines actually drawn.
function MapRenderer:draw_info_lines(lines, left, top, options)
    options = options or {}
    local base_size = options.size or 0.66
    local base_height = options.line_height or 26
    local height = options.height or (options.max_lines or 14) * base_height
    local width = options.width or 400
    local columns = math.max(1, options.columns or 1)
    local gap = columns > 1 and 24 or 0
    local column_width = (width - gap * (columns - 1)) / columns
    local function layout(size)
        local rows = {}
        for _, line in ipairs(lines or {}) do
            local raw = tostring(type(line) == "table" and line.text or line or "")
            if raw ~= "" then
                local reserve = type(line) == "table" and line.icon and 18 or 0
                local available = math.max(1, (column_width - reserve) / (24 * size))
                local part, used, first = "", 0, true
                for character in raw:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                    local byte = character:byte()
                    local units = byte and byte < 128 and 0.55 or 1
                    if used + units > available and part ~= "" then
                        rows[#rows + 1] = {text = part, line = line, icon = first and line.icon or nil, indent = reserve}
                        part, used, first = "", 0, false
                    end
                    part, used = part .. character, used + units
                end
                if part ~= "" then rows[#rows + 1] = {text = part, line = line, icon = first and line.icon or nil, indent = reserve} end
            end
        end
        return rows
    end
    local size, rows = base_size, layout(base_size)
    local line_height = base_height
    while #rows > math.max(1, math.floor(height / line_height)) * columns and size > 0.26 do
        size = size * 0.93
        line_height = base_height * size / base_size
        rows = layout(size)
    end
    local per_column = math.max(1, math.ceil(#rows / columns))
    if per_column * line_height > height then
        local scale = height / (per_column * line_height)
        size, line_height = size * scale, line_height * scale
    end
    for index, row in ipairs(rows) do
        local column = math.floor((index - 1) / per_column)
        local row_index = (index - 1) % per_column
        local x = left + column * (column_width + gap)
        local y = top - row_index * line_height
        local values = COLORS.text
        local line_color = type(row.line) == "table" and row.line.color
        if type(line_color) == "table" then values = line_color
        elseif type(line_color) == "string" and COLORS[line_color] then values = COLORS[line_color] end
        if row.icon then
            -- A compact 3x3 pictogram is derived from the affix identity, so
            -- icons remain distinct without depending on a font's glyph set.
            local hash = 7
            for i = 1, #row.icon do hash = (hash * 31 + row.icon:byte(i)) % 511 end
            hash = hash + 1
            local cell = math.max(2, 3.2 * size / base_size)
            for bit = 0, 8 do
                if math.floor(hash / (2 ^ bit)) % 2 == 1 then
                    local cx, cy = bit % 3, math.floor(bit / 3)
                    draw_rect(self.lstg, self.white, values, x + cx * cell, x + (cx + 0.8) * cell,
                        y - (cy + 1) * cell, y - (cy + 0.2) * cell)
                end
            end
        end
        self:draw_text(row.text, x + row.indent, y, size, values, 0)
    end
    return #rows
end

-- Common ordinary-game UI backdrop, using the same moonlit title art and
-- subdued vermilion accents. Replay screens retain their separate renderer.
function MapRenderer:draw_standard_backdrop()
    if TitleAssets.bg then
        self:draw_image("tnr-title-bg", 0, self.width, 0, self.height)
    end
    -- Keep enough of the title illustration visible to carry its moonlit
    -- shrine mood into the menus. Text-bearing panels supply the contrast.
    draw_rect(self.lstg, self.white, { 118, 7, 11, 23 }, 0, self.width, 0, self.height)
    local t = self.ui_time
    for index = 1, 16 do
        local phase = t * 1.7 + index * 2.13
        local x = ((index * 137 + t * (16 + index % 5 * 5)) % (self.width + 36)) - 18
        local y = ((index * 83 - t * (10 + index % 4 * 4)) % (self.height + 36)) - 18
        local alpha = 22 + math.floor((0.5 + 0.5 * math.sin(phase)) * 38)
        local dx, dy = math.cos(phase) * 3, math.sin(phase) * 1.5
        local petal = index % 3 == 0
            and { alpha, 184, 202, 255 }
            or { alpha, 255, 174, 193 }
        draw_line(self.lstg, self.white, petal, x - dx, y - dy, x + dx, y + dy, 1.6)
        if index % 2 == 0 then
            draw_diamond(self.lstg, self.white, { alpha + 10, 244, 225, 202 }, x, y, 1.2)
        end
    end
    local red = { 180, 150, 42, 55 }
    draw_rect(self.lstg, self.white, red, 36, 114, self.height - 35, self.height - 33)
    draw_rect(self.lstg, self.white, red, 36, 38, self.height - 90, self.height - 33)
    draw_rect(self.lstg, self.white, red, self.width - 114, self.width - 36, 33, 35)
    draw_rect(self.lstg, self.white, red, self.width - 38, self.width - 36, 33, 90)
end

function MapRenderer:draw_panel(left, right, bottom, top, fill_alpha)
    local lstg = self.lstg
    local image = self.white
    if right <= left or top <= bottom then return end
    draw_rect(lstg, image, { 48, 0, 0, 0 }, left + 5, right + 5, bottom - 5, top - 5)
    draw_rect(lstg, image, { 48, 25, 18, 36 }, left, right, bottom, top)
    local fill = COLORS.panel
    if fill_alpha then fill = { fill_alpha, COLORS.panel[2], COLORS.panel[3], COLORS.panel[4] } end
    draw_rect(lstg, image, fill, left + 2, right - 2, bottom + 2, top - 2)

    -- Lacquered frame with shrine-rope red corner marks and moon-silver rails.
    local rail = COLORS.panel_border
    draw_rect(lstg, image, rail, left + 5, right - 5, bottom + 2, bottom + 3.2)
    draw_rect(lstg, image, rail, left + 5, right - 5, top - 3.2, top - 2)
    draw_rect(lstg, image, rail, left + 2, left + 3.2, bottom + 5, top - 5)
    draw_rect(lstg, image, rail, right - 3.2, right - 2, bottom + 5, top - 5)

    local span = math.min(24, (right - left) * 0.16, (top - bottom) * 0.3)
    local inset = 4
    local crimson = { 225, 204, 82, 100 }
    local moon = { 205, 222, 190, 158 }
    -- Each corner uses two short bars, like the cut ends of a paper charm.
    for _, corner in ipairs({
        { left + inset, bottom + inset, 1, 1 },
        { left + inset, top - inset, 1, -1 },
        { right - inset, bottom + inset, -1, 1 },
        { right - inset, top - inset, -1, -1 },
    }) do
        local x, y, sx, sy = corner[1], corner[2], corner[3], corner[4]
        draw_rect(lstg, image, crimson, math.min(x, x + sx * span), math.max(x, x + sx * span), y - 1, y + 1)
        draw_rect(lstg, image, crimson, x - 1, x + 1, math.min(y, y + sy * span), math.max(y, y + sy * span))
        draw_diamond(lstg, image, moon, x, y, 2.1)
    end
end

-- Animated moonlit accents shared by modern map, reward, catalog and equipment
-- screens. Small particles stay behind text; focus frames carry the motion so
-- the active control remains easy to follow.
function MapRenderer:draw_focus_frame(left, right, bottom, top, phase)
    if not self.white or right <= left or top <= bottom then return end
    local t = self.ui_time or 0
    phase = tonumber(phase) or 0
    local pulse = 0.5 + 0.5 * math.sin(t * 3.2 + phase)
    local edge = { 145 + math.floor(pulse * 85), 235, 105, 110 }
    draw_rect(self.lstg, self.white, edge, left, right, bottom, bottom + 1.5)
    draw_rect(self.lstg, self.white, edge, left, right, top - 1.5, top)
    draw_rect(self.lstg, self.white, edge, left, left + 1.5, bottom, top)
    draw_rect(self.lstg, self.white, edge, right - 1.5, right, bottom, top)

    local span = right - left
    local glint_width = math.min(58, span * 0.22)
    local travel = ((t * 150 + phase * 37) % (span + glint_width)) - glint_width
    local glint_left = math.max(left, left + travel)
    local glint_right = math.min(right, left + travel + glint_width)
    if glint_right > glint_left then
        draw_rect(self.lstg, self.white, { 65 + math.floor(pulse * 65), 255, 210, 192 },
            glint_left, glint_right, top - 4, top - 2)
    end
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
    draw_rect(self.lstg, self.white, { 195, 201, 73, 91 }, left + 14, right - 14, top - 36, top - 34)
    self:draw_text("当前路线", left + 18, top - 58, 0.72, COLORS.muted, 0)
    draw_line(self.lstg, self.white, { 200, 233, 194, 163 }, left + 103, top - 57, right - 18, top - 57, 2.5)
    local route_glow = (self.ui_time or 0) * 34 % math.max(1, right - left - 125)
    draw_diamond(self.lstg, self.white, { 220, 255, 211, 183 }, left + 103 + route_glow, top - 57, 3)
    local rows = {
        { "精英", "ELITE", TYPE_META.ELITE.color },
        { "当前节点", "CURRENT", { 255, 255, 255, 255 } },
        { "未访问", "UNVISITED", { 190, 170, 175, 190 } },
        { "战斗", "ENEMY", TYPE_META.ENEMY.color },
        { "首领", "BOSS", TYPE_META.BOSS.color },
        { "商店", "SHOP", TYPE_META.SHOP.color },
        { "神社", "SHRINE", TYPE_META.SHRINE.color },
        { "事件", "EVENT", TYPE_META.EVENT.color },
    }
    for index, row in ipairs(rows) do
        local y = top - 96 - (index - 1) * 38
        if index > 1 then
            draw_rect(self.lstg, self.white, { 58, 210, 151, 144 }, left + 14, right - 14, y + 17, y + 18)
        end
        if _G.__tnr_map_node_icons_loaded then
            self:draw_image(MAP_ICON_IMAGES[row[2]], left + 17, left + 39, y - 11, y + 11)
        else
            draw_medallion(self.lstg, self.white, left + 28, y, 9, row[3], row[2] == "CURRENT")
            draw_map_glyph(self.lstg, self.white, row[2], left + 28, y, row[3], 0.92)
        end
        self:draw_text(row[1], left + 52, y + 1, 0.82, COLORS.text, 0)
    end
    draw_rect(self.lstg, self.white, { 118, 189, 55, 80 }, left + 14, left + 17, bottom + 16, bottom + 40)
    self:draw_text("悬停查看路线", left + 18, bottom + 26, 0.68, COLORS.muted, 0)
end

function MapRenderer:draw_header(session)
    local player = session:get_player(1)
    self:draw_panel(24, self.width - 24, self.height - 86, self.height - 20)
    draw_diamond(self.lstg, self.white, { 190, 218, 83, 100 }, 48, self.height - 53, 18)
    draw_diamond(self.lstg, self.white, { 255, 12, 17, 31 }, 48, self.height - 53, 13)
    self:draw_text("月", 48, self.height - 58, 0.72, { 255, 241, 212, 179 }, 1 + 4)
    self:draw_text("探索地图", 75, self.height - 45, 1.32, COLORS.text, 0)
    self:draw_text("TOUHOU NIGHT REIGN  ·  六面巡游", self.width * 0.5, self.height - 54, 0.74, COLORS.accent, 1 + 4)
    local hud = string.format("生命 %d   炸弹 %d   金钱 %d   总分 %d", player.life, player.bomb, player.money, player.score)
    -- Leave the top-right equipment button clear of the status HUD.
    self:draw_text(hud, self.width - 170, self.height - 48, 0.82, COLORS.text, 2)
    draw_rect(self.lstg, self.white, { 112, 207, 80, 96 }, 52, self.width - 175, self.height - 78, self.height - 76)
end

function MapRenderer:draw_footer(message)
    self:draw_panel(220, self.width - 24, 22, 74)
    self:draw_text(message or "选择一个相邻节点前进", self.width * 0.5, 56, 0.88, COLORS.text, 1 + 4)
    self:draw_text("方向键移动    Enter 确认    鼠标点击选择", self.width - 48, 56, 0.68, COLORS.muted, 2)
end

function MapRenderer:render_pause_menu(cursor)
    local lstg = self.lstg
    if not lstg then return end
    lstg.BeginScene()
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, { 176, 4, 7, 18 }, 0, self.width, 0, self.height)
    local panel_width = math.min(410, self.width * 0.38)
    local left = self.width - panel_width - 46
    local right = self.width - 46
    self:draw_panel(left, right, 125, self.height - 125, 228)
    self:draw_text("暂停", left + 32, self.height - 170, 1.55, COLORS.accent, 0)
    self:draw_text("方向键选择   Enter / Z 确认   Esc 返回游戏", left + 32, self.height - 215, 0.62, COLORS.muted, 0)
    local options = { "继续游戏", "重启本关", "返回菜单" }
    for index, label in ipairs(options) do
        local top = self.height - 280 - (index - 1) * 82
        local bottom = top - 58
        local selected = index == (cursor or 1)
        draw_rect(lstg, self.white, selected and { 235, 102, 38, 50 } or COLORS.map_panel,
            left + 22, right - 22, bottom, top)
        if selected then self:draw_focus_frame(left + 22, right - 22, bottom, top, index * 0.8) end
        self:draw_text((selected and ">  " or "   ") .. label, left + 44, (top + bottom) * 0.5,
            0.95, selected and COLORS.text or COLORS.muted, 0)
    end
    lstg.EndScene()
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
                -- Only outgoing links from the current layer are active.
                -- The incoming edge remains visible as a visited connection,
                -- but it must not look like a selectable return route.
                local path_from_current = node.id == view.current_node_id
                    and linked ~= nil and linked.x > node.x
                if path_from_current then
                    values = COLORS.active_line
                elseif node.visited and linked and linked.visited then
                    values = COLORS.visited_line
                end
                if path_from_current then
                    draw_line(self.lstg, self.white, { 64, 190, 64, 82 }, source.x, source.y, target.x, target.y, 9)
                    draw_line(self.lstg, self.white, values, source.x, source.y, target.x, target.y, 3.6)
                else
                    draw_line(self.lstg, self.white, values, source.x, source.y, target.x, target.y, 3.0)
                end
                if path_from_current then
                    local phase = (self.ui_time or 0) * 0.42
                    for trail = 0, 2 do
                        local progress = (phase - trail * 0.055) % 1
                        local x = source.x + (target.x - source.x) * progress
                        local y = source.y + (target.y - source.y) * progress
                        draw_diamond(self.lstg, self.white,
                            { 90 + trail * 12, 255, 224 - trail * 18, 198 }, x, y, 2.2 - trail * 0.35)
                    end
                end
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
            local pulse = 0.5 + 0.5 * math.sin((self.ui_time or 0) * 3 + node.id)
            local radius = (is_current and 25 or 22) + pulse * (is_current and 3 or 2)
            draw_circle(self.lstg, self.white,
                { 34 + math.floor(pulse * 18), outer[2], outer[3], outer[4] }, position.x, position.y, radius)
            draw_ring(self.lstg, self.white,
                { 105 + math.floor(pulse * 80), 255, is_current and 213 or 188, is_current and 175 or 150 },
                position.x, position.y, radius - 1.2, radius, 32)
            if is_current then
                for petal = 1, 4 do
                    local angle = (self.ui_time or 0) * 1.15 + petal * math.pi * 0.5
                    local orbit = 31 + pulse * 3
                    draw_ellipse(self.lstg, self.white, { 180, 255, 190, 202 },
                        position.x + math.cos(angle) * orbit, position.y + math.sin(angle) * orbit,
                        2.3, 1.15, angle)
                end
            end
        end
        if _G.__tnr_map_node_icons_loaded then
            self:draw_image(MAP_ICON_IMAGES[meta.icon], position.x - 23, position.x + 23,
                position.y - 23, position.y + 23)
        else
            draw_medallion(self.lstg, self.white, position.x, position.y, is_current and 18.5 or 16.5, outer, is_current or is_hovered)
            draw_map_glyph(self.lstg, self.white, meta.icon, position.x, position.y, outer, 1.32)
        end
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
    self:draw_flooded_layers(view, node_positions, left, right, bottom, top)
end

-- Earlier layers are no longer reachable once the player moves forward.
-- A moving deep-blue tide covers them and leaves the current/future route clear.
function MapRenderer:draw_flooded_layers(view, node_positions, left, right, bottom, top)
    local current_node
    for _, node in ipairs(view.nodes or {}) do
        if node.id == view.current_node_id then
            current_node = node
            break
        end
    end
    if not current_node then return end
    local previous_layer_x
    for _, node in ipairs(view.nodes or {}) do
        if node.x < current_node.x
                and (not previous_layer_x or node.x > previous_layer_x) then
            previous_layer_x = node.x
        end
    end
    if not current_node or not previous_layer_x then return end
    local current_position = node_positions[current_node.id]
    if not current_position then return end

    local layer_gap = (current_node.x - previous_layer_x) * (right - left)
    if layer_gap <= 0 then return end
    local center = current_position.x - layer_gap * 0.5
    local amplitude = math.min(12, layer_gap * 0.17)
    local time = self.ui_time or 0
    local function front_at(y)
        local phase = y * 0.018 + time * 1.35
        return center + math.sin(phase) * amplitude
            + math.sin(phase * 0.47 + time * 0.62) * amplitude * 0.22
    end

    local strips = 42
    local strip_height = (top - bottom) / strips
    for index = 0, strips - 1 do
        local y0 = bottom + index * strip_height
        local y1 = y0 + strip_height + 0.6
        local y_mid = (y0 + y1) * 0.5
        local tide = 0.5 + 0.5 * math.sin(time * 1.1 + y_mid * 0.025)
        local alpha = 143 + math.floor(tide * 16)
        draw_rect(self.lstg, self.white, { alpha, 3, 18, 62 }, left, front_at(y_mid), y0, y1)
    end

    -- A dark trough and a thin blue crest make the flood boundary read as a
    -- moving wave at map scale. The short inner strokes suggest flowing water.
    local samples = 48
    local previous_x, previous_y
    for index = 0, samples do
        local y = bottom + (top - bottom) * index / samples
        local x = front_at(y)
        if previous_x then
            draw_line(self.lstg, self.white, { 145, 9, 38, 92 },
                previous_x - 5, previous_y, x - 5, y, 4.2)
            draw_line(self.lstg, self.white, { 188, 52, 139, 215 },
                previous_x, previous_y, x, y, 2.4)
        end
        previous_x, previous_y = x, y
    end
    for band = 1, 6 do
        local y = bottom + band * (top - bottom) / 7 + math.sin(time * 0.7 + band) * 7
        local available = math.max(1, math.floor(front_at(y) - left - 40))
        local x = left + 10 + ((time * 31 + band * 61) % available)
        local finish = math.min(front_at(y) - 8, x + 18 + (band % 3) * 8)
        if finish > x then
            draw_line(self.lstg, self.white, { 72, 55, 147, 207 }, x, y, finish, y + 2, 1.8)
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
    self:draw_standard_backdrop()
    -- A faint moonlit chart border frames the route while leaving the title
    -- illustration visible through its glass-dark center.
    self:draw_panel(214, self.width - 24, 92, self.height - 96, 112)
    self:draw_header(session)
    local button_left, button_right = self.width - 154, self.width - 74
    local button_bottom, button_top = self.height - 76, self.height - 30
    local locked = session.preparation and session.preparation.selected_node_id ~= nil
    local hovered = self:map_equipment_hit_test(mouse_x, mouse_y)
    local button_color = locked and { 100, 80, 86, 100 } or (hovered and { 255, 235, 105, 105 } or { 210, 204, 82, 100 })
    local button_x, button_y = (button_left + button_right) * 0.5, (button_bottom + button_top) * 0.5
    if hovered then draw_diamond(lstg, self.white, { 65, 255, 130, 133 }, button_x, button_y, 24) end
    draw_diamond(lstg, self.white, button_color, button_x, button_y, 20)
    draw_diamond(lstg, self.white, locked and { 205, 22, 25, 42 } or { 230, 22, 25, 42 }, button_x, button_y, 15)
    self:draw_text("装", button_x, button_y - 5, 0.76, locked and COLORS.muted or COLORS.text, 1 + 4)
    self:draw_text("Seed: " .. tostring(session.run_seed or "-"), 48, 96, 0.72, COLORS.muted, 0)
    self:draw_legend()
    self:draw_map(view)
    self:draw_footer(view.message ~= "" and view.message or nil)
    lstg.EndScene()
end

-- Slot grid layout shared by the preparation renderer and its hit test so
-- mouse and keyboard stay in sync. Slot counts come from the character's
-- loadout, which differs per character.
--
-- These must be declared before `preparation_hit_test`, otherwise that local
-- function would resolve the names to nil globals at call time.
--
-- Each group occupies its own row, stacked from the top of the panel downward.
-- Keeping the groups in distinct rows is what prevents the weight bar (drawn in
-- the header band) from overlapping the first slot row.
local SLOT_W, SLOT_H, SLOT_GAP = 130, 58, 14
local SLOT_ROW_PITCH = 88 -- label height + slot height + spacing between rows
local SLOT_GRID_TOP = 460 -- top edge of the first slot row (bottom-up)

local function preparation_groups(loadout)
    local function group_count(key, fallback)
        local list = loadout and loadout[key]
        local count = type(list) == "table" and #list or 0
        return math.max(1, count > 0 and count or fallback)
    end
    local layout = {
        { key = "high_weapons", label = "HIGH-SPEED WEAPONS", fallback = 3 },
        { key = "low_weapons", label = "LOW-SPEED WEAPONS", fallback = 3 },
        { key = "supports", label = "SUPPORT", fallback = 1 },
        { key = "self_modifiers", label = "SELF BUFFS", fallback = 2 },
        { key = "support_modifiers", label = "SUPPORT BUFFS", fallback = 2 },
    }
    local groups = {}
    for index, entry in ipairs(layout) do
        groups[#groups + 1] = {
            key = entry.key,
            label = entry.label,
            x = 100,
            y = SLOT_GRID_TOP - (index - 1) * SLOT_ROW_PITCH,
            count = group_count(entry.key, entry.fallback),
        }
    end
    return groups
end

function MapRenderer:preparation_hit_test(x, y, row_count, cursor, loadout)
    if not x or not y then return nil end
    local groups = preparation_groups(loadout)
    -- Row base is the first row index of each group as built by
    -- _preparation_rows: action(1), relic(2), then a header and the slots of
    -- each group in order.
    local row_base = {}
    local next_row = 3
    for _, group in ipairs(groups) do
        next_row = next_row + 1 -- header
        row_base[group.key] = next_row
        next_row = next_row + group.count
    end
    for _, group in ipairs(groups) do
        for index = 1, group.count do
            local left = group.x + (index - 1) * (SLOT_W + SLOT_GAP)
            if x >= left and x <= left + SLOT_W and y >= group.y and y <= group.y + SLOT_H then
                local row = row_base[group.key] + index - 1
                if row <= (row_count or row) then return row end
            end
        end
    end
    local replay_session = self.replay and self.replay.equipment_session
    local replay_player = replay_session and replay_session:get_player(replay_session.local_player_id or 1)
    local replay_equipment = replay_player and replay_player.loadout == loadout
    local grid_top, grid_bottom, pitch, card_height = 303, 97, 35, 31
    if replay_equipment then grid_top, grid_bottom, pitch, card_height = 360, 100, 44, 40 end
    if x >= 850 and x <= self.width - 80 and y >= grid_bottom and y <= grid_top then
        local col = x < 1040 and 0 or 1
        local left = 850 + col * 190
        local line = math.floor((grid_top - y) / pitch)
        local bottom = grid_top - card_height - line * pitch
        if line < 6 and x <= left + 175 and y >= bottom and y <= bottom + card_height then
            local inventory_start = next_row + 1
            local row = inventory_start + line * 2 + col
            if row <= (row_count or row) then return row end
        end
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

function MapRenderer:render_preparation(session, cursor, message, mouse_x, mouse_y, mouse_down, edit_only, overlay)
    local lstg = self.lstg
    local player = session:get_player(session.local_player_id or 1) or session:get_player(1)
    local loadout = player and player.loadout
    local registry = session.equipment_registry
    local pending = session.acquisition_service and session.acquisition_service:get_pending(session.local_player_id or 1)
    local rows = { { kind = "action" } }
    if edit_only then rows[1].label = "Save" end
    local row_refs = {}
    local groups = preparation_groups(loadout)
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
    local replay_equipment = self.replay and self.replay.equipment_session == session
    if not replay_equipment then self:draw_standard_backdrop() end
    draw_rect(lstg, self.white, replay_equipment and { 255, 12, 15, 29 } or { 195, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
    self:draw_panel(62, 810, 48, self.height - 82)
    self:draw_panel(828, self.width - 62, 48, self.height - 82)
    local pending_definition = pending and registry and registry:get(pending.definition_id)
    local title = pending and ("仓库已满：" .. tostring(pending_definition and (pending_definition.display_name_zh or pending_definition.display_name) or pending.definition_id))
        or (replay_equipment and "EQUIPMENT LOADOUT" or "装备整备")
    self:draw_text(title, 88, self.height - 116, 1.0, COLORS.accent, 0)
    -- Weight bar: current weight against the character's capacity. It lives in
    -- the header band above the slot grid, so it can never overlap a slot row.
    -- The bar turns gold below half capacity (ultralight, which doubles high
    -- speed) and highlights when overloaded.
    local capacity = player and tonumber(player.current_capacity) or 0
    local weight = loadout and loadout:get_total_weight(registry) or 0
    local WeightPolicy = require("tnr.character.runtime.weight_speed_policy")
    local weight_class = WeightPolicy.classify(weight, capacity)
    local bar_left, bar_right = 88, 470
    local bar_bottom, bar_top = self.height - 168, self.height - 158
    local fill_color = COLORS.accent
    local class_label = ""
    if weight_class == "ULTRALIGHT" then
        fill_color = { 255, 245, 140, 120 }
        class_label = "   超轻机体"
    elseif weight_class == "OVERLOAD" then
        fill_color = { 255, 235, 105, 110 }
        class_label = "   超载"
    end
    draw_rect(lstg, self.white, { 200, 40, 48, 60 }, bar_left, bar_right, bar_bottom, bar_top)
    local ratio = capacity > 0 and math.min(1, weight / capacity) or (weight > 0 and 1 or 0)
    if ratio > 0 then
        draw_rect(lstg, self.white, fill_color, bar_left, bar_left + (bar_right - bar_left) * ratio, bar_bottom, bar_top)
    end
    self:draw_text(string.format("负重 %.1f / %d%s", weight, capacity, class_label),
        88, self.height - 140, 0.72, COLORS.muted, 0)
    local slot_w, slot_h, gap = SLOT_W, SLOT_H, SLOT_GAP
    local group_labels = { high_weapons = "高速武器", low_weapons = "低速武器", supports = "子机",
        self_modifiers = "自身增益", support_modifiers = "子机增益" }
    for _, group in ipairs(groups) do
        local label = replay_equipment and group.label or group_labels[group.key]
        self:draw_text(label, group.x, group.y + slot_h + (replay_equipment and 13 or 25), 0.64, COLORS.muted, 0)
        for index = 1, group.count do
            local left = group.x + (index - 1) * (slot_w + gap)
            local instance = loadout and loadout[group.key] and loadout[group.key][index]
            local active = instance and instance ~= false
            local is_selected = selected(group.key, index)
            draw_rect(lstg, self.white, is_selected and { 255, 95, 80, 78 } or { 205, 31, 40, 42 },
                left, left + slot_w, group.y, group.y + slot_h)
            if is_selected and not replay_equipment then
                self:draw_focus_frame(left, left + slot_w, group.y, group.y + slot_h, index + #group.key)
            end
            draw_rect(lstg, self.white, active and { 220, 78, 88, 82 } or { 150, 80, 90, 45 },
                left + 4, left + slot_w - 4, group.y + 4, group.y + slot_h - 4)
            self:draw_text(tostring(index), left + 9, group.y + slot_h - 17, 0.58, COLORS.accent, 0)
            if active and (group.key == "high_weapons" or group.key == "low_weapons" or group.key == "supports") then
                local enabled = not (instance.runtime_data and instance.runtime_data.enabled == false)
                self:draw_text(enabled and "[启用]" or "[停用]", left + 8, group.y + 14, 0.5,
                    enabled and COLORS.accent or COLORS.muted, 0)
            end
            self:draw_text(name_of(instance), left + slot_w * 0.5, group.y + slot_h * 0.5, 0.58,
                active and COLORS.text or COLORS.muted, 1 + 4)
            if active and instance and (group.key == "high_weapons" or group.key == "low_weapons") then
                local definition = registry and registry:get(instance.definition_id)
                if definition and definition.equipment_type == "WEAPON" then
                    self:draw_weapon_icon(definition, left + slot_w - 18, group.y + slot_h * 0.5, 18)
                end
            end
        end
    end
    draw_rect(lstg, self.white, (cursor or 1) == 1 and { 255, 95, 80, 78 } or { 205, 31, 40, 55 }, 70, 300, 53, 86)
    local action_label = edit_only and "保存" or (player and player.map_ready and "取消准备" or "准备")
    if replay_equipment then action_label = edit_only and "SAVE" or (player and player.map_ready and "CANCEL READY" or "READY") end
    self:draw_text(action_label, 185, 69, 0.72, COLORS.text, 1 + 4)
    local inventory_title_y = replay_equipment and 395 or 330
    self:draw_text(replay_equipment and "INVENTORY" or "仓库", 850, inventory_title_y, 0.82, COLORS.accent, 0)
    self:draw_text(string.format("%d/%d", loadout and loadout.inventory:count() or 0, loadout and loadout.inventory.capacity or 0), self.width - 88, inventory_title_y, 0.62, COLORS.muted, 2)
    for index, instance in ipairs(loadout and loadout.inventory.items or {}) do
        local col, line = (index - 1) % 2, math.floor((index - 1) / 2)
        local pitch, card_height, top = 35, 31, 303
        if replay_equipment then pitch, card_height, top = 44, 40, 360 end
        local left, bottom = 850 + col * 190, top - card_height - line * pitch
        local row = rows[cursor or 1]
        local active = row and row.kind == "inventory" and row.index == index
        draw_rect(lstg, self.white, active and { 255, 95, 80, 76 } or { 205, 31, 40, 42 }, left, left + 175, bottom, bottom + card_height)
        if active and not replay_equipment then
            self:draw_focus_frame(left, left + 175, bottom, bottom + card_height, index * 0.4)
        end
        self:draw_text(string.format("%d  %s", index, name_of(instance)), left + 8, bottom + card_height / 2, 0.53,
            active and COLORS.text or COLORS.muted, 0)
        local definition = registry and registry:get(instance.definition_id)
        if definition and definition.equipment_type == "WEAPON" then
            self:draw_weapon_icon(definition, left + 157, bottom + card_height / 2, 20)
        end
    end
    -- Equipment detail panel. A direct mouse hover wins, otherwise the
    -- keyboard cursor is inspected. The panel stays empty when nothing is
    -- focused so the grid is not cluttered with placeholder text.
    -- Ordinary loadout slots leave room between the grid and inventory. Use
    -- that space for a wider detail panel, while keeping replay presentation
    -- unchanged and leaving all twelve inventory entries unobstructed.
    local detail_left = replay_equipment and 846 or 678
    local detail_bottom = replay_equipment and 396 or 350
    self:draw_panel(detail_left, self.width - 80, detail_bottom, 628)
    if not replay_equipment then
        self:draw_focus_frame(detail_left, self.width - 80, detail_bottom, 628, 1.2)
    end
    self:draw_text("装备信息", detail_left + 20, 602, 0.86, COLORS.accent, 0)
    local row = rows[cursor or 1]
    local hover_row = self:preparation_hit_test(mouse_x, mouse_y, #rows, cursor or 1, loadout)
    local inspect_row = (hover_row and rows[hover_row]) or row
    local detail_lines = {}
    if inspect_row and inspect_row.instance and inspect_row.instance ~= false then
        local definition = inspect_row.definition
            or (registry and registry:get(inspect_row.instance.definition_id))
        detail_lines = EquipmentInfo.describe(definition, inspect_row.instance)
    elseif inspect_row and inspect_row.kind == "equipped" then
        detail_lines = { { text = "空槽位", color = "muted" },
            { text = tostring(inspect_row.group) .. " / " .. tostring(inspect_row.index), color = "muted" } }
    end
    self:draw_info_lines(detail_lines, detail_left + 20, 566,
        { size = 0.62, line_height = 25, width = self.width - detail_left - 120,
            height = 566 - detail_bottom - 15 })
    self:draw_text(pending and "选择仓库物品，Enter 替换 / Esc 放弃新物品" or "左键武器或子机启停 / 右键卸下", 850, 84, 0.60, COLORS.muted, 0)
    self:draw_text(pending and "仓库已满：选择要丢弃的物品，或按 Esc 不拾取" or message or (overlay and "方向键选择   回车确认   退格丢弃   Tab/Esc 返回商店"
        or "方向键选择   回车确认   退格丢弃   Tab/Esc 返回"), self.width * 0.5, 58, 0.68, COLORS.muted, 1 + 4)
    lstg.EndScene()
    return #rows
end

function MapRenderer:menu_hit_test(x, y)
    if not x or not y then
        return nil
    end
    -- Three by four icon grid anchored to the bottom-left, matching
    -- render_menu. Cell geometry is mirrored here so mouse picking stays exact.
    local cell = 104
    local gap = 6
    local grid_left = 44
    local grid_bottom = 36
    local grid_right = grid_left + 3 * cell + 2 * gap
    local grid_top = grid_bottom + 4 * cell + 3 * gap
    if x < grid_left or x > grid_right or y < grid_bottom or y > grid_top then
        return nil
    end
    local column = math.floor((x - grid_left) / (cell + gap))
    local row_from_bottom = math.floor((y - grid_bottom) / (cell + gap))
    if column < 0 or column > 2 or row_from_bottom < 0 or row_from_bottom > 3 then
        return nil
    end
    local row = 3 - row_from_bottom
    local index = row * 3 + column + 1
    if index > 11 then return nil end
    return index
end

function MapRenderer:network_menu_hit_test(x, y, item_count)
    if not x or not y or x < 330 or x > self.width - 330 then return nil end
    local field_count = math.max(1, (item_count or 2) - 1)
    local spacing=field_count==3 and 80 or 90
    for index = 1, field_count do
        local top = 450 - (index - 1) * spacing
        if y >= top - 58 and y <= top then return index end
    end
    local action_top = 450 - field_count * spacing
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
    self:draw_standard_backdrop()
    draw_rect(lstg, self.white, { 195, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
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

--- Character select shown after choosing single player or a network mode and
--- before the map is generated. Three character cards with a detail panel.
function MapRenderer:render_character_select(catalog, cursor, mouse_x, mouse_y)
    local lstg = self.lstg
    catalog = catalog or {}
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_standard_backdrop()
    draw_rect(lstg, self.white, { 195, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
    self:draw_panel(70, self.width - 70, 90, self.height - 70)
    self:draw_text("选择自机", self.width * 0.5, self.height - 130, 1.7, COLORS.accent, 1 + 4)
    self:draw_text("进入地图前确定本局使用的角色", self.width * 0.5, self.height - 172, 0.8, COLORS.muted, 1 + 4)

    local count = math.max(1, #catalog)
    local gap = 28
    local card_width = math.min(320, (self.width - 200 - gap * (count - 1)) / count)
    local total = card_width * count + gap * (count - 1)
    local left = (self.width - total) * 0.5
    local card_bottom = 210
    local card_top = 430
    for index = 1, count do
        local entry = catalog[index]
        local x1 = left + (index - 1) * (card_width + gap)
        local x2 = x1 + card_width
        local selected = index == (cursor or 1)
        draw_rect(lstg, self.white, selected and COLORS.accent or COLORS.map_panel,
            x1, x2, card_bottom, card_top)
        draw_rect(lstg, self.white, selected and { 235, 105, 38, 70 } or { 205, 31, 40, 42 },
            x1 + 5, x2 - 5, card_bottom + 5, card_top - 5)
        local name = entry and (entry.display_name or entry.id) or "--"
        local blurb = entry and entry.blurb or ""
        self:draw_text(string.format("%d", index), x1 + 16, card_top - 30, 0.72, COLORS.muted, 0)
        self:draw_text(name, (x1 + x2) * 0.5, card_top - 92, 1.0, COLORS.text, 1 + 4)
        self:draw_text(blurb, (x1 + x2) * 0.5, card_top - 150, 0.72, COLORS.active_line, 1 + 4)
        if selected then self:draw_text("已选择", (x1 + x2) * 0.5, card_bottom + 30, 0.74, COLORS.text, 1 + 4) end
    end

    -- Detail panel for the highlighted character.
    self:draw_panel(70, self.width - 70, 90, 185)
    local entry = catalog[cursor or 1]
    if entry then
        local detail = entry.detail or entry.blurb or ""
        self:draw_text(string.format("%s   %s", entry.display_name or entry.id, entry.display_name_en or ""),
            self.width * 0.5, 150, 0.86, COLORS.text, 1 + 4)
        self:draw_text(detail, self.width * 0.5, 116, 0.74, COLORS.muted, 1 + 4)
    end
    self:draw_text("方向键选择   回车确认   Esc 返回", self.width * 0.5, 62, 0.75, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

function MapRenderer:character_select_hit_test(x, y, count)
    if not x or not y then return nil end
    count = math.max(1, count or 0)
    local gap = 28
    local card_width = math.min(320, (self.width - 200 - gap * (count - 1)) / count)
    local total = card_width * count + gap * (count - 1)
    local left = (self.width - total) * 0.5
    local card_bottom, card_top = 210, 430
    if y < card_bottom or y > card_top then return nil end
    for index = 1, count do
        local x1 = left + (index - 1) * (card_width + gap)
        if x >= x1 and x <= x1 + card_width then return index end
    end
    return nil
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
    self:draw_standard_backdrop()
    draw_rect(lstg, self.white, { 195, 12, 15, 29 }, 300, self.width - 300, 170, self.height - 170)
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
    local options = { "重试本关" }
    if session.failure_networked then
        options[#options + 1] = "重新开始联机游玩"
    elseif (session.failure_option_count or 2) == 3 then
        options[#options + 1] = "接受现实（消耗1命继续）"
    end
    options[#options + 1] = "返回主菜单"
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_standard_backdrop()
    draw_rect(lstg, self.white, { 195, 12, 15, 29 }, 280, self.width - 280, 145, self.height - 145)
    self:draw_text("战斗失败", self.width * 0.5, self.height - 210, 1.5, COLORS.text, 1 + 4)
    self:draw_text(session.failure_networked and "P1/P2 请选择相同的处理方式" or "请选择下一步操作",
        self.width * 0.5, self.height - 255, 0.85, COLORS.muted, 1 + 4)
    for index, label in ipairs(options) do
        local bottom = 360 - (index - 1) * 68
        local selected = index == (cursor or 1)
        draw_rect(lstg, self.white, selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 }, 390, self.width - 390, bottom, bottom + 50)
        self:draw_text(selected and ">" or "", 420, bottom + 25, 0.8, COLORS.accent, 1 + 4)
        self:draw_text(label, self.width * 0.5, bottom + 25, 0.92, selected and COLORS.text or COLORS.muted, 1 + 4)
    end
    self:draw_text(session.failure_networked and "方向键选择   Enter 确认   Esc 返回主菜单"
        or "接受现实会清除弹幕、保留敌人并恢复本关初始增益", self.width * 0.5, 64, 0.68, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

-- Main menu, built entirely from the imported title screen art: a full-screen
-- background, the logo anchored to the top-left and a three by three icon grid
-- anchored to the bottom-left. Every label is part of the artwork, so no text
-- is drawn. The selected cell is highlighted with a frame and a lift.
function MapRenderer:render_menu(menu_cursor, session)
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)

    if TitleAssets.bg then
        self:draw_image("tnr-title-bg", 0, self.width, 0, self.height)
    else
        draw_rect(lstg, self.white, { 255, 12, 15, 29 }, 0, self.width, 0, self.height)
    end

    -- Logo: top-left corner.
    local logo_entry = TitleAssets.logo
    if logo_entry then
        local logo_size = { logo_entry.width, logo_entry.height }
        local logo_w = 420
        local logo_h = logo_w * (logo_size[2] / logo_size[1])
        local logo_left = 40
        local logo_top = self.height - 36
        self:draw_image("tnr-title-logo", logo_left, logo_left + logo_w, logo_top - logo_h, logo_top)
    end

    -- Eleven active menu items fill the three-by-four grid. The last row has
    -- two entries; the unused bottom-right cell stays open as breathing room.
    local cell = 104
    local gap = 6
    local grid_left = 44
    local grid_bottom = 36
    local REPLAY_INDEX = 10
    local time = self.ui_time or 0
    for index = 1, 11 do
        local column = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        local left = grid_left + column * (cell + gap)
        local bottom = grid_bottom + (3 - row) * (cell + gap)
        local selected = index == (menu_cursor or 1)
        local pulse = 0.5 + 0.5 * math.sin(time * 3.1)
        local grow = selected and (3 + pulse * 3) or 0
        local image_name = "tnr-title-icon-" .. index
        local entry = TitleAssets.get(image_name)
        local size = entry and { entry.width, entry.height } or nil
        if selected then
            -- Highlight frame behind the selected icon.
            draw_rect(lstg, self.white, { 150 + math.floor(pulse * 70), 214, 62, 44 },
                left - 6, left + cell + 6, bottom - 6, bottom + cell + 6)
            draw_line(lstg, self.white, COLORS.accent, left - 6, bottom - 6, left + cell + 6, bottom - 6, 2)
            draw_line(lstg, self.white, COLORS.accent, left - 6, bottom + cell + 6, left + cell + 6, bottom + cell + 6, 2)
            draw_line(lstg, self.white, COLORS.accent, left - 6, bottom - 6, left - 6, bottom + cell + 6, 2)
            draw_line(lstg, self.white, COLORS.accent, left + cell + 6, bottom - 6, left + cell + 6, bottom + cell + 6, 2)
        end
        if size then
            -- Preserve the icon's aspect ratio inside its cell.
            local scale = math.min((cell + grow) / size[1], (cell + grow) / size[2])
            local draw_w = size[1] * scale
            local draw_h = size[2] * scale
            local draw_left = left + (cell - draw_w) * 0.5
            local draw_bottom = bottom + (cell - draw_h) * 0.5
            self:draw_image(image_name, draw_left, draw_left + draw_w, draw_bottom, draw_bottom + draw_h)
        elseif index == 11 then
            -- A small book drawn with the same dark, moonlit and vermilion
            -- palette as the surrounding title icons.
            draw_rect(lstg, self.white, { 225, 19, 23, 38 }, left, left + cell, bottom, bottom + cell)
            draw_rect(lstg, self.white, { 220, 111, 36, 45 }, left + 12, left + cell - 12, bottom + 28, bottom + 91)
            draw_rect(lstg, self.white, { 245, 31, 37, 54 }, left + 17, left + cell - 17, bottom + 33, bottom + 86)
            draw_line(lstg, self.white, { 255, 218, 200, 194 }, left + cell / 2, bottom + 38, left + cell / 2, bottom + 81, 1)
            for mark = 0, 2 do
                local y = bottom + 72 - mark * 10
                draw_line(lstg, self.white, { 255, 218, 200, 194 }, left + 23, y, left + 43, y, 1)
                draw_line(lstg, self.white, { 255, 218, 200, 194 }, left + 61, y, left + 81, y, 1)
            end
            self:draw_text("新手教程", left + cell * 0.5, bottom + 12, 0.62, COLORS.text, 1 + 4)
        elseif index == REPLAY_INDEX then
            draw_rect(lstg, self.white, { 225, 19, 23, 38 }, left, left + cell, bottom, bottom + cell)
            local cx, cy = left + cell * 0.5, bottom + 63
            local orbit = 29 + pulse * 2
            for segment = 0, 15 do
                local a1 = segment * math.pi * 2 / 16
                local a2 = (segment + 1) * math.pi * 2 / 16
                draw_line(lstg, self.white, { 130, 125, 151, 210 },
                    cx + math.cos(a1) * orbit, cy + math.sin(a1) * orbit,
                    cx + math.cos(a2) * orbit, cy + math.sin(a2) * orbit, 1.3)
            end
            draw_diamond(lstg, self.white, { 255, 242, 220, 170 }, cx, cy, 15 + pulse)
            draw_diamond(lstg, self.white, { 255, 30, 36, 55 }, cx + 7, cy + 5, 14)
            for star = 1, 3 do
                local angle = time * 0.8 + star * math.pi * 2 / 3
                draw_diamond(lstg, self.white, { 205, 255, 178, 190 },
                    cx + math.cos(angle) * 37, cy + math.sin(angle) * 37, 2)
            end
            self:draw_text("旧作重演", cx, bottom + 13, 0.59, selected and COLORS.text or COLORS.muted, 1 + 4)
        end
    end
    lstg.EndScene()
end

function MapRenderer:tutorial_hit_test(x, y)
    if not x or not y then return nil end
    if x >= 90 and x <= 270 and y >= 70 and y <= 118 then return "prev" end
    if x >= self.width - 270 and x <= self.width - 90 and y >= 70 and y <= 118 then return "next" end
    if x >= self.width - 235 and x <= self.width - 90 and y >= self.height - 130 and y <= self.height - 88 then return "exit" end
    return nil
end

function MapRenderer:render_tutorial(page_index, mouse_x, mouse_y)
    local pages = require("tnr.ui.tutorial_pages")
    page_index = math.max(1, math.min(#pages, tonumber(page_index) or 1))
    local page = pages[page_index]
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    if TitleAssets.bg then self:draw_image("tnr-title-bg", 0, self.width, 0, self.height) end
    draw_rect(lstg, self.white, { 195, 8, 12, 25 }, 0, self.width, 0, self.height)
    self:draw_panel(70, self.width - 70, 50, self.height - 70)
    draw_rect(lstg, self.white, { 230, 100, 30, 43 }, 70, 78, 50, self.height - 70)
    self:draw_text("新手教程", 108, self.height - 122, 1.1, COLORS.accent, 0)
    self:draw_text(page.eyebrow, 110, self.height - 160, 0.7, COLORS.muted, 0)
    self:draw_text(string.format("%02d / %02d", page_index, #pages), self.width - 280, self.height - 117, 0.75, COLORS.muted, 2)
    local hover = self:tutorial_hit_test(mouse_x, mouse_y)
    local function button(left, right, bottom, top, label, active)
        draw_rect(lstg, self.white, active and { 235, 110, 45, 55 } or { 215, 35, 39, 53 }, left, right, bottom, top)
        draw_line(lstg, self.white, COLORS.panel_border, left, bottom, right, bottom, 1)
        draw_line(lstg, self.white, COLORS.panel_border, left, top, right, top, 1)
        self:draw_text(label, (left + right) * 0.5, (bottom + top) * 0.5, 0.7, COLORS.text, 1 + 4)
    end
    button(self.width - 235, self.width - 90, self.height - 130, self.height - 88, "退出教程", hover == "exit")
    self:draw_text(page.title, 128, self.height - 230, 1.55, COLORS.text, 0)
    draw_line(lstg, self.white, COLORS.accent, 128, self.height - 250, self.width - 128, self.height - 250, 1)
    for index, line in ipairs(page.lines) do
        local y = self.height - 293 - (index - 1) * 50
        self:draw_text(string.format("%02d", index), 132, y, 0.72, COLORS.accent, 0)
        self:draw_text(line, 184, y, 0.84, COLORS.text, 0)
    end
    button(90, 270, 70, 118, "上一页", hover == "prev" and page_index > 1)
    button(self.width - 270, self.width - 90, 70, 118, page_index == #pages and "完成" or "下一页", hover == "next")
    self:draw_text("← / → 翻页    Enter 下一页    Esc 返回主界面", self.width * 0.5, 90, 0.64, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

local function replay_select_geometry(width, height)
    local left, gap = 52, 14
    local available = width - left * 2 - gap * 3
    local widths = { available * 0.35, available * 0.16, available * 0.22, available * 0.27 }
    local columns, x = {}, left
    for index, field in ipairs({ "stage", "player_count", "mode", "character" }) do
        columns[field] = { left = x, right = x + widths[index], top = height - 145, bottom = 135 }
        x = x + widths[index] + gap
    end
    return {
        columns = columns,
        row_y = function(index) return height - 221 - (index - 1) * 49 end,
        start = { left = width * 0.5 - 128, right = width * 0.5 + 128, bottom = 78, top = 120 },
    }
end

function MapRenderer:replay_select_hit_test(x, y, replay)
    if not x or not y or not replay then return nil end
    local geometry = replay_select_geometry(self.width, self.height)
    if x >= geometry.start.left and x <= geometry.start.right
            and y >= geometry.start.bottom and y <= geometry.start.top then
        return { action = "start" }
    end
    local fields = {
        stage = replay:stage_list(),
        player_count = replay.PLAYER_COUNTS,
        mode = replay.MODES,
        character = replay.CHARACTERS,
    }
    for field, entries in pairs(fields) do
        if not (replay.network_lobby and field == "player_count") then
            local column = geometry.columns[field]
            if x >= column.left + 8 and x <= column.right - 8 then
                for index = 1, #entries do
                    local row_y = geometry.row_y(index)
                    if y >= row_y - 20 and y <= row_y + 20 then
                        return { field = field, index = index }
                    end
                end
            end
        end
    end
    return nil
end

--- The legacy replay picker, restyled to match the moonlit title and map UI.
function MapRenderer:render_replay_select(replay, cursor_field, mouse_x, mouse_y)
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_standard_backdrop()
    self:draw_panel(36, self.width - 36, 58, self.height - 34)
    self:draw_text("旧作重演", self.width * 0.5, self.height - 57, 1.5, COLORS.accent, 1 + 4)
    self:draw_text("按原作数据重演东方绀珠传", self.width * 0.5, self.height - 91, 0.68, COLORS.muted, 1 + 4)

    local geometry = replay_select_geometry(self.width, self.height)
    local pointer = self:replay_select_hit_test(mouse_x, mouse_y, replay)
    local stages = replay:stage_list()
    local modes = replay.MODES
    local characters = replay.CHARACTERS
    local counts = { stage = stages, player_count = replay.PLAYER_COUNTS, mode = modes, character = characters }
    local names = { stage = "关卡", player_count = "人数", mode = "规则", character = "自机" }
    local cursors = {
        stage = replay.stage_cursor or 1,
        player_count = replay.player_count_cursor or 1,
        mode = replay.mode_cursor or 1,
        character = replay.character_cursor or 1,
    }
    local section_number = 0
    for _, field in ipairs({ "stage", "player_count", "mode", "character" }) do
        if not (replay.network_lobby and field == "player_count") then
            section_number = section_number + 1
            local column = geometry.columns[field]
            self:draw_panel(column.left, column.right, column.bottom, column.top)
            self:draw_text(string.format("%02d  %s", section_number, names[field]),
                column.left + 18, column.top - 27, 0.82, COLORS.accent, 0)
            for index, entry in ipairs(counts[field]) do
                local row_y = geometry.row_y(index)
                local selected = index == cursors[field]
                local focused = cursor_field == field
                local hovered = pointer and pointer.field == field and pointer.index == index
                local row_left, row_right = column.left + 8, column.right - 8
                if selected or hovered then
                    draw_rect(lstg, self.white, hovered and { 152, 92, 54, 56 }
                        or { 144, 84, 32, 46 }, row_left, row_right, row_y - 20, row_y + 20)
                end
                if selected then
                    draw_rect(lstg, self.white, COLORS.accent, row_left + 3, row_left + 5,
                        row_y - 15, row_y + 15)
                end
                self:draw_text(entry.name, column.left + 20, row_y, selected and 0.84 or 0.76,
                    selected and COLORS.text or COLORS.muted, 0)
                if selected then
                    draw_diamond(lstg, self.white, focused and COLORS.active_line or COLORS.accent,
                        column.right - 24, row_y, focused and 4 or 3)
                end
                if focused and selected then
                    self:draw_focus_frame(row_left, row_right, row_y - 20, row_y + 20, index * 0.5)
                end
            end
        end
    end

    if replay.network_lobby then
        local column = geometry.columns.player_count
        self:draw_panel(column.left, column.right, column.bottom, column.top)
        self:draw_text("局域网", column.left + 18, column.top - 27, 0.82, COLORS.accent, 0)
        self:draw_text("双人协力", column.left + 20, geometry.row_y(1), 0.78, COLORS.text, 0)
        self:draw_text("共享残机与 Bomb", column.left + 20, geometry.row_y(2), 0.62, COLORS.muted, 0)
        for index, line in ipairs(replay.network_status or {}) do
            self:draw_text(line, column.left + 16, geometry.row_y(3) - (index - 1) * 30,
                0.58, COLORS.muted, 0)
        end
    end
    local start = geometry.start
    local start_hovered = pointer and pointer.action == "start"
    draw_rect(lstg, self.white, start_hovered and { 235, 107, 40, 48 } or { 220, 37, 40, 61 },
        start.left, start.right, start.bottom, start.top)
    self:draw_focus_frame(start.left, start.right, start.bottom, start.top, 2.4)
    self:draw_text(replay.network_lobby and "准备 / 开始" or "开始重演",
        self.width * 0.5, (start.bottom + start.top) * 0.5, 0.86, COLORS.text, 1 + 4)

    self:draw_text("鼠标点击选择　← → 切换栏目　↑ ↓ 选择　Enter 开始", self.width * 0.5, 48, 0.65, COLORS.muted, 1 + 4)
    if replay.message then
        self:draw_text(replay.message, self.width * 0.5, 143, 0.66, COLORS.accent, 1 + 4)
    elseif not replay.network_lobby and replay:selected_player_count().key==2 then
        self:draw_text("P2：WASD 移动　F 射击　G 低速　H Bomb",self.width*.5,143,.58,COLORS.muted,1+4)
    elseif replay:selected_mode().key=="modern" then
        self:draw_text("装备与锻体在本轮保留；更换自机、人数或返回主菜单将重置",self.width*.5,143,.58,COLORS.muted,1+4)
    end
    lstg.EndScene()
end

--- Legacy replay: draw the active stage through the replay runtime.
function MapRenderer:render_replay_stage(replay)
    local lstg = self.lstg
    if not lstg or not replay or not replay.runtime then return end
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    -- The replay draws at its own canvas size, which matches the project canvas.
    replay.runtime:draw()
    lstg.EndScene()
end

--- Legacy replay result screen: the outcome and the run summary.
function MapRenderer:render_replay_result(replay)
    local lstg = self.lstg
    local result = replay and replay.last_result or {}
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, { 255, 12, 15, 29 }, 260, self.width - 260, 150, self.height - 150)

    local cleared = result.outcome == "cleared"
    self:draw_text(cleared and "关卡通过" or "游戏结束",
        self.width * 0.5, self.height - 250, 1.6,
        cleared and COLORS.accent or COLORS.muted, 1 + 4)

    local lines = {
        string.format("关卡　　%s", tostring(result.stage or "-")),
        string.format("自机　　%s", tostring(result.character or "-")),
        string.format("规则　　%s", tostring(result.mode or "-")),
        string.format("得分　　%d", tonumber(result.score) or 0),
        string.format("擦弹　　%d", tonumber(result.graze) or 0),
        string.format("用时　　%.1f 秒", (tonumber(result.frames) or 0) / 60),
    }
    if cleared and result.rewards and #result.rewards > 0 then
        lines[#lines + 1] = string.format("奖励选择　%d 次", #result.rewards)
    end
    for index, line in ipairs(lines) do
        self:draw_text(line, self.width * 0.5, self.height - 310 - (index - 1) * 28, 0.82,
            COLORS.text, 1 + 4)
    end
    local hint = cleared and result.rewards and #result.rewards > 0
        and "Enter 选择奖励　Esc 返回关卡选择" or "Enter 或 Esc 返回关卡选择"
    self:draw_text(hint, self.width * 0.5, 180, 0.76, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

--- Legacy replay reward screen: the between-stage picks.
function MapRenderer:render_replay_reward(replay)
    local lstg = self.lstg
    local choices = replay and replay.reward_choices or {}
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    draw_rect(lstg, self.white, { 255, 12, 15, 29 }, 70, self.width - 70, 100, self.height - 120)
    self:draw_text("选择奖励", self.width * 0.5, self.height - 190, 1.5, COLORS.accent, 1 + 4)
    self:draw_text(string.format("第 %d 次三选一 · 玩家 %d", replay.reward_round or 1,replay.reward_player_id or 1),
        self.width * 0.5, self.height - 226, 0.76, COLORS.muted, 1 + 4)
    for index, reward in ipairs(choices) do
        local top = self.height - 300 - (index - 1) * 96
        local selected = index == (replay.reward_cursor or 1)
        draw_rect(lstg, self.white,
            selected and { 235, 105, 38, 70 } or { 210, 24, 29, 52 },
            100, 730, top - 74, top)
        if selected then
            draw_line(lstg, self.white, COLORS.accent, 100, top - 74, 730, top - 74, 2)
            draw_line(lstg, self.white, COLORS.accent, 100, top, 730, top, 2)
        end
        self:draw_text(selected and ">" or "", 120, top - 20, 0.9, COLORS.accent, 0)
        self:draw_text(reward.name, 150, top - 20, 0.86,
            selected and COLORS.text or COLORS.muted, 0)
        if reward.kind == "EQUIPMENT" then
            local equipment_session = replay:get_equipment_session()
            local definition = equipment_session and equipment_session.equipment_registry
                and equipment_session.equipment_registry:get(reward.definition_id)
            if definition and definition.equipment_type == "WEAPON" then
                self:draw_weapon_icon(definition, 150 + utf8_char_count(reward.name) * 16 + 12,
                    top - 20, 23)
            end
        end
        self:draw_text(reward.description or "", 150, top - 46, 0.60, COLORS.muted, 0)
    end
    local selected=choices[replay.reward_cursor or 1]
    if selected and selected.kind=="EQUIPMENT" then
        self:draw_panel(750, self.width-90,150,self.height-270)
        local info=EquipmentInfo.describe_reward(replay:get_equipment_session(),selected)
        self:draw_info_lines(info,770,self.height-290,{size=.6,line_height=24,width=self.width-880,height=self.height-455})
    end
    self:draw_text(replay.reward_message or "↑ ↓ 选择　Enter 确认　Tab 配装 / 仓库", self.width * 0.5, 135, 0.68, COLORS.muted, 1 + 4)
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
    self:draw_standard_backdrop()
    draw_rect(lstg, self.white, { 195, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
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

--- Equipment catalog: a browsable list of every registered definition with
--- the same player-facing detail panel used by the shop and loadout screens.
function MapRenderer:render_equipment_catalog(entries, cursor, mouse_x, mouse_y)
    local lstg = self.lstg
    entries = entries or {}
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_standard_backdrop()
    draw_rect(lstg, self.white, { 195, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
    self:draw_panel(62, 720, 80, self.height - 70)
    self:draw_panel(742, self.width - 62, 80, self.height - 70)
    self:draw_text("装备图鉴", 88, self.height - 116, 1.18, COLORS.accent, 0)
    self:draw_text(string.format("共 %d 件装备", #entries), 88, self.height - 148, 0.68, COLORS.muted, 0)

    local visible = 10
    local state = ScrollState.new(#entries, visible, cursor or 1)
    local first = state:first_visible()
    local last = math.min(#entries, first + visible - 1)
    for index = first, last do
        local entry = entries[index]
        local definition = entry and entry.definition or nil
        local row = index - first
        local bottom = self.height - 190 - row * 46
        local selected = index == (cursor or 1)
        draw_rect(lstg, self.white, selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 },
            84, 700, bottom, bottom + 36)
        if selected then self:draw_focus_frame(84, 700, bottom, bottom + 36, index * 0.31) end
        self:draw_text(selected and ">" or "", 100, bottom + 18, 0.7, COLORS.accent, 1 + 4)
        local rarity_label, rarity_color = EquipmentInfo.rarity(definition)
        local item_name = EquipmentInfo.display_name(definition)
        self:draw_text(item_name, 132, bottom + 18, 0.74, rarity_color, 0)
        if definition and definition.equipment_type == "WEAPON" then
            self:draw_weapon_icon(definition, 132 + utf8_char_count(item_name) * 17 + 12,
                bottom + 18, 23)
        end
        local slot = EquipmentInfo.slot_label(definition) or EquipmentInfo.category(definition)
        self:draw_text(slot, 470, bottom + 18, 0.62, COLORS.muted, 0)
        self:draw_text(rarity_label, 660, bottom + 18, 0.62, COLORS.muted, 2)
    end
    self:draw_scrollbar(690, 700, 110, self.height - 165, #entries, visible, cursor or 1, mouse_x, mouse_y, false)
    self:draw_text(string.format("%d / %d", cursor or 1, #entries), 390, 52, 0.72, COLORS.muted, 1 + 4)

    self:draw_focus_frame(742, self.width - 62, 80, self.height - 70, 0.9)
    self:draw_text("装备信息", 766, self.height - 116, 0.95, COLORS.accent, 0)
    local entry = entries[cursor or 1]
    local detail_lines = entry and EquipmentInfo.describe(entry.definition) or {}
    local detail_top, detail_height = self.height - 158, self.height - 255
    if entry and entry.definition and entry.definition.equipment_type == "WEAPON" then
        local preview_left, preview_right = 766, self.width - 86
        local preview_bottom, preview_top = 390, self.height - 164
        draw_rect(lstg, self.white, { 190, 25, 30, 48 },
            preview_left, preview_right, preview_bottom, preview_top)
        self:draw_text("外观预览 · 8 帧循环", preview_left + 14, preview_top - 20,
            0.62, COLORS.active_line, 0)
        draw_rect(lstg, self.white, { 130, 120, 130, 150 },
            preview_left + 16, preview_right - 16, preview_bottom + 17, preview_bottom + 19)
        draw_diamond(lstg, self.white, COLORS.accent,
            (preview_left + preview_right) * 0.5, preview_bottom + 20, 4)
        local phase = self.catalog_preview_frame or 0
        WeaponPreview.draw(lstg, entry.definition, phase,
            (preview_left + preview_right) * 0.5, preview_bottom + 26, 0.45)
        self.catalog_preview_frame = (phase + 1) % WeaponPreview.FRAME_COUNT
        detail_top, detail_height = preview_bottom - 16, preview_bottom - 96
    end
    self:draw_info_lines(detail_lines, 766, detail_top,
        { size = 0.64, line_height = 24, width = self.width - 860, height = detail_height })
    self:draw_text("方向键浏览   Esc 返回主界面", 980, 52, 0.72, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

function MapRenderer:equipment_catalog_hit_test(x, y, count, cursor)
    if not x or not y or x < 84 or x > 700 then return nil end
    local visible = 10
    local state = ScrollState.new(count or 0, visible, cursor or 1)
    local first = state:first_visible()
    -- Mirror the render geometry exactly: row 0 sits at
    -- height-190 .. height-190+36, and each following row drops by 46.
    local top_row_bottom = self.height - 190
    for row = 0, visible - 1 do
        local bottom = top_row_bottom - row * 46
        if y >= bottom and y <= bottom + 36 then
            local index = first + row
            if index <= (count or 0) then return index end
            return nil
        end
    end
    return nil
end

function MapRenderer:render_network_menu(menu)
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_standard_backdrop()
    draw_rect(lstg, self.white, { 195, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
    self:draw_panel(290, self.width - 290, 130, self.height - 120)
    local title = menu.mode == "host" and "开设局域网服务器" or "加入局域网服务器"
    local subtitle = menu.mode == "host" and "设置监听端口，等待另一位玩家加入" or "支持 localhost 或局域网 IPv4 地址"
    self:draw_text(title, self.width * 0.5, self.height - 175, 1.35, COLORS.accent, 1 + 4)
    self:draw_text(subtitle, self.width * 0.5, self.height - 215, 0.76, COLORS.muted, 1 + 4)

    local fields = menu:get_fields()
    local spacing=#fields==3 and 80 or 90
    for index, field in ipairs(fields) do
        local top = 450 - (index - 1) * spacing
        local bottom = top - 58
        local selected = menu.cursor == index
        draw_rect(lstg, self.white, selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 }, 330, self.width - 330, bottom, top)
        draw_line(lstg, self.white, selected and COLORS.accent or COLORS.panel_border, 330, bottom, self.width - 330, bottom, selected and 3 or 1)
        self:draw_text(field.label, 360, top + 22, 0.72, COLORS.muted, 0)
        local value = field.value ~= "" and field.value or field.placeholder
        if selected and field.value ~= "" and field.id~="play_mode" then value = value .. "_" end
        self:draw_text(value, 370, bottom + 27, 0.95, field.value ~= "" and COLORS.text or COLORS.muted, 0)
    end

    local action_index = #fields + 1
    local action_top = 450 - #fields * spacing
    local action_bottom = action_top - 58
    local action_selected = menu.cursor == action_index
    draw_rect(lstg, self.white, action_selected and { 235, 105, 38, 52 } or { 210, 24, 29, 46 }, 430, self.width - 430, action_bottom, action_top)
    self:draw_text(menu:get_action_label(), self.width * 0.5, action_bottom + 28, 0.95, action_selected and COLORS.text or COLORS.muted, 1 + 4)
    if menu.status then
        self:draw_text(menu.status, self.width * 0.5, #fields==3 and 119 or 155, 0.72, menu.status_is_error and { 255, 255, 105, 105 } or COLORS.accent, 1 + 4)
    end
    self:draw_text("输入内容   ↑↓/Tab 切换   Enter 确认   Esc 返回", self.width * 0.5, 82, 0.72, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

function MapRenderer:render(view, session, menu_cursor, training_cursor, training_card_id, training_catalog, training_title, training_display_name, network_menu, preparation_cursor, preparation_message, shop_cursor, relic_cursor, reward_cursor, mouse_x, mouse_y, mouse_down, preparation_edit_only, music_cursor, music_catalog, catalog_cursor, catalog_entries, preparation_overlay, character_cursor, character_catalog, tutorial_page)
    if not self.lstg then
        return
    end
    self:init()
    self.ui_time = (self.ui_time or 0) + 1 / 60
    if preparation_overlay and (session.run_state==Constants.run_states.REPLAY_SELECT
            or session.run_state==Constants.run_states.REPLAY_REWARD) then
        self:render_preparation(self.replay:get_equipment_session(),preparation_cursor,preparation_message,
            mouse_x,mouse_y,mouse_down,false,true)
        return
    end
    if session.run_state == Constants.run_states.MENU then
        if network_menu and network_menu:is_open() then
            self:render_network_menu(network_menu)
        else
            self:render_menu(menu_cursor, session)
        end
        return
    end
    if session.run_state == Constants.run_states.TUTORIAL then
        self:render_tutorial(tutorial_page, mouse_x, mouse_y)
        return
    end
    if session.run_state == Constants.run_states.MUSIC_PLAYER then
        self:render_music_player(music_cursor, music_catalog)
        return
    end
    if session.run_state == Constants.run_states.REPLAY_SELECT then
        self:render_replay_select(self.replay, self.replay_field, mouse_x, mouse_y)
        return
    end
    if session.run_state == Constants.run_states.REPLAY_STAGE then
        self:render_replay_stage(self.replay)
        return
    end
    if session.run_state == Constants.run_states.REPLAY_RESULT then
        self:render_replay_result(self.replay)
        return
    end
    if session.run_state == Constants.run_states.REPLAY_REWARD then
        self:render_replay_reward(self.replay)
        return
    end
    if session.run_state == Constants.run_states.EQUIPMENT_CATALOG then
        self:render_equipment_catalog(catalog_entries, catalog_cursor or 1, mouse_x, mouse_y)
        return
    end
    if session.run_state == Constants.run_states.CHARACTER_SELECT then
        self:render_character_select(character_catalog, character_cursor or 1, mouse_x, mouse_y)
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
    local pending_state = session.run_state == Constants.run_states.MAP
        or session.run_state == Constants.run_states.MAP_PREPARATION
        or session.run_state == Constants.run_states.REWARD
        or session.run_state == Constants.run_states.SHOP
        or session.run_state == Constants.run_states.FLOOR_CLEAR
        or session.run_state == Constants.run_states.RELIC_SELECT
    if pending_state and session.acquisition_service and session.acquisition_service:get_pending(session.local_player_id or 1) then
        self:render_preparation(session, preparation_cursor, preparation_message, mouse_x, mouse_y, mouse_down, false, true)
        return
    end
    if session.run_state == Constants.run_states.MAP then
        self:render_map(view, session, mouse_x, mouse_y)
        return
    end
    if preparation_overlay or session.run_state == Constants.run_states.MAP_PREPARATION then
        self:render_preparation(session, preparation_cursor, preparation_message, mouse_x, mouse_y, mouse_down, preparation_edit_only, preparation_overlay)
        return
    end
    if session.run_state == Constants.run_states.SHOP then
        self:render_shop(session, shop_cursor or 1, mouse_x, mouse_y, mouse_down, preparation_message)
        return
    end
    if session.run_state == Constants.run_states.SHRINE then
        self:render_shrine(session.shrine_service)
        return
    end
    if session.run_state == Constants.run_states.RELIC_SELECT then
        self:render_relic_select(session, relic_cursor or 1, mouse_x, mouse_y, mouse_down)
        return
    end
    if session.run_state == Constants.run_states.FLOOR_CLEAR then
        self:render_floor_clear(session, preparation_message)
        return
    end
    if session.run_state == Constants.run_states.REWARD then
        self:render_reward(session, reward_cursor or 1, mouse_x, mouse_y, mouse_down, preparation_message)
        return
    end
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_standard_backdrop()
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

function MapRenderer:render_shop(session, cursor, mouse_x, mouse_y, mouse_down, status)
    local lstg = self.lstg
    lstg.BeginScene(); lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height); lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_standard_backdrop()
    self:draw_panel(55, self.width - 55, 55, self.height - 70)
    self:draw_text("商店", self.width * 0.5, self.height - 110, 2.0, COLORS.accent, 1 + 4)
    if status and status ~= "" then self:draw_text(status, self.width * 0.5, self.height - 150, 0.7, COLORS.active_line, 1 + 4) end
    -- Top-right loadout button: opens the preparation screen as an overlay so
    -- the player can manage (and discard) equipment without leaving the shop.
    local button_hovered = self:shop_equipment_hit_test(mouse_x, mouse_y) == true
    local button_left, button_right = self.width - 300, self.width - 80
    local button_bottom, button_top = self.height - 140, self.height - 96
    draw_rect(lstg, self.white, button_hovered and { 255, 235, 105, 105 } or { 210, 24, 29, 62 },
        button_left, button_right, button_bottom, button_top)
    if button_hovered then self:draw_focus_frame(button_left, button_right, button_bottom, button_top, 1.1) end
    draw_line(lstg, self.white, button_hovered and COLORS.text or COLORS.panel_border, button_left, button_bottom, button_right, button_bottom, button_hovered and 2 or 1)
    draw_line(lstg, self.white, button_hovered and COLORS.text or COLORS.panel_border, button_left, button_top, button_right, button_top, button_hovered and 2 or 1)
    self:draw_text("装备整备 Tab", (button_left + button_right) * 0.5, (button_bottom + button_top) * 0.5, 0.72, COLORS.text, 1 + 4)
    local offers = session.shop_service and session.shop_service:get_offers() or {}
    local item_count = #offers
    local local_player = session:get_player(session.local_player_id or 1)
    self:draw_text(string.format("金币 %d", local_player and local_player.money or 0),
        self.width - 330, self.height - 110, 0.78, COLORS.active_line, 2)
    local geometry = shop_geometry(self.width, self.height)
    local purchases = session.shop_service and session.shop_service.purchases
        and session.shop_service.purchases[session.local_player_id or 1] or {}
    for index = 1, item_count do
        local offer = offers[index]
        local x1 = geometry.list_left + (index - 1) * (geometry.card_width + geometry.gap)
        local x2 = x1 + geometry.card_width
        local selected = index == cursor
        local purchased = purchases[index] == true
        local fill = purchased and { 180, 45, 55, 95 } or (selected and { 235, 88, 31, 43 } or COLORS.map_panel)
        draw_rect(lstg, self.white, fill, x1, x2, geometry.card_bottom, geometry.card_top)
        if selected then draw_rect(lstg, self.white, COLORS.accent, x1, x2, geometry.card_top - 3, geometry.card_top) end
        if selected then self:draw_focus_frame(x1, x2, geometry.card_bottom, geometry.card_top, index * 0.75) end
        if not purchased then
            local offered_definition = offer and offer.kind == "EQUIPMENT"
                and session.equipment_registry:get(offer.definition_id) or nil
            local label = offer and offer.kind == "EQUIPMENT"
                and tostring(offered_definition and (offered_definition.display_name_zh or offered_definition.display_name) or offer.definition_id)
                or (offer and offer.kind == "LIFE" and "团队生命"
                    or (offer and offer.kind == "LIFE_FRAGMENT" and "生命碎片" or "炸弹"))
            self:draw_text(string.format("%d", index), x1 + 16, geometry.card_top - 22, 0.7, COLORS.muted, 0)
            self:draw_text(label, (x1 + x2) * 0.5, geometry.card_top - 58, 0.72, COLORS.text, 1 + 4)
            if offered_definition and offered_definition.equipment_type == "WEAPON" then
                local icon_x = (x1 + x2) * 0.5 + utf8_char_count(label) * 8.5 + 12
                if icon_x + 11 < x2 - 8 then
                    self:draw_weapon_icon(offered_definition, icon_x, geometry.card_top - 58, 20)
                end
            end
            self:draw_text(string.format("%dG", offer and offer.price or 0), (x1 + x2) * 0.5,
                geometry.card_bottom + 24, 0.7, COLORS.active_line, 1 + 4)
        end
    end

    local ready_selected = cursor == item_count + 1
    draw_rect(lstg, self.white, ready_selected and { 235, 88, 31, 43 } or COLORS.map_panel,
        geometry.list_left, geometry.list_right, geometry.ready_bottom, geometry.ready_top)
    if ready_selected then draw_rect(lstg, self.white, COLORS.accent, geometry.list_left, geometry.list_right,
        geometry.ready_top - 3, geometry.ready_top) end
    if ready_selected then
        self:draw_focus_frame(geometry.list_left, geometry.list_right,
            geometry.ready_bottom, geometry.ready_top, 2.0)
    end
    self:draw_text("准备 / 离开商店", self.width * 0.5, (geometry.ready_bottom + geometry.ready_top) * 0.5,
        0.8, COLORS.text, 1 + 4)

    self:draw_panel(geometry.detail_left, geometry.detail_right, geometry.detail_bottom, geometry.detail_top)
    self:draw_focus_frame(geometry.detail_left, geometry.detail_right,
        geometry.detail_bottom, geometry.detail_top, 1.4)
    self:draw_text("物品信息", geometry.detail_left + 20, geometry.detail_top - 28, 0.9, COLORS.accent, 0)
    -- Resolve the inspected slot: a direct mouse hover wins, otherwise fall
    -- back to the keyboard cursor. The panel stays empty when nothing is
    -- focused.
    local hovered_index = self:shop_hit_test(mouse_x, mouse_y)
    local inspect_index = hovered_index or (cursor and cursor <= item_count and cursor) or nil
    if cursor == item_count + 1 and not hovered_index then inspect_index = nil end
    local selected_offer = inspect_index and offers[inspect_index] or nil
    local detail_lines = {}
    if inspect_index and purchases[inspect_index] then
        detail_lines = { { text = "本回合已购买", color = "muted" } }
    elseif selected_offer then
        detail_lines = EquipmentInfo.describe_offer(session, selected_offer)
        local selected_price = tonumber(selected_offer.price) or 0
        if local_player and local_player.money < selected_price then
            detail_lines[#detail_lines + 1] = { text = "金币不足", color = { 255, 235, 105, 110 } }
        end
    end
    self:draw_info_lines(detail_lines, geometry.detail_left + 20, geometry.detail_top - 62,
        { size = 0.66, line_height = 27, width = geometry.detail_right - geometry.detail_left - 40, height = geometry.detail_top - geometry.detail_bottom - 80 })
    self:draw_text("方向键选择   Enter 购买或准备   Esc 离开", self.width * 0.5, 25, 0.75, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

--- Floor transition screen shown after a floor boss is defeated.
function MapRenderer:render_floor_clear(session, message)
    local lstg = self.lstg
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_standard_backdrop()
    draw_rect(lstg, self.white, { 195, 12, 15, 29 }, 42, self.width - 42, 38, self.height - 38)
    self:draw_panel(300, self.width - 300, 210, self.height - 190)
    local floor = session and session.floor or 1
    self:draw_text("第 " .. floor .. " 层 完成", self.width * 0.5, self.height - 250, 2.4, COLORS.accent, 1 + 4)
    self:draw_text("进入第 " .. (floor + 1) .. " 层", self.width * 0.5, self.height - 320, 1.4, COLORS.text, 1 + 4)
    self:draw_text("队伍状态、装备与金钱将保留", self.width * 0.5, self.height - 380, 0.9, COLORS.muted, 1 + 4)
    self:draw_text("按 Enter 继续", self.width * 0.5, 285, 1.0, COLORS.active_line, 1 + 4)
    if message then self:draw_text(message, self.width * 0.5, 245, 0.8, COLORS.text, 1 + 4) end
    lstg.EndScene()
end

function MapRenderer:render_relic_select(session, cursor)
    local lstg = self.lstg
    lstg.BeginScene(); lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height); lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_standard_backdrop()
    self:draw_panel(250, self.width - 250, 115, self.height - 115)
    self:draw_text("选择遗物", self.width * 0.5, self.height - 165, 1.8, COLORS.accent, 1 + 4)
    local player_id = session.local_player_id or 1
    local choices = session.relic_choices[player_id] or {}
    local visible = 5
    local first, last = self:list_window(cursor or 1, #choices, visible)
    for index = first, last do
        local relic_id = choices[index]
        local y = self.height - 255 - (index - first) * 100
        local selected = index == cursor
        draw_rect(lstg, self.white, selected and { 235, 88, 31, 43 } or COLORS.map_panel, 330, self.width - 330, y - 30, y + 30)
        if selected then draw_rect(lstg, self.white, COLORS.accent, 330, self.width - 330, y + 27, y + 30) end
        local relic = session.relic_catalog and session.relic_catalog[relic_id]
        self:draw_text(string.format("%d. %s", index, EquipmentInfo.display_name(relic, relic_id)),
            self.width * 0.5, y, 0.92, COLORS.text, 1 + 4)
    end
    self:draw_scrollbar(330, self.width - 330, 145, self.height - 220, #choices, visible, cursor or 1)
    self:draw_text("方向键选择   Enter 确认", self.width * 0.5, 70, 0.85, COLORS.muted, 1 + 4)
    lstg.EndScene()
end

local function reward_label(session, choice)
    if not choice then return "未知奖励" end
    if choice.kind == "RESOURCE" then
        local amount = tonumber(choice.amount) or 1
        if choice.resource == "life" then return "队伍生命 +" .. amount end
        if choice.resource == "bomb" then return "炸弹 +" .. amount end
        return "资源"
    end
    local definition = session.equipment_registry and session.equipment_registry:get(choice.definition_id)
    return definition and (definition.display_name_zh or definition.display_name) or tostring(choice.definition_id or "未知装备")
end

local function reward_geometry(width, height)
    -- Keep the choices in a narrow, readable column and reserve the right
    -- side for details. The old three-column layout pushed the final card and
    -- long descriptions beyond the visible area on smaller game viewports.
    local outer_left = math.max(54, width * 0.055)
    local outer_right = width - outer_left
    local gap = math.max(10, height * 0.018)
    local card_height = math.max(54, math.min(72, height * 0.10))
    local card_gap = math.max(8, height * 0.018)
    local list_top = height - math.max(238, height * 0.37)
    local list_right = outer_left + (outer_right - outer_left) * 0.47
    return {
        cards_left = outer_left,
        cards_right = list_right,
        card_width = list_right - outer_left,
        card_height = card_height,
        card_gap = card_gap,
        list_top = list_top,
        detail_left = list_right + gap,
        detail_right = outer_right,
        detail_bottom = math.max(125, height * 0.195),
        detail_top = list_top,
    }
end

-- Truncate a display string so it fits inside a card. Counts UTF-8
-- characters (not bytes) so a Chinese name is not cut after one character.
local function utf8_length(text)
    local count = 0
    for _ in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
    end
    return count
end

local function utf8_sub(text, max_chars)
    text = tostring(text or "")
    if max_chars <= 0 then return "" end
    local count = 0
    local end_index = 0
    for character in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        end_index = end_index + #character
        if count >= max_chars then break end
    end
    return text:sub(1, end_index)
end

-- Truncate a display string so it fits inside a card of the given width.
local function fit_text(text, max_chars)
    text = tostring(text or "")
    if utf8_length(text) <= max_chars then return text end
    return utf8_sub(text, math.max(1, max_chars - 1)) .. "\226\128\166"
end

function MapRenderer:render_reward(session, cursor, mouse_x, mouse_y, mouse_down, message)
    local lstg = self.lstg
    lstg.BeginScene(); lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height); lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_standard_backdrop()
    self:draw_panel(55, self.width - 55, 95, self.height - 70)
    local player_id = session.local_player_id or 1
    local choices = session.reward_choices or {}
    local claims = session.reward_claims and session.reward_claims[player_id] or {}
    local required = session.reward_required or 1
    self:draw_text("选择奖励", self.width * 0.5, self.height - 155, 2.2, COLORS.accent, 1 + 4)
    self:draw_text(string.format("选择 %d 项   已选 %d 项", required, #claims), self.width * 0.5, self.height - 200, 1.0, COLORS.muted, 1 + 4)
    if session.reward_guaranteed_definition_id then
        local guaranteed = session.equipment_registry:get(session.reward_guaranteed_definition_id)
        self:draw_text("已获得：" .. tostring(guaranteed and (guaranteed.display_name_zh or guaranteed.display_name) or session.reward_guaranteed_definition_id) .. "（选择查看）", self.width * 0.5, self.height - 235, 0.75, COLORS.active_line, 1 + 4)
    end
    local geometry = reward_geometry(self.width, self.height)
    -- Three full-width rows keep every choice visible on narrow viewports.
    -- Names are truncated by UTF-8 character count so a Chinese name is never
    -- cut to one character.
    -- Reserve room for the kind label, animated weapon icon and selection
    -- status. Using the full card width here let long names run under both.
    local max_name_chars = math.max(6, math.floor((geometry.card_width - 250) / 18))
    for index = 1, 3 do
        local x1 = geometry.cards_left
        local x2 = geometry.cards_right
        local card_top = geometry.list_top - (index - 1) * (geometry.card_height + geometry.card_gap)
        local card_bottom = card_top - geometry.card_height
        local selected = index == (cursor or 1)
        local claimed = false
        for _, claim in ipairs(claims) do if claim.choice_index == index then claimed = true break end end
        draw_rect(lstg, self.white, claimed and { 230, 43, 91, 67 } or (selected and { 235, 88, 31, 43 } or COLORS.map_panel),
            x1, x2, card_bottom, card_top)
        if selected then draw_rect(lstg, self.white, COLORS.accent, x1, x2, card_top - 3, card_top) end
        if selected then self:draw_focus_frame(x1, x2, card_bottom, card_top, index * 0.75) end
        local choice = choices[index]
        local kind_label = choice and (choice.kind == "RESOURCE" and "资源"
            or (choice.kind == "EQUIPMENT" and "装备" or tostring(choice.kind))) or "--"
        local name_label = reward_label(session, choice)
        local name_color = COLORS.text
        if choice and choice.kind == "EQUIPMENT" then
            local definition = session.equipment_registry and session.equipment_registry:get(choice.definition_id)
            local _, rarity_color = EquipmentInfo.rarity(definition)
            name_color = rarity_color
        end
        local center_y = (card_bottom + card_top) * 0.5
        self:draw_text(string.format("%d", index), x1 + 15, center_y, 0.68, COLORS.muted, 0)
        self:draw_text(kind_label, x1 + 52, center_y, 0.66, COLORS.active_line, 0)
        local shown_name = fit_text(name_label, max_name_chars)
        self:draw_text(shown_name, x1 + 150, center_y, 0.76, name_color, 0)
        if choice and choice.kind == "EQUIPMENT" then
            local definition = session.equipment_registry and session.equipment_registry:get(choice.definition_id)
            if definition and definition.equipment_type == "WEAPON" then
                local icon_x = x1 + 150 + utf8_char_count(shown_name) * 18 + 12
                if icon_x + 12 < x2 - 100 then self:draw_weapon_icon(definition, icon_x, center_y, 22) end
            end
        end
        if claimed then
            self:draw_text("已选择", x2 - 72, center_y, 0.60, COLORS.text, 1 + 4)
        else
            self:draw_text("未选择", x2 - 72, center_y, 0.60, COLORS.muted, 1 + 4)
        end
    end
    self:draw_panel(geometry.detail_left, geometry.detail_right, geometry.detail_bottom, geometry.detail_top)
    self:draw_focus_frame(geometry.detail_left, geometry.detail_right, geometry.detail_bottom, geometry.detail_top, 1.6)
    self:draw_text("物品信息", geometry.detail_left + 20, geometry.detail_top - 28, 0.9, COLORS.accent, 0)
    local guaranteed_index = session.reward_guaranteed_definition_id and (#choices + 1) or nil
    local hovered = self:reward_hit_test(mouse_x, mouse_y, #choices, guaranteed_index)
    local inspect_index = hovered or cursor
    local choice = inspect_index and choices[inspect_index] or nil
    local info = choice and EquipmentInfo.describe_reward(session, choice) or {}
    if guaranteed_index and inspect_index == guaranteed_index then
        local definition = session.equipment_registry:get(session.reward_guaranteed_definition_id)
        local instance = session.reward_guaranteed_equipment and session.reward_guaranteed_equipment[player_id]
        info = EquipmentInfo.describe(definition, instance)
    end
    self:draw_info_lines(info, geometry.detail_left + 20, geometry.detail_top - 54,
        { size = 0.66, line_height = 23, width = geometry.detail_right - geometry.detail_left - 40,
            height = geometry.detail_top - geometry.detail_bottom - 65, columns = 2 })
    self:draw_text("方向键选择   回车选择/取消   鼠标点击选择", self.width * 0.5, 120, 0.8, COLORS.muted, 1 + 4)
    if message and message ~= "" then self:draw_text(message, self.width * 0.5, 145, 0.72, COLORS.active_line, 1 + 4) end
    lstg.EndScene()
end

function MapRenderer:render_shrine(service)
    local lstg = self.lstg
    if not service then return end
    lstg.BeginScene()
    lstg.RenderClear(color(lstg, COLORS.background))
    lstg.SetViewport(0, self.width, 0, self.height)
    lstg.SetScissorRect(0, self.width, 0, self.height)
    lstg.SetOrtho(0, self.width, 0, self.height)
    self:draw_standard_backdrop()
    self:draw_panel(56, self.width - 56, 78, self.height - 66, 218)
    self:draw_text("月下神社", self.width * 0.5, self.height - 116, 1.7, COLORS.accent, 1 + 4)
    self:draw_text(service.message or "选择一项神社服务", self.width * 0.5, self.height - 158,
        0.72, COLORS.muted, 1 + 4)

    if service.phase == "operation" then
        local operations = service:operations()
        local left, right = 135, self.width - 135
        for index, operation in ipairs(operations) do
            local top = self.height - 228 - (index - 1) * 76
            local bottom = top - 60
            local selected = index == (service.operation_cursor or 1)
            draw_rect(lstg, self.white, selected and { 235, 102, 38, 58 } or COLORS.map_panel,
                left, right, bottom, top)
            if selected then self:draw_focus_frame(left, right, bottom, top, index * 0.7) end
            self:draw_text(selected and ">" or "", left + 24, (top + bottom) * 0.5,
                0.9, COLORS.accent, 1 + 4)
            self:draw_text(operation.name, left + 60, (top + bottom) * 0.5,
                0.84, selected and COLORS.text or COLORS.muted, 0)
            self:draw_text(operation.description, left + 240, (top + bottom) * 0.5,
                0.66, selected and COLORS.active_line or COLORS.muted, 0)
        end
    else
        local targets = service:targets(service.operation,
            service.fusion_first and service.fusion_first.instance.instance_id or nil)
        local visible = 8
        local first, last = self:list_window(service.target_cursor or 1, #targets, visible)
        local list_left, list_right = 86, self.width * 0.54
        local top = self.height - 218
        local row_pitch, row_height = 47, 39
        for index = first, last do
            local entry = targets[index]
            local definition = entry.definition
            local name = EquipmentInfo.display_name(definition, entry.instance.definition_id)
            local slot = entry.source == "inventory" and "仓库"
                or (entry.group == "high_weapons" and "高速" or entry.group == "low_weapons" and "低速"
                    or entry.group == "supports" and "子机" or "装备")
            local row = index - first
            local bottom = top - row * row_pitch - row_height
            local selected = index == (service.target_cursor or 1)
            draw_rect(lstg, self.white, selected and { 235, 102, 38, 58 } or COLORS.map_panel,
                list_left, list_right, bottom, bottom + row_height)
            if selected then self:draw_focus_frame(list_left, list_right, bottom, bottom + row_height, index * 0.45) end
            local rarity_label, rarity_color = EquipmentInfo.rarity(definition, entry.instance)
            self:draw_text(selected and ">" or "", list_left + 14, bottom + row_height * 0.5,
                0.76, COLORS.accent, 1 + 4)
            local shown_name = fit_text(name, math.max(5, math.floor((list_right - list_left - 160) / 20)))
            self:draw_text(shown_name,
                list_left + 45, bottom + row_height * 0.5, 0.7,
                selected and rarity_color or COLORS.muted, 0)
            if definition.equipment_type == "WEAPON" then
                local icon_x = list_left + 45 + utf8_char_count(shown_name) * 15 + 10
                if icon_x + 10 < list_right - 100 then
                    self:draw_weapon_icon(definition, icon_x, bottom + row_height * 0.5, 18)
                end
            end
            self:draw_text(slot .. " · " .. rarity_label, list_right - 18, bottom + row_height * 0.5,
                0.56, COLORS.muted, 2)
        end
        self:draw_scrollbar(list_right + 10, list_right + 20, top - visible * row_pitch,
            top, #targets, visible, service.target_cursor or 1, nil, nil, false)
        self:draw_panel(self.width * 0.58, self.width - 84, 145, top)
        self:draw_text(service.operation == "fusion" and "武器属性" or "装备属性",
            self.width * 0.58 + 20, top - 30, 0.82, COLORS.accent, 0)
        local entry = targets[service.target_cursor or 1]
        local info = entry and EquipmentInfo.describe(entry.definition, entry.instance) or {
            { text = "没有符合条件的装备", color = "muted" },
        }
        if service.fusion_first then
            table.insert(info, 1, { text = "已选第一把：" .. EquipmentInfo.display_name(service.fusion_first.definition), color = "active_line" })
        end
        self:draw_info_lines(info, self.width * 0.58 + 20, top - 58,
            { size = 0.62, line_height = 24, width = self.width * 0.42 - 126, height = top - 210 })
    end
    self:draw_text("↑ ↓ 选择   Enter 确认   Esc 返回", self.width * 0.5, 108,
        0.76, COLORS.muted, 1 + 4)
    if service.message and service.phase == "target" then
        self:draw_text(service.message, self.width * 0.5, 136, 0.62, COLORS.active_line, 1 + 4)
    end
    lstg.EndScene()
end

function MapRenderer:shop_equipment_hit_test(x, y)
    if not x or not y then return nil end
    local button_left, button_right = self.width - 300, self.width - 80
    local button_bottom, button_top = self.height - 140, self.height - 96
    if x >= button_left and x <= button_right and y >= button_bottom and y <= button_top then
        return true
    end
    return nil
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

function MapRenderer:relic_hit_test(session, x, y, cursor)
    if not x or not y or x < 330 or x > self.width - 330 then return nil end
    local choices = session.relic_choices[session.local_player_id or 1] or {}
    local first, last = self:list_window(cursor or 1, #choices, 5)
    for index = first, last do
        local centre = self.height - 255 - (index - first) * 100
        if y >= centre - 30 and y <= centre + 30 then return index end
    end
    return nil
end

function MapRenderer:reward_hit_test(x, y, count, guaranteed_index)
    local geometry = reward_geometry(self.width, self.height)
    if not x or not y then return nil end
    if guaranteed_index and x >= 100 and x <= self.width - 100
            and y >= self.height - 250 and y <= self.height - 220 then return guaranteed_index end
    if x < geometry.cards_left or x > geometry.cards_right then return nil end
    for index = 1, math.min(3, count or 3) do
        local top = geometry.list_top - (index - 1) * (geometry.card_height + geometry.card_gap)
        local bottom = top - geometry.card_height
        if y >= bottom and y <= top then return index end
    end
    return nil
end

return MapRenderer
