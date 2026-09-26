-- Complete stage runtime for the legacy replay.
--
-- Ties the ECL interpreter, the adapter, the ANM animation and the background
-- into one object a stage owns. This is the piece the roguelike mode drives: it
-- loads a stage's textures and sprites, starts its main timeline, and renders
-- the field the way the reference does.

local Adapter = require("tnr.legacy_replay.adapter")
local AnmPlayer = require("tnr.legacy_replay.anm_player")
local BossUi = require("tnr.legacy_replay.boss_ui")
local StageBackground = require("tnr.legacy_replay.stage_background")

local StageRuntime = {}

StageRuntime.__index = StageRuntime

-- Every stage's enemy archive, in stage order.
local STAGE_ARCHIVES = {
    st01 = "st01enm", st02 = "st02enm", st03 = "st03enm", st04 = "st04enm",
    st05 = "st05enm", st06 = "st06enm", st07 = "st07enm",
}

StageRuntime.STAGE_ARCHIVES = STAGE_ARCHIVES

--- Resolve a reference texture path to a loaded image name.
-- The loader registers every sprite rect of every archive entry, so an image
-- name is `<archive>#<entry index>#<sprite index>` for enemy sprites, plus a
-- single name for archive entries that only carry one sprite (backgrounds,
-- faces, spell card art).
local function image_name(archive, entry_index, sprite_index)
    return string.format("tnr-th15-%s-%d-%d", archive, entry_index, sprite_index)
end

StageRuntime.image_name = image_name

--- Load every texture and sprite rect the stage needs into the engine.
-- Returns the number of images registered.
function StageRuntime.load_stage_assets(lstg, stage_key, anm, options)
    options = options or {}
    local base = options.asset_root or "assets/legacy_replay"
    local archives = {
        STAGE_ARCHIVES[stage_key],
        stage_key .. "wl",
        stage_key .. "logo",
        "enemy",
        "bullet",
        "effect",
        -- The front sheet carries the HUD icons (hearts, stars) and labels.
        "front",
        "ascii",
    }
    local loaded = 0
    local texture_status = {}
    -- Real source texture sizes, published so the background renderer tiles at
    -- the file's own dimensions instead of the anm header's logical size.
    local texture_sizes = options.texture_sizes or {}
    StageRuntime.texture_sizes = texture_sizes
    local function set_status(value)
        if type(lstg.SetResourceStatus) == "function" then pcall(lstg.SetResourceStatus, value) end
    end
    local function get_status()
        if type(lstg.GetResourceStatus) == "function" then
            local ok, value = pcall(lstg.GetResourceStatus)
            if ok then return value end
        end
        return nil
    end
    local previous = get_status()
    -- Stage art is evicted on every stage change, so register it in the
    -- persistent pool just like the title screen and the coin sheet.
    set_status("global")
    for _, archive in ipairs(archives) do
        local entries = anm[archive]
        if entries then
            for entry_index, entry in ipairs(entries) do
                local path = entry.texture
                local texture = image_name(archive, entry_index, 0)
                if not texture_status[path] then
                    local ok = pcall(lstg.LoadTexture, texture, base .. "/" .. path, false)
                    texture_status[path] = ok
                end
                if texture_status[path] then
                    -- The anm header declares a logical size that can differ
                    -- from the file (a 1024 unit tile backed by a 512 px
                    -- texture, for example). Using the declared size makes the
                    -- sprite sample past the end of the image and smear, so the
                    -- real texture size is used instead.
                    local texture_w, texture_h = 0, 0
                    if type(lstg.GetTextureSize) == "function" then
                        local ok, tw, th = pcall(lstg.GetTextureSize, texture)
                        if ok then texture_w, texture_h = tonumber(tw) or 0, tonumber(th) or 0 end
                    end
                    texture_sizes[path] = { texture_w, texture_h }
                    for sprite_index, sprite in ipairs(entry.sprites or {}) do
                        local w, h = sprite.w, sprite.h
                        local x, y = sprite.x, sprite.y
                        -- Clamp a full-texture sprite to the real dimensions.
                        if texture_w > 0 and texture_h > 0 then
                            if x + w > texture_w then w = texture_w - x end
                            if y + h > texture_h then h = texture_h - y end
                        end
                        if w > 0 and h > 0 then
                            pcall(lstg.LoadImage, image_name(archive, entry_index, sprite_index),
                                texture, x, y, w, h, w * 0.5, h * 0.5)
                            loaded = loaded + 1
                        end
                    end
                end
            end
        end
    end
    set_status(previous or "stage")
    return loaded
end

