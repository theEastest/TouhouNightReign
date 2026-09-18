-- Curated legacy content identifiers. The native bridge resolves these IDs to
-- the original classes loaded from game/legacy.
local LegacyEnemyWaves = require("tnr.stages.legacy_enemy_waves")

local ContentCatalog = {
    enemy_waves = {},
    enemies = {
        legacy_small_fairy = {
            id = "legacy_small_fairy",
            legacy_id = "lizi_小玉毛玉:Normal",
            display_name = "小玉毛玉",
            hp = 35,
            radius = 16,
            fire_pattern = "aimed",
            fire_interval = 70,
            bullet_speed = 3.0,
            drop_money = 2,
            sprite = "tnr-thlib-enemy1",
            bullet_sprite = "tnr-thlib-bullet-arrow",
        },
        legacy_red_seed = {
            id = "legacy_red_seed",
            legacy_id = "lizi_米弹毛玉红:Normal",
            display_name = "米弹毛玉",
            hp = 55,
            radius = 17,
            fire_pattern = "fan",
            fire_interval = 90,
            bullet_speed = 2.6,
            drop_money = 3,
            sprite = "tnr-thlib-enemy13",
            bullet_sprite = "tnr-thlib-bullet-butterfly",
        },
        legacy_butterfly = {
            id = "legacy_butterfly",
            legacy_id = "lizi_中玉大蝴蝶:Normal",
            display_name = "中玉大蝴蝶",
            hp = 180,
            radius = 24,
            fire_pattern = "spiral",
            fire_interval = 55,
            bullet_speed = 2.4,
            drop_money = 8,
            sprite = "tnr-thlib-enemy25",
            bullet_sprite = "tnr-thlib-bullet-ball",
        },
    },
    cards = {
        preparation_danmaku_ritual = {
            id = "preparation_danmaku_ritual",
            display_name = "准备「漫不经心的弹幕祈仪」",
            legacy_id = "道中早苗N:Normal#准备「漫不经心的弹幕祈仪」",
            hp = 520,
            duration_seconds = 60,
            pattern = "ritual",
            background_asset = "tnr-legacy-void-bg",
            effect_asset = "tnr-legacy-void-fx",
            boss_frames = {
                "tnr-legacy-void-boss-1", "tnr-legacy-void-boss-2",
                "tnr-legacy-void-boss-3", "tnr-legacy-void-boss-4",
                "tnr-legacy-void-boss-5", "tnr-legacy-void-boss-6",
                "tnr-legacy-void-boss-7", "tnr-legacy-void-boss-8",
                "tnr-legacy-void-boss-9", "tnr-legacy-void-boss-10",
                "tnr-legacy-void-boss-11", "tnr-legacy-void-boss-12",
            },
            fire_interval = 34,
            bullet_speed = 2.2,
            is_spell = true,
            time_spell = true,
            spell_bonus = 600,
        },
        fantasy_dizzy_wind = {
            id = "fantasy_dizzy_wind",
            display_name = "秘术「幻想乡的眩晕风」",
            legacy_id = "道中早苗N:Normal#秘术「幻想乡的眩晕风」",
            hp = 760,
            duration_seconds = 70,
            pattern = "wind",
            background_asset = "tnr-sanae-sc-bg2",
            fire_interval = 26,
            bullet_speed = 2.8,
            is_spell = true,
            time_spell = true,
            spell_bonus = 800,
        },
        reimu_nonspell = {
            id = "reimu_nonspell",
            display_name = "博丽灵梦·非符",
            legacy_id = "Reimu:Normal#nonspell",
            hp = 700,
            duration_seconds = 45,
            pattern = "aimed_fan",
            fire_interval = 38,
            bullet_speed = 3.2,
            is_spell = false,
            time_spell = false,
        },
        sanae_nonspell = {
            id = "sanae_nonspell",
            display_name = "东风谷早苗·非符",
            legacy_id = "Sanae:Normal#nonspell",
            hp = 620,
            duration_seconds = 45,
            pattern = "wind",
            fire_interval = 30,
            bullet_speed = 2.7,
            is_spell = false,
            time_spell = false,
        },
        marisa_nonspell = {
            id = "marisa_nonspell",
            display_name = "雾雨魔理沙·非符",
            legacy_id = "Marisa:Normal#nonspell",
            hp = 650,
            duration_seconds = 45,
            pattern = "fan",
            fire_interval = 28,
            bullet_speed = 3.0,
            is_spell = false,
            time_spell = false,
        },
        spirit_seal = {
            id = "spirit_seal",
            display_name = "灵符「灵想封印」",
            legacy_id = "Reimu:Normal#灵符「灵想封印」",
            hp = 900,
            duration_seconds = 60,
            pattern = "seal",
            fire_interval = 22,
            bullet_speed = 2.6,
            is_spell = true,
            time_spell = true,
            spell_bonus = 1000,
        },
        yin_yang_jewel = {
            id = "yin_yang_jewel",
            display_name = "玉符「阴阳大宝玉」",
            legacy_id = "Reimu:Normal#玉符「阴阳大宝玉」",
            hp = 1050,
            duration_seconds = 75,
            pattern = "spiral",
            fire_interval = 18,
            bullet_speed = 2.4,
            is_spell = true,
            time_spell = true,
            spell_bonus = 1200,
        },
        four_direction_formation = {
            id = "four_direction_formation",
            display_name = "「四方阴阳封魔阵」",
            legacy_id = "Reimu:Normal#「四方阴阳封魔阵」",
            hp = 1250,
            duration_seconds = 75,
            pattern = "cross",
            fire_interval = 20,
            bullet_speed = 3.0,
            is_spell = true,
            time_spell = true,
            spell_bonus = 1400,
        },
    },
}

