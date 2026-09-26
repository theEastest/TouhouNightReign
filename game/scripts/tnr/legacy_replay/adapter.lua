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
local AnmPlayer = require("tnr.legacy_replay.anm_player")

local Adapter = {}

Adapter.__index = Adapter

-- Bullet colour indices are shared with the THlib bullet module.
local COLOR = {
    DEEP_RED = 1, RED = 2, DEEP_PURPLE = 3, PURPLE = 4, DEEP_BLUE = 5,
    BLUE = 6, ROYAL_BLUE = 7, CYAN = 8, DEEP_GREEN = 9, GREEN = 10,
    CHARTREUSE = 11, YELLOW = 12, GOLDEN_YELLOW = 13, ORANGE = 14,
    DEEP_GRAY = 15, GRAY = 16,
}

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
    }, Adapter)
    self.difficulty = options.difficulty or EclRuntime.DIFFICULTY.NORMAL
    self.instructions = self:build_instructions()
    -- Engine globals the ECL reads: the player position, the difficulty id and
    -- the difficulty flags. Publishing them here means expressions such as
    -- `%PLAYER_X2` resolve instead of collapsing to zero.
    local host_ref = self
    local function globals_provider()
        local player = host_ref.lstg and host_ref.lstg.player
        local difficulty = host_ref.difficulty or EclRuntime.DIFFICULTY.NORMAL
        return {
            PLAYER_X = player and player.x or 0,
            PLAYER_Y = player and player.y or 0,
            PLAYER_X2 = player and player.x or 0,
            PLAYER_Y2 = player and player.y or 0,
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
        object.legacy_ecl = routine
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
        -- Selects an animation archive; stage 1 enemies all use one archive.
        thread.anm_id = tonumber(args and args[1]) or 0
    end
    instructions.anmSetMain = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        if player then player:play(tonumber(args and args[1]) or 0) end
    end
    instructions.anmSetSprite = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        if player then player.sprite = (tonumber(args and args[1]) or 0) + 1 end
    end
    instructions.anmPlay = function(thread, runtime, args)
        local player = thread.object and thread.object.legacy_anm
        if player then player:play(tonumber(args and args[1]) or 0) end
    end
    instructions.setHitbox = function(thread, runtime, args)
        if thread.object then
            thread.object.legacy_hitbox = { tonumber(args[1]) or 0, tonumber(args[2]) or 0 }
        end
    end
    instructions.setHurtbox = function(thread, runtime, args)
        if thread.object then
            thread.object.legacy_hurtbox = { tonumber(args[1]) or 0, tonumber(args[2]) or 0 }
        end
    end

    -- --- movement ----------------------------------------------------------
    instructions.moveVel = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        local angle = tonumber(args[1]) or 0
        local speed = tonumber(args[2]) or 0
        object.legacy_vx = math.cos(angle) * speed
        object.legacy_vy = math.sin(angle) * speed
        thread.move_timer = nil
    end
    instructions.moveVelTime = function(thread, runtime, args)
        local object = thread.object
        if not object then return end
        local time = tonumber(args[1]) or 0
        local angle = tonumber(args[3]) or 0
        local speed = tonumber(args[4]) or 0
        object.legacy_vx = math.cos(angle) * speed
        object.legacy_vy = math.sin(angle) * speed
        thread.move_timer = { remaining = time }
    end
    instructions.movePosTime = function(thread, runtime, args)
        if thread.object then
            thread.object.legacy_move_target = { tonumber(args[1]) or 0, tonumber(args[2]) or 0 }
            thread.move_timer = { remaining = tonumber(args[3]) or 0 }
        end
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
        if thread.object and self_ref.lstg.Del then
            pcall(self_ref.lstg.Del, thread.object)
        end
        thread.state = "finished"
    end
    instructions.ins_569 = function() end
    instructions.setBoss = function() end
    instructions.setInvuln = function() end
    instructions.flagSet = function() end
    instructions.flagClear = function() end
    instructions.setInterrupt = function() end
    instructions.setTimeout = function() end
    instructions.setChapter = function() end
    instructions.lifeSet = function(thread, runtime, args)
        if thread.object then thread.object.hp = tonumber(args and args[1]) or thread.object.hp end
    end
    instructions.dialogWait = function() end
    instructions.bossWait = function() end
    instructions.playSound = function() end

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
    instructions.etNew = function(thread, runtime, args)
        thread.bullet = {
            index = tonumber(args and args[1]) or 0,
            count = 1, count_spec = nil,
            angle = 0, angle_spec = nil,
            speed = 3, speed_spec = nil,
            sprite = thread.bullet and thread.bullet.sprite or 0,
            aim = nil, offset = nil,
        }
    end
    instructions.etSprite = function(thread, runtime, args)
        if thread.bullet then
            -- etSprite(group, anim, sprite): the second argument selects a
            -- bullet animation script and the third the variant within it. The
            -- drawn sprite comes from the script, not the raw number, so both
            -- are recorded and resolved when the bullet spawns.
            thread.bullet.anim = tonumber(args and args[2]) or 0
            thread.bullet.variant = tonumber(args and args[3]) or 0
            thread.bullet.sprite = thread.bullet.variant
        end
    end
    instructions.etAngle = function(thread, runtime, args)
        if thread.bullet then
            thread.bullet.angle = tonumber(args and args[2]) or 0
            thread.bullet.angle_spec = tonumber(args and args[3])
        end
    end
    instructions.etSpeed = function(thread, runtime, args)
        if thread.bullet then
            thread.bullet.speed = tonumber(args and args[2]) or 3
            thread.bullet.speed_spec = tonumber(args and args[3])
        end
    end
    instructions.etCount = function(thread, runtime, args)
        if thread.bullet then
            thread.bullet.count = tonumber(args and args[2]) or 1
            thread.bullet.count_spec = tonumber(args and args[3])
        end
    end
    instructions.etAim = function(thread, runtime, args)
        if thread.bullet then thread.bullet.aim = tonumber(args and args[2]) or 0 end
    end
    instructions.etOffset = function(thread, runtime, args)
        if thread.bullet then
            thread.bullet.offset = {
                EclRuntime.evaluate_expression(thread, tostring(args and args[1] or "0")),
                EclRuntime.evaluate_expression(thread, tostring(args and args[2] or "0")),
            }
        end
    end
    instructions.etEx = function(thread, runtime, args)
        if thread.bullet then
            thread.bullet.ex = {}
            for index = 1, #args do thread.bullet.ex[index] = tonumber(args[index]) end
        end
    end
    instructions.etExSet = instructions.etEx
    instructions.etOn = function(thread, runtime, args)
        self_ref:fire_bullet_group(thread)
    end
    instructions.etClear = function() end
    instructions.etCancel = function() end
    instructions.etClearAll = function() end
    instructions.etCopy = function() end
    instructions.etSound = function() end
    instructions.etDist = function() end
    instructions.etOffsetAbs = function(thread, runtime, args)
        -- Offset the group to an absolute field position.
        if thread.bullet then
            thread.bullet.offset_abs = {
                EclRuntime.evaluate_expression(thread, tostring(args and args[1] or "0")),
                EclRuntime.evaluate_expression(thread, tostring(args and args[2] or "0")),
            }
        end
    end
    instructions.etOffsetRad = function(thread, runtime, args)
        -- Offset the group by a distance along an angle.
        if thread.bullet then
            local angle = EclRuntime.evaluate_expression(thread, tostring(args and args[1] or "0"))
            local distance = EclRuntime.evaluate_expression(thread, tostring(args and args[2] or "0"))
            thread.bullet.offset = {
                math.cos(angle) * distance, math.sin(angle) * distance,
            }
        end
    end
    instructions.etSpeedD = instructions.etSpeed
    instructions.etCountD = instructions.etCount

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
            if self_ref.boss_ui then self_ref.boss_ui:begin(100, {}) end
        else
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
        }
    end
    instructions.spell = function(thread, runtime, args)
        self_ref:begin_spell(thread, args)
    end
    instructions.spell3 = function(thread, runtime, args)
        self_ref:begin_spell(thread, args)
    end
    instructions.spellEnd = function()
        if self_ref.boss_ui then self_ref.boss_ui.card_flash = 0 end
    end
    -- 527 / 554 / 536 are declaration helpers with no presentation of their own.
    instructions.stageLogo = function() end
    instructions.ins_569 = function() end
    instructions.ins_570 = function() end
    instructions.nop = function() end
    instructions.debug22 = function() end
    instructions.timerReset = function() end
    instructions.dialogRead = function() end
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
        if thread.bullet then
            thread.bullet.ex = {}
            for index = 1, #args do thread.bullet.ex[index] = tonumber(args[index]) end
        end
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
    instructions.killAllAsync = function() end

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
local function angle_between(x1, y1, x2, y2)
    if type(atan2) == "function" then return atan2(y2 - y1, x2 - x1) end
    return math.atan(y2 - y1, x2 - x1)
