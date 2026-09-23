local EquipmentRegistry = require("tnr.equipment.equipment_registry")
local WeaponDefinition = require("tnr.equipment.weapon_definition")
local SupportDefinition = require("tnr.equipment.support_definition")
local ModifierDefinition = require("tnr.equipment.modifier_definition")
local RelicDefinition = require("tnr.equipment.relic_definition")
local GuideCatalog = require("tnr.equipment.guide_catalog")

local registry = EquipmentRegistry.new()
local definitions = {}

local function register(definition)
    registry:register(definition)
    definitions[definition.equipment_id or definition.weapon_id or definition.support_id or definition.modifier_id] = definition
    return definition
end

register(WeaponDefinition.new({
    weapon_id = "test_high_weapon", name = "Test High Weapon",
    display_name_zh = "测试高速武器", display_name_en = "Test High Weapon", rarity = "COMMON", weight = 2,
    test_only = true,
    fire_interval = 4, damage = 2, projectile_type = "test", projectile_speed = 20,
    active_modes = { HIGH = true }, allowed_slots = { HIGH_WEAPON = true },
    metadata = { pattern = "straight", projectile_count = 2, spread = 0 },
}))
register(WeaponDefinition.new({
    weapon_id = "test_low_weapon", name = "Test Low Weapon",
    display_name_zh = "测试低速武器", display_name_en = "Test Low Weapon", rarity = "COMMON", weight = 3,
    test_only = true,
    fire_interval = 5, damage = 3, projectile_type = "test", projectile_speed = 18,
    active_modes = { LOW = true }, allowed_slots = { LOW_WEAPON = true },
    metadata = { pattern = "fan", projectile_count = 3, spread = 12 },
}))
register(WeaponDefinition.new({
    weapon_id = "test_dual_weapon", name = "Test Dual Weapon",
    display_name_zh = "测试双模式武器", display_name_en = "Test Dual Weapon", rarity = "COMMON", weight = 2,
    test_only = true,
    fire_interval = 6, damage = 2.5, projectile_type = "test_dual", projectile_speed = 19,
    active_modes = { HIGH = true, LOW = true },
    allowed_slots = { HIGH_WEAPON = true, LOW_WEAPON = true },
    dual_mode = true,
    metadata = { high_form = "dual_high", low_form = "dual_low", projectile_count = 2, spread = 8 },
}))
register(SupportDefinition.new({
    support_id = "test_support", name = "Test Support",
    display_name_zh = "测试子机", display_name_en = "Test Support", rarity = "COMMON", weight = 4,
    test_only = true,
    entity_count = 4, activation_mode = "INDEPENDENT", attack_mode = "INDEPENDENT",
}))
register(SupportDefinition.new({
    support_id = "test_support_alt", name = "Test Support Alt",
    display_name_zh = "测试子机·改", display_name_en = "Test Support Alt", rarity = "COMMON", weight = 5,
    test_only = true,
    entity_count = 2, activation_mode = "INDEPENDENT", attack_mode = "INDEPENDENT",
}))
register(ModifierDefinition.new({
    modifier_id = "test_self_modifier", name = "Test Self Modifier",
    display_name_zh = "测试自身增益", display_name_en = "Test Self Modifier", rarity = "COMMON",
    test_only = true,
    modifier_type = "SELF_MODIFIER", conflict_group = "projectile_size",
    metadata = { runtime_effect = "projectile_scale" },
}))
register(ModifierDefinition.new({
    modifier_id = "test_self_modifier_alt", name = "Test Self Modifier Alt",
    display_name_zh = "测试自身增益·改", display_name_en = "Test Self Modifier Alt", rarity = "COMMON",
    test_only = true,
    modifier_type = "SELF_MODIFIER", conflict_group = "projectile_size",
    metadata = { runtime_effect = "volley" },
}))
register(ModifierDefinition.new({
    modifier_id = "test_support_modifier", name = "Test Support Modifier",
    display_name_zh = "测试子机增益", display_name_en = "Test Support Modifier", rarity = "COMMON",
    test_only = true,
    modifier_type = "SUPPORT_MODIFIER", conflict_group = "formation",
    metadata = { runtime_effect = "front_concentration" },
}))
register(ModifierDefinition.new({
    modifier_id = "test_support_modifier_alt", name = "Test Support Modifier Alt",
    display_name_zh = "测试子机增益·改", display_name_en = "Test Support Modifier Alt", rarity = "COMMON",
    test_only = true,
    modifier_type = "SUPPORT_MODIFIER", conflict_group = "formation",
    metadata = { runtime_effect = "periodic_bullet_clear" },
}))

