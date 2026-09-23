-- Regenerate the equal-frequency wave difficulty tiers.
--
-- Reads the real wave catalog, scores every wave with tnr.stages.wave_difficulty
-- and buckets the sorted scores into six equal-frequency tiers, writing
-- tnr/stages/wave_tiers.lua.
--
-- Run from the game directory with the bundled Lua:
--   ..\LuaSTG-Sub-master\tool\lua\lua54.exe tools/generate_wave_tiers.lua

package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path

local WaveDifficulty = require("tnr.stages.wave_difficulty")
local Waves = require("tnr.stages.legacy_enemy_waves")

local rows = {}
for _, stage in ipairs(Waves) do
    for _, wave in ipairs(stage.waves or {}) do
        rows[#rows + 1] = { id = wave.id, score = WaveDifficulty.score(wave) }
    end
end
table.sort(rows, function(left, right)
    if left.score ~= right.score then return left.score < right.score end
    return left.id < right.id
end)

local total = #rows
local lines = {
    "-- Content-based difficulty tier per selectable wave (1 = lightest).",
    "-- Equal-frequency buckets over the real wave pool, so each tier holds a",
    "-- comparable amount of content. Generated from measured HP / enemy count /",
    "-- duration / bullet density. Do not hand-edit.",
    "return {",
}
for index, row in ipairs(rows) do
    local tier = math.min(6, math.floor((index - 1) * 6 / total) + 1)
    lines[#lines + 1] = string.format('    ["%s"] = %d,', row.id, tier)
end
lines[#lines + 1] = "}"

local path = "game/scripts/tnr/stages/wave_tiers.lua"
local file = assert(io.open(path, "w"))
file:write(table.concat(lines, "\n") .. "\n")
file:close()
print(string.format("wrote %s (%d waves)", path, total))
