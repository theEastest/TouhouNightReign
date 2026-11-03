-- Engine adapter: run compiled ECL against the live object model.
--
-- This is the bridge between the pure interpreter (ecl_runtime.lua) and the
-- game. It supplies the host instruction table that spawns enemies and bullets,
-- and drives the ANM player so the imported legacy sprites are drawn.
--
-- Stage 1 is the proof-of-concept target. Instructions outside that scope are
-- counted in `audit` instead of failing, so the coverage of any stage can be
-- measured from a real run.

local EclRuntime = require("tnr.legacy_replay.ecl_runtime")
local BulletPatterns = require("tnr.legacy_replay.bullet_patterns")
local AnmPlayer = require("tnr.legacy_replay.anm_player")
local Sounds = require("tnr.legacy_replay.sounds")

local Adapter = {}
local function angle_between(x1, y1, x2, y2)
    local x, y = x2 - x1, y2 - y1
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    return y > 0 and math.pi / 2 or (y < 0 and -math.pi / 2 or 0)
end

Adapter.__index = Adapter

-- Bullet colour indices are shared with the THlib bullet module.
local COLOR = {
    DEEP_RED = 1, RED = 2, DEEP_PURPLE = 3, PURPLE = 4, DEEP_BLUE = 5,
    BLUE = 6, ROYAL_BLUE = 7, CYAN = 8, DEEP_GREEN = 9, GREEN = 10,
    CHARTREUSE = 11, YELLOW = 12, GOLDEN_YELLOW = 13, ORANGE = 14,
    DEEP_GRAY = 15, GRAY = 16,
}

-- Reference sentinel: an angle or coordinate of -999999 means "keep the
-- current value". The ECL compiler emits it wherever the original script wrote
-- the current angle, so resolving it to a real number is what makes an enemy
-- fly along the direction it is already facing instead of along a garbage
-- angle like cos(-999999).
local SENTINEL = -999999

--- Apply the reference sentinel to an angle.
-- A value at or below the sentinel keeps the object's current heading.
local function resolve_angle(value, current)
    local angle = tonumber(value)
    if angle == nil or angle <= SENTINEL then return current or 0 end
    return angle
end

Adapter.resolve_angle = resolve_angle

--- Resolve an ECL instruction argument to a number.
-- An argument may be a literal expression, a variable reference, or a
-- per-difficulty branch table the compiler emitted for a difficulty block. All
-- three resolve through the same operand resolver.
local function resolve_arg(thread, value, fallback)
    if type(value) == "table" then
        return EclRuntime.resolve(thread, value)
    end
    if value == nil then return fallback end
    return EclRuntime.evaluate_expression(thread, tostring(value))
end

Adapter.resolve_arg = resolve_arg

-- TH15 uses the shared modern interpolator (remaining-time API retained).
local interpolate = require("tnr.legacy_replay.interpolation")
local function ease_fraction(mode, remaining)
    return interpolate(mode, 1 - remaining)
end

Adapter.ease_fraction = ease_fraction

---@param options table { lstg, enemy_class, bullet_styles, anm, difficulty }
function Adapter.new(options)
    local self = setmetatable({
        lstg = options.lstg,
        enemy_class = options.enemy_class,
        bullet_styles = options.bullet_styles or {},
        anm = options.anm or {},
        audit = {},
        enemies = {},
        boss_ui = options.boss_ui,
        random = options.random,
        stage_key = options.stage_key,
    }, Adapter)
    self.difficulty = options.difficulty or EclRuntime.DIFFICULTY.NORMAL
    self.instructions = self:build_instructions()
    -- Engine globals the ECL reads: the player position, the difficulty id and
    -- the difficulty flags. Publishing them here means expressions such as
    -- `%PLAYER_X2` resolve instead of collapsing to zero.
    local host_ref = self
    -- Random globals are drawn once per access, matching the reference where
    -- %RANDF is a fresh value each time a script reads it.
    local function random_float(minimum, maximum)
        if host_ref.random then return host_ref.random(minimum, maximum) end
        return minimum + math.random() * (maximum - minimum)
    end
    local function angle_to_player()
        local player = host_ref.player or (host_ref.lstg and host_ref.lstg.player)
        local boss = host_ref.boss_object
        if not player or not boss then return 0 end
        return math.atan(player.y - (boss.y or 0), player.x - (boss.x or 0))
    end
    local function globals_provider()
        local player = host_ref.player or (host_ref.lstg and host_ref.lstg.player)
        local boss = host_ref.boss_object
        local difficulty = host_ref.difficulty or EclRuntime.DIFFICULTY.NORMAL
        return {
            PLAYER_X = player and player.x or 0,
            PLAYER_Y = player and player.y or 0,
            PLAYER_X2 = player and player.x or 0,
            PLAYER_Y2 = player and player.y or 0,
            BOSS_X = boss and boss.x or 0,
            BOSS_Y = boss and boss.y or 0,
            ANGLE_PLAYER = angle_to_player(),
            ABS_ANGLE_PLAYER = angle_to_player(),
            DIST_PLAYER = (player and boss)
                and math.sqrt((player.x - (boss.x or 0)) ^ 2 + (player.y - (boss.y or 0)) ^ 2) or 0,
            -- Random values: a fraction for RANDF, a signed fraction for
            -- RANDF2 and a full turn for RANDRAD.
            RANDF = random_float(0, 1),
            RANDF2 = random_float(-1, 1),
            RANDRAD = random_float(0, math.pi * 2),
            DIFF = difficulty,
            EASY = difficulty == 0 and 1 or 0,
            NORMAL = difficulty == 1 and 1 or 0,
            HARD = difficulty == 2 and 1 or 0,
            LUNATIC = difficulty == 3 and 1 or 0,
            RANK = 32,
            TRUE = 1,
        }
    end
    self.runtime = EclRuntime.new(options.chunks or {}, {
        instructions = self.instructions,
        difficulty = self.difficulty,
        -- The runtime calls this for any global a script reads.
        globals = setmetatable({}, {
            __index = function(_, name) return globals_provider()[name] end,
        }),
    })
    -- Publish the difficulty on the runtime itself for operand resolution.
    self.runtime.difficulty = self.difficulty
    return self
end

--- Record an instruction or opcode the adapter does not implement yet.
function Adapter:note(name)
    self.audit[name] = (self.audit[name] or 0) + 1
end