local initial_high = register(WeaponDefinition.new({
    weapon_id = "reimu_initial_high_weapon", name = "Reimu High Weapon", weight = 0,
    display_name_zh = "灵梦高速射击", display_name_en = "Reimu High Shot", rarity = "COMMON",
    description = "灵梦的初始高速射击，向前方稳定发射封魔针。",
    fire_interval = 4, damage = 2, projectile_type = "reimu_normal", projectile_speed = 24,
    active_modes = { HIGH = true }, metadata = {
        legacy_profile = "reimu.normal_shot", pattern = "reimu_normal", projectile_count = 1, spread = 0,
    },
}))
local initial_low = register(WeaponDefinition.new({
    weapon_id = "reimu_initial_low_weapon", name = "Reimu Low Weapon", weight = 0,
    display_name_zh = "灵梦低速射击", display_name_en = "Reimu Low Shot", rarity = "COMMON",
    description = "灵梦的初始低速射击，集中火力向前方发射。",
    fire_interval = 4, damage = 2.5, projectile_type = "reimu_focused", projectile_speed = 24,
    active_modes = { LOW = true }, metadata = {
        legacy_profile = "reimu.focused_shot", pattern = "reimu_focused", projectile_count = 1, spread = 0,
    },
}))
local reimu_support_high = register(WeaponDefinition.new({
    weapon_id = "reimu_support_high_weapon", name = "Reimu Blue Support Weapon", weight = 0,
    display_name_zh = "灵梦子机高速射击", display_name_en = "Reimu Blue Support Shot", rarity = "COMMON",
    description = "子机在高速模式下发射的追踪灵弹。",
    fire_interval = 8, damage = 1, projectile_type = "reimu_support_blue", projectile_speed = 8,
    active_modes = { HIGH = true }, metadata = { projectile_count = 1, spread = 0, targeting = "nearest" },
}))
local reimu_support_low = register(WeaponDefinition.new({
    weapon_id = "reimu_support_low_weapon", name = "Reimu Orange Support Weapon", weight = 0,
    display_name_zh = "灵梦子机低速射击", display_name_en = "Reimu Orange Support Shot", rarity = "COMMON",
    description = "子机在低速模式下发射的直射灵弹。",
    fire_interval = 4, damage = 0.3, projectile_type = "reimu_support_orange", projectile_speed = 24,
    active_modes = { LOW = true }, metadata = { projectile_count = 1, spread = 0 },
}))
local initial_support = register(SupportDefinition.new({
    support_id = "reimu_initial_support", name = "Reimu Yin-Yang Support", weight = 0,
    display_name_zh = "阴阳玉", display_name_en = "Yin-Yang Orb", rarity = "COMMON",
    description = "灵梦的初始子机，四枚阴阳玉随玩家移动并自动攻击。",
    entity_count = 4, activation_mode = "ALWAYS", attack_mode = "INDEPENDENT",
    high_weapon_definition_id = "reimu_support_high_weapon",
    low_weapon_definition_id = "reimu_support_low_weapon",
    metadata = { legacy_profile = "reimu.supports" },
}))

