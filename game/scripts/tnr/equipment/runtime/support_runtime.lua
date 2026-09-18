local SupportRuntime = {}
SupportRuntime.__index = SupportRuntime

local function copy_table(value)
    if type(value) ~= "table" then return value end
    local raw = value.__immutable_raw
    if type(raw) == "table" then value = raw end
    local result = {}
    for key, item in pairs(value) do result[key] = copy_table(item) end
    return result
end

local function nearest_front_target(player_x, player_y, enemies)
    local best, best_distance
    local function is_protected(value)
        return value == true or (type(value) == "number" and value > 0)
    end
    for _, enemy in ipairs(enemies or {}) do
        if enemy and (tonumber(enemy.hp) or 0) > 0 and not is_protected(enemy.protect)
                and not is_protected(enemy.invulnerable) and enemy.colli ~= false then
            local dx, dy = (tonumber(enemy.x) or 0) - player_x, (tonumber(enemy.y) or 0) - player_y
            if dy > 0 and math.abs(dx) <= dy * math.tan(math.pi / 6) then
                local distance = dx * dx + dy * dy
                if not best_distance or distance < best_distance then
                    best, best_distance = enemy, distance
                end
            end
        end
    end
    return best
end

function SupportRuntime.new(instance, definition, slot_index)
    local count = math.max(0, math.floor(tonumber(definition.entity_count) or 0))
    local entities = {}
    for index = 1, count do
        entities[index] = { entity_index = index, x = 0, y = 0, slot_index = slot_index,
            initialized = false }
    end
    return setmetatable({
        instance_id = instance.instance_id,
        definition_id = instance.definition_id,
        slot_index = slot_index,
        definition = definition,
        entities = entities,
        cooldown = 0,
        fire_count = 0,
    }, SupportRuntime)
end

function SupportRuntime:is_active(mode)
    mode = tostring(mode or "HIGH"):upper()
    local activation = tostring(self.definition.activation_mode or "INDEPENDENT"):upper()
    if activation == "PASSIVE" then return false end
    if activation == "HIGH_ONLY" then return mode == "HIGH" end
    if activation == "LOW_ONLY" then return mode == "LOW" end
    return true
end

function SupportRuntime:entity_count()
    return #self.entities
end

