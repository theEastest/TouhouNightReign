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
local Sounds = require("tnr.legacy_replay.sounds")
local PlayerAnimation = require("tnr.legacy_replay.player_animation")
local Items = require("tnr.legacy_replay.items")
local Interfaces = require("tnr.legacy_replay.interfaces")
local BulletTypes = require("tnr.legacy_replay.data.th15_bullet_types")
local Dialogue = require("tnr.legacy_replay.dialogue")
local AnmGeometry = require("tnr.legacy_replay.anm_geometry")
local Rules = require("tnr.legacy_replay.reference_rules")
local ClassicBombs = require("tnr.legacy_replay.classic_bombs")
local ClassicShots = require("tnr.legacy_replay.classic_shots")

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

local function global_image(anm,name,index)
    for i,entry in ipairs(anm[name] or {}) do
        if index<=#entry.sprites then return image_name(name,i,index),entry.sprites[index] end
        index=index-#entry.sprites
    end
end

--- Read the sprite an animation instruction names, or nil when it names none.
-- Opcodes 300 and 304 name a frame, and 500 names a sprite index outright.
-- A negative argument means "keep the current sprite", so it is not a frame.
local function sprite_from_instruction(instruction)
    local id = instruction.id
    local value = instruction[1]
    if id == 500 then
        local index = tonumber(value)
        if index and index >= 0 then return index + 1 end
        return nil
    end
    -- 304 selects a render layer. Treating its layer number as a sprite index
    -- turns ANM 603's sprite-less 8x8 projectile into atlas sprite 24.
    if id ~= 300 then return nil end
    local index = tonumber(value)
    if not index or index < 0 then return nil end
    return index + 1
end

