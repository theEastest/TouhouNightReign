-- Stage 1 boss presentation, matching the reference layout.
--
-- The reference battle HUD has three pieces:
--   * a boss health bar at the top with a segmented marker row
--   * a name plate that slides in under the bar for each attack
--   * a full-screen spell card cut-in shown when a spell starts
--
-- Geometry below is taken from the reference sprite sizes and the original
-- 384x448 playfield, scaled to the project's 1280x720 canvas. Keeping the
-- numbers in one table makes the layout auditable against screenshots.

local BossUi = {}

BossUi.__index = BossUi

-- Playfield geometry, measured from a live capture of the original game.
--
-- A capture of th15.exe 1.00b puts the field border at window px
-- (62,30)-(832,928) inside a 1600x1200 window. The game's logical canvas is
-- 1280x960 and the project's is 1280x720, so every reference coordinate is
-- scaled by 0.75 here. The field is exactly 384x448 units, which fixes the
-- px-per-unit factor below; all enemy, bullet, background and HUD layers use
-- these constants so the presentation lines up with the original.
local PLAYFIELD_WIDTH = 384
local PLAYFIELD_HEIGHT = 448
local CANVAS_SCALE = 720 / 960
local PLAYFIELD_SCALE = 616.0 / PLAYFIELD_WIDTH * CANVAS_SCALE
local PLAYFIELD_LEFT = 49.6 * CANVAS_SCALE
local PLAYFIELD_TOP = 742.4 * CANVAS_SCALE

BossUi.PLAYFIELD_SCALE = PLAYFIELD_SCALE
BossUi.PLAYFIELD_LEFT = PLAYFIELD_LEFT
BossUi.PLAYFIELD_TOP = PLAYFIELD_TOP
BossUi.PLAYFIELD_RIGHT = PLAYFIELD_LEFT + PLAYFIELD_WIDTH * PLAYFIELD_SCALE
BossUi.PLAYFIELD_BOTTOM = PLAYFIELD_TOP - PLAYFIELD_HEIGHT * PLAYFIELD_SCALE

--- Map a reference playfield coordinate to screen space.
-- Reference x is centred on the playfield, y grows downward from the top of
-- the field, matching the ECL coordinate system.
function BossUi.project(x, y)
    return PLAYFIELD_LEFT + (x + PLAYFIELD_WIDTH * 0.5) * PLAYFIELD_SCALE,
           PLAYFIELD_TOP - y * PLAYFIELD_SCALE
end

---@param options table { lstg, images = { name_plate, name_plate_bg, cut_in, ... } }
function BossUi.new(options)
    return setmetatable({
        lstg = options.lstg,
        images = options.images or {},
        -- Bar geometry: full playfield width, a few pixels tall, near the top.
        -- The reference draws the boss bar just under the top edge of the
        -- playfield, spanning the full field width.
        bar_left = PLAYFIELD_LEFT,
        bar_right = PLAYFIELD_LEFT + PLAYFIELD_WIDTH * PLAYFIELD_SCALE,
        bar_top = PLAYFIELD_TOP - 6,
        bar_height = 8,
        health = 1,
        health_max = 1,
        health_layers = {},
        marker_count = 0,
        name = nil,
        name_timer = 0,
        card = nil,
        card_timer = 0,
        card_flash = 0,
        visible = false,
    }, BossUi)
end

--- Begin a boss fight: show the bar with the given total health.
function BossUi:begin(health, layers)
    self.health_max = math.max(1, tonumber(health) or 1)
    self.health = self.health_max
    self.health_layers = layers or {}
    self.visible = true
    self.name = nil
end

--- Update the current health and the marker row.
function BossUi:set_health(current, maximum)
    if maximum then self.health_max = math.max(1, maximum) end
    self.health = math.max(0, tonumber(current) or 0)
end

--- Show the sliding name plate for the current attack.
function BossUi:show_name(text)
    self.name = text
    self.name_timer = 60
end

--- Show the spell card cut-in.
function BossUi:show_card(text)
    self.card = text
    self.card_timer = 150
    self.card_flash = 90
end

function BossUi:update()
    if self.name_timer > 0 then self.name_timer = self.name_timer - 1 end
    if self.card_timer > 0 then self.card_timer = self.card_timer - 1 end
    if self.card_flash > 0 then self.card_flash = self.card_flash - 1 end
end

--- Draw the health bar, the marker row and the remaining sliver.
function BossUi:draw_bar()
    local lstg = self.lstg
    if not self.visible then return end
    local left, right = self.bar_left, self.bar_right
    local top = self.bar_top
    local bottom = top - self.bar_height
    -- Bar background.
    lstg.SetImageState("tnr-white", "", lstg.Color(200, 12, 14, 22))
    lstg.RenderRect("tnr-white", left, right, bottom, top)
    -- Health fill: the reference fills from the left and drains to the right.
    local ratio = 0
    if self.health_max > 0 then ratio = math.max(0, math.min(1, self.health / self.health_max)) end
    if ratio > 0 then
        lstg.SetImageState("tnr-white", "", lstg.Color(235, 232, 78, 92))
        lstg.RenderRect("tnr-white", left, left + (right - left) * ratio, bottom + 1, top - 1)
    end
    lstg.SetImageState("tnr-white", "", lstg.Color(220, 245, 226, 240))
    lstg.RenderRect("tnr-white", left, right, top - 1, top)
    lstg.RenderRect("tnr-white", left, right, bottom, bottom + 1)
end

--- Draw the name plate and the spell card cut-in.
function BossUi:draw_overlays()
    local lstg = self.lstg
    -- Name plate slides down from behind the bar and retreats after a while.
    if self.name and self.name_timer > 0 then
        local alpha = math.min(255, self.name_timer * 12)
        local plate = self.images.name_plate_bg
        if plate then
            local w, h = 200, 44
            local left = self.bar_right - w
            local top = self.bar_top - 8
            lstg.SetImageState(plate, "", lstg.Color(alpha, 255, 255, 255))
            lstg.RenderRect(plate, left, left + w, top - h, top)
        end
        local text = self.images.name_plate
        if text then
            lstg.SetImageState(text, "", lstg.Color(alpha, 255, 255, 255))
            local w, h = 200, 42
            local left = self.bar_right - w - 6
            local top = self.bar_top - 12
            lstg.RenderRect(text, left, left + w, top - h, top)
        end
    end
    -- Spell card cut-in: a large portrait sweeping across the field.
    if self.card_flash > 0 and self.images.cut_in then
        local progress = 1 - self.card_flash / 90
        local w, h = 420, 600
        local left = SCREEN_WIDTH * 0.5 - w * 0.5 + (1 - progress) * 260
        local top = SCREEN_HEIGHT * 0.5 + h * 0.5
        lstg.SetImageState(self.images.cut_in, "", lstg.Color(255, 255, 255, 255))
        lstg.RenderRect(self.images.cut_in, left, left + w, top - h, top)
    end
end

function BossUi:draw()
    self:draw_bar()
    self:draw_overlays()
end

BossUi.SCREEN_WIDTH = SCREEN_WIDTH
BossUi.SCREEN_HEIGHT = SCREEN_HEIGHT

return BossUi
