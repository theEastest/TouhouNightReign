-- First-version equipment definitions from 第一版装备指南.
-- These are data definitions only; advanced runtime hooks consume the metadata
-- progressively without changing the public equipment IDs.
local WeaponDefinition = require("tnr.equipment.weapon_definition")
local SupportDefinition = require("tnr.equipment.support_definition")
local ModifierDefinition = require("tnr.equipment.modifier_definition")

local HIGH = { HIGH_WEAPON = true }
local LOW = { LOW_WEAPON = true }
local SUPPORT = { SUPPORT = true }

local function weapon(spec)
    spec.allowed_slots = spec.allowed_slots or (spec.slot == "LOW" and LOW or HIGH)
    spec.active_modes = spec.active_modes or { [spec.slot or "HIGH"] = true }
    spec.display_name = spec.display_name_zh
    return WeaponDefinition.new(spec)
end

local function support(spec)
    spec.allowed_slots = SUPPORT
    spec.display_name = spec.display_name_zh
    return SupportDefinition.new(spec)
end

local function modifier(spec)
    spec.display_name = spec.display_name_zh
    return ModifierDefinition.new(spec)
end

local definitions = {
    -- Hakurei weapons: A3 is intentionally a LOW weapon per the confirmed rule.
    weapon({
        weapon_id = "hakurei_sealing_needle", display_name_zh = "封魔针",
        display_name_en = "Sealing Needle", slot = "HIGH", rarity = "COMMON", weight = 16,
        description = "高速发射成对的封魔针。",
        fire_interval = 4, count = 2, damage = 2.0, projectile_speed = 24,
        projectile_type = "reimu_bullet_red", penetration = 0, targeting = "NONE",
        pattern = "straight", metadata = { pattern = "straight", projectile_count = 2, spread = 0 },
        tags = { "needle", "straight", "rapid" },
    }),
    weapon({
        weapon_id = "hakurei_persuasion_needle", display_name_zh = "贯刺",
        display_name_en = "Piercing Needle", slot = "HIGH", rarity = "RARE", weight = 22,
        description = "能贯穿一个敌人的高速灵针。",
        fire_interval = 5, count = 2, damage = 2.6, projectile_speed = 28,
        projectile_type = "reimu_bullet_red", penetration = 1, targeting = "NONE",
        pattern = "straight", metadata = { pattern = "straight", projectile_count = 2, spread = 0 },
        tags = { "needle", "straight", "penetration" },
    }),
    weapon({
        weapon_id = "hakurei_dream_sealing_needle", display_name_zh = "妖怪封针",
        display_name_en = "Yokai-Sealing Needle", slot = "LOW", rarity = "LEGENDARY", weight = 30,
        description = "低速发射的强力封魔针，连续命中同一目标会不断叠加伤害。",
        fire_interval = 5, count = 2, damage = 3.2, projectile_speed = 28,
        projectile_type = "reimu_bullet_red", penetration = 0, targeting = "NONE",
        pattern = "straight", metadata = {
            pattern = "straight", projectile_count = 2, spread = 0,
            legendary_effect = "sealing_streak",
            streak_step_hits = 10, streak_damage_step = 0.01,
            streak_max_bonus = 1.0, streak_timeout_frames = 120,
        },
        tags = { "needle", "straight", "legendary", "stacking" },
    }),

    -- Kirisame weapons: B2/B3 are heavy LOW weapons.
    weapon({
        weapon_id = "marisa_magic_missile", display_name_zh = "魔法飞弹",
        display_name_en = "Magic Missile", slot = "HIGH", rarity = "COMMON", weight = 18,
        description = "发射稳定的双联魔法飞弹。",
        fire_interval = 6, count = 2, damage = 3.0, projectile_speed = 20,
        projectile_type = "marisa_bullet", penetration = 0, targeting = "NONE",
        pattern = "straight", metadata = { pattern = "straight", projectile_count = 2, spread = 0 },
        tags = { "magic", "missile", "straight" },
    }),
    weapon({
        weapon_id = "marisa_earthlight_ray", display_name_zh = "地光射线",
        display_name_en = "Earthlight Ray", slot = "LOW", rarity = "RARE", weight = 26,
        description = "周期发射短时贯穿激光。",
        fire_interval = 12, damage = 0.9, projectile_speed = 0,
        projectile_type = "MarisaLaser", penetration = 0, targeting = "FORWARD",
        pattern = "beam", metadata = {
            pattern = "beam", beam = true, beam_duration_frames = 8,
            damage_per_tick = 0.9, tick_interval = 2, penetration = "INFINITE",
        },
        tags = { "laser", "beam", "penetration" },
    }),
    weapon({
        weapon_id = "marisa_master_spark_weapon", display_name_zh = "极限火花",
        display_name_en = "Limit Spark", slot = "LOW", rarity = "LEGENDARY", weight = 38,
        description = "光束成功命中敌人时，下一个光束会概率变成小型极限火花。",
        fire_interval = 6, damage = 1.0, projectile_speed = 0,
        projectile_type = "marisa_spark", penetration = 0, targeting = "FORWARD",
        pattern = "beam", metadata = {
            pattern = "beam", beam = true, alternate_fire = "mini_master_spark",
            transform_chance = 0.10, transform_roll = "per_beam_activation",
            mini_duration_frames = 30, mini_damage_multiplier = 3.0,
            mini_penetration = "INFINITE", mini_persistent_collision = true,
        },
        tags = { "laser", "legendary", "alternate_fire" },
    }),

    -- Kochiya weapons: C3 is the heavy LOW field weapon.
    weapon({
        weapon_id = "sanae_sky_serpent", display_name_zh = "天空之蛇",
        display_name_en = "Sky Serpent", slot = "HIGH", rarity = "COMMON", weight = 18,
        description = "发射具有弱追踪能力的风刃。",
        fire_interval = 7, count = 2, damage = 2.4, projectile_speed = 16,
        projectile_type = "sanae_wind2", penetration = 0, targeting = "NEAREST_ENEMY",
        pattern = "straight", metadata = {
            pattern = "straight", projectile_count = 2, spread = 0,
            homing = true, homing_strength = "WEAK", homing_turn_ratio = 0.5,
            max_tracking_frames = 90, lose_target_behavior = "LAST_DIRECTION",
        },
        tags = { "wind", "homing" },
    }),
    weapon({
        weapon_id = "sanae_cobalt_spread", display_name_zh = "钴蓝散射",
        display_name_en = "Cobalt Spread", slot = "HIGH", rarity = "RARE", weight = 24,
        description = "向前方扇形释放五枚风弹。",
        fire_interval = 9, count = 5, damage = 2.8, projectile_speed = 17,
        projectile_type = "sanae_wind", penetration = 0, targeting = "NONE",
        pattern = "spread", metadata = {
            pattern = "spread", projectile_count = 5, spread_angles = { -20, -10, 0, 10, 20 },
        },
        tags = { "wind", "spread", "crowd_clear" },
    }),
    weapon({
        weapon_id = "sanae_yasaka_divine_wind", display_name_zh = "八坂神风",
        display_name_en = "Yasaka's Divine Wind", slot = "LOW", rarity = "LEGENDARY", weight = 32,
        description = "风刃命中后留下持续伤害旋风。",
        fire_interval = 10, count = 2, damage = 3.4, projectile_speed = 18,
        projectile_type = "sanae_wind", penetration = 0, targeting = "NONE",
        pattern = "straight", metadata = {
            pattern = "straight", projectile_count = 2, spread = 0,
            legendary_effect = "wind_field", field_duration_frames = 45,
            field_damage_interval = 10, field_radius = 28, max_active_fields = 6,
        },
        tags = { "wind", "legendary", "area_damage" },
    }),

    -- Self modifiers.
    modifier({
        modifier_id = "self_duplex_barrier", display_name_zh = "二重结界",
        display_name_en = "Duplex Barrier", modifier_type = "SELF_MODIFIER", rarity = "RARE",
        description = "每轮射击追加两枚侧向低伤弹。",
        metadata = { runtime_effect = "volley", extra_projectile_offsets = { -10, 10 },
            allow_legendary_trigger = true, no_recursive_trigger = true },
        tags = { "self", "weapon_fire" },
    }),
    modifier({
        modifier_id = "self_giant_yinyang_projectile", display_name_zh = "狂放封玉",
        display_name_en = "Giant Yin-Yang Projectile", modifier_type = "SELF_MODIFIER", rarity = "RARE",
        description = "弹体更大、更强，但速度稍慢。",
        metadata = { runtime_effect = "projectile_scale", projectile_scale = 1.30,
            hitbox_scale = 1.30, damage_multiplier = 1.10, speed_multiplier = 0.70,
            visual_scale_cap = 3, hitbox_scale_cap = 2 },
        tags = { "self", "projectile" },
    }),
    modifier({
        modifier_id = "self_high_speed_casting", display_name_zh = "高速咏唱",
        display_name_en = "High-Speed Casting", modifier_type = "SELF_MODIFIER", rarity = "COMMON",
        description = "提高射速，但降低单发伤害。",
        metadata = { runtime_effect = "cast_speed_damage", fire_interval_multiplier = 0.75,
            damage_multiplier = 0.85, min_fire_interval = 1 },
        tags = { "self", "weapon" },
    }),
    modifier({
        modifier_id = "self_magic_penetration", display_name_zh = "风祝贯通",
        display_name_en = "Magic Penetration", modifier_type = "SELF_MODIFIER", rarity = "COMMON",
        description = "所有自身弹体获得额外穿透，但是伤害下降为原有的70%。",
        metadata = { runtime_effect = "penetration_bonus", penetration_bonus = 1,
            damage_multiplier = 0.70, infinite_penetration_unchanged = true },
        tags = { "self", "penetration" },
    }),
    modifier({
        modifier_id = "self_homing_formula", display_name_zh = "诱导法",
        display_name_en = "Homing Formula", modifier_type = "SELF_MODIFIER", rarity = "RARE",
        description = "让直射弹获得弱追踪能力。",
        metadata = { runtime_effect = "homing_formula", direct_targeting = "NEAREST_ENEMY",
            already_homing_turn_multiplier = 1.20 },
        tags = { "self", "targeting" },
    }),
    modifier({
        modifier_id = "self_afterglow", display_name_zh = "短期记忆",
        display_name_en = "Afterglow", modifier_type = "SELF_MODIFIER", rarity = "RARE",
        description = "每第10轮射击会延迟复制一次，并获得短暂无敌。",
        metadata = { runtime_effect = "afterglow", fire_threshold = 10,
            delay_frames = 10, copied_damage_multiplier = 1.0,
            player_invincibility = true, pending_fires_clear_on_exit = true },
        tags = { "self", "delayed_fire" },
    }),

    -- Support systems. The high/low attack data remains local to the support;
    -- no additional equippable weapon definitions are created for these attacks.
    support({
        support_id = "support_hakurei_yinyang_orb", display_name_zh = "阴阳玉",
        display_name_en = "Yin-Yang Orb", rarity = "COMMON", weight = 24,
        description = "四枚阴阳玉，高速追踪、低速集中。",
        entity_count = 4, activation_mode = "ALWAYS", attack_mode = "INDEPENDENT",
        formation = { type = "FOLLOW", radius = 24 }, metadata = {
            high_projectile_type = "reimu_bullet_blue", high_projectile_count = 1,
            high_projectile_speed = 8, high_damage = 1.0, high_targeting = "NEAREST_ENEMY",
            low_projectile_type = "reimu_bullet_orange", low_projectile_count = 2,
            low_projectile_speed = 24, low_damage = 0.30, low_targeting = "NONE",
            damage_normalized_by_count = true,
        }, tags = { "support", "homing" },
    }),
    support({
        support_id = "support_marisa_orreries_sun", display_name_zh = "行星仪",
        display_name_en = "Orreries Sun", rarity = "RARE", weight = 30,
        description = "三枚轨道魔导器提供激光与飞弹支援。",
        entity_count = 3, activation_mode = "ALWAYS", attack_mode = "INDEPENDENT",
        formation = { type = "ORBIT", high_radius = 42, low_radius = 28 }, metadata = {
            high_projectile_type = "MarisaLaser", high_projectile_count = 1,
            high_damage = 0.75, high_projectile_speed = 0, high_beam = true,
            low_projectile_type = "marisa_missile", low_projectile_count = 1,
            low_projectile_speed = 20, low_damage = 1.0, low_targeting = "NONE",
            damage_normalized_by_count = true,
        }, tags = { "support", "orbit" },
    }),
    support({
        support_id = "support_sanae_snakeskin_amulet", display_name_zh = "长蛇戒指",
        display_name_en = "Shed Snakeskin Amulet", rarity = "RARE", weight = 22,
        description = "两枚高质量风祝子机提供精准风刃。",
        entity_count = 2, activation_mode = "ALWAYS", attack_mode = "INDEPENDENT",
        formation = { type = "FOLLOW", radius = 30 }, metadata = {
            high_projectile_type = "sanae_wind2", high_projectile_count = 1,
            high_projectile_speed = 16, high_damage = 1.5, high_targeting = "NEAREST_ENEMY",
            high_homing = true, low_projectile_type = "sanae_wind2",
            low_projectile_count = 2, low_projectile_speed = 18, low_damage = 0.75,
            low_targeting = "NONE", damage_normalized_by_count = true,
        }, tags = { "support", "wind", "homing" },
    }),
    support({
        support_id = "support_hakurei_ward_array", display_name_zh = "护身法",
        display_name_en = "Hakurei Ward Array", rarity = "RARE", weight = 18,
        description = "不主动攻击，周期产生近身消弹结界。",
        entity_count = 4, activation_mode = "PASSIVE", attack_mode = "NONE",
        formation = { type = "FOLLOW", radius = 24 }, metadata = {
            runtime_effect = "support_bullet_clear", clear_interval_frames = 180,
            clear_radius_ratio = 2.0, boss_damage = false,
        }, tags = { "support", "passive", "bullet_clear" },
    }),

    -- Support modifiers. High/low auto-target modules intentionally coexist.
    modifier({
        modifier_id = "support_modifier_front_formation", display_name_zh = "置于阵前",
        display_name_en = "Forward Formation", modifier_type = "SUPPORT_MODIFIER", rarity = "COMMON",
        description = "所有子机集中到自机前方一排。",
        conflict_group = "support_formation_override",
        metadata = { runtime_effect = "front_concentration", formation = "FRONT" },
        tags = { "support", "formation" },
    }),
    modifier({
        modifier_id = "support_modifier_orbit_formation", display_name_zh = "护置身侧",
        display_name_en = "Orbital Formation", modifier_type = "SUPPORT_MODIFIER", rarity = "RARE",
        description = "所有子机围绕自机持续环绕。",
        conflict_group = "support_formation_override",
        metadata = { runtime_effect = "orbit_formation", formation = "ORBIT", high_radius = 42, low_radius = 28 },
        tags = { "support", "formation" },
    }),
    modifier({
        modifier_id = "support_modifier_high_phantom_charge", display_name_zh = "幻影冲锋",
        display_name_en = "Phantom Charge", modifier_type = "SUPPORT_MODIFIER", rarity = "COMMON",
        description = "高速模式下子机优先位移到玩家前方±30°范围内最近的有效敌人下方进行攻击。",
        conflict_group = "support_target_high",
        metadata = { runtime_effect = "auto_target", active_mode = "HIGH",
            target = "NEAREST_ENEMY", interpolation = "SMOOTH" },
        tags = { "support", "targeting", "high_only" },
    }),
    modifier({
        modifier_id = "support_modifier_low_phantom_edge", display_name_zh = "神影无锋",
        display_name_en = "Phantom Edge", modifier_type = "SUPPORT_MODIFIER", rarity = "COMMON",
        description = "低速模式下子机优先位移到玩家前方±30°范围内最近的有效敌人下方进行攻击。",
        conflict_group = "support_target_low",
        metadata = { runtime_effect = "auto_target", active_mode = "LOW",
            target = "NEAREST_ENEMY", interpolation = "SMOOTH" },
        tags = { "support", "targeting", "low_only" },
    }),
    modifier({
        modifier_id = "support_modifier_barrier_pulse", display_name_zh = "结界脉冲",
        display_name_en = "Barrier Pulse", modifier_type = "SUPPORT_MODIFIER", rarity = "RARE",
        description = "子机周期释放小范围消弹脉冲。",
        metadata = { runtime_effect = "staggered_bullet_clear", cycle_frames = 240,
            clear_radius_ratio = 2.0, local_only = true, boss_damage = false },
        tags = { "support", "bullet_clear" },
    }),
}

return { definitions = definitions }
