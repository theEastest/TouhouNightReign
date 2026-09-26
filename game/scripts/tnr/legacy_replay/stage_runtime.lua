-- Complete stage runtime for the legacy replay.
--
-- Ties the ECL interpreter, the adapter, the ANM animation and the background
-- into one object a stage owns. This is the piece the roguelike mode drives: it
-- loads a stage's textures and sprites, starts its main timeline, and renders
-- the field the way the reference does.

local Adapter = require("tnr.legacy_replay.adapter")
local AnmPlayer = require("tnr.legacy_replay.anm_player")
local BossUi = require("tnr.legacy_replay.boss_ui")
local HudFont = require("tnr.legacy_replay.hud_font")
local Effects = require("tnr.legacy_replay.effects")
local Palette = require("tnr.legacy_replay.palette")
local StageBackground = require("tnr.legacy_replay.stage_background")
local Player = require("tnr.legacy_replay.player")
local PlayerAnimation = require("tnr.legacy_replay.player_animation")
local Items = require("tnr.legacy_replay.items")
local Interfaces = require("tnr.legacy_replay.interfaces")

local StageRuntime = {}

StageRuntime.__index = StageRuntime

-- Every stage's enemy archive, in stage order.
local STAGE_ARCHIVES = {
    st01 = "st01enm", st02 = "st02enm", st03 = "st03enm", st04 = "st04enm",
    st05 = "st05enm", st06 = "st06enm", st07 = "st07enm",
}

StageRuntime.SECTIONS = { "MainFront", "MainLatter", "MainLatter2" }

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
        -- Player ship sheets for the replay ships.
        "pl00", "pl01", "pl02", "pl03",
    }
    local loaded = 0
    local texture_status = {}
    -- A texture's path may repeat across archive entries (the shared dummy face,
    -- for example) and across archives. Reuse the first texture that loaded a
    -- path instead of skipping the load and then failing to create sprites from
    -- a texture name that was never registered.
    local texture_by_path = {}
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
                local registered = texture_by_path[path]
                if not registered then
                    local texture = image_name(archive, entry_index, 0)
                    local ok = pcall(lstg.LoadTexture, texture, base .. "/" .. path, false)
                    if ok then
                        registered = texture
                        texture_by_path[path] = texture
                    end
                end
                if registered then
                    -- The anm header declares a logical size that can differ
                    -- from the file (a 1024 unit tile backed by a 512 px
                    -- texture, for example). Using the declared size makes the
                    -- sprite sample past the end of the image and smear, so the
                    -- real texture size is used instead.
                    local texture_w, texture_h = 0, 0
                    if type(lstg.GetTextureSize) == "function" then
                        local ok, tw, th = pcall(lstg.GetTextureSize, registered)
                        if ok then texture_w, texture_h = tonumber(tw) or 0, tonumber(th) or 0 end
                    end
                    texture_sizes[path] = texture_sizes[path] or { texture_w, texture_h }
                    for sprite_index, sprite in ipairs(entry.sprites or {}) do
                        local w, h = sprite.w, sprite.h
                        local x, y = sprite.x, sprite.y
                        -- Clamp a full-texture sprite to the real dimensions.
                        if texture_w > 0 and texture_h > 0 then
                            if x + w > texture_w then w = texture_w - x end
                            if y + h > texture_h then h = texture_h - y end
                        end
                        if w > 0 and h > 0 then
                            -- A shared texture may already have this sprite, so
                            -- the create is best effort.
                            pcall(lstg.LoadImage, image_name(archive, entry_index, sprite_index),
                                registered, x, y, w, h, w * 0.5, h * 0.5)
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
    -- Session, player and items. The session owns the mode and roster so the
    -- same stage code serves solo and co-op, classic and modern.
    self.session = options.session or Interfaces.ReplaySession.new({})
    self.sht = options.sht
    self.players = {}
    self.items = Items.new({})
    self.effects = Effects.new({ anm = self.anm })
    self:create_players(options.character or "reimu")
    return self
end

