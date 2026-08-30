local SupportRuntime = {}
SupportRuntime.__index = SupportRuntime

function SupportRuntime.new(instance, definition, slot_index)
    local count = math.max(0, math.floor(tonumber(definition.entity_count) or 0))
    local entities = {}
    for index = 1, count do
        entities[index] = { entity_index = index, x = 0, y = 0, slot_index = slot_index }
    end
    return setmetatable({
        instance_id = instance.instance_id,
        definition_id = instance.definition_id,
        slot_index = slot_index,
        definition = definition,
        entities = entities,
    }, SupportRuntime)
end

function SupportRuntime:entity_count()
    return #self.entities
end

function SupportRuntime:update(player_x, player_y, mode, modifiers)
    local formation = modifiers and modifiers.support_formation or nil
    for index, entity in ipairs(self.entities) do
        local offset = (index - (#self.entities + 1) * 0.5) * 18
        if formation == "front_concentration" then offset = (index - 1) * 8 end
        entity.x = (tonumber(player_x) or 0) + offset
        entity.y = (tonumber(player_y) or 0) - (mode == "LOW" and 24 or 12)
    end
    return self.entities
end

function SupportRuntime:to_table()
    return {
        instance_id = self.instance_id,
        definition_id = self.definition_id,
        slot_index = self.slot_index,
        entity_count = #self.entities,
    }
end

return SupportRuntime
