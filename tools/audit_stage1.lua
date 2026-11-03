-- End-to-end timeline gate. This does not certify visual fidelity or input.
-- Run from the project root with LuaJIT or Lua 5.4.
package.path = "game/scripts/?.lua;" .. package.path
io.stdout:setvbuf("no")
local Stage = require("tnr.legacy_replay.stage_runtime")
local stage = Stage.new({
    lstg = {}, stage = "st01",
    difficulty = tonumber(arg[2]) or 1,
    chunks = require("tnr.legacy_replay.data.th15_all"),
    anm = require("tnr.legacy_replay.data.th15_anm"),
    std = require("tnr.legacy_replay.data.th15_std"),
    sht = require("tnr.legacy_replay.data.th15_sht"),
})
local seen, spawned, sections = {}, 0, {}
local damage_path = arg[3] == "damage"
local damage_hits = 0
local routines = {}
local spawn_thread = stage.adapter.runtime.spawn
stage.adapter.runtime.spawn = function(self, ...)
    local thread = spawn_thread(self, ...)
    routines[thread.routine] = (routines[thread.routine] or 0) + 1
    return thread
end
local spawn = stage.adapter.spawn_enemy
stage.adapter.spawn_enemy = function(self, ...)
    local enemy, thread = spawn(self, ...)
    seen[thread.routine] = (seen[thread.routine] or 0) + 1
    spawned = spawned + 1
    return enemy, thread
end
stage:start()
for frame = 1, tonumber(arg[1]) or 36000 do
    -- Survival is bypassed only for this timeline audit; no enemies are killed
    -- by the harness, so a timeout path must actually exist to finish a fight.
    for _, player in pairs(stage.players) do player.invulnerable = 999 end
    if damage_path and frame % 120 == 0 and not (stage.dialogue and stage.dialogue.active) then
        -- Inject ordinary player-shot records at living enemies to exercise
        -- collision -> damage -> phase interrupts. This is not an aim/survival test.
        for _, enemy in ipairs(stage.adapter.enemies) do
            if enemy.hp and enemy.hp > 0 and not enemy.legacy_dropped then
                stage.adapter.shots[#stage.adapter.shots + 1] = {
                    x = enemy.x, y = enemy.y, vx = 0, vy = 0,
                    player_bullet = true, damage = enemy.hp, speed = 0,
                }
                damage_hits = damage_hits + 1
            end
        end
    end
    stage:update()
    if frame % 1000 == 0 then print("progress",frame,#stage.adapter.enemies,#stage.adapter.runtime.threads) end
    if not sections[stage.section_name] then
        sections[stage.section_name] = frame
        print("section", stage.section_name, frame)
    end
    if stage:timeline_finished() then break end
end
print("frames", stage.frames, "spawned", spawned, "clear", stage:timeline_finished())
for _, name in ipairs({"st01mbs.MBoss", "st01mbs2.MBossB", "st01bs.Boss"}) do
    print("required boss", name, seen[name] or 0)
end
for _, entry in ipairs(stage.adapter:missing_report()) do print("unhandled", entry[1], entry[2]) end
assert(seen["st01mbs.MBoss"], "stage never spawned the first midboss")
assert(seen["st01mbs2.MBossB"], "stage never spawned the second midboss")
assert(seen["st01bs.Boss"], "stage never spawned the stage boss")
assert(stage:timeline_finished(), "stage did not reach its ending")
assert(not stage.adapter.boss_object, "stage cleared while a boss was still active")
assert(stage.dialogue and stage.dialogue.completed[0] and stage.dialogue.completed[1],
    "stage cleared without completing both MSG entries")
assert(next(stage.dialogue.unknown) == nil, "stage-one MSG used unknown instructions")
for _, routine in ipairs({"BossCard1", "Boss2", "BossCard2", "BossDead"}) do
    assert(routines["st01bs." .. routine], "final boss skipped phase " .. routine)
end
if damage_path then assert(damage_hits > 0, "damage path did not inject any shots") end
print("route", damage_path and "damage" or "timeout", "injected shots", damage_hits)
assert(#stage.adapter:missing_report() == 0, "stage used unsupported instructions")
print("Stage-one timeline gate passed; visual and gameplay gates remain separate")
