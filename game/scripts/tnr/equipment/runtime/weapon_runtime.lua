local WeaponRuntime = {}
WeaponRuntime.__index = WeaponRuntime

local function copy_table(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy_table(item) end
    return result
end

function WeaponRuntime.new(instance, definition, slot_type, slot_index)
    assert(instance and definition, "weapon runtime requires instance and definition")
    return setmetatable({
        instance_id = instance.instance_id,
        definition_id = instance.definition_id,
        slot_type = slot_type,
        slot_index = slot_index,
        definition = definition,
        fire_count = 0,
        cooldown = 0,
    }, WeaponRuntime)
end

function WeaponRuntime:is_active(mode)
    mode = tostring(mode or "HIGH"):upper()
    if self.definition.dual_mode then return true end
    return self.definition.active_modes and self.definition.active_modes[mode] == true
end

function WeaponRuntime:update(mode, firing, context)
    if self.cooldown > 0 then self.cooldown = self.cooldown - 1 end
    if not firing or not self:is_active(mode) or self.cooldown > 0 then return {} end
    local definition = self.definition
    local metadata = definition.metadata or {}
    local form = mode == "LOW" and metadata.low_form or metadata.high_form
    form = form or metadata.pattern or definition.projectile_type or "default"
    local count = (tonumber(metadata.projectile_count) or 1)
        + math.max(0, math.floor(tonumber(context and context.extra_projectiles) or 0))
    local spread = tonumber(metadata.spread) or 0
    local speed = tonumber(definition.projectile_speed) or 0
    local damage = tonumber(definition.damage) or 0
    local result = {}
    local origin_x = tonumber(context and context.x) or 0
    local origin_y = tonumber(context and context.y) or 0
    local aim = tonumber(context and context.angle) or 90
    for index = 1, math.max(1, math.floor(count)) do
        local offset = (index - (count + 1) * 0.5) * spread
        result[#result + 1] = {
            weapon_id = self.definition_id,
            instance_id = self.instance_id,
            projectile_type = form,
            x = origin_x,
            y = origin_y,
            angle = aim + offset,
            speed = speed,
            damage = damage,
            scale = tonumber(context and context.scale) or 1,
            slot_type = self.slot_type,
            slot_index = self.slot_index,
        }
    end
    self.fire_count = self.fire_count + 1
    self.cooldown = math.max(1, math.floor(tonumber(definition.fire_interval) or 1))
    return result
end

function WeaponRuntime:to_table()
    return {
        instance_id = self.instance_id,
        definition_id = self.definition_id,
        slot_type = self.slot_type,
        slot_index = self.slot_index,
        fire_count = self.fire_count,
        cooldown = self.cooldown,
        definition = copy_table(self.definition),
    }
end

return WeaponRuntime
