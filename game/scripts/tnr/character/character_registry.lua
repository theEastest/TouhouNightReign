local CharacterRegistry = {}
CharacterRegistry.__index = CharacterRegistry

function CharacterRegistry.new(definitions)
    local self = setmetatable({ definitions = {} }, CharacterRegistry)
    for _, definition in ipairs(definitions or {}) do
        self:register(definition)
    end
    return self
end

function CharacterRegistry:register(definition)
    assert(definition and definition.character_id, "character definition is required")
    assert(not self.definitions[definition.character_id], "duplicate character definition: " .. definition.character_id)
    self.definitions[definition.character_id] = definition
    return definition
end

function CharacterRegistry:get(character_id)
    return self.definitions[character_id]
end

function CharacterRegistry:has(character_id)
    return self:get(character_id) ~= nil
end

function CharacterRegistry:all()
    local result = {}
    for character_id, definition in pairs(self.definitions) do
        result[character_id] = definition
    end
    return result
end

return CharacterRegistry
