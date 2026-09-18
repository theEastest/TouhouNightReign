-- Project-owned paths for the extracted legacy bundle. These are data paths,
-- not Lua module search paths; native integration can opt into them later.
return {
    source = {
        thlib = "game/legacy/source/data/Thlib",
        activity = "game/legacy/source/activity7",
        generated_stage = "game/legacy/source/activity7/_editor_output.lua",
    },
    assets = {
        thlib = "game/legacy/assets/data",
        activity = "game/legacy/assets/activity7",
    },
    modules = {
        bullet = "game/legacy/source/data/Thlib/bullet/bullet.lua",
        bullet_ex = "game/legacy/source/data/Thlib/BulletEx.lua",
        laser = "game/legacy/source/data/Thlib/laser/laser.lua",
        enemy = "game/legacy/source/data/Thlib/enemy/enemy.lua",
        boss = "game/legacy/source/data/Thlib/enemy/boss.lua",
        spellcard = "game/legacy/source/data/Thlib/background/spellcard/spellcard.lua",
    },
    helpers = {
        "karl_basic_bullets.lua",
        "karl_bullet_initializer.lua",
        "karl_bullet_shapes.lua",
        "karl_bullet_task.lua",
        "karl_acc_controller.lua",
        "karl_interval_line.lua",
        "karl_nointersection_generation.lua",
        "karl_nointersection_generation_v2.lua",
    },
}
