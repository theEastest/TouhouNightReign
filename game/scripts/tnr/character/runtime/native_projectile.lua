local Simulation = require("tnr.character.runtime.projectile_runtime")
local Native = {}
local projectile_class, pulse_class
local local_player_id = 1
local function image(name, path, x, y, w, h)
    local id = "tnr-equip:" .. name
    if not lstg.CheckRes(2, id) then
        lstg.LoadTexture(id, path)
        if not w then w, h = lstg.GetTextureSize(id); x, y = 0, 0 end
        lstg.LoadImage(id, id, x, y, w, h)
    end
    return id
end
local function sprite(kind)
    local reimu_sprite_aliases = {
        reimu_normal = "reimu_bullet_red",
        reimu_focused = "reimu_bullet_red",
        reimu_support_blue = "reimu_bullet_blue",
        reimu_support_orange = "reimu_bullet_orange",
    }
    kind = reimu_sprite_aliases[kind] or kind
    if kind == "marisa_bullet" then return image(kind, "Thlib/player/marisa/marisa.png", 0, 144, 32, 16), 0.65, 0 end
    if kind == "marisa_missile" then return image(kind, "Thlib/player/marisa/marisa.png", 192, 224, 32, 16), 0.7, 0 end
    if kind == "sanae_wind2" then return image(kind, "Thlib/player/sanae/sanae_wind2.png"), 0.35, -90 end
    if kind == "sanae_wind" then return image(kind, "Thlib/player/sanae/sanae_wind.png"), 0.18, -90 end
    if kind == "MarisaLaser" or kind == "marisa_spark" then
        return image("laser", "Thlib/player/marisa/MarisaLaser.png"), 1, 0
    end
    if kind == "reimu_bullet_red" then
        return image("reimu-bullet-red", "Thlib/player/reimu/reimu.png", 192, 160, 64, 16), 1, 0
    end
    if kind == "reimu_bullet_blue" then
        return image("reimu-bullet-blue", "Thlib/player/reimu/reimu.png", 0, 160, 16, 16), 1, 0
    end
    if kind == "reimu_bullet_orange" then
        return image("reimu-bullet-orange", "Thlib/player/reimu/reimu.png", 64, 176, 64, 16), 1, 0
    end
    print("Missing Asset: equipment projectile " .. tostring(kind) .. "; using debug sprite")
    return "tnr-white", 0.5, 0
end

