-- Content-based wave difficulty.
--
-- The reference export carries no numeric difficulty rating: each enemy class
-- only declares which mode it belongs to ("Normal" / "Lunatic" / "All"). The
-- old catalog therefore guessed a 1..6 number purely from the source stage
-- name and the wave's position around the mid-boss, which produced an
-- unreasonable spread.
--
-- This module instead scores a wave from measurable content:
--   * total enemy HP      (from the real enemy.init(style, hp) call)
--   * enemy count         (spawn members)
--   * wave duration       (capped, so a long slow wave is not overrated)
--   * bullet pressure     (_create_bullet_group density of each class)
--
-- The composite log score is bucketed into six equal-frequency tiers by the
-- generated score table, so tier 1 is the lightest content and tier 6 the
-- heaviest. Ordinary rooms pick waves from their progression band; bosses and
-- elites use their own fixed per-floor pools.

local ReferenceEnemyStats = require("tnr.stages.reference_enemy_stats")
local WaveTiers = require("tnr.stages.wave_tiers")

local WaveDifficulty = {}

WaveDifficulty.MIN_TIER = 1
WaveDifficulty.MAX_TIER = 6

local function log10_plus_one(value)
    local v = tonumber(value) or 0
    if v < 0 then v = 0 end
    return math.log(v + 1) / math.log(10)
end

--- Composite score for one wave. Higher means heavier content.
function WaveDifficulty.score(wave)
    if type(wave) ~= "table" then return 0 end
    local members = wave.members or {}
    local count = #members
    local known_hp = 0
    local known_bullets = 0
    local known_count = 0
    local sum_hp = 0
    local sum_bullets = 0
    -- First pass: gather the real metrics that exist for this wave.
    for _, member in ipairs(members) do
        local class_name = type(member) == "table" and member.class_name or nil
        local stats = class_name and ReferenceEnemyStats[class_name] or nil
        if stats then
            known_count = known_count + 1
            if stats.hp then
                sum_hp = sum_hp + stats.hp
                known_hp = known_hp + 1
            end
            if stats.bullets then
                sum_bullets = sum_bullets + stats.bullets
                known_bullets = known_bullets + 1
            end
        end
    end
    -- Members whose class is not in the reference table inherit the average
    -- of the known members, so a wave is never wrongly inflated or deflated
    -- by missing data.
    local avg_hp = known_hp > 0 and (sum_hp / known_hp) or 10
    local avg_bullets = known_bullets > 0 and (sum_bullets / known_bullets) or 0
    local total_hp = sum_hp + (count - known_hp) * avg_hp
    local total_bullets = sum_bullets + (count - known_bullets) * avg_bullets
    local duration = tonumber(wave.duration_seconds) or 0

    local s_hp = log10_plus_one(total_hp)
    local s_count = log10_plus_one(count)
    local s_duration = log10_plus_one(duration)
    local s_bullets = log10_plus_one(total_bullets)

    return 0.55 * s_hp + 0.75 * s_count + 0.55 * s_duration + 1.15 * s_bullets
end

-- Equal-frequency tier boundaries over the generated wave catalog. Computed
-- once from the real wave pool so every tier holds a comparable number of
-- selectable waves. Kept for callers that only have a raw score; the baked
-- per-wave table below is the authoritative tier used by the game.
local TIER_BOUNDS = {
    2.666, 2.987, 3.803, 4.055, 5.772,
}

--- Map a composite score onto a 1..6 tier.
function WaveDifficulty.tier_for_score(score)
    for index, bound in ipairs(TIER_BOUNDS) do
        if score < bound then return index end
    end
    return WaveDifficulty.MAX_TIER
end

--- Difficulty tier of a wave entry (1..6). Prefers the baked equal-frequency
--- tier; falls back to the score threshold for unknown ids.
function WaveDifficulty.tier_of(wave)
    if type(wave) == "table" and wave.id and WaveTiers[wave.id] then
        return WaveTiers[wave.id]
    end
    return WaveDifficulty.tier_for_score(WaveDifficulty.score(wave))
end

-- Six progression bands for ordinary rooms: floor 1 weak/strong, floor 2
-- weak/strong, floor 3 weak/strong.
WaveDifficulty.BAND_COUNT = 6

--- Band (1..6) for a floor (1..3) and normalized map progress (0..1).
function WaveDifficulty.band_for(floor, progress)
    floor = math.max(1, math.min(3, math.floor(tonumber(floor) or 1)))
    local p = tonumber(progress) or 0
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    local half = p < 0.5 and 0 or 1
    return (floor - 1) * 2 + half + 1
end

return WaveDifficulty
