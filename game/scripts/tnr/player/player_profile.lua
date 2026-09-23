-- Project-owned playable character data. The numeric values mirror the
-- movement and shot rhythm of the legacy Reimu implementation, while the
-- actual image files remain replaceable project assets.
return {
    reimu = {
        id = "reimu",
        display_name = "博丽灵梦",
        normal_speed = 4.5,
        focused_speed = 2.25,
        hitbox_radius = 3,
        shot_interval = 4,
        normal_shot = {
            { offset_x = -10, angle = 90, speed = 24, damage = 2.0, radius = 5 },
            { offset_x = 10, angle = 90, speed = 24, damage = 2.0, radius = 5 },
        },
        focused_shot = {
            { offset_x = -3, angle = 90, speed = 24, damage = 2.5, radius = 4 },
            { offset_x = 3, angle = 90, speed = 24, damage = 2.5, radius = 4 },
        },
        bomb = {
            duration = 90,
            damage = 180,
            invulnerability = 360,
            max_charge_frames = 180,
            charged_duration = 120,
            charged_damage = 300,
            charged_invulnerability = 480,
        },
        art = {
            sprite_sheet = "game/assets/players/reimu/reimu.png",
            barrier = "game/assets/players/reimu/reimu_kekkai.png",
            bomb_effect = "game/assets/players/reimu/reimu_bomb_ef.png",
            bullet_effect = "game/assets/players/reimu/reimu_orange_eff.png",
        },
    },
    -- Kirisame Marisa: the fast, wide-spread character. Movement mirrors the
    -- reference implementation (hspeed 5). The missile/laser values keep the
    -- fallback runtime playable when the native THlib player is unavailable.
    marisa = {
        id = "marisa",
        display_name = "雾雨魔理沙",
        normal_speed = 5.0,
        focused_speed = 2.0,
        hitbox_radius = 3,
        shot_interval = 5,
        normal_shot = {
            { offset_x = -12, angle = 90, speed = 22, damage = 2.2, radius = 5 },
            { offset_x = 12, angle = 90, speed = 22, damage = 2.2, radius = 5 },
        },
        focused_shot = {
            { offset_x = -4, angle = 90, speed = 24, damage = 2.6, radius = 4 },
            { offset_x = 4, angle = 90, speed = 24, damage = 2.6, radius = 4 },
        },
        bomb = {
            duration = 90,
            damage = 200,
            invulnerability = 360,
            max_charge_frames = 180,
            charged_duration = 120,
            charged_damage = 320,
            charged_invulnerability = 480,
        },
        art = {
            sprite_sheet = "game/assets/players/marisa/marisa.png",
            barrier = "game/assets/players/marisa/marisa_spark.png",
            bomb_effect = "game/assets/players/marisa/marisa_bomb_ef.png",
            bullet_effect = "game/assets/players/marisa/marisa_hit_par.png",
        },
    },
    -- Kochiya Sanae: homing wind shots with reference movement (hspeed 4.5).
    sanae = {
        id = "sanae",
        display_name = "东风谷早苗",
        normal_speed = 4.5,
        focused_speed = 2.0,
        hitbox_radius = 3,
        shot_interval = 5,
        normal_shot = {
            { offset_x = -10, angle = 90, speed = 20, damage = 2.1, radius = 5 },
            { offset_x = 10, angle = 90, speed = 20, damage = 2.1, radius = 5 },
        },
        focused_shot = {
            { offset_x = -3, angle = 90, speed = 22, damage = 2.4, radius = 4 },
            { offset_x = 3, angle = 90, speed = 22, damage = 2.4, radius = 4 },
        },
        bomb = {
            duration = 90,
            damage = 170,
            invulnerability = 360,
            max_charge_frames = 180,
            charged_duration = 120,
            charged_damage = 280,
            charged_invulnerability = 480,
        },
        art = {
            sprite_sheet = "game/assets/players/sanae/sanae.png",
            barrier = "game/assets/players/sanae/sanae_barrier.png",
            bomb_effect = "game/assets/players/sanae/sanae_bomb_ef.png",
            bullet_effect = "game/assets/players/sanae/sanae_eff.png",
        },
    },
}
