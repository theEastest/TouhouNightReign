local EquipmentRegistry = require("tnr.equipment.equipment_registry")
local WeaponDefinition = require("tnr.equipment.weapon_definition")
local SupportDefinition = require("tnr.equipment.support_definition")
local ModifierDefinition = require("tnr.equipment.modifier_definition")
local RelicDefinition = require("tnr.equipment.relic_definition")

local registry = EquipmentRegistry.new()
local definitions = {}

local function register(definition)
    registry:register(definition)
    definitions[definition.equipment_id or definition.weapon_id or definition.support_id or definition.modifier_id] = definition
    return definition
end

register(WeaponDefinition.new({
    weapon_id = "test_high_weapon", name = "Test High Weapon", weight = 2,
    fire_interval = 4, damage = 2, projectile_type = "test", projectile_speed = 20,
    active_modes = { HIGH = true }, allowed_slots = { HIGH_WEAPON = true },
    metadata = { pattern = "straight", projectile_count = 2, spread = 0 },
}))
register(WeaponDefinition.new({
    weapon_id = "test_low_weapon", name = "Test Low Weapon", weight = 3,
    fire_interval = 5, damage = 3, projectile_type = "test", projectile_speed = 18,
    active_modes = { LOW = true }, allowed_slots = { LOW_WEAPON = true },
    metadata = { pattern = "fan", projectile_count = 3, spread = 12 },
}))
register(WeaponDefinition.new({
    weapon_id = "test_dual_weapon", name = "Test Dual Weapon", weight = 2,
    fire_interval = 6, damage = 2.5, projectile_type = "test_dual", projectile_speed = 19,
    active_modes = { HIGH = true, LOW = true },
    allowed_slots = { HIGH_WEAPON = true, LOW_WEAPON = true },
    dual_mode = true,
    metadata = { high_form = "dual_high", low_form = "dual_low", projectile_count = 2, spread = 8 },
}))
register(SupportDefinition.new({
    support_id = "test_support", name = "Test Support", weight = 4,
    entity_count = 4, activation_mode = "INDEPENDENT", attack_mode = "INDEPENDENT",
}))
register(SupportDefinition.new({
    support_id = "test_support_alt", name = "Test Support Alt", weight = 5,
    entity_count = 2, activation_mode = "INDEPENDENT", attack_mode = "INDEPENDENT",
}))
register(ModifierDefinition.new({
    modifier_id = "test_self_modifier", name = "Test Self Modifier",
    modifier_type = "SELF_MODIFIER", conflict_group = "projectile_size",
    metadata = { runtime_effect = "projectile_scale" },
}))
register(ModifierDefinition.new({
    modifier_id = "test_self_modifier_alt", name = "Test Self Modifier Alt",
    modifier_type = "SELF_MODIFIER", conflict_group = "projectile_size",
    metadata = { runtime_effect = "volley" },
}))
register(ModifierDefinition.new({
    modifier_id = "test_support_modifier", name = "Test Support Modifier",
    modifier_type = "SUPPORT_MODIFIER", conflict_group = "formation",
    metadata = { runtime_effect = "front_concentration" },
}))
register(ModifierDefinition.new({
    modifier_id = "test_support_modifier_alt", name = "Test Support Modifier Alt",
    modifier_type = "SUPPORT_MODIFIER", conflict_group = "formation",
    metadata = { runtime_effect = "periodic_bullet_clear" },
}))

local initial_high = register(WeaponDefinition.new({
    weapon_id = "reimu_initial_high_weapon", name = "Reimu High Weapon", weight = 0,
    fire_interval = 4, damage = 2, projectile_type = "reimu_normal", projectile_speed = 24,
    active_modes = { HIGH = true }, metadata = {
        legacy_profile = "reimu.normal_shot", pattern = "reimu_normal", projectile_count = 1, spread = 0,
    },
}))
local initial_low = register(WeaponDefinition.new({
    weapon_id = "reimu_initial_low_weapon", name = "Reimu Low Weapon", weight = 0,
    fire_interval = 4, damage = 2.5, projectile_type = "reimu_focused", projectile_speed = 24,
    active_modes = { LOW = true }, metadata = {
        legacy_profile = "reimu.focused_shot", pattern = "reimu_focused", projectile_count = 1, spread = 0,
    },
}))
local initial_support = register(SupportDefinition.new({
    support_id = "reimu_initial_support", name = "Reimu Yin-Yang Support", weight = 0,
    entity_count = 4, activation_mode = "ALWAYS", attack_mode = "INDEPENDENT",
    metadata = { legacy_profile = "reimu.supports" },
}))

local initial_relic = RelicDefinition.new({
    relic_id = "reimu_initial_relic", name = "Reimu Character Relic",
    character_relic = true, upgrade_to = "reimu_initial_relic_plus",
})
local test_relic = RelicDefinition.new({ relic_id = "test_relic", name = "Test Relic" })

return {
    registry = registry,
    definitions = definitions,
    relics = {
        reimu_initial_relic = initial_relic,
        test_relic = test_relic,
    },
    initial = {
        high_weapon = initial_high,
        low_weapon = initial_low,
        support = initial_support,
        relic = initial_relic,
    },
}
