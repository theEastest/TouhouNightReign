local CharacterDefinition = require("tnr.character.character_definition")

return CharacterDefinition.new({
    character_id = "reimu",
    name = "Reimu",
    base_high_speed = 4.5,
    base_low_speed = 2.0,
    base_capacity = 100,
    high_weapon_slots = 3,
    low_weapon_slots = 3,
    support_slots = 1,
    self_modifier_slots = 2,
    support_modifier_slots = 2,
    inventory_slots = 6,
})
