-- ECL interpreter runtime (proof of concept).
--
-- The reference Touhou games drive enemies with compiled ECL bytecode. This
-- module executes the lowered `.decl` form (see tools/compile_ecl.py) so the
-- imported stage scripts can run on the LuaSTG Sub object model.
--
-- The interpreter is deliberately small and data driven: every executable
-- instruction is one closure in OPCODES, so adding an instruction never touches
-- the run loop.
--
-- Threads
--   A routine call creates a thread with its own program counter, wait timer
--   and variable frame. Async calls (@Name() async) spawn an independent
--   thread; a plain call blocks the caller until the callee returns.

local EclRuntime = {}

EclRuntime.__index = EclRuntime

-- Difficulty ids match the reference ordering used by the branch markers.
EclRuntime.DIFFICULTY = { EASY = 0, NORMAL = 1, HARD = 2, LUNATIC = 3, OVERDRIVE = 4 }
EclRuntime.DIFFICULTY_BRANCH = {
    E = "EASY", N = "NORMAL", H = "HARD", L = "LUNATIC", O = "OVERDRIVE",
}

-- Interpreter states.
local STATE_RUNNING = "running"
local STATE_WAITING = "waiting"
local STATE_FINISHED = "finished"

--- Build a label -> instruction index map for a routine, cached on the runtime.
local function label_table(runtime, routine_name)
    runtime.label_cache = runtime.label_cache or {}
    local cached = runtime.label_cache[routine_name]
    if cached then return cached end
    local map = {}
    local routine = runtime.chunks[routine_name]
    if routine then
        for index, instruction in ipairs(routine) do
            if instruction[1] == "label" then
                map[instruction[2]] = index - 1
            end
        end
    end
    runtime.label_cache[routine_name] = map
    return map
end

EclRuntime.label_table = label_table

---@param chunks table compiled routines: name -> instruction list
---@param host table object factory / effect callbacks supplied by the adapter
function EclRuntime.new(chunks, host)
    return setmetatable({
        chunks = chunks or {},
        host = host or {},
        threads = {},
    }, EclRuntime)
end

--- Parse a lowered operand into a number.
-- Numeric literals arrive as strings such as "12" or "1.5f"; variables arrive
-- as "$A" (integer frame), "%A" (float frame) or "@Name" (routine reference).
local function parse_literal(token)
    if type(token) == "number" then return token end
    if type(token) ~= "string" then return nil end
    local value = token:match("^%-?%d+%.?%d*[fF]?$")
    if value then
        return tonumber((token:gsub("[fF]$", "")))
    end
    return nil
end

--- Resolve an operand against the thread's variable frames.
-- Defaults for engine globals the host does not override. DIFF matches the
-- active difficulty (0 easy .. 3 lunatic); the difficulty flag slots are 1 for
-- the active mode and 0 otherwise, exactly like the reference.
local GLOBAL_DEFAULT = {
    DIFF = 1,
    EASY = 0, NORMAL = 1, HARD = 0, LUNATIC = 0,
    RANK = 32,
    TIME = 0,
    TIMEOUT = 0,
    CAPTURE = 1,
    -- A normal full-stage run has no single spell selected, so SPELL_ID stays
    -- negative and the boss plays its complete sequence.
    SPELL_ID = -1,
    LIFE = 3,
    BOMB_COUNT = 3,
    MISS_COUNT = 0,
    POWER = 0,
    TRUE = 1,
}

EclRuntime.GLOBAL_DEFAULT = GLOBAL_DEFAULT

