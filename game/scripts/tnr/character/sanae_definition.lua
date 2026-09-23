local CharacterDefinition = require("tnr.character.character_definition")

-- Sanae mirrors the reference movement (hspeed 4.5) and leans on homing wind
-- shots, so her base capacity is slightly below Reimu's.
return CharacterDefinition.new({
    character_id = "sanae",
    name = "Sanae",
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
