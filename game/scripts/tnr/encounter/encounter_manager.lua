local EncounterManager = {}
EncounterManager.__index = EncounterManager

function EncounterManager.new(definitions)
    return setmetatable({ definitions = definitions or {} }, EncounterManager)
end

function EncounterManager:register(definition)
    assert(definition.id, "encounter id is required")
    self.definitions[definition.id] = definition
end

function EncounterManager:get(encounter_id)
    return self.definitions[encounter_id]
end

return EncounterManager

