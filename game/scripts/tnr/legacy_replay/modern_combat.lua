-- Equipment uses its existing y-up simulation; the imported ECL uses y-down.
-- Convert only at this boundary, retaining weapon ownership and affix callbacks.
local Bridge = require("tnr.character.runtime.character_runtime_bridge")
local Projectile = require("tnr.character.runtime.projectile_runtime")
local ProjectileArt = require("tnr.character.runtime.native_projectile")
local Affixes = require("tnr.equipment.runtime.affix_runtime")
local M = {}; M.__index = M
local unpack = table.unpack or unpack
-- Equipment damage uses the native project's scale (starter needle 2), whereas
-- TH15's SHT/ECL pair uses 16 for the base needle. Preserve equipment ratios.
M.DAMAGE_SCALE=8

function M.new(stage, session)
    if not session or not session:get_player(1) then
        session = require("tnr.core.game_session").new({run_seed=151})
        session:start_new()
    end
    local self = setmetatable({stage=stage, session=session, drivers={}, shots={}}, M)
    for id,p in pairs(stage.players) do
        if session:get_player(id) then
            local bridge = Bridge.new(session,id)
            local descriptor=stage.loadouts and stage.loadouts[id]
            local d = descriptor and bridge:create_runtime_from_descriptor(descriptor) or bridge:create_runtime()
            d.affixes = Affixes.new(d,session:get_player(id),session)
            d.affixes.on_resource = function(kind, amount)
                if kind == "money" then stage.session.money = (stage.session.money or 0)+amount
                elseif kind == "life" then stage.session:add_life(id,amount)
                elseif kind == "bomb" then stage.session:add_bomb(id,amount) end
            end
            self.drivers[id],p.combat_runtime = d,d
        end
    end
    return self
end

function M:targets()
    local out={}
    for _,e in ipairs(self.stage.adapter.enemies) do
        local radius=e.legacy_hurtbox and math.max(unpack(e.legacy_hurtbox))/2 or e.legacy_ecl and 0 or 12
        out[#out+1]={object=e,x=e.x,y=-e.y,hp=e.hp,
            radius=radius,
            colli=radius>0 and not e.legacy_deleted and not e.legacy_no_damage and not e.legacy_no_shot_contact,
            invulnerable=(e.legacy_invulnerable_until or 0)>(self.stage.adapter.frame or 0)}
    end
    return out
end

function M:save_progress()
    local copy=require("tnr.core.immutable").copy
    for id,driver in pairs(self.drivers) do
        local player=self.session:get_player(id)
        if player and player.loadout then
            local by_id={}
            for _,_,instance in player.loadout:iter_equipped() do
                by_id[tostring(instance.instance_id)]=instance
            end
            for _,instance in ipairs(player.loadout.inventory.items) do
                by_id[tostring(instance.instance_id)]=instance
            end
            for _,weapon in ipairs(driver.weapon_manager.weapons) do
                local instance=by_id[tostring(weapon.instance.instance_id)]
                if instance and instance.definition_id==weapon.instance.definition_id then
                    instance.runtime_data=instance.runtime_data or {}
                    instance.runtime_data.affix_growth=copy(weapon.growth)
                end
            end
        end
    end
end