--- Create the player ships for the session's roster.
-- Each player gets a ship built from its character's sht definition, so co-op
-- can mix characters the way the reference does.
function StageRuntime:create_players(character)
    local definition = self.sht and self.sht[character]
    if not definition then
        -- A character without sht data still gets a ship from the reference
        -- defaults so the stage remains playable.
        definition = { hitbox = 2, grazebox = 6, itembox = 28,
            move_unfocused = 4.5, move_focused = 2.0, power_levels = 4 }
    end
    -- Remember which player sheet to draw this ship and its options from.
    local character_index = { reimu = 0, marisa = 1, sanae = 2, reisen = 3 }
    local index = character_index[character] or 0
    self.primary_player_archive = string.format("pl%02d", index)
    self.player_animation = self.player_animation or
        PlayerAnimation.new(self.anm[self.primary_player_archive][1], self.primary_player_archive)
    for _, player_id in ipairs(self.session.roster:list()) do
        local player = Player.new({
            definition = definition,
            -- Spread co-op players either side of centre.
            x = self.session.roster:is_coop() and (player_id == 1 and -48 or 48) or 0,
        })
        player.player_id = player_id
        self.players[player_id] = player
    end
    self.items.player = self.players[self.session.roster:list()[1]]
    return self.players
end

--- Push a frame of input for a player and fire if the shot button is held.
function StageRuntime:apply_input(player_id, input)
    local player = self.players[player_id]
    if not player or not player.alive then return end
    player:move(input.move_x, input.move_y, input.focus)
    player:update()
    -- Drive the ship animation from the same input the movement used.
    if self.player_animation then self.player_animation:update(input) end
    if input.shoot then
        local bullets = player:fire()
        for _, bullet in ipairs(bullets) do
            self.adapter.shots = self.adapter.shots or {}
            if #self.adapter.shots < 8192 then
                self.adapter.shots[#self.adapter.shots + 1] = {
                    x = bullet.x, y = bullet.y, speed = bullet.speed,
                    angle = bullet.angle, anim = bullet.animation,
                    vx = math.cos(bullet.angle) * bullet.speed,
                    vy = math.sin(bullet.angle) * bullet.speed,
                    player_bullet = true, damage = bullet.damage,
                }
            end
        end
    end
end

--- Sample every player's input source for this frame.
function StageRuntime:sample_inputs()
    for _, player_id in ipairs(self.session.roster:list()) do
        self:apply_input(player_id, self.session.roster:sample(player_id))
    end
end

--- Start the stage's main timeline.
--- Resolve enemy bullets and enemy bodies against the players.
-- A hit costs a life, clears the nearby bullets and briefly invulnerates the
-- ship, which is the reference behaviour.
function StageRuntime:resolve_player_hits()
    local shots = self.adapter.shots
    if not shots then return end
    for _, player_id in ipairs(self.session.roster:list()) do
        local player = self.players[player_id]
        if player and player.alive and player.invulnerable <= 0 then
            local hit = false
            -- Enemy bullets.
            for index = #shots, 1, -1 do
                local shot = shots[index]
                if not shot.player_bullet and player:hits(shot.x or 0, shot.y or 0) then
                    hit = true
                    table.remove(shots, index)
                elseif not shot.player_bullet and player:grazes(shot.x or 0, shot.y or 0) then
                    -- Grazing is counted but does not cost a life.
                    player.graze = (player.graze or 0) + 1
                end
            end
            -- Enemy bodies.
            if not hit then
                for _, enemy in ipairs(self.adapter.enemies) do
                    if enemy.hp and enemy.hp > 0 then
                        local box = enemy.legacy_hurtbox
                        local radius = 24
                        if box then
                            radius = math.max(tonumber(box[1]) or 0, tonumber(box[2]) or 0)
                        end
                        if radius <= 0 then radius = 20 end
                        local dx = (enemy.x or 0) - player.x
                        local dy = (enemy.y or 0) - player.y
                        if dx * dx + dy * dy <= radius * radius then hit = true break end
                    end
                end
            end
            if hit then self:on_player_hit(player_id, player) end
        end
    end
end

