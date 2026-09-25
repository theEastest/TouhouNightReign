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
local function resolve(thread, token)
    local literal = parse_literal(token)
    if literal ~= nil then return literal end
    if type(token) ~= "string" then return 0 end
    local kind, name = token:match("^([$%%])([A-Za-z_][A-Za-z0-9_]*)$")
    if kind == "$" then
        return thread.ints[name] or 0
    elseif kind == "%" then
        return thread.floats[name] or 0
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

    -- Parenthesised comparison: (X == Y), (X >= Y), (X <= Y), (X != Y)
    local left, op, right = text:match("^%(?%s*(.-)%s*(==|~=|<|>|<=|>=)%s*(.-)%s*%)?$")
    if op then
        local lv, rv = resolve(thread, left), resolve(thread, right)
        if op == "==" then return lv == rv end
        if op == "~=" then return lv ~= rv end
        if op == "<" then return lv < rv end
        if op == ">" then return lv > rv end
        if op == "<=" then return lv <= rv end
        if op == ">=" then return lv >= rv end
    end

    -- Plain value: non-zero is true.
    return resolve(thread, text) ~= 0
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
    expression = expression:gsub("_f%((.-)%)", "%1")
    expression = expression:gsub("^%[(.*)%]$", "%1")
    -- Split on the lowest-precedence operator present.
    for _, ops in ipairs({ { "+", "-" }, { "*", "/" } }) do
        local depth = 0
        for index = #expression, 1, -1 do
            local ch = expression:sub(index, index)
            if ch == ")" then depth = depth + 1
            elseif ch == "(" then depth = depth - 1
            elseif depth == 0 and (ch == ops[1] or ch == ops[2]) and index > 1 then
                local head = expression:sub(1, index - 1)
                local tail = expression:sub(index + 1)
                local left = EclRuntime.evaluate_expression(thread, head)
                local right = EclRuntime.evaluate_expression(thread, tail)
                if ch == "+" then return left + right end
                if ch == "-" then return left - right end
                if ch == "*" then return left * right end
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
        local frames = math.floor(resolve(thread, (args or {})[1] or 0))
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
    local budget = STEPS_PER_FRAME
    while true do
        if thread.state == STATE_FINISHED then return false end
        if thread.wait > 0 then
            thread.wait = thread.wait - 1
            return true
        end
        if budget <= 0 then
            -- Yield to the next frame; the thread keeps its program counter.
            return true
        end
        budget = budget - 1
        local routine = runtime.chunks[thread.routine]
        if not routine then
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

        if op == "ins" then
            op_ins(thread, runtime, instruction[2], instruction[3])
            if thread.wait > 0 then return true end
        elseif op == "wait" then
            thread.wait = math.max(0, math.floor(resolve(thread, (instruction[2] or {})[1] or 0)))
            if thread.wait > 0 then return true end
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
        elseif op == "call" then
            runtime:call(thread, instruction[2], instruction[3])
        else
            runtime.unhandled = runtime.unhandled or {}
            runtime.unhandled[op] = (runtime.unhandled[op] or 0) + 1
        end
    end
end

EclRuntime.step = step

--- Create a thread for a routine.
function EclRuntime:spawn(routine_name, parent)
    local thread = {
        routine = routine_name,
        pc = 0,
        wait = 0,
        state = STATE_RUNNING,
        ints = {},
        floats = {},
        parent = parent,
    }
    -- ECL integer/float slots are shared per enemy in the reference; inherit
    -- the parent frame so a subroutine sees the caller's variables.
    if parent then
        thread.ints = parent.ints
        thread.floats = parent.floats
    end
    return thread
end

--- Non-blocking call: push a new thread for an async subroutine.
function EclRuntime:call(caller, routine_name, async)
    local thread = self:spawn(routine_name, caller)
    if async then
        self.threads[#self.threads + 1] = thread
        return thread
    end
    -- Synchronous call: run the callee to completion immediately, preserving
    -- ordering exactly like the reference call instruction.
    local guard = 0
    while thread.state ~= STATE_FINISHED and guard < 100000 do
        guard = guard + 1
        local before = thread.pc
        step(thread, self)
        if thread.pc == before and thread.state ~= STATE_FINISHED and thread.wait == 0 then
            -- No progress possible (e.g. a blocking wait inside a plain call).
            -- Hand the remainder to the scheduler so frames still advance.
            self.threads[#self.threads + 1] = thread
            return thread
        end
        if thread.wait > 0 then
            self.threads[#self.threads + 1] = thread
            return thread
        end
    end
    return thread
end

--- Advance every live thread by one frame.
function EclRuntime:update()
    local index = 1
    while index <= #self.threads do
        local thread = self.threads[index]
        step(thread, self)
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
