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
local BulletAnimation = require("tnr.legacy_replay.bullet_animation")
local BulletTypes = require("tnr.legacy_replay.data.th15_bullet_types")
local AnmPlayer = require("tnr.legacy_replay.anm_player")
local ChargeParticles = require("tnr.legacy_replay.charge_particles")
local ClassicShots = require("tnr.legacy_replay.classic_shots")
local Sounds = require("tnr.legacy_replay.sounds")
local ReferenceRng = require("tnr.legacy_replay.reference_rng")
local Rules = require("tnr.legacy_replay.reference_rules")
local float32 = Rules.float32
local PI, HALF_PI, TAU = float32(math.pi), float32(math.pi / 2), float32(2 * math.pi)

-- TH15 Stage's spell art records (420b2d–420d15). All six main stages use
-- their enemy ANM archive for the backdrop and the separate entrance cut-in.
local SPELL_ART = {
    st01 = { background=11, cut_in=18 },
    st02 = { background=11, cut_in=19 },
    st03 = { background=11, cut_in=20 },
    st04 = { background=9, cut_in=15 },
    st05 = { background=10, cut_in=17 },
    st06 = { background=20, cut_in=27 },
}

local Adapter = {}
local function normalize_motion_angle(value)
    value=float32(value)
    for _=1,34 do
        if value>PI then value=float32(value-TAU)
        elseif value<-PI then value=float32(value+TAU)
        else break end
    end
    return value
end

local function angle_between(x1, y1, x2, y2)
    local x, y = x2 - x1, y2 - y1
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    return y > 0 and math.pi / 2 or (y < 0 and -math.pi / 2 or 0)
end

Adapter.__index = Adapter
local function base_position(object)
    return object.legacy_base_x or (object.x or 0) - (object.legacy_rel_x or 0),
        object.legacy_base_y or (object.y or 0) - (object.legacy_rel_y or 0)
end

local function set_base_position(object, x, y)
    object.legacy_base_x, object.legacy_base_y = x, y
    object.x, object.y = x + (object.legacy_rel_x or 0), y + (object.legacy_rel_y or 0)
end

local function circle_position(circle)
    -- Native 4076a0 stores each polar product as a float before adding the
    -- center. Preserve the distinct rotated-ellipse path until verified.
    if circle.rotation == nil and circle.aspect == nil then
        local radius=float32(circle.radius)
        return float32(float32(circle.origin_x)+float32(math.cos(circle.angle)*radius)),
            float32(float32(circle.origin_y)+float32(math.sin(circle.angle)*radius))
    end
    local rotation=circle.rotation or 0
    local angle=circle.angle-rotation
    local x=math.cos(angle)*circle.radius*(circle.aspect or 1)
    local y=math.sin(angle)*circle.radius
    return circle.origin_x+x*math.cos(rotation)-y*math.sin(rotation),
        circle.origin_y+x*math.sin(rotation)+y*math.cos(rotation)