--- Load every texture and sprite rect the stage needs into the engine.
-- Returns the number of images registered.
function StageRuntime.load_stage_assets(lstg, stage_key, anm, options)
    options = options or {}
    local base = options.asset_root or "assets/legacy_replay"
    local archives = {
        STAGE_ARCHIVES[stage_key],
        stage_key .. "wl",
        stage_key .. "logo",
        stage_key .. "bs",
        stage_key .. "mbs",
        stage_key .. "mbs2",
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
    if lstg.LoadTexture and lstg.LoadImage then
        lstg.LoadTexture("tnr-replay-coin","assets/items/coin_sheet.png",false)
        for i=1,5 do lstg.LoadImage("tnr-replay-coin-"..i,"tnr-replay-coin",(i-1)*32,0,32,32) end
    end
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
                    entry.loaded_texture=registered
                    for sprite_index, sprite in ipairs(entry.sprites or {}) do
                        local w, h = sprite.w, sprite.h
                        local x, y = sprite.x + (entry.offset_x or 0), sprite.y + (entry.offset_y or 0)
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
        texture_sizes = options.texture_sizes or StageRuntime.texture_sizes or {},
        chunks = options.chunks or {},
        sprites_loaded = 0,
        frames = 0,
        time_scale = 1,
        time_accumulator = 0,
        chapter = 0,
        capture_frame = tonumber(os.getenv("TNR_REPLAY_CAPTURE_FRAME")),
        point_rate = 10000,
        character = options.character or "reimu",
        characters = options.characters,
        local_player_id = options.local_player_id or 1,
        networked = options.networked,
        loadouts = options.loadouts,
    }, StageRuntime)
    -- Resolve a reference texture path to the image name of its first sprite.
    local function resolve(path)
        local archives={self.stage_key.."wl",STAGE_ARCHIVES[self.stage_key],self.stage_key.."logo",
            self.stage_key.."bs",self.stage_key.."mbs",self.stage_key.."mbs2","enemy","bullet","effect","front","ascii","pl00","pl01","pl02","pl03"}
        for _,archive in ipairs(archives) do
            local entries=self.anm[archive] or {}
            for entry_index, entry in ipairs(entries) do
                if entry.texture == path then
                    return image_name(archive, entry_index, 1)
                end
            end
        end
        return nil
    end
    self.image_for = options.image_for or resolve
    local stage_number = tonumber(self.stage_key:match("^st(%d+)$"))
    local lifebar
    for _, entry in ipairs(self.anm.front or {}) do
        if entry.texture == "front/lifebar.png" then lifebar=entry; break end
    end
    self.boss_ui = BossUi.new({ lstg = options.lstg, lifebar = lifebar,
        name_image = stage_number and global_image(self.anm,"front",102+stage_number),
        star_image = global_image(self.anm,"front",BossUi.icon_sprite(BossUi.STAR_FIRST_SPRITE,1)),
    })
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
        stage_key = self.stage_key,
        enemy_hp_multiplier = options.enemy_hp_multiplier,
        seed = options.seed,
        random = options.random,
    })
    self.adapter.on_game_speed=function(scale) self.time_scale=scale end
    self.adapter.on_chapter=function(chapter)
        self.pending_chapter=chapter
    end
    -- Sound effects come from the same audio manager the rest of the game uses,
    -- so a replay does not ship with a second mixer. The adapter only knows the
    -- reference's numeric effect ids, so the translation happens here.
    self.audio = options.audio
    self.sound_paths = self.sound_paths or {}
    self.adapter.on_sound = function(path, volume)
        self.played_sounds = self.played_sounds or {}
        self.played_sounds[#self.played_sounds + 1] = path
        if self.audio and self.audio.play_effect then
            self.audio:play_effect(path, volume)
        end
    end
    -- The adapter resolves enemy sprites from the stage's own archive.
    self.adapter.enemy_archive_name = STAGE_ARCHIVES[self.stage_key] or "st01enm"
    -- Session, player and items. The session owns the mode and roster so the
    -- same stage code serves solo and co-op, classic and modern.
    self.session = options.session or Interfaces.ReplaySession.new({})
    self.sht = options.sht
    self.players = {}
    -- Original drop scatter and graze rewards use 0x4e9a48, the same RNG as
    -- ECL and enemy bullets. Item jitter uses a separate visual RNG.
    self.items = Items.new({random=options.item_random or self.adapter.random})
    self.adapter.on_enemy_drop=function(enemy,explicit) self:drop_enemy_items(enemy,explicit) end
    self.adapter.on_cancel_item=function(x,y) self.items:spawn_launched("cancel",x,y) end
    if self.session:mode_id()=="classic" then
        self.adapter.on_player_shots_advanced = function()
            self.classic_shot_sources = self:player_damage_sources()
        end
        self.adapter.on_enemy_step = function(enemy)
            self:resolve_enemy_shots(enemy, self.classic_shot_sources)
            self.adapter:apply_pending_damage(enemy)
            self.adapter:advance_enemy_interrupts(enemy)
            self:check_enemy_defeat(enemy)
        end
    end
    self.effects = Effects.new({ anm = self.anm })
    self:create_players(options.character or "reimu")
    self.adapter.players=self.players
    if self.session:is_coop() then self.coop=require("tnr.legacy_replay.coop").new(self) end
    if self.session:mode_id() == "modern" then
        self.modern = require("tnr.legacy_replay.modern_combat").new(self, options.equipment_session)
    end
    self.adapter.player = self.players[self.session.roster:list()[1]]
    local scenario = ({reimu = "a", marisa = "b", sanae = "c", reisen = "d"})[options.character or "reimu"]
    local msg = options.msg or require("tnr.legacy_replay.data.th15_msg")
    local script = msg[self.stage_key .. scenario]
    if script then
        self.dialogue = Dialogue.new({data = script, on_event = function(kind, value)
            if kind == "stage_end" then
                self.adapter.stage_ending_requested = true
            end
            if kind == "boss_music" and self.audio and self.audio.play_replay_bgm then
                self.audio:play_replay_bgm(self.stage_key .. "boss")
            end
        end})
        self.adapter.dialogue = self.dialogue
    end
    return self
end

--- Create the player ships for the session's roster.
-- Each player gets a ship built from its character's sht definition, so co-op
-- can mix characters the way the reference does.
function StageRuntime:create_players(character)
    local character_index = { reimu = 0, marisa = 1, sanae = 2, reisen = 3 }
    for _, player_id in ipairs(self.session.roster:list()) do
    local character=self.characters and self.characters[player_id] or character
    local definition = self.sht and self.sht[character]
    if not definition then
        -- A character without sht data still gets a ship from the reference
        -- defaults so the stage remains playable.
        definition = { hitbox = 2, grazebox = 6, itembox = 28,
            move_unfocused = 4.5, move_focused = 2.0, power_levels = 4 }
    end
    -- Remember which player sheet to draw this ship and its options from.
    local index = character_index[character] or 0
    local archive=string.format("pl%02d",index)
        local player = Player.new({
            definition = definition,
            power = math.min(400, self.session:get_power(player_id) * 100),
            -- Spread co-op players either side of centre.
            x = self.session.roster:is_coop() and (player_id == 1 and -48 or 48) or 0,
        })
        player.player_id = player_id
        player.archive=archive
        player.hitbox_half=player.hitbox/2
        player.animation=PlayerAnimation.new(self.anm[archive][1],archive)
        self.players[player_id] = player
    end
    local primary=self.players[self.local_player_id] or self.players[1]
    self.primary_player_archive=primary.archive
    self.player_animation=primary.animation
    self.items.player = self.players[self.session.roster:list()[1]]
    self.items.players=self.session:is_coop() and self.players or nil
    return self.players
end

--- Push a frame of input for a player and fire if the shot button is held.
--- Play a reference sound by its index.
-- The tone table lives in sounds.lua; this only forwards to the audio manager
-- so the stage code can name effects the way the ECL does.
function StageRuntime:play_sound(index, volume)
    if not self.audio or not self.audio.play_effect then return end
    local path = Sounds.path_for(index)
    if not path then return end
    pcall(function() self.audio:play_effect(path, volume) end)
end

--- Push a frame of input for a player and fire if the shot button is held.
function StageRuntime:apply_input(player_id, input)
    local player = self.players[player_id]
    if not player or not player.alive then return end
    local bomb_pressed=input.bomb and not player.bomb_down
    player.bomb_down=input.bomb==true
    if player.deathbomb_frames then
        player.deathbomb_frames=player.deathbomb_frames-1
        -- The native miss clock freezes input for one final frame after the
        -- Bomb window closes, then spends the life on the following frame.
        if player.deathbomb_frames<0 then
            self:on_player_hit(player_id,player)
        elseif player.deathbomb_frames>0 and bomb_pressed then
            self:use_bomb(player_id)
        end
        return
    end
    if player.respawn_frames then
        player.respawn_frames=player.respawn_frames-1
        local elapsed=60-player.respawn_frames
        -- 454a9d: 80 units of ascent over 60 frames, at 1/128 precision.
        player.y=480-math.floor(elapsed*10240/60)/128
        if player.respawn_frames>0 then
            player:update()
            if player.invulnerable<=0 then player.classic_miss_protection=nil end
            if player.animation then player.animation:update({}) end
            return
        end
        player.respawn_frames=nil
    end
    player:move(input.move_x, input.move_y, input.focus, ClassicBombs.master_spark(player) and .2 or 1)
    player:update()
    if player.invulnerable<=0 then player.classic_miss_protection=nil end
    -- Drive the ship animation from the same input the movement used.
    if player.animation then player.animation:update(input) end
    if bomb_pressed then self:use_bomb(player_id) end
    if self.modern then self.modern:input(player_id,input); return end
    -- 4557d4 enables the original trigger on frame 20. Movement is already
    -- available during this opening interval.
    local can_fire = self.frames >= 20 and not ClassicBombs.master_spark(player)
        and not (self.dialogue and self.dialogue.active)
    for _,shot in ipairs(self.adapter.shots or {}) do
        if shot.beam_length and shot.owner_player_id==player_id then
            shot.x,shot.y=player.x+shot.beam_offset_x,player.y+shot.beam_offset_y
            if not can_fire then shot.deleted=true end
        end
    end
    if can_fire then
        local bullets = player:fire(input.shoot == true)
        if #bullets > 0 then self:play_sound(0) end
        for index, bullet in ipairs(bullets) do
            self.adapter.shots = self.adapter.shots or {}
            if #self.adapter.shots < 8192 then
                self.adapter.shots[#self.adapter.shots + 1] = {
                    x = bullet.x, y = bullet.y, speed = bullet.speed,
                    angle = bullet.angle, anim = bullet.animation,
                    vx = math.cos(bullet.angle) * bullet.speed,
                    vy = math.sin(bullet.angle) * bullet.speed,
                    player_bullet = true, damage = bullet.damage,
                    owner_player_id = player_id, radius = bullet.radius, callback_tick = bullet.callback_tick,
                    player_animation = ClassicShots.animation(self.anm[player.archive], player.archive, bullet.animation,
                        self.frames * 512 + player_id * 128 + index),
                    hitbox_x = bullet.hitbox_x, hitbox_y = bullet.hitbox_y,
                    just_fired = true,
                    beam_length = bullet.beam_length, lifetime = bullet.lifetime,
                    beam_offset_x = bullet.x-player.x, beam_offset_y = bullet.y-player.y,
                    beam_hits = bullet.beam_length and {} or nil,
                }
            end
        end
    else player:stop_firing() end
end

-- Bombs use the same damage/interrupt path as shots. One press spends one
-- resource; holding the key never consumes a second bomb after the effect ends.
function StageRuntime:use_bomb(player_id)
    local p = self.players[player_id]
    if not p or not p.alive or p.classic_bomb or (p.bomb_frames or 0) > 0
        or (self.dialogue and self.dialogue.active)
        or self.session:bomb_count(player_id)<=0 then return false end
    self.session:spend_bomb(player_id)
    if self.adapter.boss_object then self.adapter.boss_object.legacy_spell_failed=true end
    p.deathbomb_frames=nil
    if self.session:mode_id()=="classic" then
        -- 456799 switches native player state to 1 when Bomb starts.
        p.classic_miss_protection=nil
        ClassicBombs.begin(self,p)
        return true
    end
    p.bomb_frames, p.invulnerable = 240, 300
    if p.combat_runtime then p.combat_runtime.affixes:bomb() end
    self:play_sound(15)
    return true
end

function StageRuntime:update_bombs()
    if self.session:mode_id()=="classic" then
        for _,id in ipairs(self.session.roster:list()) do ClassicBombs.update(self,self.players[id]) end
        ClassicBombs.update_blasts(self)
        return
    end
    for _,id in ipairs(self.session.roster:list()) do
        local p = self.players[id]
        if (p.bomb_frames or 0) > 0 then
            p.bomb_frames = p.bomb_frames - 1
            local kept = {}
            for _, shot in ipairs(self.adapter.shots or {}) do
                if shot.player_bullet or (shot.bomb_invulnerable or 0)>0 then kept[#kept + 1] = shot end
            end
            self.adapter.shots = kept
            if p.bomb_frames % 6 == 0 then
                self.effects:spawn(Effects.KIND.BULLET_BREAK, p.x, p.y)
                for _, enemy in ipairs(self.adapter.enemies) do
                    if (enemy.hp or 0) > 0 and not enemy.legacy_deleted and not enemy.legacy_no_damage
                        and (enemy.legacy_invulnerable_until or 0) <= (self.adapter.frame or 0) then
                        self.adapter:damage_enemy(enemy,40)
                        if self.coop then self.coop.aggro:record(id,40) end
                    end
                end
            end
        end
    end
end

function StageRuntime:drop_enemy_items(enemy, explicit)
    if enemy.legacy_dropped and not explicit then return end
    local kinds={[1]="power",[2]="point",[3]="power_large",[4]="life_piece",
        [5]="life",[6]="bomb_piece",[7]="bomb",[8]="full_power"}
    local counts=enemy.legacy_drop_extra or {}
    local main=enemy.legacy_drop or 0
    local n=0
    if kinds[main] then
        self.items:spawn(kinds[main],enemy.x or 0,enemy.y or 0);n=1
    end
    -- 424ee0: random initial angle, elliptical area (default 32x32), radius
    -- factor 0.5..1; successive drops turn by 90 degrees plus +/-45 degrees.
    local float32=Rules.float32
    local pi=float32(math.pi)
    local quarter_turn=float32(math.pi/2)
    local full_turn=float32(2*math.pi)
    local angle=self.items.random(-math.pi,math.pi)
    local area=enemy.legacy_drop_area or {32,32}
    for kind=1,8 do
        for _=1,math.max(0,counts[kind] or 0) do
            n=n+1
            local radius=float32(self.items.random(.5,1))
            local dx=float32(float32(math.cos(angle)*area[1])*radius)
            local dy=float32(float32(math.sin(angle)*area[2])*radius)
            self.items:spawn(kinds[kind],float32((enemy.x or 0)+dx),float32((enemy.y or 0)+dy))
            angle=float32(float32(angle+quarter_turn)+self.items.random(-math.pi/4,math.pi/4))
            if angle>pi then angle=float32(angle-full_turn) end
            if angle<-pi then angle=float32(angle+full_turn) end
        end
    end
    -- Both dropItems and the death handler consume the main and extra items.
    enemy.legacy_drop,enemy.legacy_drop_extra=0,{}
    if self.modern and n>0 then self.items:spawn("money",enemy.x or 0,enemy.y or 0) end
    if not explicit then
        enemy.legacy_dropped=true
        self.adapter:credit_chapter_target(enemy)
        self:play_sound(1)
        self.effects:spawn(Effects.KIND.ENEMY_DEATH, enemy.x or 0, enemy.y or 0)
        -- 428d26..428e03 emits items before running the death subroutine.
        if not enemy.legacy_is_boss and (enemy.hp or 1)<=0 then
            self.adapter:run_death_routine(enemy)
        end
    end
end

function StageRuntime:check_enemy_defeat(enemy)
    if (enemy.hp or 1) <= 0 and not enemy.legacy_deleted and not enemy.legacy_dropped
        and not enemy.legacy_pending_interrupt then
        self:drop_enemy_items(enemy)
    end
end

--- Sample every player's input source for this frame.
function StageRuntime:sample_inputs()
    local dialogue_input = {}
    for _, player_id in ipairs(self.session.roster:list()) do
        local input = self.session.roster:sample(player_id)
        dialogue_input.shoot = dialogue_input.shoot or input.shoot
        dialogue_input.confirm = dialogue_input.confirm or input.confirm
        dialogue_input.skip_dialogue = dialogue_input.skip_dialogue or input.skip_dialogue
        self:apply_input(player_id, input)
    end
    self.dialogue_input = dialogue_input
end

function StageRuntime:raise_point_value(player,count)
    local cap=self.adapter.difficulty==0 and 250000 or 500000
    local rate=self.session:is_coop() and (player.point_rate or 10000) or self.point_rate or 10000
    player.point_rate=math.min(cap,rate+count)
    if not self.session:is_coop() then self.point_rate=player.point_rate end
end

function StageRuntime:add_graze(player_id,count)
    local player=self.players[player_id]
    if not player or count<=0 then return end
    player.graze=math.min(99999999,(player.graze or 0)+count)
    player.chapter_graze=(player.chapter_graze or 0)+count
    -- 4573df adds one displayed point to the maximum point value.
    self:raise_point_value(player,count)
end

function StageRuntime:add_score(player,amount)
    self.stats=self.stats or {}
    self.stats.score=(self.stats.score or 0)+amount
    player.score=(player.score or 0)+amount
end

function StageRuntime:grant_fragment(player, kind)
    local session = self.session
    if kind == "life_piece" and session:mode_id() == "classic" and session:life_count(player.player_id) >= 8 then
        if session.party then session.party.life_fragments = 0 else player.life_piece = 0 end
        kind = "bomb_piece"
    end
    if session.party and kind == "life_piece" then
        session.party:add_life_fragments(1)
    elseif session.party then
        session.bomb_fragments=(session.bomb_fragments or 0)+1
        if session.bomb_fragments>=5 then
            session.bomb_fragments=session.bomb_fragments-5
            session:add_bomb(player.player_id,1)
        end
    else
        local threshold = kind == "life_piece" and 3 or 5
        player[kind] = (player[kind] or 0) + 1
        if player[kind] >= threshold then
            player[kind] = player[kind] - threshold
            if kind == "life_piece" then session:add_life(player.player_id,1)
            else session:add_bomb(player.player_id,1) end
        end
    end
end

function StageRuntime:finish_chapter()
    local next_chapter = self.pending_chapter
    if next_chapter == nil then return end
    local adapter = self.adapter
    local threshold = self.session.mode:score_extend_threshold()
    local score_chapter = threshold and next_chapter ~= 0 and adapter.chapter_targets > 0
    local ratio = score_chapter and Rules.float32(Rules.float32(adapter.chapter_defeated / adapter.chapter_targets) * 100) or 0
    local total = 0
    local ids = self.session.roster:list()
    for _, id in ipairs(ids) do
        local player = self.players[id]
        if score_chapter then
            -- 43ac50..43ad58 uses percentage units and rounds to tens.
            local graze = player.chapter_graze or 0
            local bonus = math.floor(Rules.float32(Rules.float32(graze * ratio) * 50) / 10) * 10
            self:add_score(player, bonus)
            self:raise_point_value(player, math.floor(bonus / 50000) * 10)
            total = total + bonus
        end
        player.chapter_graze = 0
    end
    -- Co-op combines the two earned bonuses for one shared fragment.
    if score_chapter and total >= threshold and self.session:life_count(ids[1]) >= 0 then
        self:grant_fragment(self.players[ids[1]], "life_piece")
    end
    self.pending_chapter = nil
    self.chapter = next_chapter
    adapter.chapter_active, adapter.chapter_targets, adapter.chapter_defeated = next_chapter, 0, 0
end

local function enemy_shot_contact(player, shot, birth_x, birth_y)
    if shot.player_bullet or (shot.no_collision and not birth_x) then return false, false end
    if shot.laser then return require("tnr.legacy_replay.laser").contact(shot, player) end
    local x,y=birth_x or shot.x,birth_y or shot.y
    local descriptor = BulletTypes[shot.sprite or shot.anim or 0]
    local size = (descriptor and descriptor.radius or 0) * (shot.scale or 1)
    if descriptor and descriptor.rectangular then
        -- 455be0 uses half the descriptor size for hits and a 24-unit box
        -- for grazing. Both rectangles are axis-aligned.
        local dx, dy = math.abs(x - player.x), math.abs(y - player.y)
        local half = player.hitbox_half or player.hitbox
        local contact = size / 2 + half
        if dx <= contact and dy <= contact then return true, false end
        local graze = 24 + half
        return false, dx <= graze and dy <= graze
    end
    local hit = player:bullet_contact(x,y,size)
    return hit, not hit and player:grazes(x,y,size)
end

local function graze_shot(stage, player_id, player, shot, x, y)
    shot.grazed_by = shot.grazed_by or {}
    local contact=shot.grazed_by[player_id] or {age=0,timer=0,interval=shot.laser and 3 or 60}
    shot.grazed_by[player_id]=contact
    if stage.networked then stage.local_grazing=true else stage.items:on_graze(player_id) end
    -- 448805 increments a curved laser's graze clock on every update, even
    -- when the ship is away. Straight lasers count only contact ticks.
    local clock=shot.laser_kind=="curve" and math.max(0,(shot.anim_frame or 0)-1) or contact.timer
    if clock%contact.interval==0 then
        if stage.networked then stage.local_graze=(stage.local_graze or 0)+1
        else stage:add_graze(player_id,1) end
        -- Bullets use a midpoint. 443804/445ca2 project the laser effect onto
        -- the beam beside the ship instead of using its often distant tail.
        local effect_x,effect_y=x,y
        if not shot.laser then effect_x,effect_y=(player.x+x)/2,(player.y+y)/2 end
        stage.adapter:spawn_animation("effect",24,effect_x,effect_y)
        stage:play_sound(22)
        contact.timer=0
    end
    contact.timer=contact.timer+1
    contact.age=contact.age+1
    if contact.age==45 and not shot.laser then
        contact.interval=30
        if stage.networked then
            stage.local_graze_drops=stage.local_graze_drops or {}
            stage.local_graze_drops[#stage.local_graze_drops+1]={x,y}
        else stage.items:spawn_graze(x,y,player_id) end
    end
end

--- Resolve enemy bullets and enemy bodies against the players.
function StageRuntime:resolve_player_hits()
    local contact_shots=self.adapter.contact_shots
    local contact_culled=self.adapter.contact_culled
    self.adapter.contact_shots=nil
    self.adapter.contact_culled=nil
    if self.dialogue and self.dialogue.active then return end
    local shots = self.adapter.shots
    if not shots then return end
    local original_contacts
    if contact_shots then
        local active={}
        for _,shot in ipairs(shots) do active[shot]=true end
        shots={}
        for _,shot in ipairs(contact_shots) do
            if not shot.deleted and (active[shot] or contact_culled[shot]) then shots[#shots+1]=shot end
        end
        original_contacts={}
        for _,shot in ipairs(shots) do original_contacts[shot]=true end
    end
    local classic = self.session:mode_id()=="classic"
    for _, player_id in ipairs(self.session.roster:list()) do
        local player = self.players[player_id]
        local active = player and player.alive and not player.deathbomb_frames and not player.respawn_frames
        local vulnerable = active and player.invulnerable <= 0
        if player and player.alive
                and (not self.networked or player_id==self.local_player_id) then
            local hit = false
            -- Enemy bullets.
            for index = #shots, 1, -1 do
                local shot = shots[index]
                -- 41950d and 4196f6 both test contact when the birth animation
                -- releases a projectile. Its earlier half-step can graze too.
                for pass=shot.birth_contact_x and 1 or 2,2 do
                    local x,y
                    if pass==1 then x,y=shot.birth_contact_x,shot.birth_contact_y end
                    local contact_hit,contact_graze,graze_x,graze_y=enemy_shot_contact(player,shot,x,y)
                    if contact_hit then
                        -- Active invulnerability still cancels contact bullets.
                        if active and (classic or vulnerable) and (not classic or not hit) then
                            hit=vulnerable
                            if not self.networked and not shot.laser then
                                if x then shot.x,shot.y=x,y end
                                if classic then self.adapter:cancel_bullet(shot) end
                                table.remove(shots,index)
                            end
                            break
                        end
                    elseif contact_graze then
                        graze_shot(self,player_id,player,shot,graze_x or x or shot.x,graze_y or y or shot.y)
                    end
                end
            end
            if active and not hit then
                for _, enemy in ipairs(self.adapter.enemies) do
                    if (enemy.hp or 0)>0 and not enemy.legacy_deleted and not enemy.legacy_no_contact
                        and (not enemy.legacy_ecl or enemy.legacy_last_update==self.adapter.frame) then
                        -- 427efa uses half the first dimension and checks the
                        -- player's hitbox with the same circle test as bullets.
                        local box = enemy.legacy_hitbox
                        local radius = box and box[1]/2 or 0
                        if vulnerable and player:bullet_contact(enemy.x,enemy.y,radius) then
                            hit=true
                            break
                        end
                        local age=(self.adapter.frame or 0)-(enemy.legacy_timer_start or 0)
                        if enemy.legacy_body_graze and age%6==0 and player:grazes(enemy.x,enemy.y,radius) then
                            if self.networked then
                                self.local_graze=(self.local_graze or 0)+1
                                self.local_grazing=true
                            else
                                self:add_graze(player_id,1)
                                self.items:on_graze(player_id)
                            end
                            self.adapter:spawn_animation("effect",24,player.x,player.y)
                            self:play_sound(22)
                        end
                    end
                end
            end
            if hit then
                if self.networked then self.local_hit=true
                else self:on_player_contact(player_id, player) end
            end
        end
    end
    if contact_shots then
        local remaining={}
        for _,shot in ipairs(shots) do remaining[shot]=true end
        local kept={}
        for _,shot in ipairs(self.adapter.shots) do
            if not original_contacts[shot] or remaining[shot] then kept[#kept+1]=shot end
        end
        self.adapter.shots=kept
    end
end

function StageRuntime:on_player_contact(player_id,player)
    if self.session:mode_id()=="classic" then
        if ClassicBombs.absorb(self,player) then return end
        -- 454bb0..454cfc permits a new Bomb press until the miss timer reaches 8.
        if not player.deathbomb_frames then
            player.deathbomb_frames=8
            self:play_sound(2)
        end
    else
        self:on_player_hit(player_id,player)
    end
end

function StageRuntime:damage_classic_enemy(player_id,enemy,amount)
    -- Native 4597ad caps the sum of this player's sources on each enemy.
    if enemy.classic_damage_frame ~= self.frames then
        enemy.classic_damage_frame = self.frames
        enemy.classic_damage = {}
    end
    local cap = self.players[player_id].definition.max_damage or 60
    local previous = enemy.classic_damage[player_id] or 0
    local damage = math.min(amount,cap-previous)
    if damage <= 0 then return 0 end
    enemy.classic_damage[player_id] = previous+damage
    -- 427cef..427d1d: protection blocks the health change, not the
    -- already resolved shot contact and score.
    if not enemy.legacy_no_damage and (enemy.legacy_invulnerable_until or 0) <= (self.adapter.frame or 0) then
        local player=self.players[player_id]
        local applied=damage
        -- 427bf7..427c19 divides the aggregate by five in native death and
        -- post-miss protection states. Keep pre-reduction damage for score.
        if self.session:mode_id()=="classic" and not self.coop
            and (not player.alive or player.classic_miss_protection) then
            applied=math.floor(damage/5)
        end
        if applied>0 then
            self.adapter:damage_enemy(enemy,applied)
            if self.coop then self.coop.aggro:record(player_id,applied) end
            self.session.mode:on_hit(self.session,player_id,enemy,applied)
        end
    end
    return damage
end

function StageRuntime:apply_miss_power(player_id,player)
    self.session.mode:on_player_hit(self.session,player_id)
    player.power=self.session:get_power(player_id)*100
    if self.session:mode_id()=="classic" then
        self.items:spawn_miss_drops(player.x,player.y,player_id)
    end
end

--- Apply the consequences of a player being hit.
function StageRuntime:on_player_hit(player_id, player)
    local contact_played=player.deathbomb_frames~=nil
    player.deathbomb_frames=nil
    if player.combat_runtime then
        local affixes=player.combat_runtime.affixes
        if affixes:defend(self.session:life_count(player_id)) then player.invulnerable=30;return end
    end
    if self.adapter.boss_object then self.adapter.boss_object.legacy_spell_failed=true end
    if self.coop then
        self.coop:hit(player_id)
        if not contact_played then self:play_sound(2) end
        return
    end
    if player.combat_runtime then
        local affixes=player.combat_runtime.affixes
        affixes:miss()
    end
    player:hit()
    if self.session:mode_id()=="classic" then player.classic_miss_protection=true end
    if not contact_played then self:play_sound(2) end
    if self.session:mode_id()=="classic" then
        -- 454bd2/454bea/454c51: the miss clock reaches three before
        -- reducing power and spawning the seven drops, after life loss.
        self.pending_miss_power=self.pending_miss_power or {}
        self.pending_miss_power[#self.pending_miss_power+1]={player_id=player_id,frame=self.frames+3}
    else
        self:apply_miss_power(player_id,player)
    end
    local can_respawn = self.session:lose_life(player_id)
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
    if can_respawn then
        local frames=self.session:mode_id()=="classic" and 31 or 40
        self.pending_respawn[#self.pending_respawn + 1] = { player_id = player_id, frames = frames }
    end
    self.on_player_death = true
end

--- Bring any pending respawns back into play.
function StageRuntime:advance_respawns()
    if self.coop then self.coop:update();return end
    local pending = self.pending_respawn
    if not pending or #pending == 0 then return end
    local remaining = {}
    for _, entry in ipairs(pending) do
        entry.frames = entry.frames - 1
        if entry.frames <= 0 then
            local player = self.players[entry.player_id]
            if player then
                local classic=self.session:mode_id()=="classic"
                player:respawn(0,classic and 480 or 300)
                if classic then player.respawn_frames,player.invulnerable=60,280 end
                self.session:restore_bombs_after_miss(entry.player_id)
                player.graze = player.graze or 0
            end
        else
            remaining[#remaining + 1] = entry
        end
    end
    self.pending_respawn = remaining
end

local function player_shot_contact(shot, enemy)
    local box = enemy.legacy_hurtbox
    local radius = box and box[1]/2 or enemy.legacy_ecl and 0 or 24
    if radius <= 0 then return false end
    local dx, dy = enemy.x - shot.x, enemy.y - shot.y
    local cos, sin = math.cos(shot.angle or 0), math.sin(shot.angle or 0)
    local along, across = dx * cos + dy * sin, dy * cos - dx * sin
    if shot.beam_length then
        dx = along - math.max(0, math.min(shot.beam_length, along))
        dy = across
        radius = radius + (shot.radius or 2)
    elseif shot.hitbox_x and shot.hitbox_y then
        -- 405000 performs each coordinate and rotation operation in float32.
        -- Its side strips include the boundary; corner circles are strict.
        local f=Rules.float32
        dx,dy=f(enemy.x-shot.x),f(enemy.y-shot.y)
        cos,sin=f(cos),f(sin)
        along=f(f(dx*cos)+f(dy*sin))
        across=f(f(dy*cos)-f(dx*sin))
        local x,y=math.abs(along),math.abs(across)
        local half_x,half_y=f(shot.hitbox_x/2),f(shot.hitbox_y/2)
        radius=f(radius)
        if x<=f(half_x+radius) and y<=half_y then return true end
        if x<=half_x and y<=f(half_y+radius) then return true end
        dx,dy=f(x-half_x),f(y-half_y)
        return f(f(dx*dx)+f(dy*dy))<f(radius*radius)
    else
        radius = radius + (shot.radius or 2)
    end
    return dx * dx + dy * dy <= radius * radius
end

function StageRuntime:player_damage_sources()
    local sources = {}
    for _, shot in ipairs(self.adapter.shots) do
        if shot.player_bullet and shot.damage and not shot.deleted and not shot.spent then
            sources[#sources + 1] = shot
        end
    end
    return sources
end

function StageRuntime:resolve_enemy_shots(enemy, sources)
    if (self.dialogue and self.dialogue.active) or not sources or #sources == 0
        or enemy.legacy_deleted or enemy.legacy_dropped or enemy.legacy_no_shot_contact or (enemy.hp or 0) <= 0 then return end
    -- 427bc8 calls 4594e0 once per enemy. Every overlapping source is
    -- consumed before the damage cap and death check are applied.
    local damage
    for _, shot in ipairs(sources) do
        if not shot.deleted and not shot.spent and not (shot.beam_hits and shot.beam_hits[enemy])
            and player_shot_contact(shot, enemy) then
            local id = shot.owner_player_id or 1
            damage = damage or {}
            damage[id] = (damage[id] or 0) + shot.damage
            if shot.beam_hits then shot.beam_hits[enemy]=true end
            if not shot.beam_length then ClassicShots.hit(shot) end
        end
    end
    if not damage then return end
    for _, id in ipairs(self.session.roster:list()) do
        if damage[id] then
            local contact_damage = self:damage_classic_enemy(id, enemy, damage[id])
            -- 4597cb increments score in units of ten.
            if contact_damage > 0 then
                self:add_score(self.players[id], 10 * math.floor((10 + math.floor(contact_damage / 10)) / 10))
            end
        end
    end
end

--- Resolve contacts for callers that step the adapter manually.
function StageRuntime:resolve_player_damage()
    local sources = self:player_damage_sources()
    for _, enemy in ipairs(self.adapter.enemies) do
        self:resolve_enemy_shots(enemy, sources)
    end
    local kept = {}
    for _, shot in ipairs(self.adapter.shots) do if not shot.deleted then kept[#kept + 1] = shot end end
    self.adapter.shots = kept
end

--- Start the stage's opening timeline.
function StageRuntime:start()
    local entry = self.stage_key .. ".main"
    if self.adapter.runtime.chunks[entry] then
        self.original_main = true
        self.timeline_done = false
        self.section_name = "main"
        self.section_thread = self.adapter.runtime:spawn(entry)
        self.adapter.runtime.threads[#self.adapter.runtime.threads+1] = self.section_thread
        return true
    end
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
    if self.original_main then
        -- The original main routine loops after requesting the ending dialog.
        -- MSG opcode 21 starts the stage transition; helper wave completion alone
        -- must never clear the stage.
        if self.adapter.stage_ending_requested then
            self.timeline_done = true
            self.on_clear = true
        end
        return
    end
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

function StageRuntime:simulation_step_due()
    if self.capture_frame and self.frames >= self.capture_frame then return false end
    return (self.time_accumulator or 0)+math.max(0,tonumber(self.time_scale) or 1)>=1
end

--- Advance the game clock at the ECL-selected global speed.
-- At 0.25x, all stage systems (players, ECL, bullets, items and animations)
-- update once per four engine frames. Network play asks this same clock before
-- consuming its next synchronized input bundle.
function StageRuntime:update()
    if self.capture_frame and self.frames >= self.capture_frame then return false end
    local scale=math.max(0,math.min(4,tonumber(self.time_scale) or 1))
    self.time_accumulator=(self.time_accumulator or 0)+scale
    local steps=0
    while self.time_accumulator>=1 and steps<4 do
        self.time_accumulator=self.time_accumulator-1
        self:_update_simulation()
        steps=steps+1
        if self.capture_frame and self.frames>=self.capture_frame then break end
    end
    return steps>0
end

function StageRuntime:_update_simulation()
    -- Opt-in developer capture: freeze simulation without relying on a short
    -- synthetic key press being sampled by the game's input loop.
    self.frames = self.frames + 1
    self:sample_inputs()
    if self.pending_miss_power then
        local pending={}
        for _,entry in ipairs(self.pending_miss_power) do
            if entry.frame<=self.frames then
                local player=self.players[entry.player_id]
                if player then self:apply_miss_power(entry.player_id,player) end
            else pending[#pending+1]=entry end
        end
        self.pending_miss_power=pending
    end
    local dialogue = self.dialogue
    local dialogue_was_active = dialogue and dialogue.active
    self.adapter:update()
    -- The GUI publishes MSG resume/end after the current enemy manager tick.
    if dialogue then dialogue:update(self.dialogue_input,dialogue_was_active) end
    self.classic_shot_sources = nil
    self.boss_ui:update()
    self.background:update()
    -- Chain to the next timeline section once the current one returns.
    self:_advance_timeline()
    if self.modern then self.modern:update() end
    self:update_bombs()
    self.adapter:advance_interrupts()
    -- Enemy drops precede bullet grazes in the native item spawn order.
    for _, enemy in ipairs(self.adapter.enemies) do
        self:check_enemy_defeat(enemy)
    end
    self:resolve_player_hits()
    self:advance_respawns()
    local auto_collect
    if self.session:mode_id()=="classic" then
        auto_collect={}
        for id,player in pairs(self.players) do
            local bomb=player.classic_bomb
            -- 43f928/43fbf3: early Bomb and dialogue promote falling and
            -- proximity-attracted items to full collection below the line.
            auto_collect[id]=(bomb and bomb.age<60) or (self.dialogue and self.dialogue.active)
        end
    end
    self.items:update(auto_collect)
    self.effects:update()
    -- Collected items feed the mode, which decides what they are worth, and
    -- score by the point rate the way the reference does.
    for _, item in ipairs(self.items:drain_collected()) do
        local owner = item.owner_player_id and self.players[item.owner_player_id] or self.items.player
        if owner then
            if item.kind=="graze" then
                owner.graze=math.min(99999999,(owner.graze or 0)+5)
                owner.chapter_graze=(owner.chapter_graze or 0)+5
                self:add_score(owner,10)
            elseif item.kind=="cancel" then
                -- Item type 10 awards two displayed PIV and ten score.
                self:raise_point_value(owner,2)
                self:add_score(owner,10)
            end
            local was_full=self.session:get_power(owner.player_id)>=4
            self.session.mode:on_item_collected(self.session, owner.player_id, item)
            if self.modern then self.modern:pickup(owner.player_id,item) end
            if item.kind=="life" then self.session:add_life(owner.player_id,1)
            elseif item.kind=="bomb" then self.session:add_bomb(owner.player_id,1)
            elseif item.kind=="life_piece" or item.kind=="bomb_piece" then
                self:grant_fragment(owner,item.kind)
            end
            owner.power = math.min(400, self.session:get_power(owner.player_id) * 100)
            if self.session:mode_id()=="classic" and (item.kind=="power" or item.kind=="power_large") then
                -- 4401d0 and 440420 award different scores at full power.
                local full_score=item.kind=="power_large" and 40000 or 10000
                self:add_score(owner,was_full and full_score or 100)
            end
            if item.kind == "point" then
                local rate=self.session:is_coop() and (owner.point_rate or 10000) or self.point_rate or 10000
                local award=Rules.point_score(rate,owner.y,owner.collect_line or 128,item.auto_collect)
                self:add_score(owner,award)
            end
        end
    end
    self:finish_chapter()
    local stats = self.stats
    -- The HUD reads power and the maximum point value from the stats table, but
    -- the mode records them on the session. Copy them across so the 霊力 and
    -- 最大得点 rows show what the player has actually collected instead of a
    -- permanent zero.
    if stats then
        local primary = self.session.roster:list()[1]
        if primary and self.session.get_power then
            stats.power = self.session:get_power(primary)
        end
        if stats.max_point == nil then stats.max_point = 0 end
        -- The reference's maximum point value is the point rate the next point
        -- item is worth, which is what the pickup raises.
        stats.max_point = self.point_rate or stats.max_point or 0
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
    local draw_jobs={}
    local function draw_animation(vm,ox,oy,parent)
        if not vm or not vm.visible or vm.finished then return end
        parent=parent or {sx=1,sy=1,alpha=255,color={255,255,255}}
        local sx,sy=parent.sx*vm.scale_x*(vm.scale2_x or 1),parent.sy*vm.scale_y*(vm.scale2_y or 1)
        local alpha=vm.color_mode==1 and vm.alpha2 or vm.alpha
        local color=vm.color_mode==1 and {vm.red2,vm.green2,vm.blue2} or vm.color or {255,255,255}
        if vm.inherit_color then
            alpha=alpha*parent.alpha/255
            color={color[1]*parent.color[1]/255,color[2]*parent.color[2]/255,color[3]*parent.color[3]/255}
        end
        local dx,dy=((vm.x or 0)+(vm.offset_x or 0))*parent.sx,((vm.y or 0)+(vm.offset_y or 0))*parent.sy
        local rotation=parent.rotation or 0
        local c,s=math.cos(rotation),math.sin(rotation)
        local world_x,world_y=ox+dx*c-dy*s,oy+dx*s+dy*c
        local angle=rotation+(vm.rotation or 0)
        local screen_pixels=parent.screen_pixels or vm.screen_pixels
        draw_jobs[#draw_jobs+1]={layer=vm.layer or 0,order=#draw_jobs+1,draw=function()
        -- Title coordinates and sprite sizes are in the original 1280×960 UI.
        local scale=BossUi.PLAYFIELD_SCALE*(screen_pixels and 0.5 or 1)
        local x=(left+right)*0.5+world_x*scale
        local y=top-world_y*scale
        local blend=AnmGeometry.blend(vm.blend_mode)
        if vm.geometry_width and vm.geometry_height and vm.sprite==0 then
            AnmGeometry.draw_rect(lstg,vm,x,y,vm.geometry_width,vm.geometry_height,
                sx*scale,sy*scale,alpha,color)
        end
        if vm.polygon_radius and lstg.RenderTexture then
            local radius=vm.polygon_radius*sx*scale
            local count=math.max(3,math.floor(vm.vars[10000] or 36))
            local center=lstg.Color(vm.alpha,vm.red,vm.green,vm.blue)
            local edge=lstg.Color(vm.alpha2,vm.red2,vm.green2,vm.blue2)
            for n=0,count-1 do
                local a,b=n*2*math.pi/count+angle,(n+1)*2*math.pi/count+angle
                local origin={x,y,.5,8,8,center}
                lstg.RenderTexture("tnr-white-texture",blend,origin,
                    {x+math.cos(a)*radius,y-math.sin(a)*radius,.5,8,8,edge},
                    {x+math.cos(b)*radius,y-math.sin(b)*radius,.5,8,8,edge},origin)
            end
        end
        local index=vm.sprite
        local entries=vm.archive_entries or {vm.archive}
        for entry_index,entry in ipairs(entries) do
            if index>=1 and index<=#entry.sprites then
                local sprite=entry.sprites[index];if not sprite then return end
                local image=image_name(vm.archive_name,vm.archive_entries and entry_index or vm.entry_index,index)
                lstg.SetImageState(image,blend,lstg.Color(alpha,color[1],color[2],color[3]))
                if vm.texture_circle_max and require("tnr.legacy_replay.anm_geometry").draw_circle(
                    lstg,vm,entry,sprite,(self.texture_sizes or {})[entry.texture] or {entry.width,entry.height},
                    x,y,scale,parent.sx,parent.sy) then
                    -- Special geometry uses scale as ring width/radius, not sprite multipliers.
                elseif lstg.RenderTexture and entry.loaded_texture then
                    local ax=(vm.anchor_x==1 and 0 or vm.anchor_x==2 and sprite.w or sprite.w/2)+(vm.anchor_dx or 0)
                    local ay=(vm.anchor_y==1 and 0 or vm.anchor_y==2 and sprite.h or sprite.h/2)+(vm.anchor_dy or 0)
                    local size=(self.texture_sizes or {})[entry.texture] or {entry.width,entry.height}
                    local texture_w=size[1] or entry.width or sprite.w
                    local texture_h=size[2] or entry.height or sprite.h
                    local u0=sprite.x+(entry.offset_x or 0)+(vm.u or 0)*texture_w
                    local v0=sprite.y+(entry.offset_y or 0)+(vm.v or 0)*texture_h
                    local du=sprite.w*(vm.uv_scale_x or 1)
                    local dv=sprite.h*(vm.uv_scale_y or 1)
                    local u1=u0+(vm.flip_x and -du or du)
                    local v1=v0+(vm.flip_y and -dv or dv)
                    local point=vm.resample_mode==1
                    local patches=require("tnr.legacy_replay.anm_geometry").uv_patches(
                        u0,u1,v0,v1,texture_w,texture_h,vm.scroll_mode_x,vm.scroll_mode_y,point)
                    local c1={alpha,color[1],color[2],color[3]}
                    local c2={vm.alpha2,vm.red2,vm.green2,vm.blue2}
                    local function tint_at(s,t)
                        local amount=vm.color_mode==2 and s or vm.color_mode==3 and t or 0
                        return lstg.Color(c1[1]+(c2[1]-c1[1])*amount,
                            c1[2]+(c2[2]-c1[2])*amount,c1[3]+(c2[3]-c1[3])*amount,
                            c1[4]+(c2[4]-c1[4])*amount)
                    end
                    local function vertex(px,py,u,v,tint)
                        local dx,dy=(px-ax)*sx*scale,(py-ay)*sy*scale
                        if vm.render_mode==8 then
                            dx,dy=AnmGeometry.rotate3(dx,dy,0,vm.rotation_x,vm.rotation_y,
                                angle,vm.rotation_system)
                        elseif vm.render_mode~=0 then
                            local ca,sa=math.cos(angle),math.sin(angle)
                            dx,dy=dx*ca-dy*sa,dx*sa+dy*ca
                        end
                        return {x+dx,y-dy,.5,u,v,tint}
                    end
                    for _,patch in ipairs(patches) do
                        if lstg.SetTextureSamplerState then
                            lstg.SetTextureSamplerState(entry.loaded_texture,patch.sampler)
                        end
                        local a,b,c,d=patch.uv[1],patch.uv[2],patch.uv[3],patch.uv[4]
                        lstg.RenderTexture(entry.loaded_texture,blend,
                            vertex(sprite.w*patch.s0,sprite.h*patch.t0,a[1],a[2],tint_at(patch.s0,patch.t0)),
                            vertex(sprite.w*patch.s1,sprite.h*patch.t0,b[1],b[2],tint_at(patch.s1,patch.t0)),
                            vertex(sprite.w*patch.s1,sprite.h*patch.t1,c[1],c[2],tint_at(patch.s1,patch.t1)),
                            vertex(sprite.w*patch.s0,sprite.h*patch.t1,d[1],d[2],tint_at(patch.s0,patch.t1)))
                    end
                elseif lstg.Render then
                    lstg.Render(image,x,y,-math.deg(angle),
                        scale*sx*(vm.flip_x and -1 or 1),scale*sy*(vm.flip_y and -1 or 1))
                else
                    local w,h=sprite.w*scale*sx,sprite.h*scale*sy
                    lstg.RenderRect(image,x-w/2,x+w/2,y-h/2,y+h/2)
                end
                break
            end
            index=index-#entry.sprites
        end
        end}
        for _,child in ipairs(vm.children or {}) do
            draw_animation(child,world_x,world_y,{sx=sx,sy=sy,alpha=alpha,color=color,
                rotation=rotation+(vm.child_rotation or 0),screen_pixels=screen_pixels})
        end
    end
    for _,enemy in ipairs(self.adapter.enemies) do
        local slots=enemy.legacy_anm_slots or {[0]=enemy.legacy_anm}
        local keys={};for slot in pairs(slots) do keys[#keys+1]=slot end;table.sort(keys)
        for _,slot in ipairs(keys) do
            if slot~=0 then
                local source=(enemy.legacy_anm_position_sources or {})[slot]
                local offset=source and source>=0 and slots[source]
                draw_animation(slots[slot],(enemy.x or 0)+(offset and offset.x or 0),
                    (enemy.y or 0)+(offset and offset.y or 0))
            end
        end
        if enemy.legacy_body_visible~=false then draw_animation(enemy.legacy_anm,enemy.x or 0,enemy.y or 0) end
    end
    for _,vm in ipairs(self.adapter.animations or {}) do draw_animation(vm,vm.origin_x,vm.origin_y) end
    table.sort(draw_jobs,function(a,b) return a.layer<b.layer or a.layer==b.layer and a.order<b.order end)
    local overlay_jobs={}
    for _,job in ipairs(draw_jobs) do
        if job.layer>=29 then overlay_jobs[#overlay_jobs+1]=job else job.draw() end
    end
    -- Bullets.
    local draw_shots={}
    for index,shot in ipairs(self.adapter.shots or {}) do
        local descriptor=BulletTypes[shot.sprite or shot.anim or 0]
        draw_shots[#draw_shots+1]={shot=shot,index=index,
            layer=shot.draw_layer or (shot.player_animation and shot.player_animation.layer)
                or (descriptor and descriptor.layer) or 0}
    end
    local active_count = #draw_shots
    for index, shot in ipairs(self.adapter.cancelled_shots) do
        local descriptor = BulletTypes[shot.sprite or shot.anim or 0]
        draw_shots[#draw_shots + 1] = { shot = shot, index = active_count + index,
            layer = shot.draw_layer or descriptor.layer }
    end
    -- Native 41a65b inserts new bullets at the active-list head; 41a103
    -- preserves that traversal in each draw layer. Draw older bullets last
    -- so the leading bullet stays visible in overlapping stage-six columns.
    table.sort(draw_shots,function(a,b) return a.layer<b.layer or a.layer==b.layer and a.index>b.index end)
    for _,record in ipairs(draw_shots) do
        local shot=record.shot
        local travel_angle=(shot.angle or 0)*(shot.reflected and -1 or 1)
        local image, width, height, bullet_scale_x, bullet_scale_y,geometry_width,geometry_height,geometry_vm = self:bullet_image(shot)
        if geometry_width and geometry_height then
            local x=left+((shot.x or 0)+192)*BossUi.PLAYFIELD_SCALE
            local y=top-(shot.y or 0)*BossUi.PLAYFIELD_SCALE
            local c=Palette.unpack(Palette.tint(shot.color_index or 0,true))
            local animation=geometry_vm or {}
            local rotation=animation.rotate_auto and (travel_angle+math.pi/2)
                or animation.rotation or (travel_angle+math.pi/2)
            AnmGeometry.draw_rect(lstg,{render_mode=animation.render_mode or 1,
                rotation=rotation,rotation_x=animation.rotation_x,rotation_y=animation.rotation_y,
                rotation_system=animation.rotation_system,blend_mode=animation.blend_mode,
                alpha=animation.alpha or 255,red=c.r,green=c.g,blue=c.b},x,y,
                geometry_width,geometry_height,BossUi.PLAYFIELD_SCALE*(bullet_scale_x or 1),
                BossUi.PLAYFIELD_SCALE*(bullet_scale_y or bullet_scale_x or 1),animation.alpha or 255,
                {c.r,c.g,c.b})
        elseif image then
            local x = left + ((shot.x or 0) + 192) * BossUi.PLAYFIELD_SCALE
            local y = top - (shot.y or 0) * BossUi.PLAYFIELD_SCALE
            -- Draw at the sprite's own size scaled into the field, then apply
            -- the scale the animation script asks for on top. That is what makes
            -- a 16 pixel sheet shape read as the large bullet the original
            -- shows instead of a small one.
            local w = (width or 16) * BossUi.PLAYFIELD_SCALE * (bullet_scale_x or 1)
            local h = (height or 16) * BossUi.PLAYFIELD_SCALE * (bullet_scale_y or bullet_scale_x or 1)
            -- The colour index tints the sprite. Player shots are drawn without
            -- a tint so they keep their own colours.
            local tint
            if shot.player_bullet or BulletTypes[shot.sprite or shot.anim or 0] then
                tint = lstg.Color(shot.legacy_bullet_animation and shot.legacy_bullet_animation.alpha or 255, 255, 255, 255)
            else
                local c = Palette.unpack(Palette.tint(shot.color_index or 27, true))
                tint = lstg.Color(c.a, c.r, c.g, c.b)
            end
            local blend = shot.transform_blend or shot.blend or ""
            local player_vm=shot.player_animation
            if shot.player_bullet and player_vm then
                local c=player_vm.color
                tint=lstg.Color(player_vm.alpha,c[1],c[2],c[3])
                blend=AnmGeometry.blend(player_vm.blend_mode)
            end
            lstg.SetImageState(image, blend, tint)
            if shot.laser_kind=="curve" then
                local _,rect,entry=self:curve_image(shot)
                require("tnr.legacy_replay.curve_laser").draw(lstg,shot,entry,rect,
                    left,top,BossUi.PLAYFIELD_SCALE,tint,blend)
            elseif shot.laser and lstg.Render then
                require("tnr.legacy_replay.laser").segments(shot,function(x1,y1,x2,y2)
                    local dx,dy=x2-x1,y2-y1
                    local length=math.sqrt(dx*dx+dy*dy)
                    local angle=math.atan2 and math.atan2(dy,dx) or math.atan(dy,dx)
                    lstg.Render(image,left+((x1+x2)/2+192)*BossUi.PLAYFIELD_SCALE,
                        top-(y1+y2)/2*BossUi.PLAYFIELD_SCALE,-math.deg(angle)-90,
                        (shot.draw_width or shot.width)/(width or 16)*BossUi.PLAYFIELD_SCALE,
                        length/(height or 16)*BossUi.PLAYFIELD_SCALE)
                end)
            elseif shot.beam_length and lstg.Render then
                local length=shot.beam_length*BossUi.PLAYFIELD_SCALE
                local dx,dy=math.cos(shot.angle)*length,-math.sin(shot.angle)*length
                -- Marisa's beam is a horizontal strip: stretch its X axis
                -- along the ray, keeping the short Y axis as its thickness.
                local entry=player_vm and player_vm.archive
                local rect=player_vm and player_vm:rect()
                local size=entry and self.texture_sizes[entry.texture]
                if lstg.RenderTexture and entry.loaded_texture and rect and size and size[1]>0 then
                    -- Repeat within the source texture explicitly: clipping a
                    -- 512-wide ANM strip to its 256-wide atlas loses its UV motion.
                    local half=rect.h*BossUi.PLAYFIELD_SCALE*player_vm.scale_y/2
                    local nx,ny=-math.sin(-shot.angle)*half,math.cos(-shot.angle)*half
                    local offset=(rect.x+player_vm.u*size[1])%size[1]
                    local consumed=0
                    while consumed<rect.w do
                        local span=math.min(size[1]-offset,rect.w-consumed)
                        local a,b=consumed/rect.w,(consumed+span)/rect.w
                        lstg.RenderTexture(entry.loaded_texture,blend,
                            {x+dx*a+nx,y+dy*a+ny,0.5,offset,rect.y,tint},
                            {x+dx*b+nx,y+dy*b+ny,0.5,offset+span,rect.y,tint},
                            {x+dx*b-nx,y+dy*b-ny,0.5,offset+span,rect.y+rect.h,tint},
                            {x+dx*a-nx,y+dy*a-ny,0.5,offset,rect.y+rect.h,tint})
                        consumed=consumed+span;offset=0
                    end
                else
                    lstg.Render(image,x+dx/2,y+dy/2,-shot.angle*180/math.pi,
                        length/(width or 16),BossUi.PLAYFIELD_SCALE)
                end
            elseif shot.player_bullet and player_vm and lstg.Render then
                local rotation=player_vm.rotate_auto and (shot.angle or 0) or player_vm.rotation or 0
                local scale=BossUi.PLAYFIELD_SCALE
                lstg.Render(image,x+(player_vm.x+(player_vm.offset_x or 0))*scale,
                    y-(player_vm.y+(player_vm.offset_y or 0))*scale,-math.deg(rotation),
                    scale*player_vm.scale_x*player_vm.scale2_x,scale*player_vm.scale_y*player_vm.scale2_y)
            elseif shot.legacy_bullet_animation and lstg.Render then
                local vm=shot.legacy_bullet_animation
                local rotation=vm.rotate_auto and (travel_angle+math.pi/2) or vm.rotation or 0
                lstg.Render(image,x,y,-math.deg(rotation),w/(width or 16),h/(height or 16))
            else
                lstg.RenderRect(image, x - w * 0.5, x + w * 0.5, y - h * 0.5, y + h * 0.5)
            end
        end
    end
    if self.modern then self.modern:draw(left,top,BossUi.PLAYFIELD_SCALE) end
    -- Effects: the death burst and bullet break animations, drawn under the
    -- items so the pickups stay readable.
    for _, effect in ipairs(self.effects.list) do
        local sprite, growth, alpha = self.effects:sprite_for(effect)
        local image = global_image(self.anm,"effect",sprite)
        local x = left + ((effect.x or 0) + 192) * BossUi.PLAYFIELD_SCALE
        local y = top - (effect.y or 0) * BossUi.PLAYFIELD_SCALE
        -- The script ramps the scale, so the ring expands across its life
        -- instead of sitting at one size.
        local r = 8 * (growth or 1) * (effect.scale or 1) * BossUi.PLAYFIELD_SCALE
        if image then
            lstg.SetImageState(image, "add+add", lstg.Color(alpha, 255, 255, 255))
            lstg.RenderRect(image, x - r, x + r, y - r, y + r)
        end
    end
    -- Items.
    for _, item in ipairs(self.items.list) do
        local image,rect = self:item_image(item)
        if image and (not self.networked or item.owner_player_id==self.local_player_id) then
            local x = left + ((item.x or 0) + (item.draw_offset_x or 0) + 192) * BossUi.PLAYFIELD_SCALE
            local y = top - ((item.y or 0)+(item.draw_offset_y or 0)) * BossUi.PLAYFIELD_SCALE
            local r = (item.kind=="power_large" and 5*math.sqrt(2) or 5) * BossUi.PLAYFIELD_SCALE
            local vm=item.animation_vm
            lstg.SetImageState(image, AnmGeometry.blend(vm and vm.blend_mode),
                lstg.Color(vm and vm.alpha or 255, 255, item.slowed_visual and 160 or 255, 255))
            if vm and rect and lstg.Render then
                lstg.Render(image,x,y,vm.render_mode~=0 and -math.deg(vm.rotation) or 0,
                    2*r/rect.w*vm.scale_x,2*r/rect.h*vm.scale_y)
            else lstg.RenderRect(image, x - r, x + r, y - r, y + r) end
        end
    end
    -- Player ships.
    for _, player_id in ipairs(self.session.roster:list()) do
        local player = self.players[player_id]
        if player and player.alive then
            local left_x = left + ((player.x or 0) + 192) * BossUi.PLAYFIELD_SCALE
            local top_y = top - (player.y or 0) * BossUi.PLAYFIELD_SCALE
            -- Option sub-ships sit at the positions the sht data gives for the
            -- current focus state and power level. The orb art is the blue
            -- yin-yang unfocused and the red one focused; the previous index
            -- pointed at a laser segment, which drew as a red bar.
            if self.modern then
                self.modern:draw_supports(player_id, left, top, BossUi.PLAYFIELD_SCALE)
            else
                local option_sprite = player.archive=="pl01" and 44 or (player.focus and 42 or 41)
                local option_image = image_name(player.archive or "pl00", 1, option_sprite)
                for _, offset in ipairs(player:option_positions()) do
                    local ox = left_x + (offset[1] or 0) * BossUi.PLAYFIELD_SCALE
                    local oy = top_y - (offset[2] or 0) * BossUi.PLAYFIELD_SCALE
                    local r = 8 * BossUi.PLAYFIELD_SCALE
                    lstg.SetImageState(option_image, "", lstg.Color(255, 255, 255, 255))
                    lstg.RenderRect(option_image, ox - r, ox + r, oy - r, oy + r)
                end
            end
            local image = self:player_image(player)
            if image then
                local w = 32 * BossUi.PLAYFIELD_SCALE
                local h = 48 * BossUi.PLAYFIELD_SCALE
                lstg.SetImageState(image, "", lstg.Color(255, 255, 255, 255))
                lstg.RenderRect(image, left_x - w * 0.5, left_x + w * 0.5, top_y - h*.5, top_y+h*.5)
            end
            -- Show TH15's tiny collision point only while focused. It is
            -- intentionally drawn over the ship so the player can see the
            -- exact point hidden by the sprite.
            if player.focus then
                local marker = "tnr-white"
                lstg.SetImageState(marker, "", lstg.Color(150, 255, 96, 132))
                lstg.RenderRect(marker, left_x - 4, left_x + 4, top_y - 4, top_y + 4)
                lstg.SetImageState(marker, "", lstg.Color(255, 255, 226, 236))
                lstg.RenderRect(marker, left_x - 1.5, left_x + 1.5, top_y - 1.5, top_y + 1.5)
            end
        end
    end
    self.boss_ui:draw_ring(self.adapter.boss_object)
    if type(lstg.SetScissorRect) == "function" then
        pcall(lstg.SetScissorRect, 0, 1280, 0, 720)
    end
    -- High ANM layers are screen effects (including TH15's 603 transition
    -- rectangle). They render above shots and ships and outside the playfield
    -- scissor, while dialogue and HUD remain legible above them.
    for _,job in ipairs(overlay_jobs) do job.draw() end
    if self.modern then self.modern:draw_player_effects(left,top,BossUi.PLAYFIELD_SCALE) end
    self:draw_dialogue()
    self.boss_ui:draw()
    self:draw_hud()
    if self.modern then self.modern:draw_hud() end
end

-- Text and source portrait presentation. Callout/portrait ANM transitions still
-- require frame-matched visual validation; the MSG state is authoritative.
function StageRuntime:draw_dialogue()
    local dialog, g = self.dialogue, self.lstg
    if not dialog or not dialog.active or not dialog.visible then return end
    local left, right, bottom = BossUi.PLAYFIELD_LEFT, BossUi.PLAYFIELD_RIGHT, BossUi.PLAYFIELD_BOTTOM
    for _, side in ipairs({"player", "enemy"}) do
        if dialog.shown[side] then
            local archive = side == "player" and self.primary_player_archive or STAGE_ARCHIVES[self.stage_key]
            local entries = self.anm[archive] or {}
            local first
            for i, entry in ipairs(entries) do
                if entry.texture and entry.texture:match("^face/[^/]+/face.*no%.png$") then first = i; break end
            end
            local index = first and first + (dialog.faces[side] or 0)
            local entry = index and entries[index]
            local body_index
            for i, candidate in ipairs(entries) do
                if candidate.texture and candidate.texture:match("^face/[^/]+/face.*bs%.png$") then body_index = i; break end
            end
            local body = body_index and entries[body_index]
            if body and entry and entry.texture:match("^face/") then
                local scale = BossUi.PLAYFIELD_SCALE / 2
                local canvas_width = (body.offset_x or 0) + body.sprites[1].w
                local origin_x = side == "player" and left - 70 or right - canvas_width * scale + 40
                local top = bottom + 500
                local light = dialog.focus == side and 255 or 96
                local function part(part_index, part_entry)
                    local rect = part_entry.sprites[1]
                    if not rect or rect.w == 0 or rect.h == 0 then return end
                    local x = origin_x + (part_entry.offset_x or 0) * scale
                    local y = top - (part_entry.offset_y or 0) * scale
                    local image = image_name(archive, part_index, 1)
                    g.SetImageState(image, "", g.Color(255, light, light, light))
                    g.RenderRect(image, x, x + rect.w * scale, y - rect.h * scale, y)
                end
                part(body_index, body)
                if entry.texture ~= "face/dummy.png" then part(index, entry) end
            end
        end
    end
    if #dialog.lines > 0 and g.RenderTTF then
        g.SetImageState("tnr-white", "", g.Color(215, 18, 22, 34))
        g.RenderRect("tnr-white", left + 12, right - 12, bottom + 16, bottom + 126)
        local row = 0
        for _, line in ipairs(dialog.lines) do
            -- Ruby annotation is preserved in the data, but needs a separate
            -- small-text pass. Do not display its control syntax as dialogue.
            if line:sub(1, 1) ~= "|" then
                local y = bottom + 98 - row * 28
                g.RenderTTF("Sans", line, left + 26, right - 26, y, y, 0, g.Color(255,255,255,255), 1.05)
                row = row + 1
            end
        end
    end
end

--- Resolve the image for an item from the item sheet.
function StageRuntime:item_image(item)
    if item.launch_delay then return nil end
    -- The item sheet is the entry whose texture ends in item.png.
    self.item_entry = self.item_entry or self:find_entry_by_texture("item.png")
    if not self.item_entry then return nil end
    if item.kind=="money" then return "tnr-replay-coin-"..(math.floor((item.timer or 0)/6)%5+1) end
    if not item.animation_vm then
        for i,entry in ipairs(self.anm.bullet or {}) do
            if entry.scripts and entry.scripts[item.animation] then
                item.animation_vm=AnmPlayer.new(entry,"bullet",i)
                item.animation_vm:play(item.animation);item.animation_age=0
                break
            end
        end
    end
    if item.animation_vm then
        while item.animation_age<(item.animation_frame or 0) do
            item.animation_vm:update();item.animation_age=item.animation_age+1
        end
        return global_image(self.anm,"bullet",item.animation_vm.sprite)
    end
    local index=({power=1,point=3,power_large=5,life_piece=7,life=9,bomb_piece=11,bomb=13,full_power=15})[item.kind] or 1
    return image_name("bullet", self.item_entry.index, index)
end

--- Resolve the image for a player ship from its current animation frame.
function StageRuntime:player_image(player)
    local sheet = player.archive or self.primary_player_archive or "pl00"
    local animation=player.animation or self.player_animation
    local sprite = animation and animation:sprite_index() or 1
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
    local classic = self.session:mode_id() == "classic"
    local label_x = 800
    local value_x = 1100
    local function sprite(index, left, right, bottom, top)
        local image = image_name("front", 1, index)
        lstg.SetImageState(image, "", lstg.Color(255,255,255,255))
        lstg.RenderRect(image,left,right,bottom,top)
    end
    -- Border geometry comes from front00's four source strips.
    sprite(1,160,208,0,720)
    sprite(2,784,1120,0,720)
    sprite(3,208,784,696,720)
    sprite(4,208,784,0,24)
    -- Value column: the score and power rows share their space with the icon
    -- rows, so the icons sit in the gap between the label and the value, and the
    -- value is right aligned at the panel edge.
    local rows = {
        { "ハイスコア", stats.hiscore or 1000000, 665 },
        { "スコア", stats.score or 0, 636 },
        { "残り人数", nil, 596 },
        { "スペルカード", nil, 549 },
        { "霊力", string.format("%.2f/4.00", stats.power or 0), 492 },
        { "最大得点", stats.max_point or 0, 465 },
        { "グレイズ", classic and (stats.chapter_graze or 0) or (stats.graze or 0), 444 },
    }
    local label_sprites = {5,6,7,9,12,11,10}
    for index, row in ipairs(rows) do
        local width = index == 6 and 120 or 108
        sprite(label_sprites[index],label_x,label_x+width,row[3],row[3]+27)
        if row[2] ~= nil then
            -- Numbers use the reference ascii glyphs, right aligned.
            self:draw_number(row[2], value_x, row[3])
        end
    end
    -- Life hearts and spell card stars, placed between the label and the value
    -- column exactly as the reference lays them out.
    local life, bombs = stats.lives or 3, stats.spellcards or 0
    local bomb_slots = self.coop and 8 or 5
    if classic then
        life = life + (stats.life_pieces or 0) / 3
        bombs = bombs + (stats.bomb_pieces or 0) / 5
        bomb_slots = math.max(bomb_slots, math.ceil(bombs))
        self:draw_number(stats.graze or 0, value_x, 424)
    end
    self:draw_life_icons(924, 592, life, 8, BossUi.HEART_FIRST_SPRITE)
    self:draw_life_icons(924, 545, bombs, bomb_slots, BossUi.STAR_FIRST_SPRITE)
    if self.coop then
        for id=1,2 do
            local remaining=self.coop.respawns[id]
            local text=string.format("P%d %s%s",id,id==self.local_player_id and "YOU " or "",
                remaining and string.format("WAIT %.1fs",remaining/60) or "ACTIVE")
            self:draw_number(text,value_x,(classic and 400 or 408)-(id-1)*28)
        end
        self:draw_number("AIM P"..self.coop.focus,value_x,345)
    end
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

--- Resolve shots through their owner's player archive (body scripts 0..4,
-- shot scripts from 5), including co-op with different characters.
function StageRuntime:player_bullet_image(shot)
    local vm=shot.player_animation
    if not vm or vm.finished or not vm.visible then return nil end
    local rect,i,index = ClassicShots.sprite(vm)
    if not rect then return nil end
    local entry = vm.archive_entries[i]
    local size=self.texture_sizes and self.texture_sizes[entry.texture]
    local width=size and size[1]>0 and math.min(rect.w,size[1]-rect.x-(entry.offset_x or 0)) or rect.w
    local height=size and size[2]>0 and math.min(rect.h,size[2]-rect.y-(entry.offset_y or 0)) or rect.h
    return image_name(vm.archive_name,i,index),width,height
end

--- Resolve the bullet image for a shot at a point in its life.
-- The animation script is a frame timeline: walk it once to find the sprite due
-- at `frame`, which lets a bullet cycle through its frames like the reference.
--- Resolve the sprite and scale an animation script asks for at a frame.
-- A bullet script opens by naming a sprite and then animates its scale, which
-- is what turns an 8 pixel dot into a small pop on spawn and what makes a
-- large bullet actually large: the sheet holds a 16 pixel shape and the script
-- scales it up. Returning the sprite alone drew every bullet at its raw size.
local function script_sprite_at_frame(script, frame)
    local sprite, scale_numerator, scale_denominator, geometry_width, geometry_height
    for _, instruction in ipairs(script) do
        local id = instruction.id
        local time = instruction.time or 0
        if time > frame then break end
        local candidate = sprite_from_instruction(instruction)
        if candidate then
            sprite = candidate
        elseif id == 402 then
            -- Absolute scale (x, y) or a single value.
            local x = tonumber(instruction[1])
            local y = tonumber(instruction[2])
            if x then
                scale_numerator, scale_denominator = x, y or x
            end
        elseif id == 412 then
            -- Scale interpolation: 412 14 4 <end_x> <end_y>. The trailing pair
            -- is the scale the animation settles on.
            local end_x = tonumber(instruction[3])
            local end_y = tonumber(instruction[4])
            if end_x then
                scale_numerator, scale_denominator = end_x, end_y or end_x
            end
        elseif id==603 then
            geometry_width,geometry_height=tonumber(instruction[1]),tonumber(instruction[2])
        end
    end
    return sprite, scale_numerator, scale_denominator,geometry_width,geometry_height
end

function StageRuntime:curve_image(shot)
    -- 447af1 chooses laser1/laser2; 44b420 selects laser1's colour row.
    local sprite=shot.sprite==1 and (575+math.floor((shot.anim_frame or 0)/2)%4)
        or 523+math.max(0,math.min(15,math.floor(shot.color_index or 0)))
    local index=sprite+1
    for entry_index,entry in ipairs(self.anm.bullet or {}) do
        if index<=#entry.sprites then
            return image_name("bullet",entry_index,index),entry.sprites[index],entry
        end
        index=index-#entry.sprites
    end
end

function StageRuntime:bullet_image(shot)
    -- Player shots live in the ship's own sheet, alongside the ship and the
    -- options. Enemy shots live in the shared bullet sheet. Drawing a player
    -- shot from the enemy sheet is what produced the oversized red beams, whose
    -- sprite happened to be a 64 pixel laser segment.
    if shot.player_bullet then return self:player_bullet_image(shot) end
    if shot.laser_kind=="curve" then
        local image,rect=self:curve_image(shot)
        if rect then return image,rect.w,rect.h,1,1 end
        return nil
    end
    local entries = self.anm.bullet
    if not entries then return nil end
    local descriptor = BulletTypes[shot.sprite or shot.anim or 0]
    if descriptor then
        local color = math.max(0, math.min(15, math.floor(shot.color_index or 0)))
        local global_sprite = descriptor.sprites[color + 1]
        local animation = self.adapter:bullet_animation(shot, descriptor)
        if animation then
            global_sprite = animation:global_sprite()
            shot.blend = animation.blend
        end
        if global_sprite and global_sprite >= 0 then
            -- bullet.anm sprite IDs span archive entries; they are not local
            -- to the entry that holds the animation. Colours select artwork.
            local local_sprite = global_sprite + 1
            for entry_index, entry in ipairs(entries) do
                if local_sprite <= #entry.sprites then
                    local rect = entry.sprites[local_sprite]
                    local animation = shot.legacy_bullet_animation
                    return image_name("bullet", entry_index, local_sprite), rect.w, rect.h,
                        animation and animation.sx or 1, animation and animation.sy or 1
                end
                local_sprite = local_sprite - #entry.sprites
            end
        end
        if animation and animation.geometry_width and animation.geometry_height then
            return nil,nil,nil,animation.sx,animation.sy,
                animation.geometry_width,animation.geometry_height,animation
        end
    end
    -- The sprite family selects which sheet script to play; the colour index
    -- only tints the shape.
    local anim = shot.anim or 0
    local info = self.adapter:bullet_anim_info(anim)
    local entry_index, script
    if info then
        entry_index, script = info.entry_index, info.script
    end
    local frame = shot.anim_frame or 0
    local sprite, scale_x, scale_y, geometry_width, geometry_height = nil, nil, nil, nil, nil
    if script then
        sprite, scale_x, scale_y, geometry_width, geometry_height = script_sprite_at_frame(script, frame)
        if not sprite then
            -- A script that only names one sprite keeps it for the whole life.
            local final_sprite,final_x,final_y,final_width,final_height=
                script_sprite_at_frame(script, math.huge)
            sprite=final_sprite
            scale_x,scale_y=scale_x or final_x,scale_y or final_y
            geometry_width,geometry_height=geometry_width or final_width,geometry_height or final_height
        end
    end
    if sprite then
        local entry = entries[entry_index]
        local rect = entry and entry.sprites and entry.sprites[sprite]
        return image_name("bullet", entry_index, sprite),
            rect and rect.w or 16, rect and rect.h or 16,
            scale_x, scale_y
    end
    if geometry_width and geometry_height then
        return nil,nil,nil,scale_x,scale_y,geometry_width,geometry_height
    end
    local fallback = entries[1] and entries[1].sprites and entries[1].sprites[1]
    return image_name("bullet", 1, 1),
        fallback and fallback.w or 16, fallback and fallback.h or 16,
        nil, nil
end

return StageRuntime