--- Apply the consequences of a player being hit.
function StageRuntime:on_player_hit(player_id, player)
    player:hit()
    self.session.mode:on_player_hit(self.session, player_id)
    self.session:lose_life(player_id)
    -- Clear the bullets around the player so respawning is survivable.
    local kept = {}
    for _, shot in ipairs(self.adapter.shots or {}) do
        if shot.player_bullet then
            kept[#kept + 1] = shot
        else
            local dx = (shot.x or 0) - player.x
            local dy = (shot.y or 0) - player.y
            if dx * dx + dy * dy > 200 * 200 then kept[#kept + 1] = shot end
        end
    end
    self.adapter.shots = kept
    -- Put the ship back in play shortly after the hit.
    self.pending_respawn = self.pending_respawn or {}
    self.pending_respawn[#self.pending_respawn + 1] = { player_id = player_id, frames = 40 }
    self.on_player_death = true
end

--- Bring any pending respawns back into play.
function StageRuntime:advance_respawns()
    local pending = self.pending_respawn
    if not pending or #pending == 0 then return end
    local remaining = {}
    for _, entry in ipairs(pending) do
        entry.frames = entry.frames - 1
        if entry.frames <= 0 then
            local player = self.players[entry.player_id]
            if player then
                player:respawn(0, 300)
                player.graze = player.graze or 0
            end
        else
            remaining[#remaining + 1] = entry
        end
    end
    self.pending_respawn = remaining
end

--- Resolve player shot hits against enemies.
-- A shot is consumed on contact and applies its damage. The mode is notified so
-- a classic run can award power on each hit.
function StageRuntime:resolve_player_damage()
    local shots = self.adapter.shots
    if not shots then return end
    local kept = {}
    for _, shot in ipairs(shots) do
        local hit = false
        if shot.player_bullet and shot.damage then
            for _, enemy in ipairs(self.adapter.enemies) do
                if not enemy.legacy_dropped and enemy.hp and enemy.hp > 0 then
                    -- The hurtbox is stored as half widths, so the collision
                    -- radius is the larger dimension.
                    local box = enemy.legacy_hurtbox
                    local radius = 24
                    if box then
                        radius = math.max(tonumber(box[1]) or 0, tonumber(box[2]) or 0)
                    end
                    if radius <= 0 then radius = 24 end
                    local dx, dy = shot.x - (enemy.x or 0), shot.y - (enemy.y or 0)
                    if dx * dx + dy * dy <= radius * radius then
                        enemy.hp = enemy.hp - shot.damage
                        hit = true
                        local owner = self.items.player
                        self.session.mode:on_hit(self.session,
                            owner and owner.player_id or 1, enemy, shot.damage)
                        break
                    end
                end
            end
        end
        if not hit then kept[#kept + 1] = shot end
    end
    self.adapter.shots = kept
end

--- Start the stage's opening timeline.
function StageRuntime:start()
    self.section_index = 0
    self.timeline_done = false
    return self:advance_section()
end

--- True when the stage's timeline has finished every section.
-- The reference treats the stage as clear once the last section returns,
-- which happens after the boss script completes.
function StageRuntime:timeline_finished()
    return self.timeline_done == true
end

--- Start the next timeline section. Returns false when there are none left.
-- The reference engine chains the sections: the opening waves, then the
-- mid-boss section, then the boss section. Each starts once the previous one
-- returns, which is how the mid-boss and boss enter the stage.
function StageRuntime:advance_section()
    local index = (self.section_index or 0) + 1
    local name = StageRuntime.SECTIONS[index]
    if not name then
        self.timeline_done = true
        return false
    end
    local routine = self.stage_key .. "." .. name
    local thread = self.adapter.runtime:spawn(routine)
    if not thread or not self.adapter.runtime.chunks[thread.routine] then
        -- A stage without this section simply moves on.
        self.section_index = index
        return self:advance_section()
    end
    self.adapter.runtime.threads[#self.adapter.runtime.threads + 1] = thread
    self.section_index = index
    self.section_thread = thread
    self.section_name = name
    -- Remember when the section started so a stalled section can be detected.
    self.section_started = self.frames or 0
    return true
end

--- Chain the next section once the current one finishes.
function StageRuntime:_advance_timeline()
    if self.timeline_done then return end
    local thread = self.section_thread
    if not thread then return end
    if thread.state ~= "finished" then return end
    if self.section_name ~= StageRuntime.SECTIONS[self.section_index] then return end
    self.section_thread = nil
    if not self:advance_section() then
        self.timeline_done = true
        self.on_clear = true
    end
end

function StageRuntime:update()
    self.frames = self.frames + 1
    self:sample_inputs()
    self.adapter:update()
    self.boss_ui:update()
    self.background:update()
    -- Chain to the next timeline section once the current one returns.
    self:_advance_timeline()
    -- Player shots damage enemies they touch, which is what makes drops and
    -- scoring happen. This runs before the drop check so an enemy killed this
    -- frame drops on the same frame.
    self:resolve_player_damage()
    -- Enemy bullets hit the player, which costs a life.
    self:resolve_player_hits()
    self:advance_respawns()
    -- An enemy that dies drops its reference drop table.
    for _, enemy in ipairs(self.adapter.enemies) do
        if enemy.hp and enemy.hp <= 0 and not enemy.legacy_dropped then
            enemy.legacy_dropped = true
            self.effects:spawn(Effects.KIND.ENEMY_DEATH, enemy.x or 0, enemy.y or 0)
            if enemy.legacy_drop and enemy.legacy_drop > 0 then
                self.items:spawn_drop({ enemy.legacy_drop, 0, 2 }, enemy.x or 0, enemy.y or 0)
            end
        end
    end
    self.items:update()
    self.effects:update()
    -- Collected items feed the mode, which decides what they are worth, and
    -- score by the point rate the way the reference does.
    for _, item in ipairs(self.items:drain_collected()) do
        local owner = self.items.player
        if owner then
            self.session.mode:on_item_collected(self.session, owner.player_id, item)
            if item.kind == "point" then
                local stats = self.stats or {}
                self.stats = stats
                stats.score = (stats.score or 0) + (self.point_rate or 10000)
                self.point_rate = math.min(100000, (self.point_rate or 10000) + 10)
            end
        end
    end
    -- Score extends: the classic ruleset grants a life at each threshold.
    local stats = self.stats
    if stats and self.session.mode.on_score_changed then
        for _, player_id in ipairs(self.session.roster:list()) do
            self.session.mode:on_score_changed(self.session, player_id, stats.score or 0)
        end
    end
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
            -- The colour index tints the sprite. Player shots are drawn without
            -- a tint so they keep their own colours.
            local tint
            if shot.player_bullet then
                tint = lstg.Color(255, 255, 255, 255)
            else
                local c = Palette.unpack(Palette.tint(shot.color_index or 27, true))
                tint = lstg.Color(c.a, c.r, c.g, c.b)
            end
            local blend = shot.blend or ""
            lstg.SetImageState(image, blend, tint)
            lstg.RenderRect(image, x - w * 0.5, x + w * 0.5, y - h * 0.5, y + h * 0.5)
        end
    end
    -- Effects: the death burst and bullet break animations, drawn under the
    -- items so the pickups stay readable.
    for _, effect in ipairs(self.effects.list) do
        local sprite, alpha = self.effects:sprite_for(effect)
        local image = image_name("effect", effect.entry, sprite)
        local x = left + ((effect.x or 0) + 192) * BossUi.PLAYFIELD_SCALE
        local y = top - (effect.y or 0) * BossUi.PLAYFIELD_SCALE
        local r = 24 * (effect.scale or 1) * BossUi.PLAYFIELD_SCALE
        lstg.SetImageState(image, "add+add", lstg.Color(alpha, 255, 255, 255))
        lstg.RenderRect(image, x - r, x + r, y - r, y + r)
    end
    -- Items.
    for _, item in ipairs(self.items.list) do
        local image = self:item_image(item)
        if image then
            local x = left + ((item.x or 0) + 192) * BossUi.PLAYFIELD_SCALE
            local y = top - (item.y or 0) * BossUi.PLAYFIELD_SCALE
            local r = 10 * BossUi.PLAYFIELD_SCALE
            lstg.SetImageState(image, "", lstg.Color(255, 255, 255, 255))
            lstg.RenderRect(image, x - r, x + r, y - r, y + r)
        end
    end
    -- Player ships.
    for _, player_id in ipairs(self.session.roster:list()) do
        local player = self.players[player_id]
        if player and player.alive then
            local left_x = left + ((player.x or 0) + 192) * BossUi.PLAYFIELD_SCALE
            local top_y = top - (player.y or 0) * BossUi.PLAYFIELD_SCALE
            -- Option sub-ships sit at the positions the sht data gives for the
            -- current focus state and power level.
            local option_image = image_name(self.primary_player_archive or "pl00", 1, 34)
            for _, offset in ipairs(player:option_positions()) do
                local ox = left_x + (offset[1] or 0) * BossUi.PLAYFIELD_SCALE
                local oy = top_y - (offset[2] or 0) * BossUi.PLAYFIELD_SCALE
                local r = 8 * BossUi.PLAYFIELD_SCALE
                lstg.SetImageState(option_image, "", lstg.Color(255, 255, 255, 255))
                lstg.RenderRect(option_image, ox - r, ox + r, oy - r, oy + r)
            end
            local image = self:player_image(player)
            if image then
                local w = 32 * BossUi.PLAYFIELD_SCALE
                local h = 48 * BossUi.PLAYFIELD_SCALE
                lstg.SetImageState(image, "", lstg.Color(255, 255, 255, 255))
                lstg.RenderRect(image, left_x - w * 0.5, left_x + w * 0.5, top_y - h, top_y)
            end
        end
    end
    if type(lstg.SetScissorRect) == "function" then
        pcall(lstg.SetScissorRect, 0, 1280, 0, 720)
    end
    self.boss_ui:draw()
    self:draw_hud()
end

--- Resolve the image for an item from the item sheet.
function StageRuntime:item_image(item)
    -- The item sheet is the entry whose texture ends in item.png.
    self.item_entry = self.item_entry or self:find_entry_by_texture("item.png")
    if not self.item_entry then return nil end
    return image_name("bullet", self.item_entry.index, self.item_entry.first_sprite)
end

--- Resolve the image for a player ship from its current animation frame.
function StageRuntime:player_image(player)
    local sheet = self.primary_player_archive or "pl00"
    local sprite = self.player_animation and self.player_animation:sprite_index() or 1
    return image_name(sheet, 1, sprite)
end

--- Find the bullet archive entry whose texture path ends with `suffix`.
function StageRuntime:find_entry_by_texture(suffix)
    for entry_index, entry in ipairs(self.anm.bullet or {}) do
        if entry.texture and entry.texture:sub(-#suffix) == suffix then
            return { index = entry_index, first_sprite = 1 }
        end
    end
    return nil
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
            -- Numbers use the reference ascii glyphs, right aligned.
            self:draw_number(row[2], value_x, row[3])
        end
    end
    -- Life hearts and spell card stars, placed between the label and the value
    -- column exactly as the reference lays them out.
    self:draw_life_icons(680, 592, stats.lives or 3, 8, BossUi.HEART_FIRST_SPRITE)
    self:draw_life_icons(680, 545, stats.spellcards or 0, 5, BossUi.STAR_FIRST_SPRITE)
end

--- Draw a number using the reference ascii glyphs, right aligned at `right_x`.
-- The ascii sheet lays its glyphs out from ASCII 33, eighteen per row, at 14px,
-- so a character's sprite is its code minus 32.
function StageRuntime:draw_number(value, right_x, y)
    local lstg = self.lstg
    local text = tostring(value)
    local draws, width = HudFont.layout(text, { advance = 16 })
    local x = right_x - width
    for _, glyph in ipairs(draws) do
        local image = image_name("ascii", 1, glyph.sprite)
        local left = x + glyph.x
        lstg.SetImageState(image, "", lstg.Color(255, 255, 255, 255))
        lstg.RenderRect(image, left, left + 18, y, y + 20)
    end
end

--- Draw a row of icon pips, using the six frame fill sprites.
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
    -- The sprite family selects which sheet script to play; the colour index
    -- only tints the shape.
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
