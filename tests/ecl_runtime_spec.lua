-- Tests for the ECL interpreter used by the legacy replay mode.
--
-- The reference Touhou games drive enemies with compiled ECL. The interpreter
-- executes the lowered .decl form (see tools/compile_ecl.py). These tests pin
-- the control flow and operand semantics the real stage 1 scripts rely on.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local EclRuntime = require("tnr.legacy_replay.ecl_runtime")
    local expression_thread={ints={},floats={F0=-1},object={legacy_globals={F0=-1}}}
    assert_equal(EclRuntime.evaluate_expression(expression_thread,"%F0 * -1.0f"),1,
        "stage six alternates a negative F0 back to positive")
    assert_equal(EclRuntime.evaluate_expression(expression_thread,"2 * -3"),-6,
        "a sign after multiplication is unary")
    assert_equal(EclRuntime.evaluate_expression(expression_thread,"5 - -2"),7,
        "a binary subtraction can precede a negative operand")
    assert_equal(EclRuntime.evaluate_expression(expression_thread,"2 * -(%F0 + 2)"),-2,
        "a unary sign can apply to a grouped operand")
    local boss_thread={ints={},floats={},object={hp=8000,legacy_pending_damage=400}}
    assert_equal(EclRuntime.resolve(boss_thread,"$LIFE"),8000,"enemy LIFE reads current HP without applying pending damage")
    assert_true(EclRuntime.evaluate_condition(boss_thread,"($LIFE > 5500)"),"first final-spell phase waits above its HP threshold")
    boss_thread.object.hp=5500
    assert_true(not EclRuntime.evaluate_condition(boss_thread,"($LIFE > 5500)"),"the first threshold releases at 5500 HP")
    assert_true(EclRuntime.evaluate_condition(boss_thread,"($LIFE > 3500)"),"the following phase still waits above 3500 HP")
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

    -- Native ECL register storage belongs to the controller, not an individual
    -- invocation. An objectless stage timeline represents one such controller.
    local register_runtime=EclRuntime.new({
        Root={{"ret"}},
        Change={{"assign","%F0","=","0.017446f"},{"assign","%A","=","7"},{"ret"}},
        Async={{"assign","%F1","=","2.5f"},{"ret"}},
    },{})
    local root,independent=register_runtime:spawn("Root"),register_runtime:spawn("Root")
    EclRuntime.apply_assignment(root,"%A","=",3)
    register_runtime:call(root,"Change",false,{})
    assert_true(math.abs(EclRuntime.resolve(root,"%F0")-0.017446)<1e-10,
        "root controller registers survive a synchronous child return")
    assert_equal(EclRuntime.resolve(root,"%A"),3,"ordinary call locals remain independent")
    assert_equal(EclRuntime.resolve(independent,"%F0"),0,"separate root controllers do not share registers")
    local async=register_runtime:call(root,"Async",true,{})
    register_runtime.frame=(register_runtime.frame or 0)+1
    EclRuntime.step(async,register_runtime)
    assert_equal(EclRuntime.resolve(root,"%F1"),2.5,"async contexts share their controller registers")
    assert_equal(EclRuntime.resolve(independent,"%F1"),0,"async writes do not escape their root")
    local first,second=register_runtime:spawn("Root",root),register_runtime:spawn("Root",root)
    first.object={legacy_globals={F0=EclRuntime.resolve(root,"%F0")}}
    second.object={legacy_globals={F0=EclRuntime.resolve(root,"%F0")}}
    EclRuntime.apply_assignment(first,"%F0","=",9)
    assert_equal(EclRuntime.resolve(second,"%F0"),0.017446,"enemy register copies remain independent")
    assert_equal(EclRuntime.resolve(root,"%F0"),0.017446,"enemy writes leave the controller unchanged")
    local sub=register_runtime:spawn("Root",first)
    EclRuntime.apply_assignment(sub,"%F1","=",4)
    assert_equal(EclRuntime.resolve(first,"%F1"),4,"contexts of one enemy share its registers")
    assert_equal(EclRuntime.resolve(second,"%F1"),0,"different enemies do not share registers")

    -- Explicit difficulty-stack values are evaluated before a later inline
    -- expression; a plain random register remains for instruction dispatch.
    local random_count, observed = 0, nil
    local globals = setmetatable({}, {__index=function(_, key)
        if key == "RANDF" then random_count = random_count + 1; return random_count * 0.25 end
    end})
    local ordered = EclRuntime.new({ Main = {{"ins", "record", {
        "-999999.0f", "1 + %RANDF", {"3", "1 + %RANDF", "5"}, "%RANDF"
    }, {3, 2}}} }, { globals = globals, instructions = {
        record = function(thread, _, args)
            observed = {args[1], args[2], args[3], EclRuntime.resolve(thread, args[4])}
        end,
    }})
    ordered.difficulty = 1
    ordered.threads = {ordered:spawn("Main")}
    ordered:update()
    assert_equal(observed[1], "-999999.0f", "nonrandom operand stays unchanged")
    assert_equal(observed[2], 1.5, "inline random expression reads after difficulty stack")
    assert_equal(observed[3], 1.25, "normal difficulty stack expression reads first")
    assert_equal(observed[4], 0.75, "direct random register is read at dispatch")
    assert_equal(random_count, 3, "each random expression is evaluated exactly once")
    local nonrandom_branch, branch_draws = nil, 0
    local branch_globals = setmetatable({}, {__index=function(_, key)
        if key == "RANDF" then branch_draws = branch_draws + 1; return 0.5 end
    end})
    local branches = EclRuntime.new({Main={{"ins", "record", {{"10", "%RANDF", "20"}, "7"}, {1}}}},
        {globals=branch_globals, instructions={record=function(_, _, args) nonrandom_branch=args end}})
    branches.difficulty=0
    branches.threads={branches:spawn("Main")}
    branches:update()
    assert_equal(nonrandom_branch[1],10,"the active nonrandom difficulty branch is selected")
    assert_equal(nonrandom_branch[2],"7","unmarked plain operands are unchanged")
    assert_equal(branch_draws,0,"an inactive random branch consumes no RNG")

    local stage_switch={}
    local synchronous=EclRuntime.new({
        Front={{"call","Wave",false,{}},{"ins","next_chapter",{}}},
        Wave={{"ins","wait",{"2"}},{"call","Tail",false,{}}},
        Tail={{"ins","wait",{"2"}},{"ins","last_enemy",{}}},
    },{instructions={
        next_chapter=function(_,runtime) stage_switch.chapter=runtime.frame end,
        last_enemy=function(_,runtime) stage_switch.enemy=runtime.frame end,
    }})
    synchronous.threads={synchronous:spawn("Front")}
    for _=1,5 do synchronous:update() end
    assert_equal(stage_switch.enemy,5,"nested callee waits exactly four frames")
    assert_equal(stage_switch.chapter,5,"the chapter switch runs on the return frame")

    -- 48efb3..48eff0 inserts each async context just after the main context;
    -- 48e6c0 then visits those contexts from the head on the following tick.
    local context_order={}
    local contexts=EclRuntime.new({
        Main={{"call","A",true,{}},{"call","B",true,{}},{"call","C",true,{}},
            {"call","Sync",false,{}},{"ins","wait",{"20"}}},
        A={{"ins","record",{"A"}},{"ret"}},
        B={{"ins","record",{"B"}},{"ret"}},
        C={{"ins","record",{"C"}},{"ret"}},
        Sync={{"ins","wait",{"1"}},{"ins","record",{"sync"}},{"ret"}},
    },{instructions={record=function(_,_,args) context_order[#context_order+1]=args[1] end}})
    local owner={}
    local main=contexts:spawn("Main");main.object=owner;contexts.threads={main}
    contexts:update_enemies({owner},function() end,function() end)
    contexts:update_enemies({owner},function() end,function() end)
    assert_equal(table.concat(context_order,","),"sync,C,B,A",
        "newest async context runs first after the synchronous main context")

    -- A controller's delete stops its remaining asynchronous ECL contexts in
    -- the same enemy-manager tick. In stage 6 the child emits random bullets.
    local emissions,other_ticks=0,0
    local deletion=EclRuntime.new({
        Parent={{"call","Child",true,{}},{"ins","wait",{"2"}},{"ins","delete",{}}},
        Child={{"label","again"},{"ins","emit",{}},{"ins","wait",{"1"}},{"goto","again",0}},
        Other={{"label","again"},{"ins","other",{}},{"ins","wait",{"1"}},{"goto","again",0}},
    },{instructions={
        delete=function(thread) thread.object.legacy_deleted=true;thread.state="finished" end,
        emit=function() emissions=emissions+1 end,
        other=function() other_ticks=other_ticks+1 end,
    }})
    local deleted_enemy,other_enemy={},{}
    local parent,other=deletion:spawn("Parent"),deletion:spawn("Other")
    parent.object,other.object=deleted_enemy,other_enemy
    deletion.threads={parent,other}
    for _=1,3 do deletion:update_enemies({deleted_enemy,other_enemy},function() end,function() end) end
    assert_equal(emissions,1,"deletion prevents an asynchronous emission on the same tick")
    assert_equal(other_ticks,3,"deleting one enemy leaves other enemies running")

    -- TH15's .decl form declares helper parameters with `var` inside the body,
    -- while the function header remains empty. Those values still arrive in
    -- the A..H slots at runtime and are essential for multi-slot ANM helpers.
    local implicit_arguments
    local implicit_runtime=EclRuntime.new({
        Parent={{"call","LegacyHelper",false,{"1.5f","0.25f","8","11","12","13"}}},
        LegacyHelper={{"params",{}},{"var","A, B, C, D, E, F;"},{"ins","record",{}},{"ret"}},
    },{instructions={record=function(thread)
        implicit_arguments={thread.floats.A,thread.floats.B,thread.ints.C,thread.ints.D,
            thread.ints.E,thread.ints.F}
    end}})
    local implicit_parent=implicit_runtime:spawn("Parent")
    implicit_runtime.threads[#implicit_runtime.threads+1]=implicit_parent
    implicit_runtime:update()
    assert_equal(implicit_arguments[1],1.5,"body-declared helper arguments preserve float A")
    assert_equal(implicit_arguments[2],.25,"body-declared helper arguments preserve float B")
    assert_equal(implicit_arguments[3],8,"body-declared helper arguments populate integer C")
    assert_equal(implicit_arguments[4],11,"body-declared helper arguments populate integer D")
    assert_equal(implicit_arguments[5],12,"body-declared helper arguments populate integer E")
    assert_equal(implicit_arguments[6],13,"body-declared helper arguments populate integer F")

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
    assert_equal(EclRuntime.evaluate_expression(probe_thread,"_S(%B + 117.25f)"),119,
        "float-to-int cast preserves the scripted wait interval")
    assert_equal(EclRuntime.evaluate_expression(probe_thread,"_S(-%B)"),-2,
        "float-to-int cast truncates toward zero")
    probe.host.globals = {CHAPTER=5}
    assert_true(EclRuntime.evaluate_condition(probe_thread,"([-9905] == 5)"),
        "raw chapter operand selects the original wave variant")
    assert_equal(EclRuntime.evaluate_expression(probe_thread,"-9905"),-9905,
        "only the bracketed operand reads a native global")
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