-- Kirisame Marisa initial kit.
local marisa_initial_high = register(WeaponDefinition.new({
    weapon_id = "marisa_initial_high_weapon", name = "Marisa High Weapon", weight = 0,
    display_name_zh = "魔理沙高速射击", display_name_en = "Marisa High Shot", rarity = "COMMON",
    description = "魔理沙的初始高速射击，向前方发射双联魔法飞弹。",
    fire_interval = 6, damage = 3.0, projectile_type = "marisa_bullet", projectile_speed = 20,
    active_modes = { HIGH = true }, metadata = {
        legacy_profile = "marisa.normal_shot", pattern = "straight", projectile_count = 2, spread = 0,
    },
}))
local marisa_initial_low = register(WeaponDefinition.new({
    weapon_id = "marisa_initial_low_weapon", name = "Marisa Low Weapon", weight = 0,
    display_name_zh = "魔理沙低速射击", display_name_en = "Marisa Low Shot", rarity = "COMMON",
    description = "魔理沙的初始低速射击，集中火力向前方发射。",
    fire_interval = 5, damage = 2.8, projectile_type = "marisa_bullet", projectile_speed = 22,
    active_modes = { LOW = true }, metadata = {
        legacy_profile = "marisa.focused_shot", pattern = "straight", projectile_count = 2, spread = 0,
    },
}))
local marisa_support_high = register(WeaponDefinition.new({
    weapon_id = "marisa_support_high_weapon", name = "Marisa Support High Weapon", weight = 0,
    display_name_zh = "魔理沙子机高速射击", display_name_en = "Marisa Support High Shot", rarity = "COMMON",
    description = "子机在高速模式下发射的魔法飞弹。",
    fire_interval = 8, damage = 1.0, projectile_type = "marisa_missile", projectile_speed = 16,
    active_modes = { HIGH = true }, metadata = { projectile_count = 1, spread = 0, targeting = "nearest" },
}))
local marisa_support_low = register(WeaponDefinition.new({
    weapon_id = "marisa_support_low_weapon", name = "Marisa Support Low Weapon", weight = 0,
    display_name_zh = "魔理沙子机低速射击", display_name_en = "Marisa Support Low Shot", rarity = "COMMON",
    description = "子机在低速模式下发射的集中魔法飞弹。",
    fire_interval = 5, damage = 0.5, projectile_type = "marisa_missile", projectile_speed = 20,
    active_modes = { LOW = true }, metadata = { projectile_count = 1, spread = 0 },
}))
local marisa_initial_support = register(SupportDefinition.new({
    support_id = "marisa_initial_support", name = "Marisa Option Support", weight = 0,
    display_name_zh = "魔理沙子机", display_name_en = "Marisa Option", rarity = "COMMON",
    description = "魔理沙的初始子机，随玩家移动并自动发射魔法飞弹。",
    entity_count = 4, activation_mode = "ALWAYS", attack_mode = "INDEPENDENT",
    high_weapon_definition_id = "marisa_support_high_weapon",
    low_weapon_definition_id = "marisa_support_low_weapon",
    metadata = { legacy_profile = "marisa.supports" },
}))

-- Kochiya Sanae initial kit.
local sanae_initial_high = register(WeaponDefinition.new({
    weapon_id = "sanae_initial_high_weapon", name = "Sanae High Weapon", weight = 0,
    display_name_zh = "早苗高速射击", display_name_en = "Sanae High Shot", rarity = "COMMON",
    description = "早苗的初始高速射击，发射具有弱追踪能力的风刃。",
    fire_interval = 5, damage = 2.2, projectile_type = "sanae_wind", projectile_speed = 18,
    active_modes = { HIGH = true }, metadata = {
        legacy_profile = "sanae.normal_shot", pattern = "straight", projectile_count = 2, spread = 0,
        homing = true, homing_strength = "WEAK",
    },
}))
local sanae_initial_low = register(WeaponDefinition.new({
    weapon_id = "sanae_initial_low_weapon", name = "Sanae Low Weapon", weight = 0,
    display_name_zh = "早苗低速射击", display_name_en = "Sanae Low Shot", rarity = "COMMON",
    description = "早苗的初始低速射击，集中火力向前方发射风弹。",
    fire_interval = 5, damage = 2.3, projectile_type = "sanae_wind", projectile_speed = 20,
    active_modes = { LOW = true }, metadata = {
        legacy_profile = "sanae.focused_shot", pattern = "straight", projectile_count = 2, spread = 0,
    },
}))
local sanae_support_high = register(WeaponDefinition.new({
    weapon_id = "sanae_support_high_weapon", name = "Sanae Support High Weapon", weight = 0,
    display_name_zh = "早苗子机高速射击", display_name_en = "Sanae Support High Shot", rarity = "COMMON",
    description = "子机在高速模式下发射的追踪风刃。",
    fire_interval = 8, damage = 1.2, projectile_type = "sanae_wind2", projectile_speed = 16,
    active_modes = { HIGH = true }, metadata = { projectile_count = 1, spread = 0, targeting = "nearest", homing = true },
}))
local sanae_support_low = register(WeaponDefinition.new({
    weapon_id = "sanae_support_low_weapon", name = "Sanae Support Low Weapon", weight = 0,
    display_name_zh = "早苗子机低速射击", display_name_en = "Sanae Support Low Shot", rarity = "COMMON",
    description = "子机在低速模式下发射的集中风弹。",
    fire_interval = 5, damage = 0.6, projectile_type = "sanae_wind2", projectile_speed = 18,
    active_modes = { LOW = true }, metadata = { projectile_count = 1, spread = 0 },
}))
local sanae_initial_support = register(SupportDefinition.new({
    support_id = "sanae_initial_support", name = "Sanae Snake Support", weight = 0,
    display_name_zh = "早苗子机", display_name_en = "Sanae Familiar", rarity = "COMMON",
    description = "早苗的初始子机，随风移动并发射追踪风刃。",
    entity_count = 2, activation_mode = "ALWAYS", attack_mode = "INDEPENDENT",
    high_weapon_definition_id = "sanae_support_high_weapon",
    low_weapon_definition_id = "sanae_support_low_weapon",
    metadata = { legacy_profile = "sanae.supports" },
}))