function Native.spawn(shot, weapon, targets)
    if not projectile_class then
        projectile_class = Class(object)
        function projectile_class:init(descriptor, source, provider)
            self.sim = Simulation.new(descriptor, source)
            self.x, self.y = self.sim.x, self.sim.y
            self.group, self.layer = GROUP_PLAYER_BULLET, LAYER_PLAYER_BULLET
            self.bound, self.colli, self.killflag = false, false, true
            self._tnr_managed_projectile = true
            self._tnr_owner_id = descriptor.owner_player_id
            self.tnr_source_instance_id = descriptor.source_instance_id
            self.tnr_projectile_type = descriptor.projectile_type
            self.provider = provider
            self.img, self.sprite_scale, self.sprite_rotation = sprite(descriptor.projectile_type)
            if self.sim.field then
                self.img = image("wind-field", "Thlib/player/sanae/sanae_wind.png")
                if source then
                    source.fields = source.fields or {}
                    local live = {}
                    for _, field in ipairs(source.fields) do if IsValid(field) then live[#live + 1] = field end end
                    local cap = self.sim.metadata.max_active_fields or 6
                    while #live >= cap do Del(table.remove(live, 1)) end
                    live[#live + 1] = self
                    source.fields = live
                end
            end
        end
        function projectile_class:frame()
            self.sim:update(self.provider(), function(target, amount)
                local enemy = target.object
                if not IsValid(enemy) or not enemy.class.colli then return false end
                local before = enemy.hp
                self.dmg, self.damage = amount, amount
                -- Execute the original collision handler (damage factors,
                -- aggro and damage ownership) without engine double collision.
                enemy.class.colli(enemy, self)
                return (enemy.hp or before) < before
            end, function(field_shot, source) Native.spawn(field_shot, source, self.provider) end)
            self.x, self.y = self.sim.x, self.sim.y
            if self.sim.dead then Del(self) end
        end
        function projectile_class:render()
            local sim = self.sim
            local alpha = self._tnr_owner_id ~= local_player_id and 180 or 255
            lstg.SetImageState(self.img, "", Color(alpha, 255, 255, 255))
            if sim.beam then
                local dx, dy = math.cos(sim.angle), math.sin(sim.angle)
                local w, l = sim.beam_width * sim.scale / sim.hitbox_scale, sim.beam_length
                local x, y = self.x, self.y
                lstg.Render4V(self.img, x-dy*w,y+dx*w,0.5, x+dx*l-dy*w,y+dy*l+dx*w,0.5,
                    x+dx*l+dy*w,y+dy*l-dx*w,0.5, x+dy*w,y-dx*w,0.5)
            elseif sim.field then
                local scale = sim.field_radius / 64
                lstg.Render(self.img, self.x, self.y, sim.age * 8, scale, scale)
            else
                local scale = self.sprite_scale * sim.scale
                lstg.Render(self.img, self.x, self.y, math.deg(sim.angle) + self.sprite_rotation, scale, scale)
            end
        end
        -- Class() copies the base callbacks into its numeric callback slots.
        -- This class is defined lazily, so register it again after overriding
        -- the named callbacks; otherwise New() runs the empty base init and
        -- leaves the projectile in GROUP_GHOST with no sprite.
        if lstg.RegisterGameObjectClass then
            lstg.RegisterGameObjectClass(projectile_class)
        end
    end
    return New(projectile_class, shot, weapon, targets)
end

function Native.set_local_player_id(player_id)
    local_player_id = tonumber(player_id) == 2 and 2 or 1
end

function Native.pulse(pulse)
    if not pulse_class then
        pulse_class = Class(object)
        function pulse_class:init(data)
            self.x, self.y, self.radius = data.x, data.y, data.radius
            self.group, self.layer, self.colli, self.bound = GROUP_GHOST, LAYER_PLAYER, false, false
        end
        function pulse_class:frame() if self.timer >= 12 then Del(self) end end
        function pulse_class:render()
            lstg.SetImageState("tnr-white", "", Color(math.floor(150 * (1 - self.timer / 12)), 160, 220, 255))
            for index = 0, 47 do
                local a, b = index * math.pi / 24, (index + 1) * math.pi / 24
                local r, inner = self.radius, math.max(0, self.radius - 2)
                lstg.Render4V("tnr-white", self.x+math.cos(a)*r,self.y+math.sin(a)*r,0.5,
                    self.x+math.cos(b)*r,self.y+math.sin(b)*r,0.5,
                    self.x+math.cos(b)*inner,self.y+math.sin(b)*inner,0.5,
                    self.x+math.cos(a)*inner,self.y+math.sin(a)*inner,0.5)
            end
        end
        if lstg.RegisterGameObjectClass then
            lstg.RegisterGameObjectClass(pulse_class)
        end
    end
    return New(pulse_class, pulse)
end

-- Which character sprite a support equipment belongs to. Initial supports
-- (reimu/marisa/sanae) and the guide supports are all mapped here so the
-- renderer never falls back to a resource that was never loaded.
local function support_sprite_for(support_id)
    support_id = tostring(support_id or "")
    if support_id:find("marisa", 1, true) then
        return image("marisa-support", "Thlib/player/marisa/marisa.png", 128, 144, 16, 16)
    elseif support_id:find("sanae", 1, true) then
        return image("sanae-support", "Thlib/player/sanae/sanae.png", 64, 144, 16, 16)
    end
    -- Reimu and any unknown support use the Reimu option sprite.
    return image("reimu-support", "Thlib/player/reimu/reimu.png", 64, 144, 16, 16)
end

function Native.render_supports(entities, alpha)
    for _, entity in ipairs(entities or {}) do
        -- Resolve the sprite from the equipment definition. Loading through
        -- image() keeps the resource alive even if the legacy character script
        -- that also loads it has not run yet (the previous hardcoded
        -- "reimu_support" lookup raised "image not found" at room start).
        local name = support_sprite_for(entity.support_id)
        lstg.SetImageState(name, "", Color(alpha or 255,255,255,255))
        lstg.Render(name, entity.x, entity.y)
    end
end

function Native.render_streaks(driver, player)
    for index, weapon in ipairs(driver.weapon_manager.weapons) do
        if weapon.definition.metadata.legendary_effect == "sealing_streak" then
            local bonus = 0
            for target in pairs(weapon.streaks) do bonus = math.max(bonus, weapon:damage_bonus(target)) end
            weapon.display_bonus = (weapon.display_bonus or 0) + (bonus - (weapon.display_bonus or 0)) * 0.25
            local value = weapon.display_bonus
            local green = value < 0.5 and 255 - value * 180 or 165 * (2 - value * 2)
            local blue = math.max(0, 255 * (1 - value * 2))
            local x, y = player.x - 20, player.y - 28 - index * 5
            SetImageState("tnr-white", "", Color(100,255,255,255))
            RenderRect("tnr-white", x, x+40, y, y+3)
            SetImageState("tnr-white", "", Color(255,255,math.floor(green),math.floor(blue)))
            if value > 0 then RenderRect("tnr-white", x, x+40*value, y, y+3) end
        end
    end
end
return Native