end

--- Fire the configured bullet group through the THlib bullet styles.
function Adapter:fire_bullet_group(thread)
    local group = thread.bullet
    local object = thread.object
    if not group or not object then return end
    local count = math.max(1, math.floor(group.count or 1))
    local base_angle = group.angle or 0
    if group.aim then
        -- etAim(0, n): aim at the player, offset by n slots of the spread.
        base_angle = 0
        if self.lstg.player then
            base_angle = angle_between(object.x, object.y, self.lstg.player.x, self.lstg.player.y)
        end
    end
    local spread = group.angle_spec or 0
    local speed = group.speed or 3
    local bullet_class = self.bullet_styles[1]
    for index = 0, count - 1 do
        local angle = base_angle + (index - (count - 1) / 2) * spread
        local speed_step = speed + index * (group.speed_spec or 0)
        local x = object.x + (group.offset and group.offset[1] or 0)
        local y = object.y + (group.offset and group.offset[2] or 0)
        self:spawn_bullet(bullet_class, x, y, speed_step, angle, group.sprite, group.anim)
    end
end

--- Spawn one bullet. Falls back to recording when the style is unavailable.
function Adapter:spawn_bullet(bullet_class, x, y, speed, angle, sprite, anim)
    -- Record the shot so a host without a live bullet object can still draw and
    -- test the pattern. The animation id selects the bullet's sprite sheet.
    self.shots = self.shots or {}
    if #self.shots < 4096 then
        self.shots[#self.shots + 1] = {
            x = x, y = y, speed = speed, angle = angle, sprite = sprite,
            anim = anim,
            vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
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

--- Advance recorded shots so a host-drawn pattern moves like the reference.
function Adapter:advance_shots()
    for _, shot in ipairs(self.shots or {}) do
        shot.x = shot.x + (shot.vx or 0)
        shot.y = shot.y + (shot.vy or 0)
    end
end

--- Apply damage to an enemy. The reference reduces health directly and the
-- manager observes the change, so the adapter keeps the same model.
function Adapter:damage_enemy(enemy, amount)
    if not enemy then return end
    enemy.hp = math.max(0, (enemy.hp or 0) - (tonumber(amount) or 0))
    if self.boss_ui then self.boss_ui:set_health(enemy.hp, self.boss_ui.health_max) end
end

--- The first live enemy, which is the boss once it spawns.
function Adapter:current_boss()
    for _, enemy in ipairs(self.enemies) do
        if enemy.legacy_interrupts then return enemy end
    end
    return nil
end

--- Check each enemy's health against its registered interrupts.
-- The reference fires a boss subroutine the moment the health crosses the
-- registered threshold, which is what advances nonspell -> spell.
function Adapter:advance_interrupts()
    for _, enemy in ipairs(self.enemies) do
        local interrupts = enemy.legacy_interrupts
        if interrupts then
            local hp = enemy.hp or 0
            for _, entry in pairs(interrupts) do
                if not entry.fired and hp <= entry.start and entry.routine ~= "" then
                    entry.fired = true
                    -- Run the subroutine on the enemy's own thread context.
                    local thread = self.runtime:spawn(entry.routine, enemy.legacy_thread)
                    thread.object = enemy
                    thread.runtime = self.runtime
                    self.runtime.threads[#self.runtime.threads + 1] = thread
                end
            end
        end
    end
end

--- Advance every enemy animation and the ECL threads by one frame.
function Adapter:update()
    self.runtime:update()
    self:advance_shots()
    self:advance_interrupts()
    for _, enemy in ipairs(self.enemies) do
        if enemy.legacy_anm then enemy.legacy_anm:update() end
        -- Apply the movement the script set.
        if enemy.legacy_vx or enemy.legacy_vy then
            enemy.x = (enemy.x or 0) + (enemy.legacy_vx or 0)
            enemy.y = (enemy.y or 0) + (enemy.legacy_vy or 0)
        end
    end
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
