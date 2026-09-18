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
}