local function resolve(thread, token)
    -- A per-difficulty branch list: pick the entry for the active difficulty.
    if type(token) == "table" then
        local difficulty = (thread.runtime and thread.runtime.difficulty)
            or (thread.host and thread.host.difficulty) or 1
        local index = math.max(1, math.min(#token, difficulty + 1))
        return resolve(thread, token[index])
    end
    local literal = parse_literal(token)
    if literal ~= nil then return literal end
    if type(token) ~= "string" then return 0 end
    local kind, name = token:match("^([$%%])([A-Za-z_][A-Za-z0-9_]*)$")
    local object = thread.object
    if name and object then
        local globals = object.legacy_globals or {}
        if globals[name] ~= nil then return globals[name] end
        if name=="ABS_X" or name=="FINAL_X" or name=="ABS_X2" or name=="FINAL_X2" then return object.x or 0 end
        if name=="ABS_Y" or name=="FINAL_Y" or name=="ABS_Y2" or name=="FINAL_Y2" then return object.y or 0 end
        if name=="ABS_ANGLE" then return object.legacy_angle or 0 end
        if name=="ABS_SPEED" then return object.legacy_speed or 0 end
        if name=="TIME" then return (thread.runtime.frame or 0)-(object.legacy_timer_start or 0) end
    end
    if kind == "$" then
        local value = thread.ints[name]
        if value ~= nil then return value end
        -- Engine globals are supplied by the host when available.
        local runtime = thread.runtime
        if runtime and runtime.host and runtime.host.globals then
            local provided = runtime.host.globals[name]
            if provided ~= nil then return provided end
        end
        return GLOBAL_DEFAULT[name] or 0
    elseif kind == "%" then
        local value = thread.floats[name]
        if value ~= nil then return value end
        local runtime = thread.runtime
        if runtime and runtime.host and runtime.host.globals then
            local provided = runtime.host.globals[name]
            if provided ~= nil then return provided end
        end
        return 0
    end
    -- Unresolved names fall back to zero, matching an uninitialised ECL slot.
    return 0
end

EclRuntime.resolve = resolve

--- Evaluate a condition string such as "1", "$A--" or "($DIFF == 3)".
-- Returns the boolean result, applying any side effect (the `--` decrement).
local function evaluate_condition(thread, text)
    text = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false end

    -- `$A--` decrements and tests for non-zero (post-decrement semantics).
    local kind, name = text:match("^([$%%])([A-Za-z_][A-Za-z0-9_]*)%-%-$")
    if kind then
        local frame = thread.ints
        local value = frame[name] or 0
        frame[name] = value - 1
        return value ~= 0
    end

    -- Lua patterns do not support regex alternation. Split operators only at
    -- depth zero, then recursively evaluate grouped boolean expressions.
    local depth, outer = 0, text:sub(1,1) == "("
    for i=1,#text do
        local c=text:sub(i,i)
        if c=="(" then depth=depth+1 elseif c==")" then depth=depth-1 end
        if depth==0 and i<#text then outer=false end
    end
    if outer then return evaluate_condition(thread,text:sub(2,-2)) end
    for _, op in ipairs({"||", "&&", "==", "!=", "<=", ">=", "<", ">"}) do
        depth=0
        for i=1,#text do
            local c=text:sub(i,i)
            if c=="(" then depth=depth+1 elseif c==")" then depth=depth-1 end
            if depth==0 and text:sub(i,i+#op-1)==op then
                local left,right=text:sub(1,i-1),text:sub(i+#op)
                if op=="||" then return evaluate_condition(thread,left) or evaluate_condition(thread,right) end
                if op=="&&" then return evaluate_condition(thread,left) and evaluate_condition(thread,right) end
                local lv,rv=EclRuntime.evaluate_expression(thread,left),EclRuntime.evaluate_expression(thread,right)
                if op=="==" then return lv==rv elseif op=="!=" then return lv~=rv
                elseif op=="<=" then return lv<=rv elseif op==">=" then return lv>=rv
                elseif op=="<" then return lv<rv else return lv>rv end
            end
        end
    end

    -- Plain value: non-zero is true.
    return EclRuntime.evaluate_expression(thread, text) ~= 0
end

EclRuntime.evaluate_condition = evaluate_condition

--- Evaluate an assignment target and expression.
local function apply_assignment(thread, target, operator, expression)
    local kind, name = target:match("^([$%%])([A-Za-z_][A-Za-z0-9_]*)$")
    -- Subscripted targets such as $A[0] are kept for later; treat as the base
    -- name so the common case keeps working.
    if not kind then
        kind, name = target:match("^([$%%])([A-Za-z_][A-Za-z0-9_]*)%[")
    end
    local value = EclRuntime.evaluate_expression(thread, expression)
    if name and thread.object and EclRuntime.GLOBAL_VALUES and EclRuntime.GLOBAL_VALUES[name] then
        local globals = thread.object.legacy_globals or {}
        thread.object.legacy_globals = globals
        local current = resolve(thread, target)
        if operator=="+=" then value=current+value elseif operator=="-=" then value=current-value end
        globals[name] = kind=="$" and math.floor(value) or value
        return
    end
    if kind == "$" then
        local current = thread.ints[name] or 0
        if operator == "+=" then value = current + value
        elseif operator == "-=" then value = current - value end
        thread.ints[name] = math.floor(value)
    elseif kind == "%" then
        local current = thread.floats[name] or 0
        if operator == "+=" then value = current + value
        elseif operator == "-=" then value = current - value end
        thread.floats[name] = value
    end
end

--- Evaluate a simple arithmetic expression (+, -, *) over literals/variables.
function EclRuntime.evaluate_expression(thread, expression)
    expression = tostring(expression):gsub("^%s+", ""):gsub("%s+$", "")
    -- Handle helper wrappers such as _f(-192) and [-1.0f] operand brackets.
    expression = expression:gsub("_f%(", "(")
    expression = expression:gsub("^%[(.*)%]$", "%1")
    -- Split on the lowest-precedence operator present.
    for _, ops in ipairs({ { "+", "-" }, { "*", "/", "%" } }) do
        local depth = 0
        for index = #expression, 1, -1 do
            local ch = expression:sub(index, index)
            if ch == ")" then depth = depth + 1
            elseif ch == "(" then depth = depth - 1
            elseif depth == 0 and (ch == ops[1] or ch == ops[2] or ch == ops[3]) and index > 1
                and not (ch == "%" and expression:sub(index+1,index+1):match("[%a_]")) then
                local head = expression:sub(1, index - 1)
                local tail = expression:sub(index + 1)
                local left = EclRuntime.evaluate_expression(thread, head)
                local right = EclRuntime.evaluate_expression(thread, tail)
                if ch == "+" then return left + right end
                if ch == "-" then return left - right end
                if ch == "*" then return left * right end
                if ch == "%" then return right == 0 and 0 or left % right end
                if ch == "/" then
                    if right == 0 then return 0 end
                    return left / right
                end
            end
        end
    end
    -- Strip one layer of parentheses.
    local inner = expression:match("^%((.*)%)$")
    if inner then return EclRuntime.evaluate_expression(thread, inner) end
    if expression:sub(1,1)=="-" then return -EclRuntime.evaluate_expression(thread,expression:sub(2)) end
    return resolve(thread, expression)
end

-- ---------------------------------------------------------------------------
-- Opcode table.

local OPCODES = {}

--- Dispatch a plain instruction call.
local function op_ins(thread, runtime, name, args)
    -- `wait` (and its float form `waitf`) block the thread. The compiler lowers
    -- the source `wait(n)` call to a plain instruction, so the scheduler must
    -- recognise it here; otherwise a routine that loops back on itself spins
    -- forever inside one step.
    if name == "wait" or name == "waitf" then
        local operand = (args or {})[1] or 0
        local frames = math.floor(type(operand)=="table" and resolve(thread,operand)
            or EclRuntime.evaluate_expression(thread,tostring(operand)))
        thread.wait = math.max(0, frames)
        return true
    end
    local handler = runtime.host.instructions and runtime.host.instructions[name]
    if handler then
        handler(thread, runtime, args)
    else
        -- Unknown instructions are recorded so the audit can list what stage
        -- content still needs an implementation.
        runtime.unhandled = runtime.unhandled or {}
        runtime.unhandled[name] = (runtime.unhandled[name] or 0) + 1
    end
    return true
end

--- One interpreter step. Returns true when the thread advanced.
-- A budget caps how many instructions one frame may execute. A script that
-- loops back without waiting would otherwise hang the engine inside this call;
-- the budget turns that into a resumable state instead.
local STEPS_PER_FRAME = 4096
local function step(thread, runtime)
    if thread.last_step_frame == runtime.frame and runtime.frame ~= nil then return false end
    thread.last_step_frame = runtime.frame
    local budget = STEPS_PER_FRAME
    while true do
        if thread.state == STATE_FINISHED then return false end
        if thread.wait > 0 then
            thread.wait = thread.wait - 1
            if thread.wait > 0 then return true end
        end
        -- Fire any deferred async calls whose delay has elapsed.
        if thread.deferred then
            local pending = {}
            for _, entry in ipairs(thread.deferred) do
                entry.remaining = entry.remaining - 1
                if entry.remaining <= 0 then
                    runtime:call(thread, entry.routine, true)
                else
                    pending[#pending + 1] = entry
                end
            end
            thread.deferred = pending
        end
        if budget <= 0 then
            -- Yield to the next frame; the thread keeps its program counter.
            return true
        end
        budget = budget - 1
        local routine = runtime.chunks[thread.routine]
        if not routine then
            runtime.unhandled = runtime.unhandled or {}
            local key = "missing_routine:" .. thread.routine
            runtime.unhandled[key] = (runtime.unhandled[key] or 0) + 1
            thread.state = STATE_FINISHED
            return false
        end
        local instruction = routine[thread.pc + 1]
        if not instruction then
            thread.state = STATE_FINISHED
            return false
        end
        thread.pc = thread.pc + 1
        local op = instruction[1]

        local difficulty_key = ({"E","N","H","L","O"})[(runtime.difficulty or 1)+1]
        if thread.diff_branch and op~="diff" and op~="diff_end"
            and not thread.diff_branch:find(difficulty_key,1,true) then
            -- Instructions can be difficulty-masked, not just stack values.
        elseif op == "ins" then
            op_ins(thread, runtime, instruction[2], instruction[3])
            if thread.wait > 0 then return true end
        elseif op == "wait" then
            thread.wait = math.max(0, math.floor(resolve(thread, (instruction[2] or {})[1] or 0)))
            if thread.wait > 0 then return true end
        elseif op == "params" then
            for index, name in ipairs(instruction[2] or {}) do
                local value = (thread.arguments or {})[index] or 0
                thread.ints[name] = value
                thread.floats[name] = value
            end
        elseif op == "label" or op == "var" or op == "value" or op == "raw" then
            -- No runtime effect.
        elseif op == "diff" then
            -- Enter a difficulty branch: remember the branch key so a `value`
            -- instruction inside it only applies to the active difficulty.
            thread.diff_branch = instruction[2]
        elseif op == "diff_end" then
            thread.diff_branch = nil
        elseif op == "goto" then
            local labels = label_table(runtime, thread.routine)
            thread.pc = labels[instruction[2]] or thread.pc
        elseif op == "goto_if" then
            local condition = evaluate_condition(thread, instruction[3])
            if instruction[2] == "unless" then condition = not condition end
            if condition then
                local labels = label_table(runtime, thread.routine)
                thread.pc = labels[instruction[4]] or thread.pc
            end
        elseif op == "assign" then
            apply_assignment(thread, instruction[2], instruction[3], instruction[4])
        elseif op == "call_after" then
            -- Deferred async call: wait N frames, then start the routine.
            local delay = math.max(0, math.floor(tonumber(instruction[3]) or 0))
            if delay > 0 then
                thread.deferred = thread.deferred or {}
                thread.deferred[#thread.deferred + 1] = {
                    remaining = delay,
                    routine = instruction[2],
                    args = instruction[4],
                }
            else
                runtime:call(thread, instruction[2], true)
            end
        elseif op == "label_offset" then
            thread.wait = math.max(0, tonumber(instruction[2]) or 0)
            if thread.wait > 0 then return true end
        elseif op == "ret" then
            -- Routine return: the thread ends here.
            thread.state = STATE_FINISHED
            return false
        elseif op == "call" then
            runtime:call(thread, instruction[2], instruction[3], instruction[4])
            -- A synchronous call parks the caller. Stop stepping it now; the
            -- scheduler resumes it once the callee has returned.
            if thread.pending_call then return true end
        else
            runtime.unhandled = runtime.unhandled or {}
            runtime.unhandled[op] = (runtime.unhandled[op] or 0) + 1
        end
    end
end

EclRuntime.step = step

--- Resolve a routine name against the compiled catalog.
-- Compiled entries are namespaced by source stage (for example
-- "st01.MainSub00") because every stage defines routines with the same bare
-- names. A call inside "st01.X" that names "MainSub00" must therefore resolve
-- to "st01.MainSub00" first.
function EclRuntime:resolve_routine(name, caller)
    if name:find("%.") and self.chunks[name] then return name end
    local namespace = caller and caller.routine and caller.routine:match("^([^%.]+)%.")
    if namespace then
        local qualified = namespace .. "." .. name
        if self.chunks[qualified] then return qualified end
        local stage = namespace:match("^(st%d%d)")
        local imports = self.chunks.__imports or {}
        for _, module in ipairs(imports[namespace] or imports[stage] or {}) do
            qualified = module .. "." .. name
            if self.chunks[qualified] then return qualified end
        end
        -- Never borrow a same-named routine from an unrelated stage.
        return namespace .. "." .. name
    end
    if self.chunks[name] then return name end
    -- Fall back to any namespace that defines the bare name. Stage-local
    -- routines are usually called from within the same stage, but an enemy can
    -- also be created by a shared helper, where no caller context exists.
    local suffix = "." .. name
    for candidate in pairs(self.chunks) do
        if candidate:sub(-#suffix) == suffix then return candidate end
    end
    return name
end

--- Build the table of engine provided global ECL variables.
-- The reference exposes read-only values such as the player position, the
-- difficulty id and the spell id under negative slot numbers. They are
-- addressed through the same `$NAME` syntax as ordinary slots.
local GLOBAL_VALUES = {
    RAND = -10000, RANDF = -9999, RANDRAD = -9998,
    FINAL_X = -9997, FINAL_Y = -9996, ABS_X = -9995, ABS_Y = -9994,
    REL_X = -9993, REL_Y = -9992, PLAYER_X = -9991, PLAYER_Y = -9990,
    ANGLE_PLAYER = -9989, TIME = -9988, RANDF2 = -9987, TIMEOUT = -9986,
    I0 = -9985, I1 = -9984, I2 = -9983, I3 = -9982,
    F0 = -9981, F1 = -9980, F2 = -9979, F3 = -9978,
    FINAL_X2 = -9977, FINAL_Y2 = -9976, ABS_X2 = -9975, ABS_Y2 = -9974,
    REL_X2 = -9973, REL_Y2 = -9972,
    PLAYER_X2 = -9965, PLAYER_Y2 = -9964,
    ABS_ANGLE_PLAYER = -9956, REL_ANGLE_PLAYER = -9955,
    ABS_ANGLE = -9971, REL_ANGLE = -9970, ABS_SPEED = -9969, REL_SPEED = -9968,
    BOSS_X = -9963, BOSS_Y = -9962, ANM_ID = -9961, RANK = -9960, DIFF = -9959,
    TRUE = -9957, LIFE = -9954, EASY = -9953, NORMAL = -9952,
    HARD = -9951, LUNATIC = -9950, MISS_COUNT = -9949, BOMB_COUNT = -9948,
    CAPTURE = -9947, ENM_CNT_REAL = -9946, SHOTTYPE = -9945, DIST_PLAYER = -9944,
    POWER = -9930, LAST_ENM_ID = -9931,
    -- th15 extra mode exposes SPELL_ID for the spell selection branch.
    SPELL_ID = -9907,
}

EclRuntime.GLOBAL_VALUES = GLOBAL_VALUES


--- Create a thread for a routine.
function EclRuntime:spawn(routine_name, parent)
    local thread = {
        routine = self:resolve_routine(routine_name, parent),
        pc = 0,
        wait = 0,
        state = STATE_RUNNING,
        ints = {},
        floats = {},
        parent = parent,
        -- The active runtime is kept on the thread so operand resolution can
        -- consult the difficulty without threading it through every call.
        runtime = self,
    }
    -- ECL integer/float slots are shared per enemy in the reference; inherit
    -- the parent frame so a subroutine sees the caller's variables.
    if parent then
        thread.ints = parent.ints
        thread.floats = parent.floats
        -- Subroutines act on the same enemy object as their caller, so the
        -- child thread inherits it. Without this an async attack routine has no
        -- object to spawn bullets from.
        thread.object = parent.object
    end
    return thread
end

--- Non-blocking call: push a new thread for an async subroutine.
function EclRuntime:call(caller, routine_name, async, operands)
    local thread = self:spawn(routine_name, caller)
    thread.async = async == true
    thread.arguments = {}
    for index, operand in ipairs(operands or {}) do
        thread.arguments[index] = type(operand)=="table" and resolve(caller,operand)
            or EclRuntime.evaluate_expression(caller, tostring(operand))
    end
    -- Local arguments and temporaries belong to the invocation. Concurrent
    -- attack routines must not overwrite the movement routine's locals.
    thread.ints, thread.floats = {}, {}
    if async then
        self.threads[#self.threads + 1] = thread
        return thread
    end
    -- A synchronous call suspends the caller until the callee finishes, even
    -- when the callee waits. Running the callee only until its first wait and
    -- then resuming the caller is not the same thing: an enemy that starts a
    -- shared behaviour and then deletes itself would delete on the spot, which
    -- is why a wave vanished before it flew anywhere. Park the caller on the
    -- callee so it resumes only once the callee has actually returned.
    caller.pending_call = thread
    local guard = 0
    while thread.state ~= STATE_FINISHED and guard < 100000 do
        guard = guard + 1
        local before = thread.pc
        step(thread, self)
        if thread.wait > 0 then break end
        if thread.pc == before and thread.state ~= STATE_FINISHED then break end
    end
    -- The callee still has work to do, so it joins the scheduler and the caller
    -- stays parked behind it.
    if thread.state ~= STATE_FINISHED then
        self.threads[#self.threads + 1] = thread
    else
        caller.pending_call = nil
    end
    return thread
end

--- Advance every live thread by one frame.
function EclRuntime:update()
    self.frame = (self.frame or 0) + 1
    local index = 1
    while index <= #self.threads do
        local thread = self.threads[index]
        local pending = thread.pending_call
        local waiting = false
        if pending then
            if pending.state == STATE_FINISHED then
                -- The callee returned, so the caller may run again.
                thread.pending_call = nil
            else
                -- A caller parked behind a synchronous call does not advance
                -- until the callee it is waiting on has finished.
                waiting = true
            end
        end
        if not waiting then
            step(thread, self)
        end
        if thread.state == STATE_FINISHED then
            table.remove(self.threads, index)
        else
            index = index + 1
        end
    end
end

function EclRuntime:live_count()
    return #self.threads
end

return EclRuntime
