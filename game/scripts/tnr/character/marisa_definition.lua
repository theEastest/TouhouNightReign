local CharacterDefinition = require("tnr.character.character_definition")

-- Marisa is the fast, wide-shot character (reference hspeed 5). She keeps the
-- same slot layout as Reimu so loadouts stay interchangeable, but has a larger
-- capacity to reflect her higher-output weapon kit.
return CharacterDefinition.new({
    character_id = "marisa",
    name = "Marisa",
    -- 10% faster and 10% lighter than Reimu.
    base_high_speed = 4.95,
    base_low_speed = 2.2,
    base_capacity = 90,
    high_weapon_slots = 4,
    low_weapon_slots = 2,
    support_slots = 1,
    self_modifier_slots = 3,
    support_modifier_slots = 1,
    inventory_slots = 6,
})