---@param options table { lstg, stage, anm, chunks, difficulty, image_for }
function StageRuntime.new(options)
    local self = setmetatable({
        lstg = options.lstg,
        stage_key = options.stage or "st01",
        anm = options.anm or {},
        chunks = options.chunks or {},
        sprites_loaded = 0,
        frames = 0,
    }, StageRuntime)
    -- Resolve a reference texture path to the image name of its first sprite.
    local function resolve(path)
        for archive, entries in pairs(self.anm) do
            for entry_index, entry in ipairs(entries) do
                if entry.texture == path then
                    return image_name(archive, entry_index, 1)
                end
            end
        end
        return path
    end
    self.image_for = options.image_for or resolve
    self.boss_ui = BossUi.new({ lstg = options.lstg })
    self.background = StageBackground.new({
        lstg = options.lstg, anm = self.anm, std = options.std,
        image_for = self.image_for,
        texture_sizes = options.texture_sizes or StageRuntime.texture_sizes or {},
    })
    self.background:set_stage(self.stage_key)
    self.adapter = Adapter.new({
        lstg = options.lstg,
        anm = self.anm,
        chunks = options.chunks,
        difficulty = options.difficulty,
        boss_ui = self.boss_ui,
    })
    -- The adapter resolves enemy sprites from the stage's own archive.
    self.adapter.enemy_archive_name = STAGE_ARCHIVES[self.stage_key] or "st01enm"
    return self
end

