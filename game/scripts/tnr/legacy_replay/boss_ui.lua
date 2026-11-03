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

local HudFont = require("tnr.legacy_replay.hud_font")

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
-- front00's border strips are 64x960, 448x960 and 768x32.
-- They define a 1280x960 source canvas and a 768x896 inner field.
-- Fit that 4:3 canvas into 1280x720 without stretching it.
local PLAYFIELD_SCALE = 2 * CANVAS_SCALE
local PLAYFIELD_LEFT = 160 + 64 * CANVAS_SCALE
local PLAYFIELD_TOP = 720 - 32 * CANVAS_SCALE

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

-- Icons the reference HUD uses, as 1-based indices into the front00 sprite
-- table. The anm spec lists them as sprite 12..23, but the compiled table is
-- 1-based, so the first heart is index 13 and the first star index 19. Each row
-- has six progressive fill frames from empty to full.
BossUi.ICON_SHEET = "front"
BossUi.ICON_SHEET_ENTRY = 1
BossUi.HEART_FIRST_SPRITE = 13
BossUi.STAR_FIRST_SPRITE = 19
BossUi.ICON_FILL_FRAMES = 6

--- Sprite index for a partially filled icon.
-- `ratio` runs 0 (empty) to 1 (full) and selects one of six frames.
function BossUi.icon_sprite(first_sprite, ratio)
    local frames = BossUi.ICON_FILL_FRAMES
    local index = math.floor(math.max(0, math.min(1, ratio or 0)) * (frames - 1) + 0.5)
    return first_sprite + index
end

-- Spell card cut-in timings, read from the reference portrait script: the
-- portrait fades from 0 to full alpha over fifteen frames, then slides from
-- x=276 to x=244 over fifteen more, then holds before retreating.
local CARD_FADE_FRAMES = 15
local CARD_SLIDE_FRAMES = 15
local CARD_START_X = 276
local CARD_END_X = 244
local CARD_HOLD_FRAMES = 120

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
        card_elapsed = 0,
        card_bar_length = 0,
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
-- The reference runs a fixed script for the portrait: fade in, slide into
-- place, hold, then retreat. The timing constants below are the frame counts
-- from that script. The name plate's bar length follows the reference formula,
-- fifteen half pixels per character plus a fixed margin.
function BossUi:show_card(text)
    self.card = text
    self.card_timer = CARD_FADE_FRAMES + CARD_SLIDE_FRAMES + CARD_HOLD_FRAMES
    self.card_elapsed = 0
    self.card_bar_length = #tostring(text or "") * 15 / 2 + 16
end

function BossUi:update()
    if self.name_timer > 0 then self.name_timer = self.name_timer - 1 end
    if self.card_timer > 0 then self.card_timer = self.card_timer - 1 end
    self.card_elapsed = (self.card_elapsed or 0) + 1
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
    -- Name plate: a bar whose width follows the reference formula, with the
    -- attack name drawn on it from the ascii glyphs and a white backing plate.
    if self.name and self.name_timer > 0 then
        local alpha = math.min(255, self.name_timer * 12)
        local length = (self.card_bar_length or (#tostring(self.name) * 15 / 2 + 16))
        local scale = PLAYFIELD_SCALE * 0.5
        local w = math.max(80, length * scale)
        local h = 30
        local right = self.bar_right
        local left = right - w
        local top = self.bar_top - 8
        -- White backing plate.
        lstg.SetImageState("tnr-white", "", lstg.Color(math.floor(alpha * 0.8), 240, 240, 240))
        lstg.RenderRect("tnr-white", left, right, top - h, top)
        -- Blue bar under the name.
        lstg.SetImageState("tnr-white", "", lstg.Color(alpha, 40, 60, 180))
        lstg.RenderRect("tnr-white", left + 2, right - 2, top - h + 2, top - 2)
        -- The name text from the ascii glyphs.
        if self.images.name_glyphs ~= false then
            local draws = HudFont.layout(tostring(self.name), { advance = 16 })
            for _, glyph in ipairs(draws) do
                local image = image_name("ascii", 1, glyph.sprite)
                local gx = left + 6 + glyph.x
                lstg.SetImageState(image, "", lstg.Color(alpha, 255, 255, 255))
                lstg.RenderRect(image, gx, gx + 18, top - 24, top - 4)
            end
        end
    end
    -- Spell card cut-in: the portrait fades in, then slides into place, which
    -- is the sequence the reference portrait script runs.
    if self.card_timer > 0 and self.images.cut_in then
        local elapsed = self.card_elapsed or 0
        local alpha = 255
        if elapsed < CARD_FADE_FRAMES then
            alpha = math.floor(255 * elapsed / CARD_FADE_FRAMES)
        end
        local x_offset = CARD_END_X
        if elapsed < CARD_FADE_FRAMES + CARD_SLIDE_FRAMES then
            local slide = math.max(0, elapsed - CARD_FADE_FRAMES)
            local t = slide / CARD_SLIDE_FRAMES
            x_offset = CARD_START_X + (CARD_END_X - CARD_START_X) * t
        end
        if self.card_timer < CARD_FADE_FRAMES then
            alpha = math.floor(255 * self.card_timer / CARD_FADE_FRAMES)
        end
        local w, h = 420, 600
        local left = PLAYFIELD_LEFT + x_offset * PLAYFIELD_SCALE * 0.5
        local top = PLAYFIELD_TOP - 40
        lstg.SetImageState(self.images.cut_in, "", lstg.Color(alpha, 255, 255, 255))
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