-- THlib's standard enemy.lua exposes eighteen ordinary styles. Keep them as
-- separate project-owned targets so the enemy practice menu can exercise the
-- original sprite sheet instead of collapsing every entry into one fairy.
local legacy_enemy_patterns = { "aimed", "fan", "spiral", "wind", "aimed_fan", "ritual" }
for style = 1, 18 do
    local id = string.format("legacy_enemy_style_%02d", style)
    if not ContentCatalog.enemies[id] then
        ContentCatalog.enemies[id] = {
            id = id,
            legacy_id = "Thlib:enemy" .. style,
            display_name = string.format("THlib Enemy Style %02d", style),
            hp = 30 + style * 8,
            radius = style >= 7 and 22 or 16,
            fire_pattern = legacy_enemy_patterns[((style - 1) % #legacy_enemy_patterns) + 1],
            fire_interval = 52 + (style % 5) * 9,
            bullet_speed = 2.2 + (style % 4) * 0.25,
            drop_money = 2 + (style % 4),
            sprite = "tnr-thlib-enemy-style-" .. style,
            bullet_sprite = style % 3 == 0 and "tnr-thlib-bullet-butterfly"
                or (style % 3 == 1 and "tnr-thlib-bullet-arrow" or "tnr-thlib-bullet-ball"),
        }
    end
end

-- Flatten the generated stage catalog for the training selector and the
-- roguelike encounter picker.  The source_stage and difficulty fields are
-- retained so the UI can explain where each real wave came from.
for _, stage in ipairs(LegacyEnemyWaves) do
    for _, wave in ipairs(stage.waves or {}) do
        local entry = {
            id = wave.id,
            display_name = wave.name,
            legacy_stage = stage.source_stage,
            difficulty = wave.difficulty,
            duration_frames = wave.duration_frames,
            duration_seconds = wave.duration_seconds,
            classes = wave.classes,
            members = wave.members,
            legacy_exact = true,
        }
        ContentCatalog.enemy_waves[entry.id] = entry
    end
end

-- The original activity contains many editor-generated cards. Keep stable
-- metadata here so the training UI and seeded room selector can resolve the
-- exact native boss class/card slot.
local imported_cards = {
    { "illusion_fraser_vortex", "错觉「弗雷泽的小漩涡」", 1000, 50, "vortex", true },
    { "illusion_windmill", "错舌「吱呦呦吱呦吱呦风车」", 1500, 60, "windmill", true },
    { "illusion_light_seal", "幻化「幻光封印」", 1000, 50, "light_seal", true },
    { "illusion_spread_barrier", "幻化「扩散结界」", 1000, 50, "barrier", true },
    { "illusion_galaxy_arm", "幻化「星河旋臂」", 1000, 50, "orbit", true },
    { "illusion_love_spark", "幻化「恋色spark的悲哀」", 1000, 50, "starburst", true },
    { "illusion_wind_god_ritual", "幻化「风神忍者的仪式」", 1000, 50, "ritual", true },
    { "illusion_miracle_windblade", "幻化「奇迹在风中飘荡」", 1000, 50, "wind", true },
    { "illusion_seven_flavor", "幻化「七味阳炎」", 1000, 50, "fan", true },
    { "illusion_night_hide", "幻化「夜盲型神隐秘术」", 1000, 30, "seal", true },
    { "peace_flame", "幻化酒吞童子「平安的烈焰」", 1200, 60, "ritual", true },
    { "left_hand_ruin", "幻化茨木童子「灭世之左手」", 1200, 60, "cross", true },
    { "gray_wing_magician", "幻化鸦天狗「灰翼魔术师」", 1300, 60, "wind", true },
    { "tree_spirit_yahoo", "幻化木灵「激动Yahoo——！」", 1300, 60, "spiral", true },
    { "flower_fern_tower", "幻化球女「花色卷柏楼」", 1300, 60, "fan", true },
    { "artemis_ray", "借物「阿尔忒尼斯超级射线」", 1500, 70, "laser", true },
    { "sacred_frog_ritual", "长生咒「正一位蛙大明神的加护」", 100, 30, "ritual", true },
    { "nine_tail_dimension", "「穿梭次元的九条稻荷」", 2000, 70, "spiral", true },
    { "pure_malice_crystal", "杀符「纯真无垢的恶意结晶」", 4000, 120, "cross", true },
    { "larva_eternity", "虫符「Etanity Larva」", 750, 60, "spiral", true },
    { "harden", "蛹符「Harden」", 580, 60, "seal", true },
    { "sleep_powder", "粼符「Sleep Powder」", 800, 60, "wind", true },
    { "cithaerias_pyropina", "蝶符「Cithaerias Pyropina」", 1000, 60, "fan", true },
    { "narrow_vision", "夜符「Narrow Vision」", 600, 60, "seal", true },
    { "birds_ensemble", "歌符「群鸟合奏」", 850, 75, "fan", true },
    { "siren_song", "「海妖之歌」", 900, 75, "wind", true },
    { "spirit_thought_seal", "灵符「灵想封印」", 900, 60, "seal", true },
    { "yin_yang_treasure", "玉符「阴阳大宝玉」", 1000, 75, "spiral", true },
    { "four_way_exorcism", "「四方阴阳封魔阵」", 1100, 75, "formation", true },
    { "anti_aircraft_fire", "魔符「Anti-aircraft Fire」", 850, 60, "aimed_fan", true },
    { "mushroom_growth", "菌符「蘑菇滋生剂」", 950, 75, "spiral", true },
    { "luminous_organs", "灯符「Luminous Organs」", 550, 60, "ritual", true },
}

for _, entry in ipairs(imported_cards) do
    local id, name, hp, duration, pattern, is_spell = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
    if not ContentCatalog.cards[id] then
        ContentCatalog.cards[id] = {
            id = id,
            display_name = name,
            legacy_id = "activity7:" .. id,
            hp = hp,
            duration_seconds = duration,
            pattern = pattern,
            fire_interval = pattern == "laser" and 42 or 24,
            bullet_speed = pattern == "laser" and 3.2 or 2.8,
            is_spell = is_spell,
            time_spell = id == "sacred_frog_ritual" or id == "four_way_exorcism",
            spell_bonus = hp,
            background_asset = "tnr-legacy-void-bg",
            effect_asset = "tnr-legacy-void-fx",
            boss_frames = {
                "tnr-legacy-void-boss-1", "tnr-legacy-void-boss-2",
                "tnr-legacy-void-boss-3", "tnr-legacy-void-boss-4",
                "tnr-legacy-void-boss-5", "tnr-legacy-void-boss-6",
                "tnr-legacy-void-boss-7", "tnr-legacy-void-boss-8",
                "tnr-legacy-void-boss-9", "tnr-legacy-void-boss-10",
                "tnr-legacy-void-boss-11", "tnr-legacy-void-boss-12",
            },
        }
    end
end

local function import_editor_card_metadata()
    if not io or not io.open then return end
    local file = io.open("legacy/source/activity7/_editor_output.lua", "rb")
    if not file then
        file = io.open("game/legacy/source/activity7/_editor_output.lua", "rb")
    end
    if not file then return end
    local pattern_names = {
        "aimed", "fan", "spiral", "wind", "seal", "cross", "ritual",
        "radial", "orbit", "curtain", "rain", "burst", "laser",
    }
    local current_boss = "legacy_boss"
    local occurrence = {}
    local card_slots = {}
    local line_number = 0
    for line in file:lines() do
        line_number = line_number + 1
        local boss_id = line:match('^_editor_class%["([^\"]+)"%]=Class%(boss%)')
        if boss_id then current_boss = boss_id end
        if line:match('^table%.insert%(_editor_class%["[^\"]+"%]%.cards,') then
            card_slots[current_boss] = (card_slots[current_boss] or 0) + 1
        end
        local name, t1, t2, t3, hp, drop, extra = line:match('_tmp_sc=boss%.card%.New%("([^\"]*)",([^,]+),([^,]+),([^,]+),([^,]+),%{([^}]*)%},([^%)]+)%)')
        -- `_lico_boss` and its `test` cards are editor fixtures, not playable
        -- content.  Do not expose them through practice or seeded rooms.
        local is_test_entry = current_boss:sub(1, 1) == "_" or name == "test"
        if hp and not is_test_entry then
            extra = tostring(extra or ""):match("^%s*(.-)%s*$")
            local spell = name ~= ""
            local t1_seconds, t2_seconds, t3_seconds = tonumber(t1), tonumber(t2), tonumber(t3)
            local time_spell = spell and t1_seconds and t2_seconds and t3_seconds
                and t1_seconds == t2_seconds and t2_seconds == t3_seconds
            occurrence[current_boss] = (occurrence[current_boss] or 0) + 1
            local ordinal = occurrence[current_boss]
            local id = string.format("legacy_card_%05d", line_number)
            if not ContentCatalog.cards[id] then
                local numeric_hp = tonumber(hp) or 600
                local duration = tonumber(t3) or 60
                local pattern = pattern_names[((line_number + ordinal - 1) % #pattern_names) + 1]
                local display_name = spell and name or (current_boss .. " Nonspell " .. ordinal)
                ContentCatalog.cards[id] = {
                    id = id,
                    display_name = display_name,
                    legacy_id = current_boss .. "#" .. (spell and name or "nonspell"),
                    legacy_boss = current_boss,
                    legacy_card_slot = (card_slots[current_boss] or 0) + 1,
                    legacy_source_line = line_number,
                    legacy_exact = true,
                    hp = numeric_hp,
                    duration_seconds = duration,
                    pattern = pattern,
                    fire_interval = 18 + (line_number % 24),
                    bullet_speed = 2.2 + (line_number % 7) * 0.16,
                    is_spell = spell,
                    time_spell = time_spell == true,
                    survival = extra == "true",
                    spell_bonus = numeric_hp,
                    background_asset = "tnr-legacy-void-bg",
                    effect_asset = "tnr-legacy-void-fx",
                    boss_frames = {
                        "tnr-legacy-void-boss-1", "tnr-legacy-void-boss-2",
                        "tnr-legacy-void-boss-3", "tnr-legacy-void-boss-4",
                        "tnr-legacy-void-boss-5", "tnr-legacy-void-boss-6",
                        "tnr-legacy-void-boss-7", "tnr-legacy-void-boss-8",
                        "tnr-legacy-void-boss-9", "tnr-legacy-void-boss-10",
                        "tnr-legacy-void-boss-11", "tnr-legacy-void-boss-12",
                    },
                }
            end
        end
    end
    file:close()
end

import_editor_card_metadata()

local imported_visual_sets = {
    { background = "tnr-legacy-void-bg", effect = "tnr-legacy-void-fx", frames = {
        "tnr-legacy-void-boss-1", "tnr-legacy-void-boss-2", "tnr-legacy-void-boss-3",
        "tnr-legacy-void-boss-4", "tnr-legacy-void-boss-5", "tnr-legacy-void-boss-6",
        "tnr-legacy-void-boss-7", "tnr-legacy-void-boss-8", "tnr-legacy-void-boss-9",
        "tnr-legacy-void-boss-10", "tnr-legacy-void-boss-11", "tnr-legacy-void-boss-12",
    } },
    { background = "tnr-legacy-buduc-bg", effect = "tnr-legacy-sf-effect", frames = { "tnr-legacy-qxs-boss" } },
    { background = "tnr-sanae-sc-bg1", effect = "tnr-legacy-charge", frames = { "tnr-legacy-stupid-boss" } },
}
for _, card in pairs(ContentCatalog.cards) do
    if card.legacy_source_line then
        local visual = imported_visual_sets[(card.legacy_source_line % #imported_visual_sets) + 1]
        card.background_asset = visual.background
        card.effect_asset = visual.effect
        card.boss_frames = visual.frames
    end
end

-- Stable aliases used by the project menus. These point at the exact card
-- slots in the generated reference classes (movement entries are included in
-- the slot numbering, just as boss.lua consumes them).
local native_aliases = {
    reimu_nonspell = { boss = "Reimu:Normal", slot = 2, combat = true },
    spirit_seal = { boss = "Reimu:Normal", slot = 4, combat = true },
    yin_yang_jewel = { boss = "Reimu:Normal", slot = 9, combat = true },
    four_direction_formation = { boss = "Reimu:Normal", slot = 11, combat = true },
    marisa_nonspell = { boss = "Marisa:Normal", slot = 2, combat = true },
    anti_aircraft_fire = { boss = "Marisa:Normal", slot = 4, combat = true },
    -- Marisa's exported card list includes a dialogue entry and a movement
    -- entry immediately before this spell.  The spell itself is slot 9;
    -- using slot 8 starts the movement object and produces an empty room
    -- without bullets or a boss HP bar.
    mushroom_growth = { boss = "Marisa:Normal", slot = 9, combat = true },
}
for id, alias in pairs(native_aliases) do
    local card = ContentCatalog.cards[id]
    if card then
        card.legacy_boss = alias.boss
        card.legacy_card_slot = alias.slot
        card.legacy_exact = true
        card.legacy_expected_combat = alias.combat == true
    end
end

local pattern_bullet_sprites = {
    aimed = "tnr-thlib-bullet-gun",
    aimed_fan = "tnr-thlib-bullet-gun",
    fan = "tnr-thlib-bullet-butterfly",
    spiral = "tnr-thlib-bullet-ball",
    wind = "tnr-thlib-bullet-ellipse",
    seal = "tnr-thlib-bullet-square",
    cross = "tnr-thlib-bullet-star",
    ritual = "tnr-thlib-bullet-arrow",
    laser = "tnr-thlib-bullet-void",
    radial = "tnr-thlib-bullet-star",
    orbit = "tnr-thlib-bullet-ball",
    curtain = "tnr-thlib-bullet-ellipse",
    rain = "tnr-thlib-bullet-butterfly",
    burst = "tnr-thlib-bullet-arrow",
    vortex = "tnr-thlib-bullet-ball",
    windmill = "tnr-thlib-bullet-butterfly",
    light_seal = "tnr-thlib-bullet-square",
    barrier = "tnr-thlib-bullet-ellipse",
    starburst = "tnr-thlib-bullet-star",
    formation = "tnr-thlib-bullet-star",
}
local bullet_render_scales = {
    ["tnr-thlib-bullet-arrow"] = 0.6,
    ["tnr-thlib-bullet-gun"] = 0.4,
    ["tnr-thlib-bullet-void"] = 0.4,
    ["tnr-thlib-bullet-butterfly"] = 0.7,
    ["tnr-thlib-bullet-square"] = 0.8,
    ["tnr-thlib-bullet-ball"] = 0.75,
    ["tnr-thlib-bullet-mildew"] = 0.4,
    ["tnr-thlib-bullet-ellipse"] = 0.801,
    ["tnr-thlib-bullet-star"] = 0.998,
}
for _, card in pairs(ContentCatalog.cards) do
    if not card.bullet_sprite then
        card.bullet_sprite = pattern_bullet_sprites[card.pattern] or "tnr-thlib-bullet-gun"
    end
    card.bullet_render_scale = card.bullet_render_scale or bullet_render_scales[card.bullet_sprite] or 0.4
end
for _, enemy in pairs(ContentCatalog.enemies) do
    enemy.bullet_render_scale = enemy.bullet_render_scale or bullet_render_scales[enemy.bullet_sprite] or 0.4
end

return ContentCatalog