local initial_relic = RelicDefinition.new({
    relic_id = "reimu_initial_relic", name = "Reimu Character Relic",
    display_name_zh = "灵梦角色遗物", display_name_en = "Reimu Character Relic",
    description = "灵梦的专属遗物。", character_relic = true,
    upgrade_to = "reimu_initial_relic_plus",
})
local initial_relic_plus = RelicDefinition.new({
    relic_id = "reimu_initial_relic_plus", name = "Reimu Character Relic +",
    display_name_zh = "灵梦角色遗物·改", display_name_en = "Reimu Character Relic +",
    description = "强化后的灵梦专属遗物。", character_relic = true,
    upgrade_from = "reimu_initial_relic",
    metadata = { upgraded = true },
})
local marisa_initial_relic = RelicDefinition.new({
    relic_id = "marisa_initial_relic", name = "Marisa Character Relic",
    display_name_zh = "魔理沙角色遗物", display_name_en = "Marisa Character Relic",
    description = "魔理沙的专属遗物。", character_relic = true,
    upgrade_to = "marisa_initial_relic_plus",
})
local marisa_initial_relic_plus = RelicDefinition.new({
    relic_id = "marisa_initial_relic_plus", name = "Marisa Character Relic +",
    display_name_zh = "魔理沙角色遗物·改", display_name_en = "Marisa Character Relic +",
    description = "强化后的魔理沙专属遗物。", character_relic = true,
    upgrade_from = "marisa_initial_relic",
    metadata = { upgraded = true },
})
local sanae_initial_relic = RelicDefinition.new({
    relic_id = "sanae_initial_relic", name = "Sanae Character Relic",
    display_name_zh = "早苗角色遗物", display_name_en = "Sanae Character Relic",
    description = "早苗的专属遗物。", character_relic = true,
    upgrade_to = "sanae_initial_relic_plus",
})
local sanae_initial_relic_plus = RelicDefinition.new({
    relic_id = "sanae_initial_relic_plus", name = "Sanae Character Relic +",
    display_name_zh = "早苗角色遗物·改", display_name_en = "Sanae Character Relic +",
    description = "强化后的早苗专属遗物。", character_relic = true,
    upgrade_from = "sanae_initial_relic",
    metadata = { upgraded = true },
})
local test_relic = RelicDefinition.new({ relic_id = "test_relic", name = "Test Relic" })
local test_relic_bonus = RelicDefinition.new({ relic_id = "test_relic_bonus", name = "Test Relic Bonus" })
local test_relic_guard = RelicDefinition.new({ relic_id = "test_relic_guard", name = "Test Relic Guard" })

-- Keep the legacy test fixtures above stable while exposing the first-version
-- production equipment through the same registry used by live sessions.
for _, definition in ipairs(GuideCatalog.definitions) do
    register(definition)
end

return {
    registry = registry,
    definitions = definitions,
    relics = {
        reimu_initial_relic = initial_relic,
        reimu_initial_relic_plus = initial_relic_plus,
        marisa_initial_relic = marisa_initial_relic,
        marisa_initial_relic_plus = marisa_initial_relic_plus,
        sanae_initial_relic = sanae_initial_relic,
        sanae_initial_relic_plus = sanae_initial_relic_plus,
        test_relic = test_relic,
        test_relic_bonus = test_relic_bonus,
        test_relic_guard = test_relic_guard,
    },
    -- Per-character starting kit. `initial_by_character` is the authoritative
    -- lookup; the flat `initial` entry keeps the original Reimu convenience
    -- accessor working for older callers and tests.
    initial_by_character = {
        reimu = {
            high_weapon = initial_high,
            low_weapon = initial_low,
            support = initial_support,
            relic = initial_relic,
        },
        marisa = {
            high_weapon = marisa_initial_high,
            low_weapon = marisa_initial_low,
            support = marisa_initial_support,
            relic = marisa_initial_relic,
        },
        sanae = {
            high_weapon = sanae_initial_high,
            low_weapon = sanae_initial_low,
            support = sanae_initial_support,
            relic = sanae_initial_relic,
        },
    },
    initial = {
        high_weapon = initial_high,
        low_weapon = initial_low,
        support = initial_support,
        relic = initial_relic,
    },
}
