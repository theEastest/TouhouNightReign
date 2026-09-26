-- Tests for the ECL engine adapter used by the legacy replay mode.
--
-- The adapter binds interpreter instructions to the object model. These tests
-- run the whole th15 stage 1 timeline against a recording host and assert the
-- enemies and bullets it produces, so a regression in the instruction mapping
-- fails here instead of only in a live game.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local Adapter = require("tnr.legacy_replay.adapter")
    local chunks = require("tnr.legacy_replay.data.th15_all")
    local anm = require("tnr.legacy_replay.data.th15_anm")

    -- A recording host: enemy and bullet creation are both counted.
    local enemies_created, bullets_created = 0, 0
    local fake = {
        New = function(class, ...)
            local args = { ... }
            if class == "enemy" then
                enemies_created = enemies_created + 1
                return { x = 0, y = 0, hp = 100 }
            end
            bullets_created = bullets_created + 1
            return { x = args[3], y = args[4] }
        end,
        Del = function() end,
        player = { x = 0, y = 0 },
    }
    local adapter = Adapter.new({
        lstg = fake,
        enemy_class = "enemy",
        bullet_styles = { "fake_bullet" },
        anm = anm,
        chunks = chunks,
    })

    -- The stage 1 timeline must be startable.
    local thread = adapter.runtime:spawn("st01.MainFront")
    assert_true(thread ~= nil, "the stage 1 timeline starts")
    assert_equal(thread.routine, "st01.MainFront", "the timeline resolves to the stage 1 entry")
    adapter.runtime.threads[#adapter.runtime.threads + 1] = thread

    -- Run the opening waves.
    for _ = 1, 900 do adapter:update() end
    assert_true(#adapter.enemies > 0, "the timeline spawns enemies")
    assert_true(enemies_created > 0, "enemies go through the object factory")

    -- Enemy positions must spread across the playfield instead of collapsing to
    -- the origin, which is what happens when expression arguments are not
    -- evaluated.
    local min_x, max_x = math.huge, -math.huge
    for _, enemy in ipairs(adapter.enemies) do
        min_x = math.min(min_x, enemy.x or 0)
        max_x = math.max(max_x, enemy.x or 0)
    end
    assert_true(max_x > min_x, "enemies spawn across the playfield width")

    -- Bullets must be produced by the attack routines.
    assert_true(#(adapter.shots or {}) > 0, "attack routines fire bullets")

    -- Every instruction the stage uses must be implemented. A non-zero count
    -- here means the adapter is missing a mapping the stage depends on.
    local report = adapter:missing_report()
    assert_equal(#report, 0, "stage 1 uses no unimplemented instruction")

    -- The difficulty branch list must resolve per mode: a harder difficulty
    -- waits fewer frames before the same attack.
    local function first_wait_frames(difficulty)
        local diff_adapter = Adapter.new({
            lstg = fake,
            enemy_class = "enemy",
            anm = anm,
            chunks = chunks,
            difficulty = difficulty,
        })
        local attack = diff_adapter.runtime:spawn("st01.GirlA01_at")
        attack.runtime = diff_adapter.runtime
        diff_adapter.runtime.threads[#diff_adapter.runtime.threads + 1] = attack
        for _ = 1, 5 do diff_adapter.runtime:update() end
        return attack.wait
    end
    local normal_wait = first_wait_frames(1)
    local lunatic_wait = first_wait_frames(3)
    assert_true(normal_wait > lunatic_wait,
        "lunatic waits fewer frames than normal for the same opening")
end
