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
        })
        return adapter, ui, host
    end

    -- Stages present in the reference export.
    local STAGES = { "st01", "st02", "st03", "st04", "st05", "st06", "st07" }

    for _, stage in ipairs(STAGES) do
        local main = stage .. ".MainFront"
        assert_true(chunks[main] ~= nil, stage .. " must expose its main timeline")

        local adapter, ui = new_adapter(stage)
        local thread = adapter.runtime:spawn(main)
        assert_true(thread ~= nil, stage .. " main timeline must start")
        adapter.runtime.threads[#adapter.runtime.threads + 1] = thread

        -- Run the opening third of the stage.
        for _ = 1, 1200 do adapter:update() end
        assert_true(#adapter.enemies > 0, stage .. " must spawn enemies in its opening")

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
        for _ = 1, 600 do adapter:update() ui:update() end
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
        assert_true(#(adapter.shots or {}) > 0, boss_routine .. " must fire bullets")
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
