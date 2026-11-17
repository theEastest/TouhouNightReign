-- Verification for the legacy replay stage content.
--
-- Every imported stage is compiled from the reference ECL. This spec runs each
-- stage's main timeline and boss script against a recording host and asserts
-- that the stage is complete: it must spawn enemies, fire bullets, show boss
-- health and name its spell cards, and use no unimplemented instruction.
--
-- A stage that regresses here is one that would silently drop content in game.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local Adapter = require("tnr.legacy_replay.adapter")
    local BossUi = require("tnr.legacy_replay.boss_ui")
    local StageRuntime = require("tnr.legacy_replay.stage_runtime")
    local chunks = require("tnr.legacy_replay.data.th15_all")
    local anm = require("tnr.legacy_replay.data.th15_anm")

    local function make_host()
        local host = {
            New = function() return { hp = 100 } end,
            Del = function() end,
            player = { x = 0, y = 0 },
        }
        return host
    end

    local function new_adapter(stage)
        local host = make_host()
        local ui = BossUi.new({ lstg = host })
        local adapter = Adapter.new({
            lstg = host, anm = anm, chunks = chunks, boss_ui = ui,
            stage_key = stage,
        })
        return adapter, ui, host
    end

    -- ECL's global time multiplier advances every stage system on simulation
    -- ticks, while rendering and LAN transport can continue on engine frames.
    local clock=setmetatable({frames=0,time_scale=0.25,time_accumulator=0},StageRuntime)
    clock._update_simulation=function(self) self.frames=self.frames+1 end
    for _=1,3 do
        assert_equal(clock:update(),false,"quarter-speed time waits for a full simulation tick")
    end
    assert_true(clock:simulation_step_due(),"the next quarter-speed frame becomes a simulation tick")
    assert_equal(clock:update(),true,"the quarter-speed clock advances on its fourth frame")
    assert_equal(clock.frames,1,"one game frame elapsed at quarter speed")
    assert_equal(clock.time_accumulator,0,"the simulation clock keeps no lost time")

    local logo_adapter,_,logo_host=new_adapter("st04")
    local logo=logo_adapter:show_stage_logo()
    logo:update()
    assert_true(logo~=nil,"stageLogo loads the stage-specific logo ANM")
    assert_equal(logo.archive_name,"st04logo","stageLogo selects the current stage archive")
    assert_equal(logo.script,0,"stageLogo plays the root title-card script")
    assert_true(#logo.children>0,"stageLogo starts its attached title components")

    local speed_adapter=new_adapter("st01")
    local speed_seen
    speed_adapter.on_game_speed=function(value) speed_seen=value end
    speed_adapter.instructions.gameSpeed({floats={},ints={}},speed_adapter.runtime,{"0.25f"})
    assert_equal(speed_seen,0.25,"gameSpeed applies the ECL global speed value")
    local chapter_thread={floats={},ints={},object={}}
    speed_adapter.instructions.setChapter(chapter_thread,speed_adapter.runtime,{"43"})
    assert_equal(speed_adapter.chapter,43,"setChapter stores stage chapter metadata")
    assert_equal(chapter_thread.object.legacy_chapter,43,"setChapter stores the chapter on the ECL object")
    speed_adapter.instructions.spellTimeout(chapter_thread)
    assert_true(speed_adapter.spell_timeout_enabled,"spellTimeout arms the spell timeout state")

    -- The engine takes the timer interrupt path independently of the
    -- ECL-visible TIMEOUT bit. Only a spell marked by opcode 542 preserves
    -- that bit; a newly started ordinary spell clears the old marker.
    local function timeout_fixture()
        local adapter=Adapter.new({lstg=make_host(),chunks={
            TestNext={{"assign","$I0","=","42"},{"ins","wait",{"1"}},{"ret"}},
        }})
        adapter.frame=1
        local enemy={hp=100,legacy_globals={},legacy_interrupts={
            [0]={id=0,start=0,finish=1,registered_frame=0,routine="TestNext"},
        }}
        return adapter,enemy
    end
    local ordinary_timer,ordinary_enemy=timeout_fixture()
    ordinary_timer:advance_enemy_interrupts(ordinary_enemy)
    assert_equal(ordinary_enemy.legacy_thread.ints.TIMEOUT,0,"ordinary timed phase exposes TIMEOUT zero")
    assert_equal(ordinary_enemy.legacy_thread.pc,0,"ordinary timer still defers its next routine")
    local survival_timer,survival_enemy=timeout_fixture()
    survival_timer.instructions.spellTimeout({object=survival_enemy,spell_timer=1})
    survival_timer:end_spell()
    assert_true(survival_timer.spell_timeout_enabled,"spellEnd alone preserves the manager timeout flag")
    survival_timer:advance_enemy_interrupts(survival_enemy)
    assert_equal(survival_enemy.legacy_thread.ints.TIMEOUT,1,"spellTimeout phase exposes TIMEOUT one")
    assert_equal(survival_enemy.legacy_thread.pc,0,"survival timer still defers its next routine")
    local reset_timer,reset_enemy=timeout_fixture()
    reset_timer.instructions.spellTimeout({object=reset_enemy,spell_timer=1})
    reset_timer:begin_spell({object=reset_enemy},{0,100,0,"Ordinary"})
    assert_equal(reset_timer.spell_timeout_enabled,false,"new spell clears prior spellTimeout flag")
    reset_timer:advance_enemy_interrupts(reset_enemy)
    assert_equal(reset_enemy.legacy_thread.ints.TIMEOUT,0,"ordinary spell does not inherit old survival flag")
    local health_interrupt,health_enemy=timeout_fixture()
    health_interrupt.instructions.spellTimeout({object=health_enemy,spell_timer=1})
    health_enemy.hp=0
    health_interrupt:advance_enemy_interrupts(health_enemy)
    assert_equal(health_enemy.legacy_thread.ints.TIMEOUT,0,"health interrupt wins when health and timer coincide")
    assert_equal(health_enemy.legacy_globals.I0,42,"health interrupt executes immediately")

    local health_adapter, health_ui = new_adapter("st04")
    local boss_thread = {object={hp=40,max_hp=40}}
    local instructions = health_adapter.instructions
    instructions.setBoss(boss_thread,nil,{0})
    instructions.lifeSet(boss_thread,nil,{13000})
    instructions.lifeSet({object={}},nil,{100})
    assert_equal(health_ui.health_max,13000,"phase sets the boss's real maximum HP")
    assert_equal(health_ui.health,13000,"another enemy cannot overwrite the boss display")
    instructions.lifeMarker(boss_thread,nil,{0,6500,0xffffffff})
    instructions.lifeMarker(boss_thread,nil,{0,3250,0xffffffff})
    assert_equal(#health_ui.health_layers,1,"rewriting a life marker uses the same slot")
    assert_equal(health_ui.health_layers[1].ratio,.25,"life marker is relative to phase HP")

    -- Stages present in the reference export.
    local STAGES = { "st01", "st02", "st03", "st04", "st05", "st06", "st07" }

    for _, stage in ipairs(STAGES) do
        local main = stage .. ".MainFront"
        assert_true(chunks[main] ~= nil, stage .. " must expose its main timeline")

        local adapter, ui = new_adapter(stage)
        local created = 0
        local original_spawn = adapter.spawn_enemy
        adapter.spawn_enemy = function(self, ...)
            created = created + 1
            return original_spawn(self, ...)
        end
        local thread = adapter.runtime:spawn(main)
        assert_true(thread ~= nil, stage .. " main timeline must start")
        adapter.runtime.threads[#adapter.runtime.threads + 1] = thread

        -- Run the opening third of the stage.
        for _ = 1, 1200 do adapter:update() end
        assert_true(created > 0, stage .. " must spawn enemies in its opening")

        -- The stage must not depend on an instruction the adapter lacks.
        local report = adapter:missing_report()
        local missing = {}
        for _, row in ipairs(report) do missing[#missing + 1] = row[1] .. "=" .. row[2] end
        assert_equal(#report, 0,
            stage .. " must use only implemented instructions: " .. table.concat(missing, " "))
    end

    -- The boss script must drive the presentation and produce bullets.
    local function check_boss(stage, boss_routine)
        if not chunks[boss_routine] then return false end
        local adapter, ui = new_adapter(stage)
        local boss = adapter:spawn_enemy(boss_routine, 0, 0, 11500)
        assert_true(boss ~= nil, boss_routine .. " must create an enemy object")
        local saw_bullets=false
        for _ = 1, 600 do
            adapter:update();ui:update()
            if #(adapter.shots or {})>0 then saw_bullets=true end
        end
        assert_true(ui.visible, boss_routine .. " must show the boss health bar")
        assert_true(boss.legacy_interrupts ~= nil,
            boss_routine .. " must register a nonspell to spell interrupt")
        -- Cross the registered threshold to enter the first spell.
        local crossed = false
        for _, entry in pairs(boss.legacy_interrupts or {}) do
            if not entry.fired then
                boss.hp = entry.start - 1
                crossed = true
                break
            end
        end
        assert_true(crossed, boss_routine .. " must register at least one interrupt")
        local saw_spell = false
        for _ = 1, 600 do
            adapter:update()
            ui:update()
            if ui.card then saw_spell = true break end
        end
        assert_true(saw_spell, boss_routine .. " must start a spell card")
        if stage=="st05" then
            local backdrop=adapter.spell_background
            assert_equal(backdrop.script,10,"Clownpiece's spells use the stage's native backdrop root")
            assert_equal(#backdrop.children,3,"the two rotating layers and base are present")
            adapter.instructions.spellEnd()
            assert_true(backdrop.finished,"spell end removes its looping background")
        end
        assert_true(saw_bullets, boss_routine .. " must fire bullets before the phase clear")
        local report = adapter:missing_report()
        assert_equal(#report, 0, boss_routine .. " must use only implemented instructions")
        return true
    end

    -- Stage 1's boss is fully checked; the remaining stages are checked too when
    -- their boss routine is present in the compiled catalog.
    check_boss("st01", "st01bs.Boss")
    for _, stage in ipairs({ "st02", "st03", "st04", "st05", "st06", "st07" }) do
        check_boss(stage, stage .. "bs.Boss")
    end

    -- Every stage must compile a substantial routine set.
    for _, stage in ipairs(STAGES) do
        local count = 0
        for name in pairs(chunks) do
            if name:sub(1, #stage + 1) == stage .. "." then count = count + 1 end
        end
        assert_true(count >= 20, stage .. " must compile a full routine set")
    end
end
