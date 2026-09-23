local CharacterDefinition = require("tnr.character.character_definition")

-- Sanae mirrors the reference movement (hspeed 4.5) and leans on homing wind
-- shots, so her base capacity is slightly below Reimu's.
return CharacterDefinition.new({
    character_id = "sanae",
    name = "Sanae",
    -- 10% slower but 20% heavier than Reimu.
    base_high_speed = 4.05,
    base_low_speed = 1.8,
    base_capacity = 120,
    high_weapon_slots = 1,
    low_weapon_slots = 3,
    support_slots = 3,
    self_modifier_slots = 1,
    support_modifier_slots = 3,
    inventory_slots = 6,
})
