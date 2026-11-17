-- TH15 boss life rings and stage HUD.
--
-- Geometry below is taken from the reference sprite sizes and the original
-- 384x448 playfield, scaled to the project's 1280x720 canvas. Keeping the
-- numbers in one table makes the layout auditable against screenshots.

local Geometry = require("tnr.legacy_replay.anm_geometry")

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

---@param options table { lstg, lifebar, name_image, star_image, images }
function BossUi.new(options)
    return setmetatable({
        lstg = options.lstg,
        images = options.images or {},
        lifebar = options.lifebar,
        name_image = options.name_image,
        star_image = options.star_image,
        health = 1,
        health_max = 1,
        health_layers = {},
        stars = 0,
        card = nil,
        card_timer = 0,
        card_elapsed = 0,
        visible = false,
    }, BossUi)
end

--- Begin a boss fight: show the bar with the given total health.
function BossUi:begin(health, layers)
    self.health_max = math.max(1, tonumber(health) or 1)
    self.health = self.health_max
    self.health_layers = layers or {}
    self.stars = 0
    self.remaining = nil
    self.card = nil
    self.card_timer = 0
    self.hide_ring = false
    self.visible = true
end

--- Update the current health and the marker row.
function BossUi:set_health(current, maximum)
    if maximum then self.health_max = math.max(1, maximum) end
    self.health = math.max(0, tonumber(current) or 0)
end

--- Show the spell card cut-in.
-- The reference runs a fixed script for the portrait: fade in, slide into
-- place, hold, then retreat.
function BossUi:show_card(text)
    self.card = text
    self.card_timer = CARD_FADE_FRAMES + CARD_SLIDE_FRAMES + CARD_HOLD_FRAMES
    self.card_elapsed = 0
end

function BossUi:update()
    if self.card_timer > 0 then self.card_timer = self.card_timer - 1 end
    self.card_elapsed = (self.card_elapsed or 0) + 1
end

function BossUi:draw_ring(enemy)
    local g, entry = self.lstg, self.lifebar
    if not self.visible or self.hide_ring or not enemy or not entry or not entry.loaded_texture
        or not g.RenderTexture or enemy.legacy_spell_timeout_enabled then return end
    local x, y = BossUi.project(enemy.x, enemy.y)
    local ratio = math.max(0, math.min(1, self.health / self.health_max))
    -- front.anm 237–240 use a red arc, two thin outlines and phase markers.
    local vm = {texture_circle_max=38,vars={[10000]=38,[10001]=0},
        scale_x=2,scale_y=116,alpha=255,red=255,green=255,blue=255,color_mode=0,
        rotation=-math.pi/2,arc_angle=-2*math.pi}
    local size = {32,32}
    Geometry.draw_circle(g,vm,entry,entry.sprites[2],size,x,y,CANVAS_SCALE)
    vm.scale_y=108
    Geometry.draw_circle(g,vm,entry,entry.sprites[2],size,x,y,CANVAS_SCALE)
    if ratio > 0 then
        vm.scale_x,vm.scale_y,vm.arc_angle=8,112,-2*math.pi*ratio
        Geometry.draw_circle(g,vm,entry,entry.sprites[1],size,x,y,CANVAS_SCALE)
    end
    for _, marker in pairs(self.health_layers) do
        if marker.ratio > 0 and marker.ratio < 1 then
            local angle = math.pi/2 + marker.ratio*2*math.pi
            local mx, my = x+math.cos(angle)*112*CANVAS_SCALE,y+math.sin(angle)*112*CANVAS_SCALE
            local colour = marker.colour % 0x100000000
            local tint = g.Color(math.floor(colour/0x1000000),math.floor(colour/0x10000)%256,
                math.floor(colour/0x100)%256,colour%256)
            local w,h=3*CANVAS_SCALE,6*CANVAS_SCALE
            g.RenderTexture(entry.loaded_texture,"",{mx-w,my+h,.5,20,0,tint},{mx+w,my+h,.5,26,0,tint},
                {mx+w,my-h,.5,26,12,tint},{mx-w,my-h,.5,20,12,tint})
        end
    end
end

--- Draw boss name, remaining spells, card title and time.
function BossUi:draw()
    if not self.visible then return end
    local lstg = self.lstg
    local top, left, right = PLAYFIELD_TOP, PLAYFIELD_LEFT, BossUi.PLAYFIELD_RIGHT
    if self.name_image and lstg.RenderRect then
        lstg.SetImageState(self.name_image,"",lstg.Color(255,255,255,255))
        lstg.RenderRect(self.name_image,left+7,left+7+256*CANVAS_SCALE,top-32*CANVAS_SCALE,top)
    end
    if self.star_image and lstg.RenderRect then
        lstg.SetImageState(self.star_image,"",lstg.Color(255,255,255,255))
        for i=1,self.stars do
            local x=left+7+(i-1)*13
            lstg.RenderRect(self.star_image,x,x+12,top-28,top-16)
        end
    end
    if lstg.RenderTTF then
        local function draw_text(text,x,y,align,scale)
            local outline=lstg.Color(255,12,5,20)
            for _,offset in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                lstg.RenderTTF("Sans",text,x+offset[1],x+offset[1],y+offset[2],y+offset[2],align,outline,scale)
            end
            lstg.RenderTTF("Sans",text,x,x,y,y,align,lstg.Color(255,255,255,255),scale)
        end
        if self.card then draw_text(self.card,right-13,top-2,2,1) end
        if self.remaining then
            local seconds=math.floor(self.remaining/60)
            local hundredths=math.floor(self.remaining%60*100/60)
            local centre=(left+right)/2
            draw_text(string.format("%02d",seconds),centre+2,top-39,2,1.25)
            draw_text(string.format(".%02d",hundredths),centre+2,top-48,0,.70)
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

return BossUi