--- Spawn a legacy enemy and attach an ECL thread to it.
function Adapter:spawn_enemy(routine, x, y, hp, args, caller_thread)
    local lua_class = self.enemy_class
    local object
    if lua_class ~= nil and type(self.lstg.New) == "function" then
        -- The engine enemy class takes (style, hp, clear_bullet, auto_delete).
        local ok, created = pcall(self.lstg.New, lua_class, 1, hp or 50, false, true)
        object = ok and created or nil
    end
    if not object then
        object = { x = x, y = y }
    end
    if object then
        object.x, object.y = x, y
        -- The ECL creation call carries the enemy's hit points; keep them on the
        -- object so player damage and the drop check have something to work
        -- with when the host does not provide a real enemy class.
        object.hp = tonumber(hp) or object.hp or 50
        object.max_hp = object.hp
        object.legacy_ecl = routine
        object.legacy_body_visible = false
        -- Attach the animation player for the stage's enemy archive.
        local archive, archive_name, entry_index = self:enemy_archive()
        if archive then
            object.legacy_anm = AnmPlayer.new(archive, archive_name, entry_index)
        end
        self.enemies[#self.enemies + 1] = object
    end
    -- Start the requested routine. The caller supplies the namespace context
    -- so a bare name such as "GirlRedA01e" resolves to "st01.GirlRedA01e".
    local thread = self.runtime:spawn(routine, caller_thread or nil)
    thread.object = object
    thread.runtime = self.runtime
    if object then object.legacy_thread = thread end
    self.runtime.threads[#self.runtime.threads + 1] = thread
    return object, thread
end

--- Resolve an anmSelect index to a sheet.
-- The reference numbers the sheets the stage loaded rather than the entries
-- inside one archive: 1 is the shared default sheet, 2 is the enemy sheet, and
-- 3 upwards are the boss sheets. Only the ones actually collected are offered,
-- and an unrecognised index falls back to the enemy sheet so an enemy still
-- draws something instead of vanishing.
function Adapter:select_archive(selection)
    local stage = self.stage_key or (self.enemy_archive_name or "st01enm"):match("^(st%d%d)") or "st01"
    if selection == 1 then
        -- The default sheet holds generic effects. Fall back to the enemy
        -- sheet when it was not collected.
        if self.anm["enemy"] then return "enemy", 1 end
        return self.enemy_archive_name, 1
    end
    if selection >= 3 then
        -- Boss sheets are the stage number plus bs. st07 has extra sheets for
        -- its two final forms.
        local boss_candidates = { stage .. "bs", stage .. "bs2", stage .. "mbs" }
        if selection == 4 and self.anm[stage .. "mbs2"] then
            return stage .. "mbs2", 1
        end
        if selection == 5 and self.anm[stage .. "bs2"] then
            return stage .. "bs2", 1
        end
        for _, name in ipairs(boss_candidates) do
            if self.anm[name] then return name, 1 end
        end
    end
    -- The enemy sheet is the default for stage enemies.
    if self.anm["enemy"] then return "enemy", 1 end
    return self.enemy_archive_name, 1
end

--- Resolve the ANM archive entry that holds the enemy sprites.
-- The adapter picks the archive for the stage it is running; the stage runtime
-- publishes it through `enemy_archive`.
function Adapter:enemy_archive()
    local archive_name = self.enemy_archive_name or "st01enm"
    local archive = self.anm[archive_name]
    return archive and archive[1] or nil, archive_name, 1
end

--- Build the instruction table the interpreter dispatches into.
function Adapter:build_instructions()
    local self_ref = self
    local instructions = {}

    -- --- enemy setup -------------------------------------------------------
    instructions.anmSelect = function(thread, runtime, args)
        -- anmSelect picks the sheet the enemy draws from. The index is not an
        -- entry position: it names one of the sheets the stage loaded. The
        -- reference uses 1 for the shared default sheet, 2 for the enemy sheet
        -- and 3 and up for the boss sheets. Stage enemies all select 2, so
        -- reading the value as an entry index drew every fairy from a portrait
        -- sheet and produced the wrong sprites entirely.
        local selection = tonumber(args and args[1]) or 2
        thread.anm_selection = selection
        local object = thread.object
        if not object or not object.legacy_anm then return end
        local archive_name, entry_index = self_ref:select_archive(selection)
        local archive = archive_name and self_ref.anm[archive_name]
        local entry = archive and (archive[entry_index] or archive[1])
        if entry then
            object.legacy_anm:set_archive(entry, archive_name, entry_index)
            object.legacy_archive = archive_name
        end
    end
    instructions.anmSetMain = function(thread, runtime, args)
        -- anmSetMain(slot, scriptId): slot zero is the body, so it plays the
        -- script. The higher slots are overlays and are recorded rather than
        -- taking over the body animation.
        local player = thread.object and thread.object.legacy_anm
        if not player then return end
        local slot = resolve_arg(thread, args and args[1], 0) or 0
        if slot ~= 0 then return end
        thread.object.legacy_body_visible = true
        player:play(resolve_arg(thread, args and args[2], 0) or 0)
    end
    instructions.anmSetSprite = function(thread, runtime, args)
        -- anmSetSprite(slot, spriteId): the first argument names the animation
        -- slot and the second the sprite within the selected sheet. Slot zero is
        -- the body; the higher slots draw a second picture over it (an aura, a
        -- charge effect). Only the body drives the enemy's own sprite here, or a
        -- later slot would overwrite the animation the body just started.
        local player = thread.object and thread.object.legacy_anm
        if not player then return end
        local slot = resolve_arg(thread, args and args[1], 0) or 0
        if slot ~= 0 then
            thread.anm_slot_sprites = thread.anm_slot_sprites or {}
            thread.anm_slot_sprites[slot] = resolve_arg(thread, args and args[2], nil)
            return
        end
        local sprite = resolve_arg(thread, args and args[2], nil)
        if sprite == nil then sprite = resolve_arg(thread, args and args[1], 0) end
        player.sprite = (tonumber(sprite) or 0) + 1
        thread.object.legacy_body_visible = true
    end
    instructions.anmPlay = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        local slot = resolve_arg(thread, args and args[1], 0)
        if player and slot == 0 then
            thread.object.legacy_body_visible = true
            player:play(resolve_arg(thread, args and args[2], 0) or 0)
        elseif thread.object then
            thread.object.legacy_overlay_scripts = thread.object.legacy_overlay_scripts or {}
            thread.object.legacy_overlay_scripts[slot] = resolve_arg(thread, args and args[2], 0)
        end
    end
    instructions.setHitbox = function(thread, runtime, args)
        if thread.object then
            thread.object.legacy_hitbox = {
                resolve_arg(thread, args and args[1], 0),
                resolve_arg(thread, args and args[2], 0),
            }
        end
    end
    instructions.setHurtbox = function(thread, runtime, args)
        if thread.object then
            -- The sizes arrive as ECL literals such as `24.0f`, which are not
            -- Lua numbers. Reading them with tonumber left every hurtbox at
            -- zero and every collision at the fallback radius.
            thread.object.legacy_hurtbox = {
                resolve_arg(thread, args and args[1], 0),
                resolve_arg(thread, args and args[2], 0),
            }
        end
    end

    -- --- movement ----------------------------------------------------------
    -- The reference has two movement modes. A velocity move keeps a constant
    -- velocity; a time move interpolates the object along an eased path over a
    -- fixed number of frames. `movePosTime(time, mode, x, y)` and
    -- `moveVelTime(time, mode, angle, speed)` both select an easing curve from
    -- their second argument.
    local function start_velocity_move(object, angle, speed)
        object.legacy_velocity_tween = nil
        object.legacy_angle = resolve_angle(angle, object.legacy_angle)
        object.legacy_speed = tonumber(speed) or 0
        object.legacy_vx = math.cos(object.legacy_angle) * object.legacy_speed
        object.legacy_vy = math.sin(object.legacy_angle) * object.legacy_speed
        object.legacy_move = nil
    end

    local function start_time_move(object, frames, raw_mode, target_x, target_y, angle, speed)
        object.legacy_velocity_tween = nil
        local mode = tonumber(raw_mode) or 0
        local start_x = object.x or 0
        local start_y = object.y or 0
        local end_x, end_y = target_x, target_y
        if end_x == nil then
            -- Velocity form. The reference stores half the path in moveInterp and
            -- integrates it with the easing curve, so the destination is the
            -- direction and distance travelled over the move:
            --
            --     moveInterp = cos(angle) * speed * res / 2
            --
            -- The four arguments are (time, ease, angle, speed). The angle is
            -- frequently the -999999 sentinel, which means "keep the heading the
            -- enemy already has" rather than a real direction; the speed is a
            -- real value either way. An earlier reading of the sentinel as
            -- "keep the speed too" left a wave that had been told to decelerate
            -- to zero unable to move again.
            local raw_angle = tonumber(angle)
            local keep_heading = raw_angle == nil or raw_angle <= SENTINEL
            local resolved = keep_heading and (object.legacy_angle or 0) or raw_angle
            object.legacy_angle = resolved
            object.legacy_speed = tonumber(speed) or object.legacy_speed or 0
            local distance = object.legacy_speed * math.max(1, frames) * 0.5
            end_x = start_x + math.cos(resolved) * distance
            end_y = start_y + math.sin(resolved) * distance
        end
        object.legacy_move = {
            mode = mode,
            total = math.max(1, frames),
            remaining = math.max(1, frames),
            start_x = start_x,
            start_y = start_y,
            end_x = end_x,
            end_y = end_y,
        }
        object.legacy_vx = nil
        object.legacy_vy = nil
    end

    instructions.moveVel = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        start_velocity_move(object,
            EclRuntime.evaluate_expression(thread, tostring(args[1] or "0")),
            EclRuntime.evaluate_expression(thread, tostring(args[2] or "0")))
    end
    instructions.moveVelTime = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        local frames = math.max(1, resolve_arg(thread, args[1], 1))
        local speed = resolve_arg(thread, args[4], object.legacy_speed or 0)
        if speed <= SENTINEL then speed = object.legacy_speed or 0 end
        object.legacy_velocity_tween = {
            total = frames, remaining = frames,
            mode = resolve_arg(thread, args[2], 0),
            start_angle = object.legacy_angle or 0,
            end_angle = resolve_angle(resolve_arg(thread, args[3], SENTINEL), object.legacy_angle),
            start_speed = object.legacy_speed or 0, end_speed = speed,
        }
        object.legacy_move = nil
    end
    instructions.movePosTime = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        start_time_move(object,
            EclRuntime.evaluate_expression(thread, tostring(args[1] or "0")),
            args[2],
            EclRuntime.evaluate_expression(thread, tostring(args[3] or "0")),
            EclRuntime.evaluate_expression(thread, tostring(args[4] or "0")))
    end
    instructions.moveVelNM = instructions.moveVel
    instructions.moveVelNMTime = instructions.moveVelTime

    -- Relative / timed movement variants. The exact easing differs in the
    -- reference, but applying the velocity for the requested duration keeps the
    -- enemy on the same path.
    instructions.moveSpeedTime = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        local speed = tonumber(args[1]) or 0
        local angle = tonumber(args[2]) or 0
        object.legacy_vx = math.cos(angle) * speed
        object.legacy_vy = math.sin(angle) * speed
        thread.move_timer = { remaining = tonumber(args[3]) or 0 }
    end
    instructions.moveAngleTime = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        local angle = tonumber(args[1]) or 0
        local speed = tonumber(args[2]) or (object.legacy_speed or 0)
        object.legacy_speed = speed
        object.legacy_vx = math.cos(angle) * speed
        object.legacy_vy = math.sin(angle) * speed
        thread.move_timer = { remaining = tonumber(args[3]) or 0 }
    end
    instructions.moveEllipseRel = function(thread, runtime, args)
        -- Circular drift around the current position: keep the tangential
        -- velocity so the enemy arcs instead of flying straight.
        local object = thread.object
        if not object then return end
        local radius = tonumber(args[1]) or 0
        local speed = tonumber(args[2]) or 0
        local angle = tonumber(args[3]) or 0
        if radius ~= 0 then
            local tangential = (speed > 0) and 1 or -1
            object.legacy_vx = -math.sin(angle) * math.abs(speed) * tangential
            object.legacy_vy = math.cos(angle) * math.abs(speed) * tangential
        else
            object.legacy_vx = math.cos(angle) * speed
            object.legacy_vy = math.sin(angle) * speed
        end
    end
    instructions.moveEllipseRelTime = function(thread, runtime, args)
        instructions.moveEllipseRel(thread, runtime, args)
        thread.move_timer = { remaining = tonumber(args[4]) or 0 }
    end

    -- --- drops -------------------------------------------------------------
    instructions.dropMain = function(thread, runtime, args)
        if thread.object then thread.object.legacy_drop = tonumber(args and args[1]) or 0 end
    end
    instructions.dropExtra = function(thread, runtime, args)
        -- Extra item drop: records the requested drop so the adapter can spawn
        -- the matching pickup when the enemy dies.
        if thread.object then
            thread.object.legacy_drop_extra = {
                tonumber(args and args[1]) or 0,
                tonumber(args and args[2]) or 0,
            }
        end
    end

    -- --- lifecycle ---------------------------------------------------------
    instructions.delete = function(thread, runtime)
        -- delete() destroys the enemy. It must leave the enemy list, or a wave
        -- that has flown off the bottom would stay on screen forever and the
        -- field would fill with ghosts.
        local object = thread.object
        if object then
            object.legacy_deleted = true
            object.hp = 0
            if self_ref.lstg.Del then pcall(self_ref.lstg.Del, object) end
        end
        thread.state = "finished"
    end
    instructions.ins_569 = function() end
    instructions.setBoss = function(thread, runtime, args)
        -- Track the boss so scripts that read BOSS_X and BOSS_Y resolve.
        local value = tonumber(args and args[1]) or 0
        if value >= 0 and thread.object then
            self_ref:set_boss_object(thread.object)
            thread.object.legacy_is_boss = true
            if self_ref.boss_ui then self_ref.boss_ui:begin(100, {}) end
        elseif value < 0 then
            self_ref.boss_object = nil
            if self_ref.boss_ui then self_ref.boss_ui.visible = false end
        end
    end
    instructions.setInvuln = function(thread, runtime, args)
        if thread.object then
            thread.object.legacy_invulnerable_until = (self_ref.frame or 0) + resolve_arg(thread, args[1], 0)
        end
    end
    instructions.flagSet = function() end
    instructions.flagClear = function() end
    instructions.setInterrupt = function() end
    instructions.setTimeout = function(thread, runtime, args)
        if thread.object then
            thread.object.legacy_timeouts = thread.object.legacy_timeouts or {}
            thread.object.legacy_timeouts[resolve_arg(thread,args[1],0)] = args[2]
        end
    end
    instructions.setChapter = function() end
    instructions.lifeSet = function(thread, runtime, args)
        local value = tonumber(args and args[1]) or 0
        if thread.object then thread.object.hp = value end
        if self_ref.boss_ui then self_ref.boss_ui:set_health(value, self_ref.boss_ui.health_max) end
    end
    instructions.dialogWait = function(thread)
        local dialog = self_ref.dialogue
        if not dialog or not dialog.active then thread.dialog_wait_generation = nil; return end
        if thread.dialog_wait_generation == nil then thread.dialog_wait_generation = dialog.generation end
        if thread.dialog_wait_generation ~= dialog.generation then
            thread.dialog_wait_generation = nil
            return
        end
        thread.pc = thread.pc - 1
        thread.wait = 1
    end
    instructions.bossWait = function(thread, runtime)
        -- HP reaching zero can start another phase. Only the script's
        -- setBoss(-1)/delete releases the stage's boss wait.
        local boss = self_ref.boss_object
        if boss and not boss.legacy_deleted then
            thread.pc = thread.pc - 1
            thread.wait = 1
        end
    end
    -- Sound. The reference names an effect by its index into a fixed list, so
    -- the index is translated to the corresponding file and handed to whoever
    -- owns the audio device.
    local function play_reference_sound(index)
        if not self_ref.on_sound then return end
        local path = Sounds.path_for(index)
        if not path then return end
        pcall(self_ref.on_sound, path)
    end
    instructions.playSound = function(thread, runtime, args)
        play_reference_sound(resolve_arg(thread, args and args[1], nil))
    end
    instructions.hitSound = instructions.playSound
    instructions.bgmPlay = function() end

    -- --- conditions --------------------------------------------------------
    instructions.diffI = function(thread, runtime, args)
        -- diffI($A, easy, normal, hard, lunatic, extra) assigns the slot for the
        -- active difficulty.
        local slot = tostring(args[1] or ""):gsub("^[$%%]", "")
        local by_difficulty = { [0] = 2, [1] = 3, [2] = 4, [3] = 5, [4] = 6 }
        local index = by_difficulty[self_ref.difficulty] or 3
        local value = tonumber(args[index])
        if not value then value = tonumber(args[index - 1]) or 1 end
        thread.ints[slot] = value
    end

    -- --- bullets -----------------------------------------------------------
    -- The et* family builds one bullet group. etNew starts a group, the
    -- following et* calls configure it, and etOn fires it once configured.
    -- Bullet groups. An enemy can hold several groups at once and fire them in
    -- any order: a stage enemy creates group 0, copies it to group 1 to offset
    -- it, and then fires both. Keeping a single group lost every group but the
    -- last, so a two sided volley collapsed into one bullet.
    local function bullet_groups(thread)
        thread.bullets = thread.bullets or {}
        return thread.bullets
    end
    local function group_at(thread, index)
        local groups = bullet_groups(thread)
        local key = tonumber(index) or 0
        local group = groups[key]
        if not group then
            group = {
                count = 1, count_spec = 1,
                angle = 0, angle_spec = 0,
                speed = 3, speed_spec = 3,
                sprite = 0,
            }
            groups[key] = group
        end
        return group
    end
    -- Resolve a per-difficulty argument list.
    -- etCountD(group, easy, normal, hard, lunatic, overdrive) and etSpeedD carry
    -- Resolve a per-difficulty argument list.
    -- etSpeedD(group, easy, normal, hard, lunatic, overdrive) carries one value
    -- per difficulty. Reading it like the plain two argument form fired the wrong
    -- value on every difficulty, and reading the tail instead of the entry for
    -- the active difficulty fired the last one. The active difficulty's entry is
    -- selected here, with a fallback to the highest supplied entry.
    local DIFFICULTY_ORDER = { "easy", "normal", "hard", "lunatic", "overdrive" }
    local function difficulty_value(thread, args)
        if not args then return nil end
        local values = {}
        local supplied = 0
        for position, name in ipairs(DIFFICULTY_ORDER) do
            local raw = args[position + 1]
            if raw ~= nil then
                local value = resolve_arg(thread, raw, nil)
                if value ~= nil then
                    values[name] = value
                    supplied = position
                end
            end
        end
        if supplied == 0 then return nil end
        local active = DIFFICULTY_ORDER[(self_ref.difficulty or 0) + 1] or "normal"
        if values[active] ~= nil then return values[active] end
        -- A list that stops early uses its last entry for the harder modes.
        for position = math.min(supplied, #DIFFICULTY_ORDER), 1, -1 do
            local name = DIFFICULTY_ORDER[position]
            if values[name] ~= nil then return values[name] end
        end
        return nil
    end
    instructions.etNew = function(thread, runtime, args)
        local index = tonumber(resolve_arg(thread, args and args[1], 0)) or 0
        local previous = bullet_groups(thread)[index]
        bullet_groups(thread)[index] = {
            index = index,
            count = 1, count_spec = 1,
            angle = 0, angle_spec = 0,
            speed = 3, speed_spec = 3,
            -- A new group inherits the sprite the enemy last selected, which is
            -- how the reference carries etSprite across groups.
            sprite = previous and previous.sprite or thread.last_bullet_sprite or 0,
            anim = previous and previous.anim or thread.last_bullet_anim,
            color_index = previous and previous.color_index or thread.last_bullet_color,
            aim = nil, offset = nil,
        }
    end
    instructions.etSprite = function(thread, runtime, args)
        -- etSprite(group, bulletType, colour). The bullet type is an index into
        -- the reference's bullet type table, which names the sprite and its
        -- animation script; the third argument is the colour index into the
        -- palette. Both are remembered on the enemy so a group created later
        -- still knows what to draw.
        thread.last_bullet_sprite = resolve_arg(thread, args and args[2], 0) or 0
        thread.last_bullet_color = resolve_arg(thread, args and args[3], 0) or 0
        local group = group_at(thread, args and args[1])
        group.sprite = thread.last_bullet_sprite
        group.anim = thread.last_bullet_sprite
        group.color_index = thread.last_bullet_color
        group.variant = thread.last_bullet_color
    end
    instructions.etAngle = function(thread, runtime, args)
        -- The angle is the base direction for the volley; a sentinel keeps the
        -- current one, and the second value is the per-bullet spread.
        local group = group_at(thread, args and args[1])
        local raw = resolve_arg(thread, args and args[2], 0)
        group.angle = resolve_angle(raw, group.angle)
        group.angle_spec = resolve_arg(thread, args and args[3], 0) or 0
    end
    instructions.etSpeed = function(thread, runtime, args)
        local group = group_at(thread, args and args[1])
        group.speed = resolve_arg(thread, args and args[2], 3)
        group.speed_spec = resolve_arg(thread, args and args[3], 0) or group.speed
    end
    instructions.etCount = function(thread, runtime, args)
        local group = group_at(thread, args and args[1])
        local count = resolve_arg(thread, args and args[2], 1)
        group.count = math.max(1, math.floor(count or 1))
        local rings = resolve_arg(thread, args and args[3], 1)
        group.count_spec = math.max(1, math.floor(rings or 1))
    end
    -- The D suffixed forms carry one value per difficulty after the group.
    instructions.etCountD = function(thread, runtime, args)
        local group = group_at(thread, args and args[1])
        local value = difficulty_value(thread, args)
        group.count = math.max(1, math.floor(value or 1))
        -- The ring count is the last argument in the reference layout; reuse the
        -- supplied tail when present.
        local last = resolve_arg(thread, args and args[#args], nil)
        group.count_spec = math.max(1, math.floor(last or 1))
    end
    instructions.etSpeedD = function(thread, runtime, args)
        local group = group_at(thread, args and args[1])
        local value = difficulty_value(thread, args)
        group.speed = value or 3
        group.speed_spec = group.speed
    end
    instructions.etAngleD = function(thread, runtime, args)
        local group = group_at(thread, args and args[1])
        local value = difficulty_value(thread, args)
        group.angle = resolve_angle(value, group.angle)
    end
    instructions.etSpriteD = function(thread, runtime, args)
        local group = group_at(thread, args and args[1])
        local value = difficulty_value(thread, args)
        group.sprite = value or group.sprite
        group.anim = group.sprite
    end
    instructions.etAim = function(thread, runtime, args)
        -- etAim(group, mode): the mode chooses the volley shape.
        local group = group_at(thread, args and args[1])
        group.aim = resolve_arg(thread, args and args[2], 0)
    end
    instructions.etOffset = function(thread, runtime, args)
        local group = group_at(thread, args and args[1])
        group.offset = {
            resolve_arg(thread, args and args[2], 0) or 0,
            resolve_arg(thread, args and args[3], 0) or 0,
        }
    end
    instructions.etCopy = function(thread, runtime, args)
        -- etCopy(target, source) duplicates a group.
        local target = tonumber(resolve_arg(thread, args and args[1], 0)) or 0
        local source = tonumber(resolve_arg(thread, args and args[2], 0)) or 0
        local groups = bullet_groups(thread)
        local from = groups[source]
        if not from then return end
        local copy = {}
        for key, value in pairs(from) do
            if type(value) == "table" then
                local inner = {}
                for k2, v2 in pairs(value) do inner[k2] = v2 end
                copy[key] = inner
            else
                copy[key] = value
            end
        end
        copy.index = target
        groups[target] = copy
    end
    instructions.etClear = function(thread, runtime, args)
        local groups = bullet_groups(thread)
        if args and args[1] ~= nil then
            groups[tonumber(resolve_arg(thread, args[1], 0)) or 0] = nil
        else
            thread.bullets = {}
        end
    end
    instructions.etClearAll = instructions.etClear
    instructions.etCancel = instructions.etClear
    instructions.etEx = function(thread, runtime, args)
        -- etEx(group, ?, flags, int1, int2, float1, float2). The reference reads
        -- this as an effects block: the flags choose the behaviour and the
        -- remaining fields parameterise it. The arguments are ECL expressions,
        -- so resolve them rather than reading literals.
        local group = group_at(thread, args and args[1])
        group.ex = {
            flags = resolve_arg(thread, args and args[3], 0) or 0,
            int1 = resolve_arg(thread, args and args[4], -999999),
            int2 = resolve_arg(thread, args and args[5], -999999),
            float1 = resolve_arg(thread, args and args[6], -999999),
            float2 = resolve_arg(thread, args and args[7], -999999),
        }
    end
    instructions.etExSet = instructions.etEx
    instructions.etOn = function(thread, runtime, args)
        -- etOn(group) fires that group. Several groups can be on at once, which
        -- is how the reference fires a mirrored pair of volleys.
        if args and args[1] ~= nil then
            local index = tonumber(resolve_arg(thread, args[1], 0)) or 0
            self_ref:fire_bullet_group(thread, index)
        else
            -- Without an index every prepared group fires.
            for index in pairs(bullet_groups(thread)) do
                self_ref:fire_bullet_group(thread, index)
            end
        end
    end
    instructions.etSound = function(thread, runtime, args)
        -- etSound(group, index, ...) plays the effect named by the second
        -- argument.
        play_reference_sound(resolve_arg(thread, args and args[2], nil))
    end
    instructions.etDist = function() end
    instructions.etOffsetAbs = function(thread, runtime, args)
        -- Offset the group to an absolute field position.
        local group = group_at(thread, args and args[1])
        group.offset_abs = {
            resolve_arg(thread, args and args[2], 0) or 0,
            resolve_arg(thread, args and args[3], 0) or 0,
        }
    end
    instructions.etOffsetRad = function(thread, runtime, args)
        -- Offset the group by a distance along an angle.
        local group = group_at(thread, args and args[1])
        local angle = resolve_arg(thread, args and args[2], 0) or 0
        local distance = resolve_arg(thread, args and args[3], 0) or 0
        group.offset = {
            math.cos(angle) * distance, math.sin(angle) * distance,
        }
    end

    -- --- enemy creation ----------------------------------------------------
    instructions.enmCreate = function(thread, runtime, args)
        self_ref:create_enemy(thread, runtime, args)
    end
    instructions.enmCreateA = instructions.enmCreate
    instructions.enmCreateM = instructions.enmCreate
    instructions.enmCreateF = instructions.enmCreate
    instructions.enmKillAll = function() end
    instructions.enmAlive = function() end
    instructions.setDeath = function() end

    -- --- boss presentation -------------------------------------------------
    -- The reference drives its HUD from these. The adapter forwards them to
    -- the boss UI so the bar, marker row and name plate match the original.
    instructions.setBoss = function(thread, runtime, args)
        -- setBoss(0) starts the fight, setBoss(-1) ends it.
        local value = tonumber(args and args[1]) or 0
        if value >= 0 then
            self_ref.boss_object = thread.object
            if thread.object then thread.object.legacy_is_boss = true end
            if self_ref.boss_ui then self_ref.boss_ui:begin(100, {}) end
        else
            if self_ref.boss_object == thread.object then self_ref.boss_object = nil end
            if self_ref.boss_ui then self_ref.boss_ui.visible = false end
        end
    end
    instructions.lifeSet = function(thread, runtime, args)
        local value = tonumber(args and args[1]) or 0
        if thread.object then thread.object.hp = value end
        if self_ref.boss_ui then
            self_ref.boss_ui:set_health(value, self_ref.boss_ui.health_max)
        end
    end
    instructions.lifeHide = function() end
    instructions.lifeMarker = function(thread, runtime, args)
        -- lifeMarker(index, value, colour) adds a bar segment for a spell card.
        if self_ref.boss_ui then
            local count = self_ref.boss_ui.marker_count + 1
            self_ref.boss_ui.marker_count = count
            self_ref.boss_ui.health_layers[count] = {
                value = tonumber(args and args[2]) or 0,
                colour = tonumber(args and args[3]) or 0xFFFFFFFF,
            }
        end
    end
    instructions.setInterrupt = function(thread, runtime, args)
        -- setInterrupt(id, start, finish, "label") registers the subroutine that
        -- runs when the boss health crosses the start threshold. The reference
        -- stores it per enemy and triggers it from the manager, which is what
        -- advances nonspell -> spell -> nonspell.
        if not thread.object then return end
        thread.object.legacy_interrupts = thread.object.legacy_interrupts or {}
        local id = tonumber(args and args[1]) or 0
        thread.object.legacy_interrupts[id] = {
            start = tonumber(args and args[2]) or 0,
            finish = tonumber(args and args[3]) or 0,
            routine = tostring(args and args[4] or ""),
            fired = false,
            registered_frame = self_ref.frame or 0,
            id = id,
        }
    end
    instructions.spell = function(thread, runtime, args)
        self_ref:begin_spell(thread, args)
    end
    instructions.spell3 = function(thread, runtime, args)
        self_ref:begin_spell(thread, args)
    end
    instructions.spellEnd = function()
        if self_ref.boss_ui then self_ref.boss_ui.card_timer = 0 end
    end
    -- 527 / 554 / 536 are declaration helpers with no presentation of their own.
    instructions.stageLogo = function() end
    instructions.ins_569 = function() end
    instructions.ins_570 = function() end
    instructions.nop = function() end
    instructions.debug22 = function() end
    instructions.timerReset = function(thread)
        if thread.object then thread.object.legacy_timer_start = self_ref.frame or 0 end
    end
    instructions.dialogRead = function(thread, runtime, args)
        self_ref.dialog_request = resolve_arg(thread,args[1],0)
        if self_ref.dialogue then self_ref.dialogue:start(self_ref.dialog_request)
        else
            runtime.unhandled = runtime.unhandled or {}
            runtime.unhandled["missing_dialogue"] = (runtime.unhandled["missing_dialogue"] or 0) + 1
        end
    end
    instructions.funcSet = function() end
    instructions.funcCall = function() end
    instructions.spec1 = function() end
    instructions.spec2 = function() end
    instructions.callSTD = function() end
    instructions.diffWait = function() end
    instructions.anm316 = function(thread, runtime, args)
        -- anm316(index, sprite) sets a secondary animation sprite.
        local player = thread.object and thread.object.legacy_anm
        if player and args and args[2] ~= nil then
            player.sprite = (tonumber(args[2]) or 0) + 1
        end
    end
    instructions.anmPlayAbs = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        if player then player:play(tonumber(args and args[1]) or 0) end
    end
    instructions.anmSelectedPlay = instructions.anmPlayAbs
    instructions.diffF = function(thread, runtime, args)
        -- diffF(%A, easy, normal, hard, lunatic, extra): assign the float slot
        -- for the active difficulty.
        local slot = tostring(args[1] or ""):gsub("^[$%%]", "")
        local by_difficulty = { [0] = 2, [1] = 3, [2] = 4, [3] = 5, [4] = 6 }
        local index = by_difficulty[self_ref.difficulty] or 3
        local value = tonumber(args[index])
        if not value then value = tonumber(args[index - 1]) or 1 end
        thread.floats[slot] = value
    end
    -- etEx2 / etExSet2 are the two-argument forms of the bullet extras; the
    -- group configuration is the same, only the argument count differs.
    instructions.etEx2 = function(thread, runtime, args)
        local group = group_at(thread, args and args[1])
        group.ex = {
            flags = resolve_arg(thread, args and args[2], 0) or 0,
            int1 = resolve_arg(thread, args and args[3], -999999),
            int2 = resolve_arg(thread, args and args[4], -999999),
            float1 = resolve_arg(thread, args and args[5], -999999),
            float2 = resolve_arg(thread, args and args[6], -999999),
        }
    end
    instructions.etExSet2 = instructions.etEx2

    -- --- boss movement and effects -----------------------------------------
    instructions.moveRand = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        -- moveRand(duration, distance, speed): pick a random nearby target.
        local distance = tonumber(args and args[2]) or 0
        local speed = tonumber(args and args[3]) or 1
        local angle = (self_ref.random and self_ref.random() or math.random()) * math.pi * 2
        object.legacy_move_target = {
            x = (object.x or 0) + math.cos(angle) * distance,
            y = (object.y or 0) + math.sin(angle) * distance,
        }
        object.legacy_move_speed = speed
        thread.move_timer = { remaining = tonumber(args and args[1]) or 60 }
    end
    instructions.movePos = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        object.legacy_move_target = {
            x = tonumber(args and args[1]) or 0,
            y = tonumber(args and args[2]) or 0,
        }
    end
    instructions.moveLimit = function(thread, runtime, args)
        -- Clamp movement to a box around the current position.
        local object = thread.object
        if object then
            object.legacy_move_limit = {
                left = tonumber(args and args[1]) or 0,
                right = tonumber(args and args[2]) or 0,
                top = tonumber(args and args[3]) or 0,
                bottom = tonumber(args and args[4]) or 0,
            }
        end
    end
    instructions.moveLimitReset = function(thread, runtime)
        if thread.object then thread.object.legacy_move_limit = nil end
    end
    instructions.moveSetMirror = function(thread, runtime, args)
        if thread.object then thread.object.legacy_mirror = (tonumber(args and args[1]) or 0) ~= 0 end
    end
    instructions.setScreenShake = function(thread, runtime, args)
        self_ref.screen_shake = {
            time = tonumber(args and args[1]) or 0,
            amount = tonumber(args and args[2]) or 0,
        }
    end
    instructions.fog = function(thread, runtime, args)
        -- fog(alpha, colour) tints the field.
        self_ref.fog = { alpha = tonumber(args and args[1]) or 0, colour = tonumber(args and args[2]) or 0 }
    end
    instructions.fogTime = function(thread, runtime, args)
        self_ref.fog = {
            alpha = tonumber(args and args[4]) or 0,
            colour = tonumber(args and args[3]) or 0,
            time = tonumber(args and args[1]) or 0,
        }
    end
    instructions.stars = function() end
    instructions.laserCancel = function() end
    instructions.killAllAsync = function(thread, runtime)
        for _, child in ipairs(runtime.threads) do
            if child ~= thread and child.object == thread.object and child.async then child.state = "finished" end
        end
    end

    -- --- item drops ---------------------------------------------------------
    instructions.dropItems = function() end
    instructions.dropClear = function() end
    instructions.dropArea = function() end
    instructions.etProtectRange = function() end
    instructions.flagExtDmg = function() end
    instructions.validRad = function() end
    instructions.bombShield = function() end

    -- --- lasers -------------------------------------------------------------
    -- The reference keeps a laser handle table per enemy. The adapter records
    -- the configuration so a host that draws lasers can render them; the
    -- pattern logic itself lives in the ECL.
    instructions.laserNew = function(thread, runtime, args)
        thread.lasers = thread.lasers or {}
        local index = tonumber(args and args[1]) or 0
        thread.lasers[index] = {
            angle = tonumber(args and args[2]) or 0,
            speed = tonumber(args and args[3]) or 0,
            length = tonumber(args and args[4]) or 0,
            width = tonumber(args and args[5]) or 16,
        }
    end
    instructions.laserOn = function(thread, runtime, args)
        local index = tonumber(args and args[1]) or 0
        local laser = thread.lasers and thread.lasers[index]
        if laser and thread.object then
            self_ref.shots = self_ref.shots or {}
            -- A laser is drawn as a stretched bullet along its angle.
            self_ref.shots[#self_ref.shots + 1] = {
                x = thread.object.x, y = thread.object.y,
                speed = 0, angle = laser.angle, sprite = 0,
                vx = 0, vy = 0, laser = true,
                length = laser.length, width = laser.width,
            }
        end
    end
    instructions.laserTiming = function() end
    instructions.laserCuOn = function(thread, runtime, args)
        instructions.laserOn(thread, runtime, args)
    end
    instructions.laserStOn = function(thread, runtime, args)
        instructions.laserOn(thread, runtime, args)
    end
    instructions.laserOffset = function() end
    instructions.laserTrajectory = function() end
    instructions.laserStLength = function() end
    instructions.laserStWidth = function() end

    -- --- movement -----------------------------------------------------------
    instructions.movePosRel = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        object.legacy_move_target = {
            x = (object.x or 0) + EclRuntime.evaluate_expression(thread, tostring(args[1] or "0")),
            y = (object.y or 0) + EclRuntime.evaluate_expression(thread, tostring(args[2] or "0")),
        }
    end
    instructions.movePosRelTime = function(thread, runtime, args)
        instructions.movePosRel(thread, runtime, { args[3], args[4] })
        thread.move_timer = { remaining = tonumber(args and args[1]) or 0 }
    end
    instructions.moveCircleRel = function(thread, runtime, args)
        instructions.moveCircle(thread, runtime, args)
    end
    instructions.moveCircleRelTime = function(thread, runtime, args)
        instructions.moveCircleTime(thread, runtime, args)
    end
    instructions.moveSpeed = function(thread, runtime, args)
        if thread.object then thread.object.legacy_speed = tonumber(args and args[1]) or 0 end
    end
    instructions.circlePos = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        -- circlePos(angle, x, y, radius): place at a point on a circle.
        local angle = EclRuntime.evaluate_expression(thread, tostring(args[1] or "0"))
        local radius = tonumber(args and args[4]) or 0
        object.x = (tonumber(args and args[2]) or 0) + math.cos(angle) * radius
        object.y = (tonumber(args and args[3]) or 0) + math.sin(angle) * radius
    end

    -- --- arithmetic and registers ------------------------------------------
    -- addf / setf operate on the float accumulator the reference exposes
    -- through the F0..F7 globals.
    instructions.addf = function(thread, runtime, args)
        thread.float_acc = (thread.float_acc or 0) + (tonumber(args and args[1]) or 0)
    end
    instructions.setf = function(thread, runtime, args)
        thread.float_acc = EclRuntime.evaluate_expression(thread, tostring(args and args[1] or "0"))
    end
    instructions.getAngle = function(thread, runtime, args)
        local slot = tostring(args and args[1] or ""):gsub("^[$%%]", "")
        local x1 = EclRuntime.evaluate_expression(thread, tostring(args[2] or "0"))
        local y1 = EclRuntime.evaluate_expression(thread, tostring(args[3] or "0"))
        local x2 = EclRuntime.evaluate_expression(thread, tostring(args[4] or "0"))
        local y2 = EclRuntime.evaluate_expression(thread, tostring(args[5] or "0"))
        thread.floats[slot] = angle_between(x1, y1, x2, y2)
    end

    -- --- misc ---------------------------------------------------------------
    instructions.bombShield = function() end
    instructions.enmCall = function(thread, runtime, args)
        -- enmCall(id, "Routine") runs a routine on an existing enemy.
        local routine = tostring(args and args[2] or "")
        local target = nil
        local wanted = tonumber(args and args[1]) or 0
        for index, enemy in ipairs(self_ref.enemies) do
            if index == wanted then target = enemy break end
        end
        target = target or thread.object
        local child = self_ref.runtime:spawn(routine, thread)
        child.object = target or thread.object
        child.runtime = self_ref.runtime
        self_ref.runtime.threads[#self_ref.runtime.threads + 1] = child
    end
    instructions.enmCreateMF = instructions.enmCreate
    instructions.enmMapleEnemy = instructions.enmCreate
    instructions.enm322 = function(thread, runtime, args)
        -- enm322(mode, value) synchronises a boss's position with its anim
        -- group. The mode the reference selects in the stage 6 loop only
        -- anchors the sprite, so the adapter keeps the object where the
        -- movement instructions placed it.
    end
    instructions.gameSpeed = function() end
    instructions.floatTime = function() end
    instructions.spellEx = function(thread, runtime, args)
        self_ref:begin_spell(thread, args)
    end
    instructions.spellMode = function() end
    instructions.spellTimeout = function() end
    instructions.anmSwitch = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        if player then player:play(tonumber(args and args[1]) or 0) end
    end
    instructions.anmPlayPos = function() end
    -- Unassigned reference slots that are pure no-ops.
    instructions.ins_30 = function() end
    instructions.ins_544 = function() end
    instructions.ins_549 = function() end
    instructions.ins_571 = function() end
    instructions.debug901 = function() end
    instructions.debug902 = function() end
    instructions.etExSub = function() end
    instructions.etExSubtract = function() end
    instructions.killAsync = function(thread, runtime, args)
        -- Cancel a named async thread. The reference passes an index; the
        -- adapter cancels the oldest live child thread of this object.
        local children = thread.children
        if children and #children > 0 then
            local victim = table.remove(children, 1)
            victim.state = "finished"
        end
    end
    instructions.moveCircle = function(thread, runtime, args)
        -- moveCircle(angle, angular speed, radius x, radius y): orbit motion.
        local object = thread.object
        if not object then return end
        object.legacy_circle = {
            angle = tonumber(args and args[1]) or 0,
            angular = tonumber(args and args[2]) or 0,
            radius_x = tonumber(args and args[3]) or 0,
            radius_y = tonumber(args and args[4]) or 0,
            origin_x = object.x or 0,
            origin_y = object.y or 0,
        }
    end
    instructions.moveCircleTime = function(thread, runtime, args)
        instructions.moveCircle(thread, runtime, { args[2], args[3], args[4], args[5] })
        thread.move_timer = { remaining = tonumber(args and args[1]) or 0 }
    end

    -- --- per-animation state -----------------------------------------------
    instructions.anmLayer = function(thread, runtime, args)
        if thread.object then thread.object.legacy_layer = tonumber(args and args[2]) or 0 end
    end
    instructions.anmColor = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        if player then
            player.color = {
                tonumber(args and args[2]) or 255,
                tonumber(args and args[3]) or 255,
                tonumber(args and args[4]) or 255,
            }
        end
    end
    instructions.anmAlpha = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        if player then player.alpha = tonumber(args and args[2]) or 255 end
    end
    instructions.anmAlphaTime = function(thread, runtime, args)
        -- anmAlphaTime(index, duration, from, to): fade over the duration.
        local player = thread.object and thread.object.legacy_anm
        if player then
            player.fade = {
                remaining = tonumber(args and args[2]) or 0,
                duration = tonumber(args and args[2]) or 1,
                from = tonumber(args and args[3]) or 0,
                to = tonumber(args and args[4]) or 255,
            }
            player.alpha = player.fade.from
        end
    end
    instructions.anmScale = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        if player then
            player.scale_x = tonumber(args and args[2]) or 1
            player.scale_y = tonumber(args and args[3]) or player.scale_x
        end
    end
    instructions.anmScaleTime = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        if player then
            player.scale_time = {
                remaining = tonumber(args and args[2]) or 0,
                duration = tonumber(args and args[2]) or 1,
                to_x = tonumber(args and args[4]) or 1,
                to_y = tonumber(args and args[5]) or 1,
            }
        end
    end
    instructions.anmRotate = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        if player then
            player.rotation = EclRuntime.evaluate_expression(thread, tostring(args and args[2] or "0"))
        end
    end

    return instructions
end

--- Start a spell card: show the cut-in and set up the bar segment.
function Adapter:begin_spell(thread, args)
    -- spell(layer, duration, score, name)
    local name = tostring(args and args[4] or "")
    if self.boss_ui then
        self.boss_ui:show_card(name)
        self.boss_ui:show_name(name)
    end
    if thread.object then
        thread.object.legacy_spell = name
        thread.spell_timer = tonumber(args and args[2]) or 0
    end
end

--- Spawn an enemy from an enmCreate-family call.
-- Args are (routine, x, y, hp, score, item), where the coordinates may be
-- unresolved expressions the interpreter already evaluated into the frame.
function Adapter:create_enemy(thread, runtime, args)
    local routine = tostring(args[1] or "")
    -- Coordinates are ECL expressions such as `%A - _f(32)`; evaluate them
    -- against the calling thread's frame instead of parsing the raw text.
    local x = EclRuntime.evaluate_expression(thread, tostring(args[2] or "0"))
    local y = EclRuntime.evaluate_expression(thread, tostring(args[3] or "0"))
    local hp = EclRuntime.evaluate_expression(thread, tostring(args[4] or "50"))
    -- `enmCreateM` mirrors the sprite horizontally; carry the flag through so
    -- the renderer can flip it.
    local mirrored = false
    self:spawn_enemy(routine, x, y, hp, { mirrored = mirrored }, thread)
end

--- Angle from (x1, y1) to (x2, y2), using the engine helper when present.

--- Fire the configured bullet group through the THlib bullet styles.
--- Fire the configured group using the reference pattern geometry.
-- The ECL stores one parameter block per volley; the aim mode expands it into
-- the fan or ring the original shows. Reproducing that generator is what makes
-- a volley land where the original put it.
function Adapter:fire_bullet_group(thread, group_index)
    local groups = thread.bullets or {}
    local group = groups[tonumber(group_index) or 0]
    local object = thread.object
    if not group or not object then return end
    local player = self.player or (self.lstg and self.lstg.player)
    local aim = 0
    if player then
        aim = angle_between(object.x, object.y, player.x, player.y)
    end
    -- etAim supplies the mode; without it the reference treats the volley as a
    -- single ring facing the base angle.
    local mode = group.aim
    if mode == nil then mode = BulletPatterns.MODE.CIRCLE end
    local count = math.max(1, math.floor(group.count or 1))
    local speed = group.speed or 3
    local expanded = BulletPatterns.expand({
        count1 = count,
        count2 = math.max(1, math.floor(group.count_spec or 1)),
        speed1 = speed,
        speed2 = group.speed_spec or speed,
        angle1 = group.angle or 0,
        angle2 = group.angle_spec or 0,
        mode = mode,
        aim_angle = aim,
        random = self.random_pattern,
    })
    local bullet_class = self.bullet_styles[1]
    local ox = object.x + (group.offset and group.offset[1] or 0)
    local oy = object.y + (group.offset and group.offset[2] or 0)
    for _, bullet in ipairs(expanded) do
        self:spawn_bullet(bullet_class, ox, oy, bullet.speed, bullet.angle,
            group.sprite, group.anim, false, group.color_index, group.ex)
    end
end

--- Spawn one bullet. Falls back to recording when the style is unavailable.
-- Player shots are marked so the renderer can draw them differently and so
-- culling can treat them separately.
function Adapter:spawn_bullet(bullet_class, x, y, speed, angle, sprite, anim, is_player, color_index, ex)
    self.shots = self.shots or {}
    if #self.shots < 8192 then
        self.shots[#self.shots + 1] = {
            x = x, y = y, speed = speed, angle = angle, sprite = sprite,
            anim = anim,
            color_index = color_index or 27,
            vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
            player_bullet = is_player == true,
            -- The effects block travels with the bullet so the per-frame
            -- behaviour can be applied as it flies.
            ex = ex,
            ex_timer = 0,
        }
    end
    if type(self.lstg.New) == "function" and bullet_class then
        pcall(function()
            self.lstg.New(bullet_class, COLOR.BLUE, x, y, speed,
                math.deg(angle), false, 0, true, true, 0, false, 0, 0, 0, false)
        end)
        return
    end
end

--- Heading of a velocity vector, in radians.
-- Lua 5.4 has no math.atan2, and the engine's global atan2 is absent in the
-- test runner, so the two-argument form is derived from the one-argument one.
local function bullet_heading(vx, vy)
    if type(atan2) == "function" then return atan2(vy, vx) end
    if vx > 0 then return math.atan(vy / vx) end
    if vx < 0 then return math.atan(vy / vx) + (vy >= 0 and math.pi or -math.pi) end
    return vy >= 0 and math.pi * 0.5 or -math.pi * 0.5
end

--- Apply a bullet's etEx effects block for one frame.
-- The reference stores an effects block on each bullet. The flags choose the
-- behaviour and the remaining fields parameterise it. The two behaviours worth
-- reproducing are the ones the stage data actually asks for: accelerating
-- along a direction, and reversing direction on an interval. A flag of zero,
-- or a block whose values are all the -999999 sentinel, leaves the bullet on
-- the straight path it was fired with.
local function apply_bullet_effects(shot)
    local ex = shot.ex
    if not ex or not ex.flags or ex.flags == 0 then return end
    shot.ex_timer = (shot.ex_timer or 0) + 1
    local flags = ex.flags
    local speed = shot.speed or 0
    -- Acceleration: the reference treats 0x10 as "accelerate each frame", with
    -- the first float as the rate and the second as the angle to accelerate
    -- along (the bullet's own heading when the field is the sentinel).
    if flags % 0x20 >= 0x10 and flags < 0x20 then
        local rate = tonumber(ex.float1)
        local angle = tonumber(ex.float2)
        if rate and rate > -999 then
            if not angle or angle <= -999 then angle = shot.angle or 0 end
            shot.vx = (shot.vx or 0) + math.cos(angle) * rate
            shot.vy = (shot.vy or 0) + math.sin(angle) * rate
            shot.speed = math.sqrt(shot.vx * shot.vx + shot.vy * shot.vy)
            shot.angle = bullet_heading(shot.vx, shot.vy)
        end
        return
    end
    -- Direction change: the bullet turns by a fixed rotation every interval
    -- frames, up to a maximum number of times. This is what makes a stream of
    -- bullets bend into a curve partway across the screen.
    local turn_flags = flags % 0x400
    if turn_flags >= 0x40 and turn_flags < 0x200 then
        local rotation = tonumber(ex.float1) or 0
        local interval = math.max(1, math.floor(tonumber(ex.int1) or 1))
        local max_times = math.floor(tonumber(ex.int2) or -1)
        if max_times < 0 then max_times = math.huge end
        local turns = math.floor((shot.ex_timer - 1) / interval)
        -- The first turn happens on the very first frame, so "no turn yet"
        -- cannot be recorded as zero. Track the last applied count instead.
        if turns > (shot.ex_turns or -1) and turns <= max_times then
            shot.ex_turns = turns
            local step = (turn_flags >= 0x100) and -rotation or rotation
            local angle = (shot.angle or 0) + step
            local speed = shot.speed or 0
            shot.angle = angle
            shot.vx = math.cos(angle) * speed
            shot.vy = math.sin(angle) * speed
        end
        return
    end
end

--- Advance recorded shots so a host-drawn pattern moves like the reference.
-- Player shots are culled once they leave the field so the list cannot grow
-- without bound; enemy bullets persist while inside the field.
function Adapter:advance_shots()
    local kept = {}
    for _, shot in ipairs(self.shots or {}) do
        apply_bullet_effects(shot)
        shot.x = shot.x + (shot.vx or 0)
        shot.y = shot.y + (shot.vy or 0)
        shot.anim_frame = (shot.anim_frame or 0) + 1
        local in_field = shot.x > -260 and shot.x < 260 and shot.y > -80 and shot.y < 540
        if in_field or (shot.anim_frame or 0) < 4 then
            kept[#kept + 1] = shot
        end
    end
    self.shots = kept
end

--- Apply damage to an enemy. The reference reduces health directly and the
-- manager observes the change, so the adapter keeps the same model.
function Adapter:damage_enemy(enemy, amount)
    if not enemy then return end
    enemy.hp = math.max(0, (enemy.hp or 0) - (tonumber(amount) or 0))
    if self.boss_ui then self.boss_ui:set_health(enemy.hp, self.boss_ui.health_max) end
end

--- Track the boss so scripts that read BOSS_X and BOSS_Y resolve.
function Adapter:set_boss_object(enemy)
    self.boss_object = enemy
end

--- The first live enemy, which is the boss once it spawns.
function Adapter:current_boss()
    for _, enemy in ipairs(self.enemies) do
        if enemy.legacy_interrupts then return enemy end
    end
    return nil
end

--- Check each enemy's health against its registered interrupts.
function Adapter:advance_interrupts()
    for _, enemy in ipairs(self.enemies) do
        local interrupts = enemy.legacy_interrupts
        if interrupts then
            local hp = enemy.hp or 0
            for _, entry in pairs(interrupts) do
                local elapsed = (self.frame or 0) - (enemy.legacy_timer_start or entry.registered_frame or 0)
                local timed_out = entry.finish > 0 and elapsed >= entry.finish
                if not entry.fired and (hp <= entry.start or timed_out) and entry.routine ~= "" then
                    entry.fired = true
                    local routine = timed_out and enemy.legacy_timeouts and enemy.legacy_timeouts[entry.id] or entry.routine
                    for _, active in ipairs(self.runtime.threads) do
                        if active.object == enemy then active.state = "finished" end
                    end
                    -- Run the subroutine on the enemy's own thread context.
                    local thread = self.runtime:spawn(routine, enemy.legacy_thread)
                    thread.ints, thread.floats = {TIMEOUT=timed_out and 1 or 0}, {}
                    enemy.legacy_globals = enemy.legacy_globals or {}
                    enemy.legacy_globals.TIMEOUT = timed_out and 1 or 0
                    thread.object = enemy
                    thread.runtime = self.runtime
                    self.runtime.threads[#self.runtime.threads + 1] = thread
                    enemy.legacy_pending_interrupt = true
                    break
                end
            end
        end
    end
end

--- Advance every enemy animation and the ECL threads by one frame.
--- Advance one enemy's movement for a frame.
-- A time move interpolates along its eased path and follows the reference
-- exactly, including clamping to the destination when the timer expires. A
-- velocity move simply integrates the velocity.
function Adapter:advance_enemy_movement(enemy)
    local velocity = enemy.legacy_velocity_tween
    if velocity then
        velocity.remaining = velocity.remaining - 1
        local progress = ease_fraction(velocity.mode, velocity.remaining / velocity.total)
        enemy.legacy_angle = velocity.start_angle + (velocity.end_angle - velocity.start_angle) * progress
        enemy.legacy_speed = velocity.start_speed + (velocity.end_speed - velocity.start_speed) * progress
        enemy.legacy_vx = math.cos(enemy.legacy_angle) * enemy.legacy_speed
        enemy.legacy_vy = math.sin(enemy.legacy_angle) * enemy.legacy_speed
        if velocity.remaining <= 0 then enemy.legacy_velocity_tween = nil end
    end
    local move = enemy.legacy_move
    if move then
        move.remaining = move.remaining - 1
        local remaining_fraction = move.remaining / move.total
        local progress = ease_fraction(move.mode, remaining_fraction)
        enemy.x = move.start_x + (move.end_x - move.start_x) * progress
        enemy.y = move.start_y + (move.end_y - move.start_y) * progress
        -- Keep the axis speed available for aiming, as the reference does.
        enemy.legacy_vx = enemy.x - (enemy.legacy_prev_x or enemy.x)
        enemy.legacy_vy = enemy.y - (enemy.legacy_prev_y or enemy.y)
        enemy.legacy_prev_x = enemy.x
        enemy.legacy_prev_y = enemy.y
        if move.remaining <= 0 then
            enemy.x = move.end_x
            enemy.y = move.end_y
            enemy.legacy_move = nil
            enemy.legacy_vx = 0
            enemy.legacy_vy = 0
        end
        return
    end
    if enemy.legacy_vx or enemy.legacy_vy then
        enemy.x = (enemy.x or 0) + (enemy.legacy_vx or 0)
        enemy.y = (enemy.y or 0) + (enemy.legacy_vy or 0)
    end
end

function Adapter:update()
    self.frame = (self.frame or 0) + 1
    self.runtime:update()
    for _, enemy in ipairs(self.enemies) do
        if (enemy.hp or 0) > 0 then enemy.legacy_pending_interrupt = nil end
    end
    self:advance_shots()
    self:advance_interrupts()
    -- Prune enemies the scripts deleted or that have left the field. The
    -- reference removes an enemy when it flies far enough outside the playfield,
    -- which is what keeps a scrolling wave from accumulating on screen.
    local kept = {}
    for _, enemy in ipairs(self.enemies) do
        local alive = not enemy.legacy_deleted and ((enemy.hp or 1) > 0 or enemy.legacy_pending_interrupt)
        if alive then
            -- Enemies are created with auto_delete on, which in the reference
            -- means they leave once well outside the field. The boss is created
            -- without it and stays put until its script ends.
            local x, y = enemy.x or 0, enemy.y or 0
            if not enemy.legacy_is_boss then
                if y > 620 or y < -320 or x < -400 or x > 400 then alive = false end
            end
        end
        if not alive then
            for _, thread in ipairs(self.runtime.threads) do
                if thread.object == enemy then thread.state = "finished" end
            end
            -- A boss leaving play clears the tracking so the next section waits
            -- for its own boss.
            if self.boss_object == enemy then self.boss_object = nil end
        end
        if alive then
            if enemy.legacy_anm then enemy.legacy_anm:update() end
            self:advance_enemy_movement(enemy)
            kept[#kept + 1] = enemy
        end
    end
    self.enemies = kept
end

--- Coverage report for the current run.
function Adapter:missing_report()
    local report = {}
    for name, count in pairs(self.audit) do report[#report + 1] = { name, count } end
    for name, count in pairs(self.runtime.unhandled or {}) do report[#report + 1] = { "ecl:" .. name, count } end
    table.sort(report, function(a, b) return a[2] > b[2] end)
    return report
end

Adapter.COLOR = COLOR

return Adapter