function M:input(id,input)
    local d,p=self.drivers[id],self.stage.players[id]
    if not d then return end
    local allowed=p.alive and not (self.stage.dialogue and self.stage.dialogue.active)
    local shots=d.bridge:update(d,input.focus and "LOW" or "HIGH",input.shoot==true,
        {x=p.x,y=-p.y,moving=(input.move_x or 0)~=0 or (input.move_y or 0)~=0,
         enemies=self:targets(),attack_allowed=allowed,room_generation=1})
    p.itembox=30*d.affixes.pickup_multiplier
    p.invulnerable=math.max(p.invulnerable,d.afterglow_invulnerability or 0)
    for _,shot in ipairs(shots) do
        self.shots[#self.shots+1]=Projectile.new(shot,d.weapon_manager:find(shot.source_instance_id),d.affixes)
    end
    local g=d.p_gauge
    if g.event then
        self.active_gauge=g
        local kept={}
        for _,s in ipairs(self.stage.adapter.shots) do if not s.p_hazard then kept[#kept+1]=s end end
        self.stage.adapter.shots=kept
        if g.event==2 then
            local copy=require("tnr.core.immutable").copy
            local count=#kept
            for i=1,count do
                local s=kept[i]
                if not s.player_bullet then
                    -- The presentation VM is rebuilt from the copied age.
                    -- A deep table copy would drop its animation methods.
                    local state={}
                    for key,value in pairs(s) do
                        if key~="legacy_bullet_animation" then state[key]=value end
                    end
                    local c=copy(state);c.p_hazard=true;c.reflected=not s.reflected
                    kept[#kept+1]=c
                end
            end
        end
    end
    if self.active_gauge==g and g.hazard==1 and g.hazard_frames>0 and g.frame%3==0 then
        for _=1,4 do
            self.stage.adapter:spawn_bullet(nil,-190+d.p_rng:next_float()*380,-4,
                2+d.p_rng:next_float()*2,math.pi/2,0,0,false,2)
            local s=self.stage.adapter.shots[#self.stage.adapter.shots];s.p_hazard=true
        end
    end
end

function M:update()
    if self.stage.dialogue and self.stage.dialogue.active then return end
    local targets=self:targets()
    local kept,fields={},{}
    for _,s in ipairs(self.shots) do
        s:update(targets,function(t,damage,shot)
            if (t.object.hp or 0)<=0 or t.object.legacy_no_damage then return false end
            local id=shot.owner_player_id or s.owner_player_id or 1
            local player=self.stage.players[id]
            local amount=damage*M.DAMAGE_SCALE*(1+(player and player.training_damage_bonus or 0))
            self.stage.adapter:damage_enemy(t.object,amount)
            if self.stage.coop then self.stage.coop.aggro:record(id,amount) end
            t.object.legacy_last_owner=id
            return true
        end,function(shot,weapon) fields[#fields+1]=Projectile.new(shot,weapon,s.affix_runtime) end)
        if not s.dead then kept[#kept+1]=s end
    end
    for _,s in ipairs(fields) do kept[#kept+1]=s end
    self.shots=kept
end

function M:pickup(id,item)
    local d=self.drivers[id];if not d then return end
    if item.kind=="power" then d.p_gauge:restore(10,"pickup")
    elseif item.kind=="power_large" or item.kind=="full_power" then d.p_gauge:restore(20,"pickup")
    elseif item.kind=="money" then self.stage.session.money=(self.stage.session.money or 0)+1 end
end

function M:draw(left,top,scale)
    local api=self.stage.lstg
    if not api.CheckRes or not api.Render or not api.Render4V then return end
    for _,s in ipairs(self.shots) do
        local alpha = s.owner_player_id == self.stage.local_player_id and 255 or 180
        ProjectileArt.render_projectile(api, s, left + (s.x + 192) * scale, top + s.y * scale, scale, alpha)
    end
end

function M:draw_supports(id,left,top,scale)
    local api,driver=self.stage.lstg,self.drivers[id]
    if not driver or not api.CheckRes or not api.Render then return end
    local alpha = id == self.stage.local_player_id and 255 or 180
    ProjectileArt.render_supports(driver.support_manager.last_entities, alpha, api, left + 192 * scale, top, scale)
end

function M:draw_hud()
    local api=self.stage.lstg
    if not api.RenderTTF then return end
    local function rect(color,l,r,b,t) api.SetImageState("tnr-white","",api.Color(unpack(color)));api.RenderRect("tnr-white",l,r,b,t) end
    local function text(s,x,y) api.RenderTTF("Sans",s,x,x+270,y,y+20,0,api.Color(255,255,230,230),0.6) end
    for id,d in pairs(self.drivers) do
        local g=d.p_gauge;local l,y=806,388-(id-1)*170
        text(string.format("P%d  %.1f%%",id,g.value),l,y+20)
        rect({220,30,25,40},l,l+270,y,y+12)
        rect({255,240,60,90},l,l+270*g.value/g.maximum,y,y+12)
        rect({255,255,230,220},l+270*30/g.maximum-1,l+270*30/g.maximum+1,y-2,y+14)
        rect({255,110,210,255},l+242,l+244,y-2,y+14)
        text(string.format("渴血兽 %.0f%%",g.progress/g.progress_maximum*100),l,y-22)
        rect({220,35,15,25},l,l+270,y-34,y-31)
        rect({255,210,35,65},l,l+270*g.progress/g.progress_maximum,y-34,y-31)
        if api.Render and rawget(_G,"lstg") then
            require("tnr.character.runtime.status_art").grid(d.affixes:statuses(),l,y-56,270,d.affixes,text)
        end
    end
end

function M:draw_player_effects(left,top,scale)
    local api=self.stage.lstg
    for id,d in pairs(self.drivers) do
        local p=self.stage.players[id];local g=d.p_gauge
        local x,y=left+(p.x+192)*scale,top-p.y*scale
        if api.Render4V and self.active_gauge==g and g.hazard==3 and g.hazard_frames>0 then
            require("tnr.character.runtime.vision_mask").render(api,x,y,scale)
        end
        if g.resting then
            api.SetImageState("tnr-white","",api.Color(220,255,50,70))
            for i=1,24 do
                local a=math.rad(i*15+g.frame*3)
                local px,py=x+math.cos(a)*24*scale,y+math.sin(a)*24*scale
                api.RenderRect("tnr-white",px-2,px+2,py-2,py+2)
            end
        end
    end
end
return M
