local SupportRuntime = require("tnr.equipment.runtime.support_runtime")

local Manager = {}
Manager.__index = Manager

function Manager.new(loadout, registry, modifiers)
    local self = setmetatable({ supports = {}, registry = registry, modifiers = modifiers, frame = 0 }, Manager)
    for index, instance in ipairs(loadout and loadout.supports or {}) do
        if instance and instance ~= false then
            local definition = registry and registry.get and registry:get(instance.definition_id)
            if definition then self.supports[#self.supports + 1] = SupportRuntime.new(instance, definition, index) end
        end
    end
    local total = self:entity_count()
    local ordinal = 0
    for _, support in ipairs(self.supports) do
        for _, entity in ipairs(support.entities) do
            ordinal = ordinal + 1
            entity.global_index = ordinal
            entity.stagger_offset = total > 0 and math.floor(240 * (ordinal - 1) / total) or 0
            entity.radius = 24
            entity.support_id = support.definition_id
        end
    end
    return self
end

function Manager:entity_count()
    local count = 0
    for _, support in ipairs(self.supports) do count = count + support:entity_count() end
    return count
end

function Manager:update(player_x, player_y, mode, modifiers, enemies)
    modifiers = modifiers or self.modifiers
    local modifier_context = { frame = self.frame or 0, mode = mode, enemies = enemies, total_entities = self:entity_count() }
    if modifiers then
        modifier_context = modifiers:apply_hook("on_support_formation", modifier_context)
        modifier_context = modifiers:apply_hook("on_support_update", modifier_context)
    end
    modifier_context.clear_pulses = {}
    local result = {}
    local current_frame = self.frame or 0
    for _, support in ipairs(self.supports) do
        local entities = support:update(player_x, player_y, mode, modifier_context)
        local support_metadata = support.definition.metadata or {}
        local base_radius = tonumber((support.definition.formation or {}).radius) or 24
        for _, entity in ipairs(entities) do
            result[#result + 1] = entity
            if support_metadata.runtime_effect == "support_bullet_clear"
                    and ((current_frame + 1) % math.max(1, math.floor(tonumber(support_metadata.clear_interval_frames) or 180)) == 0) then
                modifier_context.clear_pulses[#modifier_context.clear_pulses + 1] = {
                    x = entity.x, y = entity.y,
                    radius = base_radius * (tonumber(support_metadata.clear_radius_ratio) or 2),
                }
            end
            if modifier_context.staggered_bullet_clear
                    and current_frame >= (entity.stagger_offset or 0)
                    and (current_frame - (entity.stagger_offset or 0))
                        % math.max(1, math.floor(modifier_context.staggered_cycle_frames or 240)) == 0 then
                modifier_context.clear_pulses[#modifier_context.clear_pulses + 1] = {
                    x = entity.x, y = entity.y,
                    radius = entity.radius * math.min(2, tonumber(modifier_context.clear_radius_ratio) or 2),
                }
            end
        end
    end
    self.frame = current_frame + 1
    self.last_modifier_context = modifier_context
    return result
end

function Manager:fire(mode, firing, context)
    local result = {}
    for _, support in ipairs(self.supports) do
        local shots = support:fire(mode, firing, context, self.registry)
        for _, shot in ipairs(shots) do
            if self.modifiers then
                shot = self.modifiers:apply_hook("on_support_fire", shot)
                shot = self.modifiers:apply_hook("on_support_projectile_create", shot)
            end
            result[#result + 1] = shot
        end
    end
    return result
end

function Manager:to_table()
    local result = { entity_count = self:entity_count(), supports = {} }
    for index, support in ipairs(self.supports) do result.supports[index] = support:to_table() end
    return result
end

return Manager
