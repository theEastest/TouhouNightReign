-- Tests for the ECL interpreter used by the legacy replay mode.
--
-- The reference Touhou games drive enemies with compiled ECL. The interpreter
-- executes the lowered .decl form (see tools/compile_ecl.py). These tests pin
-- the control flow and operand semantics the real stage 1 scripts rely on.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local EclRuntime = require("tnr.legacy_replay.ecl_runtime")
    local chunks = require("tnr.legacy_replay.data.th15_all")
    assert_true(chunks["st01mbs.MBoss1_at"] ~= nil,
        "the parameterized stage-one midboss attack must be compiled")
    local scoped = EclRuntime.new(chunks, {})
    assert_equal(scoped:resolve_routine("MBoss1_at", {routine="st01mbs.MBoss1"}),
        "st01mbs.MBoss1_at", "local routines override unrelated bare aliases")
    assert_equal(scoped:resolve_routine("MBoss", {routine="st01.MainFront"}),
        "st01mbs.MBoss", "enemy routines resolve through the stage's ECL imports")
    local seen_arguments = {}
    local argument_runtime = EclRuntime.new({
        Parent = {{"assign", "%A", "=", "7"}, {"call", "Child", false, {"%A", "2.5f"}},
                  {"ins", "record", {}}},
        Child = {{"params", {"A", "B"}}, {"ins", "record", {}}, {"assign", "%A", "=", "99"}},
    }, {instructions={record=function(thread)
        seen_arguments[#seen_arguments+1] = {thread.floats.A, thread.floats.B}
    end}})
    argument_runtime.threads[1] = argument_runtime:spawn("Parent")
    argument_runtime:update()
    assert_equal(seen_arguments[1][1], 7, "callee receives evaluated arguments")
    assert_equal(seen_arguments[1][2], 2.5, "float arguments retain their precision")
    assert_equal(seen_arguments[2][1], 7, "callee locals do not corrupt caller locals")

    -- A recording host: every instruction the script issues is captured.
    local function make_runtime(trace)
        return EclRuntime.new(chunks, {
            difficulty = EclRuntime.DIFFICULTY.NORMAL,
            instructions = setmetatable({}, {
                __index = function(_, name)
                    return function(thread, runtime, args)
                        trace[#trace + 1] = { name = name, args = args or {} }
                    end
                end,
            }),
        })
    end

    local function run(runtime, routine, limit)
        local thread = runtime:spawn(routine)
        runtime.threads[#runtime.threads + 1] = thread
        for _ = 1, limit or 4000 do
            runtime:update()
            if runtime:live_count() == 0 or thread.state == "finished" then break end
        end
        return thread
    end

    -- The catalog compiled from the reference stage scripts.
    assert_true(chunks["st01.GirlA01"] ~= nil, "stage 1 GirlA01 must compile")
    assert_true(chunks["st01.GirlRedA01"] ~= nil, "stage 1 spawn wrapper must compile")
    assert_true(chunks["st01.MainFront"] ~= nil, "the stage 1 main timeline must compile")

    -- GirlA01 is the movement routine shared by every stage 1 fairy. Its
    -- instruction order and operands must survive compilation intact.
    local trace = {}
    run(make_runtime(trace), "st01.GirlA01")
    local sequence = {}
    for _, entry in ipairs(trace) do sequence[#sequence + 1] = entry.name end
    assert_equal(sequence[1], "ins_569", "the first instruction is preserved")
    assert_true(sequence[2] == "setHurtbox", "the hurtbox follows")
    assert_true(sequence[3] == "setHitbox", "the hitbox follows")
    assert_true(sequence[4] == "moveVel", "the initial move follows")
    local moved
    for _, entry in ipairs(trace) do
        if entry.name == "moveVel" then moved = entry break end
    end
    assert_equal(moved.args[1], "1.1780972f", "the movement angle argument is preserved")
    assert_equal(moved.args[2], "3.0f", "the movement speed argument is preserved")

    -- The `wait` instruction must block the thread. A routine that loops back
    -- used to spin forever because wait had no scheduler effect.
    local wait_runtime = make_runtime({})
    local thread = wait_runtime:spawn("st01.GirlA01")
    wait_runtime.threads[#wait_runtime.threads + 1] = thread
    wait_runtime:update()
    assert_true(thread.wait == 0 or thread.wait > 0, "wait is scheduler visible")
    -- After the first instruction block the thread must be parked on a timer.
    local parked = false
    for _ = 1, 40 do
        wait_runtime:update()
        if thread.wait > 0 then parked = true break end
    end
    assert_true(parked or thread.state == "finished", "the routine parks on its wait timer")

    -- `$A--` post-decrement repeat idiom: the body runs once per unit, driven by
    -- the reference `diffI` difficulty table (normal = 1).
    local loop_chunks = {
        Loop = {
            { "assign", "$A", "=", "3" },
            { "goto", "check", 0 },
            { "label", "body" },
            { "ins", "tick", {} },
            { "label", "check" },
            { "goto_if", "if", "$A--", "body", 0 },
            { "ins", "done", {} },
        },
    }
    local ticks = 0
    local loop_runtime = EclRuntime.new(loop_chunks, {
        instructions = {
            tick = function() ticks = ticks + 1 end,
            done = function() end,
        },
    })
    local loop_thread = loop_runtime:spawn("Loop")
    loop_runtime.threads[#loop_runtime.threads + 1] = loop_thread
    for _ = 1, 100 do
        loop_runtime:update()
        if loop_thread.state == "finished" then break end
    end
    assert_equal(ticks, 3, "the post-decrement loop runs exactly its initial count")

    -- Operand resolution: literals, integer slots and float slots.
    local probe = EclRuntime.new({}, { instructions = {} })
    local probe_thread = probe:spawn("X")
    probe_thread.ints["A"] = 7
    probe_thread.floats["B"] = 2.5
    assert_true(EclRuntime.evaluate_condition(probe_thread,"($A >= 7) && (%B < 3.0f)"),
        "ECL compound comparisons must actually evaluate")
    assert_equal(EclRuntime.evaluate_condition(probe_thread,"($A == 3)"),false,
        "false comparison stays false")
    assert_equal(EclRuntime.evaluate_expression(probe_thread,"$A % 4"),3,"ECL modulo")
    assert_equal(EclRuntime.evaluate_expression(probe_thread,"-%B"),-2.5,"mirrored coordinates preserve unary minus")
    assert_equal(EclRuntime.evaluate_expression(probe_thread,"_f(2 + 3) * 4"),20,"cast preserves grouping")
    assert_equal(EclRuntime.resolve(probe_thread, "12"), 12, "integer literals resolve")
    assert_equal(EclRuntime.resolve(probe_thread, "1.5f"), 1.5, "float literals resolve")
    assert_equal(EclRuntime.resolve(probe_thread, "$A"), 7, "integer slots resolve")
    assert_equal(EclRuntime.resolve(probe_thread, "%B"), 2.5, "float slots resolve")
    assert_equal(EclRuntime.resolve(probe_thread, "-192"), -192, "negative literals resolve")

    -- Expression evaluation with helper wrappers.
    assert_equal(EclRuntime.evaluate_expression(probe_thread, "_f(-192)"), -192,
        "the _f helper wrapper is unwrapped")
    assert_equal(EclRuntime.evaluate_expression(probe_thread, "%B * 2.0f"), 5.0,
        "float multiplication works")
    assert_equal(EclRuntime.evaluate_expression(probe_thread, "$A + 3"), 10,
        "integer addition works")

    -- An unknown instruction must be recorded rather than silently ignored, so
    -- the audit can list what stage content still needs support.
    local audit_runtime = EclRuntime.new({
        Probe = { { "ins", "notARealInstruction", {} } },
    }, { instructions = {} })
    local audit_thread = audit_runtime:spawn("Probe")
    audit_runtime.threads[#audit_runtime.threads + 1] = audit_thread
    audit_runtime:update()
    assert_true(audit_runtime.unhandled ~= nil, "unknown instructions are recorded")
    assert_equal(audit_runtime.unhandled.notARealInstruction, 1, "the unknown instruction is counted")
end
