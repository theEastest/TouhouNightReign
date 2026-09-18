-- StageSpec is the project-owned format used by the fallback runtime and the
-- future native THlib adapter.  All IDs are English; display_name is UI text.
local Specs = {
    ordinary_stage_01 = {
        id = "ordinary_stage_01",
        kind = "ordinary",
        display_name = "夜行道中",
        background = "tnr-bg-night-road",
        waves = {
            { delay = 0, enemy = "legacy_small_fairy", count = 5, formation = "line", y = 650 },
            { delay = 35, enemy = "legacy_red_seed", count = 4, formation = "sides", y = 680 },
            { delay = 45, enemy = "legacy_butterfly", count = 2, formation = "pair", y = 690 },
        },
        mid_boss = {
            id = "sanae_mid",
            display_name = "东风谷早苗",
            hp = 950,
            cards = { "reimu_nonspell" },
        },
        clear_after_mid_boss = true,
    },
    boss_stage_01 = {
        id = "boss_stage_01",
        kind = "boss",
        display_name = "博丽灵梦",
        boss = {
            id = "reimu",
            display_name = "博丽灵梦",
            cards = {
                "reimu_nonspell",
                "spirit_seal",
                "yin_yang_jewel",
                "four_direction_formation",
            },
        },
    },

    elite_stage_01 = {
        id = "elite_stage_01",
        kind = "elite",
        display_name = "Elite Boss",
        background = "tnr-bg-night-road",
    },

    -- Kept as a compatibility fixture for headless tests and debug commands.
    test_enemy_stage = {
        id = "test_enemy_stage",
        kind = "ordinary",
        encounter_id = "enemy_test_01",
        waves = { 3, 5, 1 },
        duration_seconds = 45,
    },
    test_boss_stage = {
        id = "test_boss_stage",
        kind = "boss",
        encounter_id = "boss_test_01",
        nonspell_count = 1,
        spell_count = 1,
        duration_seconds = 60,
    },
}

local wave_sets = {
    { "legacy_enemy_style_01", "legacy_enemy_style_05", "legacy_enemy_style_10" },
    { "legacy_enemy_style_02", "legacy_enemy_style_06", "legacy_enemy_style_11" },
    { "legacy_enemy_style_03", "legacy_enemy_style_07", "legacy_enemy_style_12" },
    { "legacy_enemy_style_04", "legacy_enemy_style_08", "legacy_enemy_style_13" },
    { "legacy_enemy_style_05", "legacy_enemy_style_09", "legacy_enemy_style_14" },
    { "legacy_enemy_style_06", "legacy_enemy_style_10", "legacy_enemy_style_15" },
}
local nonspell_pool = { "reimu_nonspell", "sanae_nonspell", "marisa_nonspell" }

for index, wave_set in ipairs(wave_sets) do
    local stage_id = string.format("ordinary_stage_%02d", index)
    if not Specs[stage_id] then
        Specs[stage_id] = {
            id = stage_id,
            kind = "ordinary",
            display_name = "夜行道中 " .. index,
            background = "tnr-bg-night-road",
            waves = {
                { delay = 0, enemy = wave_set[1], count = 4 + (index % 2), formation = "line", y = 650 },
                { delay = 35, enemy = wave_set[2], count = 3 + (index % 3), formation = "sides", y = 680 },
                { delay = 45, enemy = wave_set[3], count = 2 + (index % 2), formation = "pair", y = 690 },
            },
            mid_boss = {
                id = index % 3 == 0 and "reimu_mid" or "sanae_mid",
                display_name = index % 3 == 0 and "博丽灵梦" or "东风谷早苗",
                cards = { nonspell_pool[((index - 1) % #nonspell_pool) + 1] },
            },
            clear_after_mid_boss = true,
        }
    end
end

return Specs