end

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
    if type(value) == "number" then return value end
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
    local rng, random = nil, options.random
    if not random then
        rng = ReferenceRng.new(options.seed)
        random = function(low, high) return rng:range(low, high) end
    end
    local self = setmetatable({
        lstg = options.lstg,
        enemy_class = options.enemy_class,
        bullet_styles = options.bullet_styles or {},
        anm = options.anm or {},
        audit = {},
        enemies = {},
        shots = {},
        cancelled_shots = {},
        bullet_anim_cache = {},
        bullet_rects = {},
        chapter_active = 0,
        chapter_targets = 0,
        chapter_defeated = 0,
        boss_ui = options.boss_ui,
        rng = rng,
        random = random,
        stage_key = options.stage_key,
        enemy_hp_multiplier = math.max(0.5, math.min(2, tonumber(options.enemy_hp_multiplier) or 1)),
    }, Adapter)
    for _, entry in ipairs(self.anm.bullet or {}) do
        for _, rect in ipairs(entry.sprites or {}) do
            self.bullet_rects[#self.bullet_rects + 1] = rect
        end
    end
    self.spawn_ticks_for = function(shot, interrupt) return self:bullet_spawn_ticks(shot, interrupt) end
    self.difficulty = options.difficulty or EclRuntime.DIFFICULTY.NORMAL
    self.instructions = self:build_instructions()
    -- Engine globals the ECL reads: the player position, the difficulty id and
    -- the difficulty flags. Publishing them here means expressions such as
    -- `%PLAYER_X2` resolve instead of collapsing to zero.
    local host_ref = self
    local function angle_to_player()
        local player = host_ref.player or (host_ref.lstg and host_ref.lstg.player)
        local boss = host_ref.boss_object
        if not player or not boss then return 0 end
        return angle_between(boss.x or 0,boss.y or 0,player.x,player.y)
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
            DIFF = difficulty,
            EASY = difficulty == 0 and 1 or 0,
            NORMAL = difficulty == 1 and 1 or 0,
            HARD = difficulty == 2 and 1 or 0,
            LUNATIC = difficulty == 3 and 1 or 0,
            CHAPTER = host_ref.chapter_active,
            RANK = 32,
            TRUE = 1,
        }
    end
    self.runtime = EclRuntime.new(options.chunks or {}, {
        instructions = self.instructions,
        difficulty = self.difficulty,
        get_player=function() return host_ref.player or (host_ref.lstg and host_ref.lstg.player) end,
        get_boss=function() return host_ref.boss_object end,
        -- The runtime calls this for any global a script reads.
        globals = setmetatable({}, {
            __index = function(_, name)
                if name=="RANDF" then return host_ref.random(0,1) end
                if name=="RANDF2" then return host_ref.random(-1,1) end
                if name=="RANDRAD" then return host_ref.random(-math.pi,math.pi) end
                if name=="RAND" then
                    return rng and rng:next_u32() % 0x80000000 or math.floor(host_ref.random(0,0x80000000))
                end
                return globals_provider()[name]
            end,
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
    local base_hp = tonumber(hp) or 50
    local scaled_hp = base_hp * (self.enemy_hp_multiplier or 1)
    local lua_class = self.enemy_class
    local object
    if lua_class ~= nil and type(self.lstg.New) == "function" then
        -- The engine enemy class takes (style, hp, clear_bullet, auto_delete).
        local ok, created = pcall(self.lstg.New, lua_class, 1, scaled_hp, false, true)
        object = ok and created or nil
    end
    if not object then
        object = { x = x, y = y }
    end
    if object then
        object.x, object.y = x, y
        object.legacy_mirror=args and args.mirrored or false
        object.legacy_flags=object.legacy_mirror and 524288 or 0
        -- The ECL creation call carries the enemy's hit points; keep them on the
        -- object so player damage and the drop check have something to work
        -- with when the host does not provide a real enemy class.
        object.hp = scaled_hp or object.hp or 50
        object.max_hp = object.hp
        object.legacy_drop = args and args.main_drop or 0
        object.legacy_ecl = routine
        object.legacy_chapter = self.chapter_active
        object.legacy_body_visible = false
        object.legacy_timer_start = self.frame or 0
        -- 42613e initializes a two-tick protection timer. In ECL the
        -- creation call itself runs the first enemy tick.
        object.legacy_invulnerable_until = (self.frame or 0) + (self.runtime.updating_enemies and 2 or 3)
        -- Attach the animation player for the stage's enemy archive.
        local archive, archive_name, entry_index = self:enemy_archive()
        if archive then
            object.legacy_anm = AnmPlayer.new(archive, archive_name, entry_index)
        end
    end
    -- Start the requested routine. The caller supplies the namespace context
    -- so a bare name such as "GirlRedA01e" resolves to "st01.GirlRedA01e".
    local thread = self.runtime:spawn(routine, caller_thread or nil)
    -- Creation copies the caller's per-enemy registers, not its local stack.
    -- th15.exe 42e305..42e344 copies the creation parameter blocks by value.
    thread.ints, thread.floats = {}, {}
    if object and caller_thread then
        object.legacy_globals = {}
        for _, prefix in ipairs({"I", "F"}) do
            for index = 0, prefix == "I" and 3 or 7 do
                local name = prefix .. index
                object.legacy_globals[name] = EclRuntime.resolve(caller_thread,
                    (prefix == "I" and "$" or "%") .. name)
            end
        end
    end
    if object and args and args.legacy_globals then
        object.legacy_globals={}
        for name,value in pairs(args.legacy_globals) do object.legacy_globals[name]=value end
    end
    thread.object = object
    thread.runtime = self.runtime
    if object then object.legacy_thread = thread end
    self.runtime.threads[#self.runtime.threads + 1] = thread
    if self.runtime.updating_enemies or (args and args.initialize_now) then
        -- 426212 calls Enemy::update before linking the new enemy at the tail.
        object.x,object.y=Rules.motion_coordinate(object.x),Rules.motion_coordinate(object.y)
        object.legacy_initialized_frame = self.runtime.frame or 0
        EclRuntime.step(thread, self.runtime)
        self:finish_enemy_step(object)
    end
    self.enemies[#self.enemies + 1] = object
    return object, thread
end

--- Resolve an anmSelect index to a sheet.
-- The reference numbers the sheets the stage loaded rather than the entries
-- inside one archive: 1 is the shared default sheet, 2 is the enemy sheet, and
-- 3 upwards are the boss sheets. Only the ones actually collected are offered,
-- and an unrecognised index falls back to the enemy sheet so an enemy still
-- draws something instead of vanishing.
function Adapter:select_archive(selection)
    local stage=self.stage_key or "st01"
    if selection==0 or selection==1 then return self.anm.effect and "effect" or "enemy",1 end
    if selection==2 then return "enemy",1 end
    if selection==3 then return stage.."enm",1 end
    return stage.."enm",1
end

-- Scripts and sprite IDs are global to the archive, even across texture entries.
function Adapter:animation(selection,script)
    return self:animation_from_archive(self:select_archive(selection),script)
end

function Adapter:animation_from_archive(name,script)
    local entries=self.anm[name] or {}
    for index,entry in ipairs(entries) do
        if entry.scripts and entry.scripts[script] then
            local vm=AnmPlayer.new(entry,name,index)
            vm.archive_entries=entries
            vm.on_effect=function(effect_id,source) self:spawn_effect_from_vm(effect_id,source) end
            vm:play(script)
            return vm
        end
    end
    self:note("anm:"..tostring(name)..":"..tostring(script))
end

function Adapter:spawn_animation(name,script,x,y)
    local vm=self:animation_from_archive(name,script)
    if vm then
        vm.origin_x,vm.origin_y=x,y
        self.animations=self.animations or {}
        self.animations[#self.animations+1]=vm
    end
    return vm
end

--- ANM 508 selects the native effect table (422900), independent of script IDs.
function Adapter:spawn_effect_from_vm(effect_id,source)
    if effect_id == 1 then
        source.charge = ChargeParticles.new(self.random)
    else
        self:note("anm_effect:" .. tostring(effect_id))
    end
end

--- Run the stage's own title-card ANM when the ECL requests stageLogo.
function Adapter:show_stage_logo()
    local archive_name=(self.stage_key or "st01").."logo"
    local entries=self.anm[archive_name] or {}
    for index,entry in ipairs(entries) do
        if entry.scripts and entry.scripts[0] then
            local vm=AnmPlayer.new(entry,archive_name,index)
            vm.archive_entries=entries
            vm.on_effect=function(effect_id,source) self:spawn_effect_from_vm(effect_id,source) end
            vm.origin_x,vm.origin_y=0,0
            if vm:play(0) then
                vm.screen_pixels=true
                self.animations=self.animations or {}
                self.animations[#self.animations+1]=vm
                return vm
            end
        end
    end
    self:note("stage_logo:"..archive_name)
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
    instructions.anmSelect=function(t,r,a)
        if t.object then t.object.legacy_anm_selection=resolve_arg(t,a[1],2) end
        t.anm_selection=resolve_arg(t,a[1],2)
    end
    local function play_slot(o,slot,script)
        local vm=self_ref:animation(o.legacy_anm_selection or 2,script)
        if not vm then return end
        o.legacy_anm_slots=o.legacy_anm_slots or {};o.legacy_anm_slots[slot]=vm
        if slot==0 then
            o.legacy_anm=vm;o.legacy_body_visible=true
        end
        return vm
    end
    local function slot_animation(t,a,main)
        local o=t.object;if not o then return end
        local slot,script=resolve_arg(t,a[1],0),resolve_arg(t,a[2],0)
        if play_slot(o,slot,script) and slot==0 then
            o.legacy_main_script=main and script or nil
            o.legacy_main_selection=o.legacy_anm_selection or 2
            o.legacy_pose=0
        end
    end
    instructions.anmSetMain=function(t,r,a) slot_animation(t,a,true) end
    instructions.anmSetSprite=function(t,r,a) slot_animation(t,a,false) end
    local function spawn_animation(t,selection,script,absolute)
        local vm=self_ref:animation(selection,script)
        if vm then
            vm.origin_x=absolute and 0 or (t.object and t.object.x or 0)
            vm.origin_y=absolute and 0 or (t.object and t.object.y or 0)
            self_ref.animations=self_ref.animations or {};self_ref.animations[#self_ref.animations+1]=vm
        end
        return vm
    end
    instructions.anmPlay=function(t,r,a) spawn_animation(t,resolve_arg(t,a[1],1),resolve_arg(t,a[2],0),false) end
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
            if (thread.object.legacy_chapter_weight or 0) == 0 then
                thread.object.legacy_chapter_weight = 1
                self_ref.chapter_targets = self_ref.chapter_targets + 1
            end
        end
    end

    -- --- movement ----------------------------------------------------------
    -- The reference has two movement modes. A velocity move keeps a constant
    -- velocity; a time move interpolates the object along an eased path over a
    -- fixed number of frames. `movePosTime(time, mode, x, y)` and
    -- `moveVelTime(time, mode, angle, speed)` both select an easing curve from
    -- their second argument.
    local function start_velocity_move(object, angle, speed)
        object.legacy_circle=nil
        object.legacy_scalar_tweens=nil
        object.legacy_velocity_tween = nil
        object.legacy_angle = resolve_angle(angle, object.legacy_angle)
        object.legacy_speed = tonumber(speed) or 0
        object.legacy_vx = math.cos(object.legacy_angle) * object.legacy_speed
        object.legacy_vy = math.sin(object.legacy_angle) * object.legacy_speed
        object.legacy_move = nil
    end

    local function start_time_move(object, frames, raw_mode, target_x, target_y, angle, speed)
        object.legacy_circle=nil
        object.legacy_scalar_tweens=nil
        object.legacy_velocity_tween = nil
        local mode = tonumber(raw_mode) or 0
        if frames<=0 then object.legacy_move=nil;return end
        local start_x, start_y = base_position(object)
        local end_x, end_y = target_x, target_y
        if end_x and end_x<=SENTINEL then end_x=start_x end
        if end_y and end_y<=SENTINEL then end_y=start_y end
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

    local function movement_angle(object,value,no_mirror)
        if value<=SENTINEL then return object.legacy_angle or 0 end
        if object.legacy_mirror and not no_mirror then
            value=HALF_PI-normalize_motion_angle(float32(value)-HALF_PI)
        end
        return normalize_motion_angle(value)
    end
    instructions.moveVel = function(thread, runtime, args, no_mirror)
        local object = thread.object
        if not object then return end
        start_velocity_move(object,
            movement_angle(object,resolve_arg(thread,args[1],SENTINEL),no_mirror),
            resolve_angle(resolve_arg(thread,args[2],SENTINEL),object.legacy_speed))
    end
    instructions.moveVelTime = function(thread, runtime, args, no_mirror)
        local object = thread.object
        if not object then return end
        object.legacy_circle=nil
        object.legacy_scalar_tweens=nil
        local frames = math.max(1, resolve_arg(thread, args[1], 1))
        local speed = resolve_arg(thread, args[4], object.legacy_speed or 0)
        if speed <= SENTINEL then speed = object.legacy_speed or 0 end
        local start_angle=object.legacy_angle or 0
        local end_angle=movement_angle(object,resolve_arg(thread,args[3],SENTINEL),no_mirror)
        if math.abs(start_angle-end_angle)>=math.pi then
            if end_angle>start_angle then start_angle=start_angle+2*math.pi else end_angle=end_angle+2*math.pi end
        end
        object.legacy_velocity_tween = {
            total = frames, remaining = frames,
            mode = resolve_arg(thread, args[2], 0),
            start_angle = start_angle,end_angle = end_angle,
            start_speed = object.legacy_speed or 0, end_speed = speed,
        }
        object.legacy_speed_interpolation_mode=resolve_arg(thread,args[2],0)
        object.legacy_move = nil
    end
    instructions.movePosTime = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        start_time_move(object,
            resolve_arg(thread,args[1],0),resolve_arg(thread,args[2],0),
            resolve_arg(thread,args[3],0),resolve_arg(thread,args[4],0))
    end
    instructions.moveVelNM = function(t,r,a) instructions.moveVel(t,r,a,true) end
    instructions.moveVelNMTime = function(t,r,a) instructions.moveVelTime(t,r,a,true) end

    local function scalar_velocity_time(thread,args,field)
        local object = thread.object
        if not object then return end
        local duration=resolve_arg(thread,args[1],0)
        local mode=resolve_arg(thread,args[2],0)
        local operand=resolve_arg(thread,args[3],SENTINEL)
        if mode==7 then
            -- 42a87c interprets the operand as a per-tick turn.
            if operand<=SENTINEL then operand=0 end
            if field=="legacy_angle" and object.legacy_mirror then operand=-operand end
        elseif field=="legacy_angle" then
            operand=movement_angle(object,operand)
        else
            operand=resolve_angle(operand,object[field])
        end
        object.legacy_scalar_tweens=object.legacy_scalar_tweens or {}
        object.legacy_scalar_tweens[field]=duration>0 and {
            total=duration,remaining=duration,mode=mode,
            first=object[field] or 0,last=operand} or nil
        if field=="legacy_speed" and duration>0 then
            object.legacy_speed_interpolation_mode=mode
        end
        object.legacy_circle=nil;object.legacy_move=nil
    end
    instructions.moveSpeedTime = function(thread, runtime, args)
        scalar_velocity_time(thread,args,"legacy_speed")
    end
    instructions.moveAngleTime = function(thread, runtime, args)
        scalar_velocity_time(thread,args,"legacy_angle")
    end
    instructions.moveEllipseRel = function(thread, runtime, args)
        instructions.moveCircle(thread,runtime,args,true,true)
    end
    instructions.moveEllipseRelTime = function(thread, runtime, args)
        instructions.moveCircleTime(thread,runtime,args,true,true)
    end

    -- --- drops -------------------------------------------------------------
    instructions.dropMain = function(thread, runtime, args)
        if thread.object then thread.object.legacy_drop = resolve_arg(thread,args[1],0) end
    end
    instructions.dropExtra = function(thread, runtime, args)
        -- Extra item drop: records the requested drop so the adapter can spawn
        -- the matching pickup when the enemy dies.
        if thread.object then
            local o=thread.object
            o.legacy_drop_extra=o.legacy_drop_extra or {}
            local kind=resolve_arg(thread,args[1],0)
            o.legacy_drop_extra[kind]=(o.legacy_drop_extra[kind] or 0)+resolve_arg(thread,args[2],0)
        end
    end

    -- --- lifecycle ---------------------------------------------------------
    instructions.delete = function(thread, runtime)
        local object = thread.object
        if object then
            -- 426212 links the enemy even if its initial script returns
            -- deletion. The manager clears the initial-update bit on its
            -- first visit and unlinks the object on its next visit.
            if object.legacy_initialized_frame and object.legacy_initialized_frame == runtime.frame then
                object.legacy_delete_after_init = true
            end
            object.legacy_deleted = true
            object.hp = 0
            if self_ref.lstg.Del then pcall(self_ref.lstg.Del, object) end
        end
        thread.state = "finished"
    end
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
    local function flags(thread,args,clear)
        local o=thread.object;if not o then return end
        local bits=resolve_arg(thread,args[1],0)
        local value=o.legacy_flags or 0
        for i=0,31 do
            local bit=2^i
            if math.floor(bits/bit)%2==1 then
                local present=math.floor(value/bit)%2==1
                if clear and present then value=value-bit
                elseif not clear and not present then value=value+bit end
            end
        end
        o.legacy_flags=value
        local function has(bit) return math.floor(value/bit)%2==1 end
        o.legacy_mirror=has(524288)
        o.legacy_no_shot_contact=has(1) or has(32)
        o.legacy_no_damage=o.legacy_no_shot_contact or has(16)
        o.legacy_no_contact=has(2) or has(32)
        o.legacy_body_graze=has(512)
        o.legacy_keep_x,o.legacy_keep_y=has(4),has(8)
        o.legacy_no_clear=not has(256) and (has(32) or has(128) or has(1024) or has(0x400000) or has(0x800000))
    end
    instructions.flagSet=function(t,r,a) flags(t,a,false) end
    instructions.flagClear=function(t,r,a) flags(t,a,true) end
    instructions.setTimeout = function(thread, runtime, args)
        if thread.object then
            thread.object.legacy_timeouts = thread.object.legacy_timeouts or {}
            thread.object.legacy_timeouts[resolve_arg(thread,args[1],0)] = args[2]
        end
    end
    instructions.setChapter = function(thread,runtime,args)
        local chapter=resolve_arg(thread,args and args[1],0)
        self_ref.chapter=chapter
        if thread.object then
            thread.object.legacy_chapter=chapter
            thread.object.legacy_chapter_weight=0
        end
        if self_ref.on_chapter then self_ref.on_chapter(chapter) end
    end
    instructions.dialogWait = function(thread)
        local dialog = self_ref.dialogue
        if not dialog or not dialog.active or dialog.resume_available then return end
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
    local function play_reference_sound(index, volume)
        if not self_ref.on_sound then return end
        local path = Sounds.path_for(index)
        if not path then return end
        pcall(self_ref.on_sound, path, volume)
    end
    instructions.playSound = function(thread, runtime, args)
        play_reference_sound(resolve_arg(thread, args and args[1], nil))
    end
    instructions.hitSound = instructions.playSound
    instructions.bgmPlay = function() end

    -- --- conditions --------------------------------------------------------
    local function assign_difficulty(thread, args, round)
        if not args[1] or #args < 2 then return end
        local index = math.min(self_ref.difficulty + 2, #args)
        local value = resolve_arg(thread, args[index], 0)
        EclRuntime.apply_assignment(thread, args[1], "=", round(value))
    end
    instructions.diffI = function(thread, runtime, args)
        assign_difficulty(thread, args, math.floor)
    end
    instructions.diffF = function(thread, runtime, args)
        -- Declarations preserve the ECL suffix ("0.3f"). Use the expression
        -- resolver and respect whether the destination is local or enemy-wide.
        assign_difficulty(thread, args, float32)
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
        -- Group operands may be ECL registers such as $A, not just literals.
        -- resolve_arg leaves already-evaluated numbers alone and evaluates a
        -- dynamic operand once, matching etNew and etOn.
        local key = tonumber(resolve_arg(thread, index, 0)) or 0
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
    local function difficulty_operand()
        local difficulty = self_ref.difficulty or EclRuntime.DIFFICULTY.NORMAL
        return 2 + (difficulty >= 0 and difficulty <= 2 and difficulty or 3)
    end
    instructions.etNew = function(thread, runtime, args)
        local index = tonumber(resolve_arg(thread, args and args[1], 0)) or 0
        -- Native 42bafa clears all 0x380 bytes before applying these defaults.
        -- Sprite/colour, absolute offsets and transforms never survive etNew.
        bullet_groups(thread)[index] = {
            index = index,
            count = 1, count_spec = 1,
            angle = 0, angle_spec = 0,
            speed = 2, speed_spec = 0,
            sprite = 0, anim = 0, color_index = 0,
            aim = 0, offset = nil,
            fire_sound = 21, transform_sound = 38,
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
        group.count = math.max(0, math.floor(count or 1))
        local rings = resolve_arg(thread, args and args[3], 1)
        group.count_spec = math.max(0, math.floor(rings or 1))
    end
    -- 42bf71/42bfe5 select the same difficulty from two four-operand
    -- banks: bullet count and layers, or the first and last speeds.
    instructions.etCountD = function(thread, runtime, args)
        local index = difficulty_operand()
        instructions.etCount(thread, runtime, {args[1],args[index],args[index + 4]})
    end
    instructions.etSpeedD = function(thread, runtime, args)
        local index = difficulty_operand()
        instructions.etSpeed(thread, runtime, {args[1],args[index],args[index + 4]})
    end
    instructions.etAngleD = function(thread, runtime, args)
        local group = group_at(thread, args and args[1])
        local value = resolve_arg(thread, args and args[difficulty_operand()], nil)
        group.angle = resolve_angle(value, group.angle)
    end
    instructions.etSpriteD = function(thread, runtime, args)
        local group = group_at(thread, args and args[1])
        local value = resolve_arg(thread, args and args[difficulty_operand()], nil)
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
        -- Native 42bbc0 copies the entire parameter block. Nested transform
        -- records must not alias: etExSub on the copy changes only that group.
        local copy = require("tnr.core.immutable").copy(from)
        copy.index = target
        groups[target] = copy
    end
    local function clear_bullets(t,a,cancel)
        local radius=resolve_arg(t,a and a[1],10000)
        local x,y=t.object and t.object.x or 0,t.object and t.object.y or 0
        local shots=self_ref.shots
        -- 41e650 walks the active list newest first and includes half the
        -- projectile's collision size in the radius test.
        for index=#shots,1,-1 do
            local shot=shots[index]
            if not shot.player_bullet and not shot.laser and not shot.deleted then
                local descriptor=BulletTypes[shot.sprite or shot.anim or 0]
                local extent=radius+(descriptor and descriptor.radius or 0)*(shot.scale or 1)/2
                if (shot.x-x)^2+(shot.y-y)^2<=extent^2 then
                    if cancel and self_ref.on_cancel_item
                        and math.abs(shot.x)<224 and shot.y>-32 and shot.y<480 then
                        self_ref.on_cancel_item(shot.x,shot.y)
                    end
                    self_ref:cancel_bullet(shot)
                end
            end
        end
        -- 42d389 cancels ordinary bullets first, then traverses the separate
        -- laser list. Their fragments also contribute item RNG and PIV.
        local laser_pieces={}
        local function emit(px,py)
            if cancel and self_ref.on_cancel_item and math.abs(px)<224 and py> -32 and py<480 then
                self_ref.on_cancel_item(px,py)
            end
        end
        local function visual(px,py,shot)
            local script=require("tnr.legacy_replay.laser").cancel_effect_script(shot)
            if script then self_ref:spawn_animation("bullet",script,px,py) end
        end
        -- 441db0 walks the laser list from its oldest head to the tail.
        for _,shot in ipairs(shots) do
            if shot.laser and not shot.deleted then
                local pieces=require("tnr.legacy_replay.laser").cancel_in_circle(shot,x,y,radius,emit,visual)
                if shot.deleted then
                    for _,piece in ipairs(pieces) do laser_pieces[#laser_pieces+1]=piece end
                end
            end
        end
        local kept={}
        for _,shot in ipairs(shots) do
            if not shot.deleted then kept[#kept+1]=shot end
        end
        for _,piece in ipairs(laser_pieces) do kept[#kept+1]=piece end
        self_ref.shots=kept
    end
    instructions.etClear=function(t,r,a) clear_bullets(t,a,false) end
    instructions.etClearAll=function(t) clear_bullets(t,nil,false) end
    instructions.etCancel=function(t,r,a) clear_bullets(t,a,true) end
    local function configure_transform(thread,args,indexed,wide)
        local group=group_at(thread,args[1])
        local shift=indexed and 1 or 0
        local slot=indexed and resolve_arg(thread,args[2],0)+1 or #(group.transforms or {})+1
        local function value(i,default) return resolve_arg(thread,args[i+shift],default) end
        local e={async=value(2,0)~=0,flags=value(3,0),int1=value(4,-999999),int2=value(5,-999999)}
        if wide then
            e.int3,e.int4=value(6,0),value(7,0)
            e.float1,e.float2,e.float3,e.float4=value(8,-999999),value(9,-999999),value(10,-999999),value(11,-999999)
        else e.float1,e.float2=value(6,-999999),value(7,-999999) end
        group.transforms=group.transforms or {};group.transforms[slot]=e
        group.ex=e
    end
    instructions.etEx=function(t,r,a) configure_transform(t,a,false,false) end
    instructions.etExSet=function(t,r,a) configure_transform(t,a,true,false) end
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
        -- Native 42c3d0 stores both sound IDs; 41c6b3 plays the first once
        -- per volley. Configuring a group is silent, even if firing is delayed.
        local group=group_at(thread,args[1])
        group.fire_sound=resolve_arg(thread,args[2],-1)
        group.transform_sound=resolve_arg(thread,args[3],-1)
    end
    instructions.etDist = function(thread, runtime, args)
        group_at(thread,args[1]).distance=resolve_arg(thread,args[2],0)
    end
    instructions.etOffsetAbs = function(thread, runtime, args)
        -- Offset the group to an absolute field position.
        local group = group_at(thread, args and args[1])
        group.offset_abs = {
            resolve_arg(thread, args and args[2], 0) or 0,
            resolve_arg(thread, args and args[3], 0) or 0,
        }
        -- Native 42be84: x < -990 switches back to the enemy origin.
        if group.offset_abs[1] < -990 then group.offset_abs=nil end
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
    instructions.enmCreateA = function(thread,runtime,args)
        self_ref:create_enemy(thread,runtime,args,true)
    end
    instructions.enmCreateM = function(t,r,a) self_ref:create_enemy(t,r,a,false,true) end
    instructions.enmCreateAM = function(t,r,a) self_ref:create_enemy(t,r,a,true,true) end
    instructions.enmCreateF = function(t,r,a) self_ref:create_enemy(t,r,a,false,false,true) end
    instructions.enmCreateMF = function(t,r,a) self_ref:create_enemy(t,r,a,false,true,true) end
    instructions.enmCreateAF = function(t,r,a) self_ref:create_enemy(t,r,a,true,false,true) end
    instructions.enmCreateAMF = function(t,r,a) self_ref:create_enemy(t,r,a,true,true,true) end
    local function clear_enemies(thread,suppress_death_script)
        local enemies=self_ref.enemies
        local index=1
        while index and enemies[index] do
            local o=enemies[index]
            local next_index=index<#enemies and index+1 or nil
            if o~=thread.object and not o.legacy_deleted and not o.legacy_is_boss and not o.legacy_no_clear then
                o.hp=0
                -- 428e6d..428eb4 clears loot and chapter credit before death.
                o.legacy_drop,o.legacy_drop_extra,o.legacy_chapter_weight=0,{},0
                if suppress_death_script then o.legacy_death_routine=nil end
                if self_ref.on_enemy_drop then self_ref.on_enemy_drop(o) end
                -- 428eb9 marks the enemy for removal before its normal tick.
                o.legacy_deleted=true
            end
            index=next_index
        end
    end
    instructions.enmKillAll = function(thread) clear_enemies(thread,false) end
    -- 429090 has the same removal path, but clears the death subroutine first.
    instructions.ins_571 = function(thread) clear_enemies(thread,true) end
    instructions.enmAlive = function() end
    instructions.setDeath = function(thread,runtime,args)
        if thread.object then
            local name=tostring(args[1] or "")
            thread.object.legacy_death_routine=name~="0" and name or nil
        end
    end

    -- --- boss presentation -------------------------------------------------
    -- The reference drives its HUD from these. The adapter forwards them to
    -- the boss UI so the bar, marker row and name plate match the original.
    instructions.setBoss = function(thread, runtime, args)
        -- setBoss(0) starts the fight, setBoss(-1) ends it.
        local value = resolve_arg(thread,args[1],0)
        local enemy = thread.object
        if value >= 0 then
            self_ref.boss_object = enemy
            if enemy then enemy.legacy_is_boss = true end
            if self_ref.boss_ui then self_ref.boss_ui:begin(enemy and enemy.max_hp or 1) end
        elseif self_ref.boss_object == enemy then
            self_ref.boss_object = nil
            if self_ref.boss_ui then self_ref.boss_ui.visible = false end
            self_ref:end_spell()
        end
    end
    instructions.lifeSet = function(thread, runtime, args)
        local enemy = thread.object
        if not enemy then return end
        local value = resolve_arg(thread,args[1],0)
        -- 42b8e4 sets both the current and maximum HP for the new phase.
        value = value * (self_ref.enemy_hp_multiplier or 1)
        enemy.hp, enemy.max_hp, enemy.legacy_scaled_hp = value, value, value*7
        if self_ref.boss_ui and self_ref.boss_object==enemy then
            self_ref.boss_ui:set_health(value,value)
        end
    end
    instructions.lifeHide = function(thread,runtime,args)
        if self_ref.boss_ui then self_ref.boss_ui.hide_ring=resolve_arg(thread,args[1],0)%2==1 end
    end
    instructions.lifeMarker = function(thread, runtime, args)
        local enemy=thread.object
        if not enemy or self_ref.boss_object~=enemy or not self_ref.boss_ui then return end
        local index=resolve_arg(thread,args[1],0)+1
        -- 42b5a1 stores this slot's threshold as a fraction of maximum HP.
        self_ref.boss_ui.health_layers[index] = {
            ratio = resolve_arg(thread,args[2],0) / math.max(1,enemy.max_hp or 1),
            colour = resolve_arg(thread,args[3],0xFFFFFFFF),
        }
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
    instructions.spellEnd = function(thread)
        if thread and thread.object then thread.object.legacy_spell_damage=false end
        self_ref:end_spell()
    end
    -- 527 / 554 / 536 are declaration helpers with no presentation of their own.
    instructions.stageLogo = function() self_ref:show_stage_logo() end
    instructions.ins_569 = function(thread, runtime, args)
        local enemy = thread.object
        if not enemy then return end
        local previous = enemy.legacy_chapter_weight or 0
        if previous == 0 or previous == 1 then
            local weight = resolve_arg(thread, args[1], 0)
            enemy.legacy_chapter_weight = weight
            if previous == 1 or weight > 0 then
                self_ref.chapter_targets = self_ref.chapter_targets + weight - previous
            end
        end
    end
    instructions.ins_570 = function(thread)
        if thread.object then self_ref:credit_chapter_target(thread.object) end
    end
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
    instructions.funcSet = function(thread,runtime,args)
        if thread.object then thread.object.legacy_func=resolve_arg(thread,args[1],0) end
    end
    instructions.funcCall = function() end
    instructions.spec1 = function() end
    instructions.spec2 = function() end
    instructions.callSTD = function() end
    instructions.diffWait = function(thread, runtime, args)
        local index=math.min(self_ref.difficulty+1,#args)
        thread.wait=math.max(0,math.floor(resolve_arg(thread,args[index],0)))
    end
    instructions.anm316 = function(thread, runtime, args)
        local enemy=thread.object
        if not enemy then return end
        local offset=resolve_arg(thread,args[2],0)
        -- 429c17 replaces the slot with an attack script from the animation
        -- bank. A negative offset restores the base script.
        play_slot(enemy,resolve_arg(thread,args[1],0),
            (enemy.legacy_main_script or 0)+(offset>=0 and 5+offset or 0))
    end
    instructions.anmPlayAbs=function(t,r,a) spawn_animation(t,resolve_arg(t,a[1],1),resolve_arg(t,a[2],0),true) end
    instructions.anmSelectedPlay=function(t,r,a)
        local o=t.object;if not o then return end
        -- 429b6b uses the first attack script regardless of movement direction.
        play_slot(o,resolve_arg(t,a[1],0),(o.legacy_main_script or 0)+5)
    end
    -- etEx2 / etExSet2 are the two-argument forms of the bullet extras; the
    -- group configuration is the same, only the argument count differs.
    instructions.etEx2=function(t,r,a) configure_transform(t,a,false,true) end
    instructions.etExSet2=function(t,r,a) configure_transform(t,a,true,true) end

    -- --- boss movement and effects -----------------------------------------
    instructions.moveRand = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        local duration=resolve_arg(thread,args[1],60)
        local box=object.legacy_move_limit
        local cx=box and (box.left+box.right)/2 or 0
        local cy=box and (box.top+box.bottom)/2 or 0
        local quarter_w=box and (box.right-box.left)/4 or 0
        local quarter_h=box and (box.bottom-box.top)/4 or 0
        local random=self_ref.random
        local signed=random(-1,1)
        local angle
        -- Native 42b28f: steer back toward the middle near horizontal edges;
        -- otherwise favour the player's side with a two-in-three chance.
        if object.x<cx-quarter_w then angle=signed*math.pi/3
        elseif object.x>cx+quarter_w then angle=(signed*math.pi/3+2*math.pi)%(2*math.pi)-math.pi
        else
            angle=signed*math.pi/4
            local word=self_ref.rng and self_ref.rng:next_u16() or math.floor(random(0,65536))
            local roll=word%3
            local player_right=(self_ref.player and self_ref.player.x or 0)>object.x
            if player_right and roll==0 or not player_right and roll~=0 then angle=angle+math.pi end
        end
        if object.y<cy-quarter_h then angle=math.abs(angle)
        elseif object.y>cy+quarter_h then angle=-math.abs(angle) end
        if math.abs(angle+math.pi/2)<.05 then angle=angle<-math.pi/2 and -math.pi/2-.05 or -math.pi/2+.05
        elseif math.abs(angle-math.pi/2)<.05 then angle=angle<math.pi/2 and math.pi/2-.05 or math.pi/2+.05 end
        local speed=resolve_arg(thread,args[3],1)
        start_velocity_move(object,angle,speed)
        -- 42b573 writes the mode to the angle interpolator again, leaving
        -- the speed channel at its previous mode (linear for a fresh boss).
        object.legacy_velocity_tween={total=math.max(1,duration),remaining=math.max(1,duration),
            mode=object.legacy_speed_interpolation_mode or 0,
            start_angle=angle,end_angle=angle,start_speed=speed,end_speed=0}
    end
    instructions.movePos = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        local x,y=resolve_arg(thread,args[1],SENTINEL),resolve_arg(thread,args[2],SENTINEL)
        local base_x, base_y = base_position(object)
        set_base_position(object, x>SENTINEL and x or base_x, y>SENTINEL and y or base_y)
        object.legacy_move=nil;object.legacy_velocity_tween=nil
        object.legacy_circle=nil
        object.legacy_vx,object.legacy_vy=0,0
    end
    instructions.moveLimit = function(thread, runtime, args)
        -- Clamp movement to a box around the current position.
        local object = thread.object
        if object then
            object.legacy_move_limit = {
                left = resolve_arg(thread,args[1],0)-resolve_arg(thread,args[3],0)/2,
                right = resolve_arg(thread,args[1],0)+resolve_arg(thread,args[3],0)/2,
                top = resolve_arg(thread,args[2],0)-resolve_arg(thread,args[4],0)/2,
                bottom = resolve_arg(thread,args[2],0)+resolve_arg(thread,args[4],0)/2,
            }
        end
    end
    instructions.moveLimitReset = function(thread, runtime)
        if thread.object then thread.object.legacy_move_limit = nil end
    end
    instructions.moveSetMirror = function(thread, runtime, args)
        if thread.object then
            local o=thread.object
            local enabled=resolve_arg(thread,args and args[1],0)~=0
            local flags=o.legacy_flags or 0
            local current=math.floor(flags/524288)%2==1
            if current~=enabled then flags=flags+(enabled and 524288 or -524288) end
            o.legacy_flags=flags;o.legacy_mirror=enabled
        end
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
    instructions.stars = function(thread,runtime,args)
        if self_ref.boss_ui and thread.object==self_ref.boss_object then
            self_ref.boss_ui.stars=math.max(0,resolve_arg(thread,args[1],0))
        end
    end
    instructions.laserCancel = function(thread,runtime,args)
        local Laser=require("tnr.legacy_replay.laser")
        for _,shot in ipairs(self_ref.shots or {}) do
            if shot.laser then
                local script=Laser.cancel_effect_script(shot)
                if shot.laser_kind=="moving" or shot.laser_kind=="stationary" then
                    -- 445140 / 4474f0 use a strict full-segment boundary.
                    for distance=8,shot.length or 0,16 do
                        if distance+8<(shot.length or 0) then
                            local x=shot.x+math.cos(shot.angle)*distance
                            local y=shot.y+math.sin(shot.angle)*distance*(shot.reflected and -1 or 1)
                            if self_ref.on_cancel_item and math.abs(x)<224 and y> -32 and y<480 then
                                self_ref.on_cancel_item(x,y)
                            end
                            if script then self_ref:spawn_animation("bullet",script,x,y) end
                        end
                    end
                elseif shot.nodes and script then
                    -- 44b1f0 produces curve effects but no cancel items.
                    for i=1,#shot.nodes,3 do
                        local node=shot.nodes[i]
                        self_ref:spawn_animation("bullet",script,node.x,node.y)
                    end
                end
                shot.deleted=true
            end
        end
    end
    instructions.killAllAsync = function(thread, runtime)
        for _, child in ipairs(runtime.threads) do
            if child ~= thread and child.object == thread.object and child.async then child.state = "finished" end
        end
    end

    -- --- item drops ---------------------------------------------------------
    instructions.dropItems = function(t)
        if t.object and self_ref.on_enemy_drop then self_ref.on_enemy_drop(t.object,true) end
    end
    instructions.dropClear = function(t)
        if t.object then t.object.legacy_drop=0;t.object.legacy_drop_extra={} end
    end
    instructions.dropArea = function(t,r,a)
        if t.object then t.object.legacy_drop_area={resolve_arg(t,a[1],0),resolve_arg(t,a[2],0)} end
    end
    instructions.etProtectRange = function() end
    instructions.flagExtDmg = function(thread,runtime,args)
        if thread.object then thread.object.legacy_ext_damage=resolve_arg(thread,args[1],0) end
    end
    instructions.validRad = function(thread,runtime,args)
        local angle=Rules.normalize_angle(resolve_arg(thread,args[1],0))
        EclRuntime.apply_assignment(thread,args[1],"=",angle)
    end
    instructions.bombShield = function() end

    -- --- lasers -------------------------------------------------------------
    -- The reference keeps a laser handle table per enemy. The adapter records
    -- the configuration so a host that draws lasers can render them; the
    -- pattern logic itself lives in the ECL.
    instructions.laserNew = function(thread, runtime, args)
        local group=group_at(thread,resolve_arg(thread,args[1],0))
        group.laser = {
            initial = resolve_arg(thread,args[2],0),
            length = resolve_arg(thread,args[3],0),
            travel = resolve_arg(thread,args[4],0),
            width = resolve_arg(thread,args[5],16),
        }
    end
    local function laser_on(thread,args,kind)
        local group=group_at(thread,resolve_arg(thread,args[1],0))
        local object=thread.object
        if not group.laser or not object then return end
        local x=(group.offset_abs and group.offset_abs[1] or object.x)+(group.offset and group.offset[1] or 0)
        local y=(group.offset_abs and group.offset_abs[2] or object.y)+(group.offset and group.offset[2] or 0)
        self_ref.next_laser_id=(self_ref.next_laser_id or 65535)+1
        local handle=kind=="stationary" and resolve_arg(thread,args[2],0) or self_ref.next_laser_id
        self_ref.shots=self_ref.shots or {}
        self_ref.shots[#self_ref.shots+1]=require("tnr.legacy_replay.laser").new(group,group.laser,x,y,kind,handle)
    end
    instructions.laserOn = function(thread,runtime,args) laser_on(thread,args,"moving") end
    instructions.laserTiming = function(thread,runtime,args)
        local group=group_at(thread,resolve_arg(thread,args[1],0))
        group.laser=group.laser or {}
        group.laser.timing={}
        for i=1,5 do group.laser.timing[i]=resolve_arg(thread,args[i+1],0) end
    end
    instructions.laserCuOn = function(thread, runtime, args)
        laser_on(thread,args,"curve")
    end
    instructions.laserStOn = function(thread, runtime, args)
        laser_on(thread,args,"stationary")
    end
    instructions.laserOffset = function() end
    instructions.laserTrajectory = function() end
    instructions.laserStLength = function() end
    instructions.laserStWidth = function() end

    -- --- movement -----------------------------------------------------------
    instructions.movePosRel = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        -- Relative position is a second coordinate channel, not a delta to
        -- FINAL_X/Y. Native instructions 400/402 select 0x88/0xcc and sum them.
        local x,y=resolve_arg(thread,args[1],SENTINEL),resolve_arg(thread,args[2],SENTINEL)
        local base_x, base_y = base_position(object)
        local old_x,old_y=object.legacy_rel_x or 0,object.legacy_rel_y or 0
        object.legacy_rel_x=x>SENTINEL and x or old_x
        object.legacy_rel_y=y>SENTINEL and y or old_y
        set_base_position(object, base_x, base_y)
        object.legacy_rel_move=nil
        object.legacy_rel_circle=nil
    end
    instructions.movePosRelTime = function(thread, runtime, args)
        local object=thread.object
        if not object then return end
        object.legacy_rel_circle=nil
        local frames=resolve_arg(thread,args[1],0)
        if frames<=0 then object.legacy_rel_move=nil;return end
        local x,y=resolve_arg(thread,args[3],SENTINEL),resolve_arg(thread,args[4],SENTINEL)
        local sx,sy=object.legacy_rel_x or 0,object.legacy_rel_y or 0
        object.legacy_rel_move={total=frames,remaining=frames,
            mode=resolve_arg(thread,args[2],0),start_x=sx,start_y=sy,
            end_x=x>SENTINEL and x or sx,end_y=y>SENTINEL and y or sy}
    end
    instructions.moveCircleRel = function(thread, runtime, args)
        instructions.moveCircle(thread, runtime, args, true)
    end
    instructions.moveCircleRelTime = function(thread, runtime, args)
        instructions.moveCircleTime(thread, runtime, args, true)
    end
    instructions.moveSpeed = function(thread, runtime, args)
        local o=thread.object
        if o then
            o.legacy_speed=resolve_angle(resolve_arg(thread,args[1],SENTINEL),o.legacy_speed)
            o.legacy_vx=math.cos(o.legacy_angle or 0)*o.legacy_speed
            o.legacy_vy=math.sin(o.legacy_angle or 0)*o.legacy_speed
            if o.legacy_scalar_tweens then o.legacy_scalar_tweens.legacy_speed=nil end
        end
    end
    instructions.circlePos = function(thread, runtime, args)
        -- circlePos(outX,outY,angle,radius) writes a vector. It never moves
        -- the enemy; boss scripts use the outputs as emitter offsets.
        local angle,radius=resolve_arg(thread,args[3],0),resolve_arg(thread,args[4],0)
        EclRuntime.apply_assignment(thread,args[1],"=",math.cos(angle)*radius)
        EclRuntime.apply_assignment(thread,args[2],"=",math.sin(angle)*radius)
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
        local x1,y1=resolve_arg(thread,args[2],0),resolve_arg(thread,args[3],0)
        local x2,y2=resolve_arg(thread,args[4],0),resolve_arg(thread,args[5],0)
        EclRuntime.apply_assignment(thread,args[1],"=",float32(angle_between(x1,y1,x2,y2)))
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
    instructions.enmMapleEnemy = instructions.enmCreate
    instructions.enm322 = function(thread, runtime, args)
        -- 429597 writes a per-animation source slot; 428a23 adds that VM's
        -- local position to the target animation's entity position.
        local object=thread.object;if not object then return end
        object.legacy_anm_position_sources=object.legacy_anm_position_sources or {}
        object.legacy_anm_position_sources[resolve_arg(thread,args[1],0)]=resolve_arg(thread,args[2],-1)
    end
    instructions.gameSpeed = function(thread,runtime,args)
        local scale=resolve_arg(thread,args and args[1],1)
        self_ref.game_speed=math.max(0,math.min(4,tonumber(scale) or 1))
        if self_ref.on_game_speed then self_ref.on_game_speed(self_ref.game_speed) end
    end
    instructions.floatTime = function(thread,runtime,args)
        local slot=resolve_arg(thread,args[1],0)
        local first,last=resolve_arg(thread,args[5],0),resolve_arg(thread,args[6],0)
        local duration=resolve_arg(thread,args[3],0)
        thread.float_tweens=thread.float_tweens or {}
        thread.float_tweens[slot]=duration>0 and {target=args[2],duration=duration,
            mode=resolve_arg(thread,args[4],0),first=first,last=last,started=runtime.frame or 0} or nil
        EclRuntime.apply_assignment(thread,args[2],"=",first)
    end
    instructions.spellEx = function(thread, runtime, args)
        self_ref:begin_spell(thread, args)
    end
    instructions.spellMode = function(thread,runtime,args)
        if thread.object then thread.object.legacy_spell_damage=resolve_arg(thread,args[1],0)%2==1 end
    end
    instructions.spellTimeout = function(thread)
        self_ref.spell_timeout_enabled=true
        if thread.object then
            thread.object.legacy_spell_timeout_enabled=true
            thread.object.legacy_spell_timeout=math.max(0,tonumber(thread.spell_timer) or 0)
        end
    end
    instructions.anmSwitch = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        if player then player:play(tonumber(args and args[1]) or 0) end
    end
    instructions.anmPlayPos = function(t,r,a)
        -- Native 4295c9..4296be: archive, script, relative X/Y, Z rotation.
        local vm=spawn_animation(t,resolve_arg(t,a[1],1),resolve_arg(t,a[2],0),false)
        if vm then
            vm.origin_x=vm.origin_x+resolve_arg(t,a[3],0)
            vm.origin_y=vm.origin_y+resolve_arg(t,a[4],0)
            vm.rotation=vm.rotation+resolve_arg(t,a[5],0)
        end
    end
    -- Diagnostic output has no battle-state effect.
    instructions.ins_30 = function() end
    -- 42ca97 toggles the native homing-exclusion flag, used by the moons.
    instructions.ins_544 = function(t,r,a)
        flags(t,{0x8000000},resolve_arg(t,a[1],0)==0)
    end
    instructions.ins_549 = function(t,r,a)
        flags(t,{0x80000000},resolve_arg(t,a[1],0)==0)
    end
    instructions.debug901 = function() end
    instructions.debug902 = function() end
    instructions.etExSub = function(t,r,a)
        local group=group_at(t,a[1]);local slot=resolve_arg(t,a[2],0)+1
        local entry=group.transforms and group.transforms[slot]
        if entry then entry.routine=r:resolve_routine(tostring(a[3]),t) end
    end
    instructions.etExSubtract = function(t,r,a)
        local group=group_at(t,a[1]);if group.transforms then table.remove(group.transforms) end
    end
    instructions.killAsync = function(thread, runtime, args)
        local id=resolve_arg(thread,args[1],-1)
        for index=#runtime.threads,1,-1 do
            local victim=runtime.threads[index]
            if victim.object==thread.object and victim.async_id==id and victim.state~="finished" then
                victim.state="finished";break
            end
        end
    end
    instructions.moveCircle = function(thread, runtime, args, relative, ellipse)
        -- Native 408/410: angle, angular velocity, radius, radial velocity.
        -- Switching into circle mode preserves this channel's old position as
        -- its center; calling it again preserves the established center.
        local object = thread.object
        if not object then return end
        local key=relative and "legacy_rel_circle" or "legacy_circle"
        local base_x, base_y = base_position(object)
        local circle=object[key] or {
            origin_x=relative and (object.legacy_rel_x or 0) or base_x,
            origin_y=relative and (object.legacy_rel_y or 0) or base_y}
        for index,name in ipairs({"angle","angular","radius","radial"}) do
            circle[name]=resolve_angle(resolve_arg(thread,args[index],SENTINEL),circle[name])
        end
        if ellipse then
            circle.rotation=resolve_angle(resolve_arg(thread,args[5],SENTINEL),circle.rotation)
            circle.aspect=resolve_angle(resolve_arg(thread,args[6],SENTINEL),circle.aspect or 1)
        else circle.rotation,circle.aspect=nil,nil end
        object[key]=circle
        local x,y=circle_position(circle)
        if relative then
            object.legacy_rel_x,object.legacy_rel_y=x,y
            set_base_position(object, base_x, base_y)
        else
            set_base_position(object, x, y)
        end
        if relative then object.legacy_rel_move=nil
        else object.legacy_move=nil;object.legacy_velocity_tween=nil end
    end
    instructions.moveCircleTime = function(thread, runtime, args, relative, ellipse)
        local object=thread.object
        if not object then return end
        local key=relative and "legacy_rel_circle" or "legacy_circle"
        if not object[key] then instructions.moveCircle(thread,runtime,{SENTINEL,SENTINEL,SENTINEL,SENTINEL},relative) end
        local circle=object[key]
        local frames=resolve_arg(thread,args[1],0)
        if frames<=0 then circle.tween=nil;return end
        local tween={total=frames,remaining=frames,mode=resolve_arg(thread,args[2],0),first={},last={}}
        local fields=ellipse and {"angular","radius","radial","rotation","aspect"} or {"angular","radius","radial"}
        for index,name in ipairs(fields) do
            circle[name]=circle[name] or (name=="aspect" and 1 or 0)
            tween.first[name]=circle[name]
            tween.last[name]=resolve_angle(resolve_arg(thread,args[index+2],SENTINEL),circle[name])
        end
        circle.tween=tween
    end

    -- --- per-animation state -----------------------------------------------
    local function animation_slot(thread,args)
        local object=thread.object
        local slot=resolve_arg(thread,args[1],0)
        return object and ((object.legacy_anm_slots or {})[slot] or (slot==0 and object.legacy_anm))
    end
    instructions.anmLayer = function(thread, runtime, args)
        local vm=animation_slot(thread,args)
        if vm then vm.layer=resolve_arg(thread,args[2],0) end
        if thread.object and resolve_arg(thread,args[1],0)==0 then thread.object.legacy_layer=resolve_arg(thread,args[2],0) end
    end
    instructions.anmColor = function(thread, runtime, args)
        local player = animation_slot(thread,args)
        if player then
            player.red,player.green,player.blue=resolve_arg(thread,args[2],255),resolve_arg(thread,args[3],255),resolve_arg(thread,args[4],255)
            player.color={player.red,player.green,player.blue}
        end
    end
    instructions.anmAlpha = function(thread, runtime, args)
        local player = animation_slot(thread,args)
        if player then player.alpha=resolve_arg(thread,args[2],255);player.tweens.alpha=nil end
    end
    instructions.anmAlphaTime = function(thread, runtime, args)
        -- Arguments are slot, duration, easing, target alpha.
        local player = animation_slot(thread,args)
        if player then
            player:ramp("alpha",resolve_arg(thread,args[4],255),resolve_arg(thread,args[2],0),resolve_arg(thread,args[3],0))
        end
    end
    instructions.anmScale = function(thread, runtime, args)
        local player = animation_slot(thread,args)
        if player then
            player.scale_x=resolve_arg(thread,args[2],1);player.scale_y=resolve_arg(thread,args[3],player.scale_x)
            player.tweens.scale_x=nil;player.tweens.scale_y=nil
        end
    end
    instructions.anmScaleTime = function(thread, runtime, args)
        local player = animation_slot(thread,args)
        if player then
            player:ramp("scale_x",resolve_arg(thread,args[4],1),resolve_arg(thread,args[2],0),resolve_arg(thread,args[3],0))
            player:ramp("scale_y",resolve_arg(thread,args[5],1),resolve_arg(thread,args[2],0),resolve_arg(thread,args[3],0))
        end
    end
    instructions.anmRotate = function(thread, runtime, args)
        local player = animation_slot(thread,args)
        if player then
            player.rotation=resolve_arg(thread,args[2],0)
        end
    end

    return instructions
end

function Adapter:end_spell()
    if self.spell_background then
        self.spell_background.finished = true
        self.spell_background = nil
    end
    if self.boss_ui then self.boss_ui.card, self.boss_ui.card_timer = nil, 0 end
    self.spell_active = false
end

--- Start a spell card and its original stage animations.
function Adapter:begin_spell(thread, args)
    -- spell(layer, duration, score, name)
    local name = tostring(args and args[4] or "")
    self:end_spell()
    -- Native 420474 starts a new spell by clearing the spell manager's
    -- timeout-card flag. ECL spellTimeout (542) can arm it again afterwards.
    self.spell_timeout_enabled = false
    self.spell_active = true
    local art = SPELL_ART[self.stage_key]
    local archive = self.stage_key and self.stage_key.."enm"
    if art and self.anm[archive] then
        self.spell_background = self:spawn_animation(archive,art.background,0,0)
        self:spawn_animation(archive,art.cut_in,0,0)
    end
    if self.boss_ui then
        self.boss_ui:show_card(name)
    end
    if thread.object then
        thread.object.legacy_spell_damage = true
        thread.object.legacy_scaled_hp = (thread.object.hp or 0)*7
        thread.object.legacy_spell = name
        thread.object.legacy_spell_failed = false
        thread.object.legacy_spell_timeout_enabled = nil
        thread.spell_timer = tonumber(args and args[2]) or 0
    end
end

--- Spawn an enemy from an enmCreate-family call.
-- Args are (routine, x, y, hp, score, item), where the coordinates may be
-- unresolved expressions the interpreter already evaluated into the frame.
function Adapter:create_enemy(thread, runtime, args, absolute, mirrored, without_boss)
    -- 42928a skips the F variants while boss slot zero is occupied.
    if without_boss and self.boss_object and not self.boss_object.legacy_deleted then return end
    local routine = tostring(args[1] or "")
    -- Coordinates are ECL expressions such as `%A - _f(32)`; evaluate them
    -- against the calling thread's frame instead of parsing the raw text.
    local x = resolve_arg(thread,args[2],0)
    local y = resolve_arg(thread,args[3],0)
    local hp = resolve_arg(thread,args[4],50)
    -- 4260ac initializes the main drop from the last enmCreate argument.
    local main_drop = resolve_arg(thread,args[6],0)
    -- Native 42e226..42e295: the A variants use field coordinates; ordinary
    -- creation adds the caller's FINAL position (including relative motion).
    if not absolute and thread.object then
        x=x+(thread.object.x or 0);y=y+(thread.object.y or 0)
    end
    if thread.object and thread.object.legacy_mirror then
        x=-x;mirrored=not mirrored
    end
    self:spawn_enemy(routine, x, y, hp, { mirrored = mirrored, main_drop = main_drop }, thread)
end

function Adapter:run_death_routine(enemy)
    if enemy.legacy_death_called or not enemy.legacy_death_routine
            or enemy.legacy_death_routine=="" then return end
    enemy.legacy_death_called=true
    self.runtime:call(enemy.legacy_thread,enemy.legacy_death_routine,false,{})
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
    local ox=(group.offset_abs and group.offset_abs[1] or object.x)+(group.offset and group.offset[1] or 0)
    local oy=(group.offset_abs and group.offset_abs[2] or object.y)+(group.offset and group.offset[2] or 0)
    local aim = 0
    if player then
        aim = angle_between(ox, oy, player.x, player.y)
    end
    -- etAim supplies the mode; without it the reference treats the volley as a
    -- single ring facing the base angle.
    local mode = group.aim
    if mode == nil then mode = BulletPatterns.MODE.CIRCLE end
    local count = math.max(0, math.floor(group.count or 1))
    local speed = group.speed or 3
    local expanded = BulletPatterns.expand({
        count1 = count,
        count2 = math.max(0, math.floor(group.count_spec or 1)),
        speed1 = speed,
        speed2 = group.speed_spec or speed,
        angle1 = group.angle or 0,
        angle2 = group.angle_spec or 0,
        mode = mode,
        aim_angle = aim,
        random = self.random,
    })
    local bullet_class = self.bullet_styles[1]
    for _, bullet in ipairs(expanded) do
        self:spawn_bullet(bullet_class, ox+math.cos(bullet.angle)*(group.distance or 0),
            oy+math.sin(bullet.angle)*(group.distance or 0), bullet.speed, bullet.angle,
            group.sprite, group.anim, false, group.color_index, group.ex, group.transforms)
    end
    if group.fire_sound and group.fire_sound>=0 then
        -- The imported fire-sound IDs often resolve to unrelated UI/timeout
        -- sounds in the flattened table. TH15's enemy projectile voice is
        -- enep00; keep it quiet because it is emitted once per volley.
        if self.on_sound then
            local path = Sounds.path_for(1)
            if path then pcall(self.on_sound, path, 0.16) end
        end
    end
end

--- Spawn one bullet. Falls back to recording when the style is unavailable.
-- Player shots are marked so the renderer can draw them differently and so
-- culling can treat them separately.
function Adapter:spawn_bullet(bullet_class, x, y, speed, angle, sprite, anim, is_player, color_index, ex, transforms)
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
            transforms = transforms and require("tnr.core.immutable").copy(transforms),
            ex_timer = 0,
        }
        local shot=self.shots[#self.shots]
        if not shot.player_bullet then
            shot.random=self.random
            require("tnr.legacy_replay.bullet_transforms").prepare_spawn(
                shot,self.player,self.spawn_ticks_for)
        end
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

function Adapter:shot_in_field(shot)
    if not shot.player_bullet then
        local descriptor = BulletTypes[shot.sprite or shot.anim or 0]
        local color = math.max(0, math.min(15, math.floor(shot.color_index or 0)))
        -- 41991a uses the current ANM sprite, including the larger birth
        -- animation, rather than the projectile's eventual live sprite.
        local animation = descriptor and self:bullet_animation(shot,descriptor)
        local sprite = animation and animation:global_sprite()
        if not sprite and descriptor then sprite=descriptor.sprites[color + 1] end
        local rect = sprite and self.bullet_rects[sprite + 1]
        if not rect and descriptor then
            local fallback=descriptor.sprites[color + 1]
            rect=fallback and self.bullet_rects[fallback + 1]
        end
        if rect then
            -- 41991a..4199e1 clips ordinary bullets by their sprite extents.
            local half_scale = math.abs(shot.scale or 1)/2
            local half_w, half_h = rect.w*half_scale, rect.h*half_scale
            return shot.x + half_w > -192 and shot.x - half_w < 192
                and shot.y + half_h > -64 and shot.y - half_h < 448
        end
    end
    return shot.x > -260 and shot.x < 260 and shot.y > -80 and shot.y < 540
end

function Adapter:advance_player_shot(shot)
    if shot.deleted then return end
    local vm = shot.player_animation
    local age = shot.anim_frame or 0
    if vm and (vm.finished or (age >= 10 and not shot.beam_length and not ClassicShots.inside_field(shot))) then
        shot.deleted = true
        return
    end
    if shot.callback_tick == 1 and not shot.spent then
        ClassicShots.advance_homing(shot, self.enemies)
    else
        shot.previous_x, shot.previous_y = shot.x, shot.y
        if shot.just_fired then
            -- 4589de subtracts the initial velocity. The ordinary first
            -- update adds it back, leaving the projectile at the muzzle.
            shot.just_fired = nil
        elseif not shot.beam_length then
            shot.x = Rules.motion_coordinate(shot.x + (shot.vx or 0))
            shot.y = Rules.motion_coordinate(shot.y + (shot.vy or 0))
        end
    end
    shot.anim_frame = age + 1
    if vm then vm:update() end
    if (shot.lifetime and shot.anim_frame > shot.lifetime)
        or (not vm and shot.anim_frame > 5 and not self:shot_in_field(shot)) then shot.deleted = true end
end

--- Advance scripted bullets by one frame with five ticks of launch grace.
function Adapter:advance_shots(player_shots_updated)
    local cancelling = {}
    for _, shot in ipairs(self.cancelled_shots) do
        local animation = shot.legacy_bullet_animation
        animation:advance_to(animation.age + 1)
        if not animation.finished then cancelling[#cancelling + 1] = shot end
    end
    self.cancelled_shots = cancelling
    local kept = {}
    local culled_for_contact={}
    local emitted={}
    local shots=self.shots or {}
    local original_count=#shots
    local order={}
    -- Native callbacks run lasers (priority 0x1b) before ordinary bullets
    -- (0x1c). Lasers append at the tail; bullets insert at the head.
    -- Player sources normally already advanced before the enemy manager.
    for index,shot in ipairs(shots) do
        if shot.player_bullet then order[#order+1]=index end
    end
    for index,shot in ipairs(shots) do
        if not shot.player_bullet and shot.laser then order[#order+1]=index end
    end
    for index=#shots,1,-1 do
        local shot=shots[index]
        if not shot.player_bullet and not shot.laser then order[#order+1]=index end
    end
    for _,index in ipairs(order) do
        local shot=shots[index]
        if shot.player_bullet then
            if not player_shots_updated then self:advance_player_shot(shot) end
            if not shot.deleted then kept[index]=shot end
        elseif not shot.deleted then
        shot.random=self.random
        local birth_guard_paused=shot.birth_offscreen_pending
        local native_split_protected=shot.native_split_grace and (shot.keep_offscreen or 0)>0
        if not birth_guard_paused then
            shot.keep_offscreen=math.max(0,(shot.keep_offscreen or 0)-1)
        end
        shot.bomb_invulnerable=math.max(0,(shot.bomb_invulnerable or 0)-1)
        if shot.laser then
            local Laser=require("tnr.legacy_replay.laser")
            if shot.native_full_cancel_pending then shot.deleted=true
            else
                Laser.update(shot,self.player)
                for _,event in ipairs(shot.bounce_emissions or {}) do
                    local transforms=require("tnr.core.immutable").copy(shot.transforms)
                    for i,entry in ipairs(shot.transforms or {}) do
                        if entry==event.entry then transforms[i].int1=math.max(0,(entry.int1 or 0)-1); break end
                    end
                    local group={angle=event.angle,speed=event.speed,sprite=shot.sprite,color_index=shot.color_index,transforms=transforms}
                    local config={initial=0,length=shot.max_length,travel=shot.travel_limit,width=shot.width,timing=shot.timing}
                    local child=Laser.new(group,config,event.x,event.y,"moving",shot.laser_handle)
                    Laser.update(child,self.player)
                    emitted[#emitted+1]=child
                end
                shot.bounce_emissions=nil
                if not shot.deleted and (native_split_protected or shot.keep_offscreen>0 or Laser.in_field(shot)) then kept[index]=shot end
            end
        else
            if shot.transforms then require("tnr.legacy_replay.bullet_transforms").update(shot,self.player,self.spawn_ticks_for)
            else apply_bullet_effects(shot) end
            if birth_guard_paused and not shot.birth_offscreen_pending then
                -- 41dce0 ticks once on the frame that birth releases.
                shot.keep_offscreen=math.max(0,(shot.keep_offscreen or 0)-1)
            end
            shot.previous_x,shot.previous_y=shot.x,shot.y
            local scale=float32(shot.motion_scale or 1)
            local dx=float32(float32(shot.vx or 0)*scale)
            local dy=float32(float32(shot.vy or 0)*scale)
            shot.x = float32(float32(shot.x) + dx)
            shot.y = float32(float32(shot.y) + (shot.reflected and -dy or dy))
            shot.anim_frame = (shot.anim_frame or 0) + 1
            if not shot.deleted and (not shot.lifetime or shot.anim_frame <= shot.lifetime) then
                if shot.keep_offscreen > 0 or shot.anim_frame <= 5 or self:shot_in_field(shot) then
                    kept[index] = shot
                else
                    -- Native 4196f6 checks contact before 41991a culls the
                    -- sprite; let the stage resolve this final tick once.
                    culled_for_contact[index]=shot
                end
            end
        end
        for _,event in ipairs(shot.transform_emissions or {}) do
            emitted[#emitted+1]=self:laser_from_transform(shot,event)
        end
        shot.transform_emissions=nil
        for _,event in ipairs(shot.transform_enemies or {}) do
            local e=event.entry
            local globals={}
            for n=1,4 do
                globals["I"..(n-1)]=e["int"..n] or 0
                globals["F"..(n-1)]=e["float"..n] or 0
            end
            -- 426050 copies the creation registers before 426212 performs
            -- the first enemy tick, even when called by a bullet transform.
            self:spawn_enemy(e.routine,event.x,event.y,10000,
                {initialize_now=true,legacy_globals=globals})
        end
        shot.transform_enemies=nil
        for _,sound in ipairs(shot.transform_sounds or {}) do self.instructions.playSound({},nil,{sound}) end
        shot.transform_sounds=nil
        for flag in pairs(shot.unsupported_transforms or {}) do
            self.unsupported_transforms=self.unsupported_transforms or {};self.unsupported_transforms[flag]=true
        end
        end
    end
    local ordered_kept={}
    for index=1,#shots do
        if kept[index] then ordered_kept[#ordered_kept+1]=kept[index]
        elseif index>original_count and not shots[index].deleted then
            -- Initializing a transform controller can append new shots;
            -- the manager snapshots its next node, so they start next tick.
            ordered_kept[#ordered_kept+1]=shots[index]
        end
    end
    for _,shot in ipairs(emitted) do ordered_kept[#ordered_kept+1]=shot end
    self.shots = ordered_kept
    self.contact_shots=nil
    self.contact_culled=nil
    if next(culled_for_contact) then
        local contacts={}
        local culled={}
        for index=1,original_count do
            local shot=kept[index] or culled_for_contact[index]
            if shot then contacts[#contacts+1]=shot end
            if culled_for_contact[index] then culled[shot]=true end
        end
        for index=original_count+1,#shots do
            if not shots[index].deleted then contacts[#contacts+1]=shots[index] end
        end
        for _,shot in ipairs(emitted) do contacts[#contacts+1]=shot end
        self.contact_shots=contacts
        self.contact_culled=culled
    end
end

function Adapter:laser_from_transform(source,event)
    -- Native 41c127..41c4ce consumes two adjacent transform slots. Infinite
    -- lasers use a packed delete bit/handle and a different width operand.
    local p,e=event.prep,event.finish
    local fixed=p.int1==1
    local function value(n,fallback) return n and n>-999990 and n or fallback end
    local origin_x,origin_y=event.x or source.x,event.y or source.y
    local angle=tonumber(p.float1)
    if not angle or angle<=-999990 then
        angle=event.angle or source.angle or 0
    elseif angle>=999990 then
        -- 41c1f2 treats the positive sentinel as an aim-at-player request,
        -- using the bullet position and player position at laser creation.
        local player=self.player or (self.lstg and self.lstg.player)
        if player then
            local dx=float32(float32(player.x or 0)-float32(origin_x or 0))
            local dy=float32(float32(player.y or 0)-float32(origin_y or 0))
            angle=(dx==0 and dy==0) and HALF_PI or float32(angle_between(0,0,dx,dy))
        else
            angle=event.angle or source.angle or 0
        end
    else
        angle=normalize_motion_angle(angle)
    end
    local group={angle=angle,speed=value(p.float2,event.speed or source.speed),
        sprite=p.int2,color_index=p.int3,distance=value(e.float3,0),
        transforms=not fixed and source.transforms or nil}
    self.next_laser_id=(self.next_laser_id or 65535)+1
    local handle=fixed and math.floor((p.int4 or 0)/256)%256 or self.next_laser_id
    local config={initial=p.float3,length=p.float4,travel=fixed and 0 or value(e.float1,0),
        width=value(fixed and e.float1 or e.float2,16),
        timing=fixed and {e.int1,e.int2,e.int3,e.int4,0} or {0,0,0,0,0}}
    local laser=require("tnr.legacy_replay.laser").new(group,config,origin_x,origin_y,fixed and "stationary" or "moving",handle)
    laser.rotation_speed=fixed and value(e.float2,0) or 0
    laser.transform_pc=fixed and 19 or (e.int3 or 0)+1
    if not fixed then self.instructions.playSound({},nil,{e.int1}) end
    return laser
end

--- Apply damage to an enemy. The reference reduces health directly and the
-- manager observes the change, so the adapter keeps the same model.
function Adapter:damage_enemy(enemy, amount)
    if not enemy then return end
    amount=tonumber(amount) or 0
    if enemy.legacy_ext_damage==1 then
        -- 427bcf adds the return from 431a30 to the base damage. The
        -- callback returns the base damage again plus any queued orb damage.
        amount=amount*2
        local registers=enemy.legacy_globals
        if registers and (registers.I3 or 0)>0 then
            amount=amount+registers.I3
            registers.I3=0
        end
    end
    if enemy.legacy_spell_damage then
        -- 424dc0 keeps a scaled accumulator so small hits still add up.
        local scaled = (enemy.legacy_scaled_hp or (enemy.hp or 0)*7)-amount
        local threshold = enemy.legacy_damage_threshold or 0
        enemy.legacy_scaled_hp = scaled
        enemy.hp = math.max(0,threshold+math.modf((scaled-threshold*7)/7))
    else
        enemy.hp = math.max(0, (enemy.hp or 0) - amount)
    end
    if self.boss_ui and enemy==self.boss_object then self.boss_ui:set_health(enemy.hp, self.boss_ui.health_max) end
end

function Adapter:apply_pending_damage(enemy)
    local registers=enemy.legacy_globals
    if enemy.legacy_ext_damage==1 and registers and (registers.I3 or 0)>0 then
        -- 427bdd consumes the external-damage callback before 427cef checks
        -- protection. A protected boss must not carry orb damage into its
        -- next vulnerable frame.
        if enemy.legacy_no_damage or (enemy.legacy_invulnerable_until or 0)>(self.frame or 0) then
            registers.I3=0
        else
            self:damage_enemy(enemy,0)
        end
    end
end

function Adapter:credit_chapter_target(enemy)
    local weight = enemy.legacy_chapter_weight or 0
    if weight > 0 and enemy.legacy_chapter == self.chapter_active then
        self.chapter_defeated = self.chapter_defeated + weight
        enemy.legacy_chapter_weight = 0
    end
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
        self:advance_enemy_interrupts(enemy)
    end
    local boss = self.boss_object
    if self.boss_ui then
        local remaining
        for _, entry in pairs(boss and boss.legacy_interrupts or {}) do
            if not entry.fired and entry.routine~="" and entry.finish>0 then
                local elapsed=self.frame-(boss.legacy_timer_start or entry.registered_frame)
                local time=math.max(0,entry.finish-elapsed)
                remaining=remaining and math.min(remaining,time) or time
            end
        end
        self.boss_ui.remaining=remaining
    end
end

function Adapter:advance_enemy_interrupts(enemy)
    local frame = self.frame or 0
    local interrupts = enemy.legacy_interrupts
    if not interrupts or enemy.legacy_deleted or enemy.legacy_interrupt_frame==frame then return end
    -- 430050 checks the first enabled health slot, followed by the first
    -- enabled timer slot when health has not crossed its threshold.
    local health, timer
    for id=0,7 do
        local entry=interrupts[id]
        if entry and not entry.fired and entry.start>=0 and entry.routine~="" then
            health=health or entry
            if not timer and entry.finish>0 then timer=entry end
        end
    end
    enemy.legacy_damage_threshold=health and health.start or 0
    local entry=health and (enemy.hp or 0)<=health.start and health
    local timed_out=false
    if not entry and timer and frame-(enemy.legacy_timer_start or timer.registered_frame)>=timer.finish then
        entry,timed_out=timer,true
    end
    if not entry then return end

    entry.fired=true
    enemy.legacy_interrupt_frame,enemy.legacy_timer_start=frame,frame
    enemy.hp=entry.start
    if not timed_out or (enemy.legacy_spell_timeout_enabled and not enemy.legacy_spell_failed) then
        self:credit_chapter_target(enemy)
    end
    enemy.legacy_chapter_weight=0
    enemy.legacy_spell_timeout_enabled=nil
    local routine=timed_out and enemy.legacy_timeouts and enemy.legacy_timeouts[entry.id] or entry.routine
    for _,active in ipairs(self.runtime.threads) do
        if active.object==enemy then active.state="finished" end
    end
    local thread=self.runtime:spawn(routine,enemy.legacy_thread)
    -- 430287 marks a timer interrupt, but 430299 clears that ECL-visible bit
    -- unless the global spell manager's spellTimeout flag (0x08) is armed.
    -- Keep timed_out separate: it still selects the timeout routine and delays
    -- its first step even when the script observes TIMEOUT == 0.
    thread.ints,thread.floats={TIMEOUT=(timed_out and self.spell_timeout_enabled) and 1 or 0},{}
    enemy.legacy_globals=enemy.legacy_globals or {}
    enemy.legacy_globals.TIMEOUT=thread.ints.TIMEOUT
    thread.object,thread.runtime=enemy,self.runtime
    enemy.legacy_thread,enemy.legacy_pending_interrupt=thread,true
    self.runtime.threads[#self.runtime.threads+1]=thread
    -- 427da5 starts health-triggered scripts immediately; 427eb4 only
    -- switches context on timeout, so its script starts on the next tick.
    if not timed_out then EclRuntime.step(thread,self.runtime) end
end

--- Advance every enemy animation and the ECL threads by one frame.
--- Advance one enemy's movement for a frame.
-- A time move interpolates along its eased path and follows the reference
-- exactly, including clamping to the destination when the timer expires. A
-- velocity move simply integrates the velocity.
local function advance_circle(circle)
    local tween=circle.tween
    if tween then
        tween.remaining=math.max(0,tween.remaining-1)
        local t=ease_fraction(tween.mode,tween.remaining/tween.total)
        for name in pairs(tween.first) do
            circle[name]=tween.first[name]+(tween.last[name]-tween.first[name])*t
        end
        if tween.remaining==0 then circle.tween=nil end
    end
    -- The native circle accumulator stores a float and wraps after each tick.
    -- Its rounding affects the final motion angle used by ECL emitters.
    circle.angle=normalize_motion_angle(float32(circle.angle+circle.angular))
    circle.radius=circle.radius+circle.radial
    return circle_position(circle)
end

function Adapter:advance_absolute_movement(enemy)
    if enemy.legacy_circle then
        local old_x,old_y=enemy.x,enemy.y
        enemy.x,enemy.y=advance_circle(enemy.legacy_circle)
        enemy.legacy_vx,enemy.legacy_vy=enemy.x-old_x,enemy.y-old_y
        return
    end
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
    if enemy.legacy_scalar_tweens and next(enemy.legacy_scalar_tweens) then
        for field,tween in pairs(enemy.legacy_scalar_tweens) do
            tween.remaining=math.max(0,tween.remaining-1)
            local value
            if tween.mode==7 then
                -- 41f0ce/41f0f2 accumulates the unwrapped value in the
                -- interpolator and holds its last value on the terminal tick.
                if tween.remaining>0 then tween.first=float32(tween.first+tween.last) end
                value=tween.first
            else
                local t=ease_fraction(tween.mode,tween.remaining/tween.total)
                value=tween.first+(tween.last-tween.first)*t
            end
            enemy[field]=field=="legacy_angle" and normalize_motion_angle(value) or value
            if tween.remaining==0 then enemy.legacy_scalar_tweens[field]=nil end
        end
        enemy.legacy_vx=math.cos(enemy.legacy_angle or 0)*(enemy.legacy_speed or 0)
        enemy.legacy_vy=math.sin(enemy.legacy_angle or 0)*(enemy.legacy_speed or 0)
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
        enemy.x = enemy.x + float32(enemy.legacy_vx or 0)
        enemy.y = enemy.y + float32(enemy.legacy_vy or 0)
    end
end

local function combine_position(previous, base, relative)
    -- 4278d0 forms a velocity from the summed channels, then integrates and
    -- floors the final position as a separate motion channel.
    local delta = float32(float32(base + relative) - previous)
    return Rules.motion_coordinate(previous + delta),delta
end

function Adapter:advance_enemy_movement(enemy)
    -- Advance both channels independently; collisions, rendering and emission
    -- use their sum. Absolute velocity must not integrate the relative offset.
    local old_x,old_y=enemy.x or 0,enemy.y or 0
    enemy.x, enemy.y = base_position(enemy)
    self:advance_absolute_movement(enemy)
    local move=enemy.legacy_rel_move
    if enemy.legacy_rel_circle then
        enemy.legacy_rel_x,enemy.legacy_rel_y=advance_circle(enemy.legacy_rel_circle)
    end
    if move then
        move.remaining=math.max(0,move.remaining-1)
        local t=ease_fraction(move.mode,move.remaining/move.total)
        enemy.legacy_rel_x=move.start_x+(move.end_x-move.start_x)*t
        enemy.legacy_rel_y=move.start_y+(move.end_y-move.start_y)*t
        if move.remaining==0 then enemy.legacy_rel_move=nil end
    end
    local base_x, base_y = Rules.motion_coordinate(enemy.x), Rules.motion_coordinate(enemy.y)
    local rel_x = Rules.motion_coordinate(enemy.legacy_rel_x or 0)
    local rel_y = Rules.motion_coordinate(enemy.legacy_rel_y or 0)
    enemy.legacy_rel_x, enemy.legacy_rel_y = rel_x, rel_y
    local final_x,final_vx=combine_position(old_x,base_x,rel_x)
    local final_y,final_vy=combine_position(old_y,base_y,rel_y)
    enemy.x,enemy.y=final_x,final_y
    local box = enemy.legacy_move_limit
    if box then
        enemy.x = math.max(box.left, math.min(box.right, enemy.x))
        enemy.y = math.max(box.top, math.min(box.bottom, enemy.y))
        base_x, base_y = float32(enemy.x - rel_x), float32(enemy.y - rel_y)
    end
    enemy.legacy_base_x, enemy.legacy_base_y = base_x, base_y
    -- 4278d0 stores this delta before 404170 quantizes the visible position;
    -- ECL's FINAL_ANGLE uses the stored velocity, not the quantized delta.
    enemy.legacy_final_vx,enemy.legacy_final_vy=final_vx,final_vy
    if enemy.legacy_final_vx~=0 or enemy.legacy_final_vy~=0 then
        enemy.legacy_final_angle=angle_between(0,0,final_vx,final_vy)
    end
end

function Adapter:bullet_anim_info(id)
    local cached = self.bullet_anim_cache[id]
    if cached ~= nil then return cached or nil end
    for entry_index, entry in ipairs(self.anm.bullet or {}) do
        local script = entry.scripts and entry.scripts[id]
        if script then
            local info = { entry_index = entry_index, script = script }
            self.bullet_anim_cache[id] = info
            return info
        end
    end
    self.bullet_anim_cache[id] = false
end

function Adapter:bullet_spawn_ticks(shot, interrupt)
    local descriptor = BulletTypes[shot.sprite or shot.anim or 0]
    local info = descriptor and self:bullet_anim_info(descriptor.script)
    if not info then return nil end
    local key = interrupt or 0
    info.spawn_ticks = info.spawn_ticks or {}
    if info.spawn_ticks[key] == nil then
        local ticks, offset = BulletAnimation.spawn_ticks(info.script, descriptor, interrupt)
        info.spawn_ticks[key] = ticks and { ticks, offset } or false
    end
    local result = info.spawn_ticks[key]
    if result then return result[1], result[2] end
end

function Adapter:bullet_animation(shot, descriptor)
    local animation = shot.legacy_bullet_animation
    if not animation then
        local info = self:bullet_anim_info(descriptor.script)
        if not info then return nil end
        local color = math.max(0, math.min(15, math.floor(shot.color_index or 0)))
        local spawn_effect = shot.spawn_effect or (shot.ex and shot.ex.flags == 2)
        animation = BulletAnimation.new(info.script, descriptor, color, spawn_effect, shot.spawn_effect_id)
        shot.legacy_bullet_animation = animation
    end
    local age = (shot.anim_frame or 0) - (shot.spawn_effect_age or 0) + (shot.spawn_animation_offset or 0)
    animation:advance_to(math.max(0, age))
    return animation
end

function Adapter:cancel_bullet(shot)
    -- Bullet::cancel applies one half-step, then freezes the bullet in ANM
    -- interrupt 1 until it ends (41e250). The caller decides whether to drop an item.
    shot.deleted = true
    local descriptor = BulletTypes[shot.sprite or shot.anim or 0]
    local animation = descriptor and self:bullet_animation(shot, descriptor)
    if not animation then return end
    self.cancel_visual_rng = self.cancel_visual_rng or ReferenceRng.new(151)
    if not animation:interrupt(1, self.cancel_visual_rng:range(-math.pi, math.pi)) then return end
    shot.x = shot.x + (shot.vx or 0) * 0.5
    shot.y = shot.y + (shot.vy or 0) * 0.5 * (shot.reflected and -1 or 1)
    shot.vx, shot.vy = 0, 0
    self.cancelled_shots[#self.cancelled_shots + 1] = shot
end

function Adapter:apply_enemy_function(enemy)
    -- Native callback table 4caf58: Ringo's velocity propagation, Clownpiece's
    -- moon cancellation, scrolling laser rows, and graze-based slowing.
    local kind=enemy.legacy_func or 0
    if kind==0 then return end
    local globals=enemy.legacy_globals or {}
    for _,shot in ipairs(self.shots or {}) do
        if not shot.player_bullet and not shot.deleted then
            if kind==1 and not shot.laser and shot.custom_mode==1 then
                for _,other in ipairs(self.shots) do
                    if not other.player_bullet and not other.laser and not other.deleted
                        and (other.custom_mode or 0)==0
                        and (other.x-shot.x)^2+(other.y-shot.y)^2<=400 then
                        other.custom_mode=2;other.vx,other.vy=shot.vx,shot.vy
                        other.speed,other.angle=shot.speed,shot.angle
                        other.transform_pc=9;other.transform_block=nil;other.transform_active={}
                    end
                end
            elseif kind==2 and not shot.laser and (shot.custom_mode or 0)==0 then
                if (shot.x-enemy.x)^2+(shot.y-enemy.y)^2<(globals.F0 or 0)^2 then
                    self:cancel_bullet(shot)
                end
            elseif kind==3 and shot.laser then
                shot.y=shot.y+(shot.laser_handle==0 and (globals.F0 or 0) or (globals.F1 or 0))
            elseif kind==4 and not shot.laser and shot.custom_mode==1 then
                local descriptor=BulletTypes[shot.sprite or 0]
                local radius=descriptor and descriptor.radius or 0
                local near=false
                for _,p in ipairs(self.players or {self.player}) do
                    local reach=math.max(40,radius/2.5)+(p.hitbox or 2)
                    if p.alive~=false and (shot.x-p.x)^2+(shot.y-p.y)^2<reach^2+radius^2 then near=true end
                end
                if near then
                    local factor=globals.F0 or 1
                    -- 4319ad..4319e9 scales the vector but leaves +0xc50
                    -- nominal speed unchanged for future transforms.
                    shot.vx=float32(float32(shot.vx)*float32(factor))
                    shot.vy=float32(float32(shot.vy)*float32(factor))
                end
            end
        end
    end
end

function Adapter:finish_enemy_step(enemy)
    if not enemy or enemy.legacy_deleted then return end
    enemy.legacy_last_update=self.frame
    if (enemy.hp or 0) > 0 then enemy.legacy_pending_interrupt = nil end
    -- 428984–428999 calls the enemy's callback after ECL, before bullet updates.
    self:apply_enemy_function(enemy)
    if self.on_enemy_step then self.on_enemy_step(enemy)
    else self:apply_pending_damage(enemy) end
end

function Adapter:enemy_has_left_field(enemy)
    -- 4277be..4278cc: once the main sprite has entered the playfield,
    -- leaving it removes the enemy before ECL and damage for that frame.
    -- The movement flags can suppress removal on either axis.
    local vm = enemy.legacy_anm_slots and enemy.legacy_anm_slots[0] or enemy.legacy_anm
    local rect = vm and vm:rect()
    if rect then
        enemy.legacy_half_width = math.abs(rect.w * (vm.scale_x or 1)) / 2
        enemy.legacy_half_height = math.abs(rect.h * (vm.scale_y or 1)) / 2
    end
    local w, h = enemy.legacy_half_width or 0, enemy.legacy_half_height or 0
    local x, y = enemy.x or 0, enemy.y or 0
    local outside_x = x + w < -192 or x - w > 192
    local outside_y = y + h < 0 or y - h > 448
    if not outside_x and not outside_y then enemy.legacy_entered_field = true end
    if not enemy.legacy_entered_field then return false end
    if outside_x then return not enemy.legacy_keep_x end
    return outside_y and not enemy.legacy_keep_y
end

function Adapter:advance_enemy_pose(enemy)
    local base=enemy.legacy_main_script
    if not base then return end
    -- 4275ee..42765b switches banks on horizontal motion changes. Scripts
    -- 3 and 4 finish the left and right movement poses and return to idle.
    local vx=enemy.legacy_final_vx or 0
    local direction=vx<-.03 and -1 or vx>.03 and 1 or 0
    local previous=enemy.legacy_pose
    if direction==previous then return end
    local offset
    if direction==0 then offset=previous==-1 and 3 or 4
    else offset=direction==-1 and 1 or 2 end
    local vm=self:animation(enemy.legacy_main_selection,base+offset)
    if vm then enemy.legacy_anm=vm;enemy.legacy_anm_slots[0]=vm end
    enemy.legacy_pose=direction
end

function Adapter:update()
    self.frame = (self.frame or 0) + 1
    -- Player::on_tick moves the homing shots before EnemyManager::on_tick
    -- advances the enemies. Their damage sources are checked afterwards.
    for _, shot in ipairs(self.shots) do
        if shot.player_bullet then self:advance_player_shot(shot) end
    end
    if self.on_player_shots_advanced then self.on_player_shots_advanced() end
    -- 42895a advances the current enemy's position before running its ECL.
    self.runtime:update_enemies(self.enemies,
        function(enemy)
            self:advance_enemy_movement(enemy)
            self:advance_enemy_pose(enemy)
            if self:enemy_has_left_field(enemy) then enemy.legacy_deleted = true end
        end,
        function(enemy) self:finish_enemy_step(enemy) end,
        function(enemy)
            if enemy.legacy_invulnerable_until and enemy.legacy_invulnerable_until >= self.frame then
                enemy.legacy_invulnerable_until = enemy.legacy_invulnerable_until + 1
            end
            if enemy.legacy_timer_start then enemy.legacy_timer_start = enemy.legacy_timer_start + 1 end
        end)
    self:advance_shots(true)
    self:advance_interrupts()
    -- Prune enemies removed by ECL, damage, or the field check.
    local kept = {}
    for _, enemy in ipairs(self.enemies) do
        local alive = not enemy.legacy_deleted and ((enemy.hp or 1) > 0 or enemy.legacy_pending_interrupt)
        if not alive and not enemy.legacy_delete_after_init then
            enemy.legacy_removed = true
            for _, thread in ipairs(self.runtime.threads) do
                if thread.object == enemy then thread.state = "finished" end
            end
            -- A boss leaving play clears the tracking so the next section waits
            -- for its own boss.
            if self.boss_object == enemy then
                self.boss_object = nil
                if self.boss_ui then self.boss_ui.visible=false end
                self:end_spell()
            end
        end
        if alive then
            if enemy.legacy_anm_slots then
                for _,vm in pairs(enemy.legacy_anm_slots) do
                    vm.source_object=enemy
                    vm:update()
                end
            elseif enemy.legacy_anm then
                enemy.legacy_anm.source_object=enemy
                enemy.legacy_anm:update()
            end
        end
        if alive or enemy.legacy_delete_after_init then kept[#kept + 1] = enemy end
    end
    self.enemies = kept
    local roots={}
    local function collect_roots(vm,x,y)
        if not vm then return end
        x=x+(vm.x or 0)+(vm.offset_x or 0);y=y+(vm.y or 0)+(vm.offset_y or 0)
        for _,root in ipairs(vm.pending_roots or {}) do
            root.origin_x,root.origin_y=x,y
            roots[#roots+1]=root
        end
        vm.pending_roots={}
        for _,child in ipairs(vm.children or {}) do collect_roots(child,x,y) end
    end
    for _,enemy in ipairs(kept) do
        for _,vm in pairs(enemy.legacy_anm_slots or {[0]=enemy.legacy_anm}) do collect_roots(vm,enemy.x or 0,enemy.y or 0) end
    end
    local animations={}
    for _,vm in ipairs(self.animations or {}) do
        vm:update()
        collect_roots(vm,vm.origin_x or 0,vm.origin_y or 0)
        if not vm.finished then animations[#animations+1]=vm end
    end
    for _,vm in ipairs(roots) do animations[#animations+1]=vm end
    self.animations=animations
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
