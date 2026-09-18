-- Backend-independent equipment projectile simulation. Damage is committed by
-- the backend callback so invulnerability and native boss damage factors remain
-- authoritative. A rejected hit must not consume penetration or proc effects.
local Factory = require("tnr.character.runtime.projectile_factory")
local Runtime = {}
Runtime.__index = Runtime
local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end
local function protected(value)
    return value == true or (type(value) == "number" and value > 0)
end
local function valid(target)
    return target and (target.hp or 0) > 0 and not protected(target.protect)
        and not protected(target.invulnerable) and target.colli ~= false
end
local function key(target) return target.object or target end
local function segment_distance(x, y, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local t = math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / math.max(0.00001, dx * dx + dy * dy)))
    return ((x - ax - dx * t) ^ 2 + (y - ay - dy * t) ^ 2) ^ 0.5
end

function Runtime.new(shot, weapon)
    local self = setmetatable(Factory.from_shot(shot), Runtime)
    self.weapon = weapon
    self.age, self.hit_count, self.hit_targets = 0, 0, {}
    self.angle = math.rad(self.angle)
    self.beam = self.metadata.beam == true
    self.field = self.metadata.is_wind_field == true
    self.radius = self.radius * self.hitbox_scale
    self.max_age = self.field and (self.metadata.field_duration_frames or 45)
        or (self.beam and (self.metadata.beam_duration_frames or 8))
        or self.metadata.lifetime_frames or 180
    self.tick_interval = self.field and (self.metadata.field_damage_interval or 10)
        or (self.metadata.tick_interval or 2)
    self.tick_interval = math.max(1, self.tick_interval)
    self.field_radius = self.metadata.field_radius or 28
    self.beam_width = (self.metadata.mini_master_spark and 28 or 8) * self.hitbox_scale
    self.beam_length = self.metadata.beam_length or 640
    return self
end

function Runtime:update(targets, damage, spawn_field)
    if self.dead then return end
    self.metadata = self.metadata or {}
    self.hit_targets = self.hit_targets or {}
    self.hit_count = self.hit_count or 0
    self.age = self.age or 0
    if not self.angle then self.angle = atan2(self.vy or 0, self.vx or 0) end
    if not self.speed then self.speed = ((self.vx or 0)^2 + (self.vy or 0)^2)^0.5 end
    self.max_age = self.max_age or self.metadata.lifetime_frames or 180
    self.tick_interval = self.tick_interval or 1
    self.radius = self.radius or 4
    self.penetration = self.penetration or 0
    local ax, ay = self.x, self.y
    local persistent = self.beam or self.field
    if not persistent then
        if (self.metadata.homing or self.targeting == "NEAREST_ENEMY")
                and self.age < (self.metadata.max_tracking_frames or 90) then
            if not self.target_selected then
                local best_distance
                for _, target in ipairs(targets) do
                    if valid(target) then
                        local distance = (target.x - self.x)^2 + (target.y - self.y)^2
                        if not best_distance or distance < best_distance then
                            best_distance, self.target_key = distance, key(target)
                        end
                    end
                end
                self.target_selected = self.target_key ~= nil
            end
            local selected
            for _, target in ipairs(targets) do
                if key(target) == self.target_key and valid(target) then selected = target; break end
            end
            if selected then
                local desired = atan2(selected.y - self.y, selected.x - self.x)
                local delta = (desired - self.angle + math.pi) % (2 * math.pi) - math.pi
                local turn = math.min(0.12, (self.metadata.homing_turn_rate or 0.04)
                    * (self.metadata.homing_turn_multiplier or 1))
                self.angle = self.angle + math.max(-turn, math.min(turn, delta))
            end
        end
        self.vx, self.vy = math.cos(self.angle) * self.speed, math.sin(self.angle) * self.speed
        self.x, self.y = self.x + self.vx, self.y + self.vy
    end
    if not persistent or self.age % self.tick_interval == 0 then
        for _, target in ipairs(targets) do
            local target_key = key(target)
            if valid(target) and (persistent or not self.hit_targets[target_key]) then
                local radius = target.radius or math.max(target.a or 0, target.b or 0)
                local distance, reach
                if self.beam then
                    distance = segment_distance(target.x, target.y, self.x, self.y,
                        self.x + math.cos(self.angle) * self.beam_length, self.y + math.sin(self.angle) * self.beam_length)
                    reach = radius + self.beam_width
                elseif self.field then
                    distance = ((target.x - self.x)^2 + (target.y - self.y)^2)^0.5
                    reach = radius + self.field_radius
                else
                    distance = segment_distance(target.x, target.y, ax, ay, self.x, self.y)
                    reach = radius + self.radius
                end
                if distance <= reach then
                    local bonus = self.weapon and self.weapon:damage_bonus(target_key) or 0
                    if damage(target, self.damage * (1 + bonus), self) then
                        self.hit_targets[target_key] = self.age
                        self.hit_count = self.hit_count + 1
                        if self.weapon then
                            self.weapon:record_hit(target_key)
                            if self.beam and not self.hit_reported and not self.metadata.mini_master_spark then
                                self.weapon:notify_projectile_hit(self.weapon.frame)
                                self.hit_reported = true
                            end
                        end
                        if not self.field and self.metadata.legendary_effect == "wind_field" and spawn_field then
                            local shot = Factory.from_shot(self)
                            shot.x, shot.y, shot.speed = target.x, target.y, 0
                            shot.angle = math.deg(self.angle)
                            shot.metadata.is_wind_field = true
                            shot.metadata.homing = false
                            shot.targeting = "NONE"
                            spawn_field(shot, self.weapon)
                        end
                        if not persistent and self.hit_count > self.penetration then self.dead = true; break end
                    end
                end
            end
        end
    end
    self.age = self.age + 1
    if self.age >= self.max_age then self.dead = true end
end

return Runtime
