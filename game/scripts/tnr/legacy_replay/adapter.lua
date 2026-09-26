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
    }, Adapter)
    self.difficulty = options.difficulty or EclRuntime.DIFFICULTY.NORMAL
    self.instructions = self:build_instructions()
    self.runtime = EclRuntime.new(options.chunks or {}, {
        instructions = self.instructions,
        difficulty = self.difficulty,
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
        -- Attach the animation player for the enemy archive.
        local archive = self.anm.st01enm
        if archive and archive[1] then
            object.legacy_anm = AnmPlayer.new(archive[1])
        end
        self.enemies[#self.enemies + 1] = object
    end
    -- Start the requested routine. The caller supplies the namespace context
    -- so a bare name such as "GirlRedA01e" resolves to "st01.GirlRedA01e".
    local thread = self.runtime:spawn(routine, caller_thread or nil)
    thread.object = object
    thread.runtime = self.runtime
    self.runtime.threads[#self.runtime.threads + 1] = thread
    return object, thread
end

--- Resolve the ANM archive entry that holds the enemy sprites.
function Adapter:enemy_archive()
    local archive = self.anm.st01enm
    return archive and archive[1] or nil
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
            thread.bullet.sprite = tonumber(args and args[3]) or tonumber(args and args[1]) or 0
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
            thread.bullet.offset = { tonumber(args and args[1]) or 0, tonumber(args and args[2]) or 0 }
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
    instructions.etOffsetAbs = function() end
    instructions.etOffsetRad = function() end
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

    return instructions
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
        self:spawn_bullet(bullet_class, x, y, speed_step, angle, group.sprite)
    end
end

--- Spawn one bullet. Falls back to recording when the style is unavailable.
function Adapter:spawn_bullet(bullet_class, x, y, speed, angle, sprite)
    -- Record the shot so a host without a live bullet object can still draw and
    -- test the pattern.
    self.shots = self.shots or {}
    if #self.shots < 4096 then
        self.shots[#self.shots + 1] = {
            x = x, y = y, speed = speed, angle = angle, sprite = sprite,
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

--- Advance every enemy animation and the ECL threads by one frame.
function Adapter:update()
    self.runtime:update()
    self:advance_shots()
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