function SupportRuntime:update(player_x, player_y, mode, modifiers)
    modifiers = modifiers or {}
    local formation = modifiers and modifiers.support_formation or nil
    local px, py = tonumber(player_x) or 0, tonumber(player_y) or 0
    local target = modifiers and modifiers.support_auto_target == "NEAREST_ENEMY"
        and nearest_front_target(px, py, modifiers.enemies) or nil
    for index, entity in ipairs(self.entities) do
        local offset = (index - (#self.entities + 1) * 0.5) * 18
        if formation == "front_concentration" then offset = (index - 1) * 8 end
        if target then
            local target_x = tonumber(target.x) or px
            local target_y = (tonumber(target.y) or py) - 24
            if entity.initialized then
                entity.x = (entity.x or target_x) + (target_x - (entity.x or target_x)) * 0.25
                entity.y = (entity.y or target_y) + (target_y - (entity.y or target_y)) * 0.25
            else
                entity.x, entity.y = target_x, target_y
            end
            entity.auto_target_id = target.id or target.enemy_id
        elseif formation == "orbit" or (not formation and self.definition.formation.type == "ORBIT") then
            local radius = mode == "LOW"
                and (tonumber(modifiers.low_radius) or 28)
                or (tonumber(modifiers.high_radius) or 42)
            local ordinal = formation == "orbit" and entity.global_index or index
            local total = formation == "orbit" and modifiers.total_entities or #self.entities
            local angle = (ordinal - 1) * (math.pi * 2 / math.max(1, total or 1)) + (modifiers.frame or 0) * 0.04
            entity.x = px + math.cos(angle) * radius
            entity.y = py + math.sin(angle) * radius
        else
            local tx, ty
            if formation == "front_concentration" then
                tx = px + (entity.global_index - ((modifiers.total_entities or #self.entities) + 1) / 2) * 20
                local edge_distance = math.min(entity.global_index - 1,
                    (modifiers.total_entities or #self.entities) - entity.global_index)
                ty = py + 28 + math.min(1, edge_distance) * 10
            elseif self.definition.support_id == "support_sanae_snakeskin_amulet" then
                tx = px + (index == 1 and -1 or 1) * (mode == "LOW" and 10 or 30)
                ty = py + (mode == "LOW" and 28 or 18)
            else
                tx = px + offset * (mode == "LOW" and 0.55 or 1)
                ty = py - (mode == "LOW" and 8 or 16)
            end
            entity.x = entity.initialized and entity.x + (tx - entity.x) * 0.25 or tx
            entity.y = entity.initialized and entity.y + (ty - entity.y) * 0.25 or ty
            entity.auto_target_id = nil
        end
        entity.initialized = true
    end
    return self.entities
end

function SupportRuntime:fire(mode, firing, context, registry)
    if self.cooldown > 0 then self.cooldown = self.cooldown - 1 end
    if not firing or not self:is_active(mode) or self.cooldown > 0
            or tostring(self.definition.attack_mode or "INDEPENDENT"):upper() == "NONE" then
        return {}
    end
    local definition_id = tostring(mode or "HIGH"):upper() == "LOW"
        and (self.definition.low_weapon_definition_id or self.definition.weapon_definition_id)
        or (self.definition.high_weapon_definition_id or self.definition.weapon_definition_id)
    local weapon = registry and definition_id and registry.get and registry:get(definition_id) or nil
    local metadata = self.definition.metadata or {}
    local weapon_metadata = weapon and weapon.metadata or {}
    local mode_name = tostring(mode or "HIGH"):upper()
    local prefix = mode_name == "LOW" and "low_" or "high_"
    local function mode_value(name, fallback)
        local value = metadata[prefix .. name]
        if value == nil then value = metadata[name] end
        if value == nil then value = fallback end
        return value
    end
    local projectile_type = mode_value("projectile_type", weapon and weapon.projectile_type) or "default"
    local count = tonumber(mode_value("projectile_count", weapon_metadata.projectile_count)) or 1
    local spread = tonumber(mode_value("spread", weapon_metadata.spread)) or 0
    local speed = tonumber(mode_value("projectile_speed", weapon and (weapon.speed or weapon.projectile_speed))) or 8
    local damage = tonumber(mode_value("damage", weapon and weapon.damage)) or 1
    local result = {}
    local player_x, player_y = tonumber(context and context.x) or 0, tonumber(context and context.y) or 0
    local angle = tonumber(context and context.angle) or 90
    for _, entity in ipairs(self.entities) do
        for index = 1, math.max(1, math.floor(count)) do
            local shot_metadata = copy_table(metadata)
            shot_metadata.beam = mode_value("beam", false)
            shot_metadata.homing = mode_value("homing", false) or mode_value("targeting") == "NEAREST_ENEMY"
            shot_metadata.beam_duration_frames = mode_value("beam_duration_frames", 8)
            shot_metadata.tick_interval = mode_value("tick_interval", 2)
            shot_metadata.max_tracking_frames = 90
            shot_metadata.homing_turn_rate = 0.04
            result[#result + 1] = {
                owner_player_id = context and context.player_id,
                source_type = "support",
                source_instance_id = self.instance_id,
                projectile_type = projectile_type,
                x = (entity.x or player_x) + (count == 2 and (index == 1 and -3 or 3) or 0),
                y = entity.y or player_y,
                angle = angle + (index - (count + 1) * 0.5) * spread,
                speed = speed,
                damage = damage,
                scale = 1,
                targeting = mode_value("targeting", weapon and weapon.targeting),
                metadata = shot_metadata,
            }
        end
    end
    self.fire_count = self.fire_count + 1
    self.cooldown = math.max(1, math.floor(tonumber(metadata.fire_interval or (weapon and weapon.fire_interval)) or 8))
    return result
end

function SupportRuntime:to_table()
    return {
        instance_id = self.instance_id,
        definition_id = self.definition_id,
        slot_index = self.slot_index,
        entity_count = #self.entities,
        cooldown = self.cooldown,
        fire_count = self.fire_count,
    }
end

return SupportRuntime
