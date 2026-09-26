-- Sound effect table.
--
-- The original keeps one flat list of WAV files and the ECL names an effect by
-- its position. This is that list, in the order the reference game stores it,
-- read from the executable's own name table. Keeping it here means an
-- instruction such as playSound(27) plays the sound the original played
-- instead of silence, and no effect needs a hand written mapping.

local Sounds = {}

-- Index to file stem, in the reference's own order.
Sounds.NAMES = {
    "plst00", "enep00", "pldead00", "power0",
    "power1", "tan00", "tan01", "tan02",
    "ok00", "cancel00", "select00", "gun00",
    "cat00", "lazer00", "lazer01", "enep01",
    "damage00", "item00", "kira00", "kira01",
    "kira02", "timeout", "graze", "powerup",
    "pause", "cardget", "damage01", "timeout2",
    "invalid", "slash", "ch00", "ch01",
    "extend", "nep00", "bonus", "bonus2",
    "enep02", "lazer02", "nodamage", "boon00",
    "don00", "boon01", "ch02", "ch03",
    "extend2", "pin00", "pin01", "lgods1",
    "lgods2", "lgods3", "lgods4", "lgodsget",
    "msl", "msl2", "pldead01", "heal",
    "msl3", "fault", "noise", "etbreak",
    "tan03", "wolf", "bonus4", "big",
    "item01",
}

--- Resolve a reference sound index to its file stem, or nil.
function Sounds.name_for(index)
    local value = tonumber(index)
    if value == nil then return nil end
    value = math.floor(value)
    if value < 0 then return nil end
    return Sounds.NAMES[value + 1]
end

--- Resolve a reference sound index to an asset path, or nil.
function Sounds.path_for(index)
    local name = Sounds.name_for(index)
    if not name then return nil end
    return "assets/audio/se/se_" .. name .. ".wav"
end

return Sounds
