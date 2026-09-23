local CharacterDefinition = require("tnr.character.character_definition")

-- Marisa is the fast, wide-shot character (reference hspeed 5). She keeps the
-- same slot layout as Reimu so loadouts stay interchangeable, but has a larger
-- capacity to reflect her higher-output weapon kit.
return CharacterDefinition.new({
    character_id = "marisa",
    name = "Marisa",
    base_high_speed = 5.0,
    base_low_speed = 2.0,
    base_capacity = 110,
    high_weapon_slots = 3,
    low_weapon_slots = 3,
    support_slots = 1,
    self_modifier_slots = 2,
    support_modifier_slots = 2,
    inventory_slots = 6,
})