--- Start the stage's main timeline.
function StageRuntime:start()
    local routine = self.stage_key .. ".MainFront"
    local thread = self.adapter.runtime:spawn(routine)
    if not thread then return false end
    self.adapter.runtime.threads[#self.adapter.runtime.threads + 1] = thread
    self.main_thread = thread
    return true
end

function StageRuntime:update()
    self.frames = self.frames + 1
    self.adapter:update()
    self.boss_ui:update()
    self.background:update()
end

--- Draw the stage: background, enemies with their animation, bullets, HUD.
function StageRuntime:draw()
    local lstg = self.lstg
    if not lstg then return end
    self.background:draw()
    self.background:draw_fog()
    -- Everything inside the field is clipped to it, exactly like the reference,
    -- so an enemy entering from above is cut off at the border.
    local left = BossUi.PLAYFIELD_LEFT
    local right = BossUi.PLAYFIELD_RIGHT
    local bottom = BossUi.PLAYFIELD_BOTTOM
    local top = BossUi.PLAYFIELD_TOP
    if type(lstg.SetScissorRect) == "function" then
        pcall(lstg.SetScissorRect, left, right, bottom, top)
    end
    -- Enemies.
    for _, enemy in ipairs(self.adapter.enemies) do
        local player = enemy.legacy_anm
        if player then
            local sprite = player.sprites and player.sprites[player.sprite]
            if sprite then
                local image = self:enemy_image(enemy)
                if image then
                    local x = left + ((enemy.x or 0) + 192) * BossUi.PLAYFIELD_SCALE
                    local y = top - (enemy.y or 0) * BossUi.PLAYFIELD_SCALE
                    local w = sprite.w * BossUi.PLAYFIELD_SCALE
                    local h = sprite.h * BossUi.PLAYFIELD_SCALE
                    local alpha = player.alpha or 255
                    local colour = player.color or { 255, 255, 255 }
                    lstg.SetImageState(image, "",
                        lstg.Color(alpha, colour[1], colour[2], colour[3]))
                    lstg.RenderRect(image, x - w * 0.5, x + w * 0.5, y - h, y)
                end
            end
        end
    end
    -- Bullets.
    for _, shot in ipairs(self.adapter.shots or {}) do
        local image, width, height = self:bullet_image(shot)
        if image then
            local x = left + ((shot.x or 0) + 192) * BossUi.PLAYFIELD_SCALE
            local y = top - (shot.y or 0) * BossUi.PLAYFIELD_SCALE
            -- Draw at the sprite's own size scaled into the field.
            local w = (width or 16) * BossUi.PLAYFIELD_SCALE
            local h = (height or 16) * BossUi.PLAYFIELD_SCALE
            lstg.SetImageState(image, "", lstg.Color(255, 255, 255, 255))
            lstg.RenderRect(image, x - w * 0.5, x + w * 0.5, y - h * 0.5, y + h * 0.5)
        end
    end
    if type(lstg.SetScissorRect) == "function" then
        pcall(lstg.SetScissorRect, 0, 1280, 0, 720)
    end
    self.boss_ui:draw()
    self:draw_hud()
end

--- Draw the right hand status panel, matching the reference layout.
-- Coordinates are converted from the original capture: the labels sit just
-- right of the playfield and the values are right aligned at x=738. Hearts and
-- stars use the front sheet's progressive fill sprites.
function StageRuntime:draw_hud()
    local lstg = self.lstg
    local stats = self.stats or {}
    local label_x = 510
    local value_x = 738
    -- Value column: the score and power rows share their space with the icon
    -- rows, so the icons sit in the gap between the label and the value, and the
    -- value is right aligned at the panel edge.
    local rows = {
        { "ハイスコア", stats.hiscore or 1000000, 665 },
        { "スコア", stats.score or 0, 636 },
        { "残り人数", nil, 596 },
        { "スペルカード", nil, 549 },
        { "霊力", stats.power or 0, 492 },
        { "最大得点", stats.max_point or 0, 465 },
        { "グレイズ", stats.graze or 0, 444 },
    }
    for _, row in ipairs(rows) do
        lstg.RenderTTF("Sans", row[1], label_x, label_x, row[3], row[3], 0,
            lstg.Color(255, 240, 236, 236), 0.8)
        if row[2] ~= nil then
            -- Values right align to the panel edge, clear of the icon row.
            lstg.RenderTTF("Sans", tostring(row[2]), value_x, value_x, row[3], row[3], 2,
                lstg.Color(255, 255, 255, 255), 0.9)
        end
    end
    -- Life hearts and spell card stars, placed between the label and the value
    -- column exactly as the reference lays them out.
    self:draw_life_icons(680, 592, stats.lives or 3, 8, BossUi.HEART_FIRST_SPRITE)
    self:draw_life_icons(680, 545, stats.spellcards or 0, 5, BossUi.STAR_FIRST_SPRITE)
end

--- Draw a row of icon pips, using the six frame fill sprites.
-- `value` may be fractional so a partially filled pip renders as the reference
-- shows it while a life is being collected.
function StageRuntime:draw_life_icons(x, y, value, capacity, first_sprite)
    local lstg = self.lstg
    local icon_w = 20
    local icon_h = 25
    for index = 1, capacity do
        local ratio = math.max(0, math.min(1, (value or 0) - (index - 1)))
        local sprite = BossUi.icon_sprite(first_sprite, ratio)
        local image = image_name("front", BossUi.ICON_SHEET_ENTRY, sprite)
        local left = x + (index - 1) * icon_w
        lstg.SetImageState(image, "", lstg.Color(255, 255, 255, 255))
        lstg.RenderRect(image, left, left + icon_w, y, y + icon_h)
    end
end

--- Resolve the image for an enemy from its animation player.
-- The player records the archive name it was built from, so the sprite can be
-- addressed directly instead of searching by table identity.
function StageRuntime:enemy_image(enemy)
    local player = enemy.legacy_anm
    if not player then return nil end
    local archive = player.archive_name
    local entry_index = player.entry_index or 1
    if not archive then
        archive = STAGE_ARCHIVES[self.stage_key]
    end
    return image_name(archive, entry_index, player.sprite)
end

--- Resolve the bullet image from the bullet archive.
-- The bullet archive keeps several sheets; each etSprite animation maps to a
-- sheet script whose first instruction names the sprite to draw.
--- Resolve the bullet archive entry and script for a shot's animation.
-- Cached per animation id because the walk is otherwise repeated every frame
-- for every bullet on screen.
function StageRuntime:bullet_anim_info(anim)
    self.bullet_anim_cache = self.bullet_anim_cache or {}
    local cached = self.bullet_anim_cache[anim]
    if cached ~= nil then return cached end
    local entries = self.anm.bullet
    local result = nil
    if entries then
        for entry_index, entry in ipairs(entries) do
            local script = entry.scripts and entry.scripts[anim]
            if script then
                result = { entry_index = entry_index, script = script }
                break
            end
        end
    end
    self.bullet_anim_cache[anim] = result
    return result
end

--- Resolve the bullet image for a shot at a point in its life.
-- The animation script is a frame timeline: walk it once to find the sprite due
-- at `frame`, which lets a bullet cycle through its frames like the reference.
function StageRuntime:bullet_image(shot)
    local entries = self.anm.bullet
    if not entries then return nil end
    local anim = shot.anim or 0
    local info = self:bullet_anim_info(anim)
    local entry_index, script
    if info then
        entry_index, script = info.entry_index, info.script
    end
    -- Pick the sprite for the current frame: the last sprite instruction whose
    -- time has passed.
    local frame = shot.anim_frame or 0
    local sprite = nil
    if script then
        for _, instruction in ipairs(script) do
            if (instruction.id == 300 or instruction.id == 304) and instruction[1] then
                if (instruction.time or 0) <= frame then
                    sprite = (tonumber(instruction[1]) or 0) + 1
                else
                    break
                end
            end
        end
        -- A script that only names one sprite keeps it for the whole life.
        if not sprite then
            for _, instruction in ipairs(script) do
                if (instruction.id == 300 or instruction.id == 304) and instruction[1] then
                    sprite = (tonumber(instruction[1]) or 0) + 1
                    break
                end
            end
        end
    end
    if sprite then
        local entry = entries[entry_index]
        local rect = entry and entry.sprites and entry.sprites[sprite]
        return image_name("bullet", entry_index, sprite),
            rect and rect.w or 16, rect and rect.h or 16
    end
    local fallback = entries[1] and entries[1].sprites and entries[1].sprites[1]
    return image_name("bullet", 1, 1),
        fallback and fallback.w or 16, fallback and fallback.h or 16
end

return StageRuntime
