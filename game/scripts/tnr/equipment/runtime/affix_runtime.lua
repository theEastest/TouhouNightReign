local Catalog = require("tnr.equipment.affix_catalog")
local RNG = require("tnr.core.rng")
local A = {}; A.__index=A
function A.new(driver,player,session)
 local self=setmetatable({driver=driver,player=player,session=session,entries={},frame=0,bread={},frost=0,
  frost_level=0,shield=0,bomb_frames=0,pickup_multiplier=1,rng=RNG.new((session.run_seed or 1)+driver.player_id*131)},A)
 local g=driver.p_gauge
 for _,w in ipairs(driver.weapon_manager.weapons) do
  w.affix_runtime=self
  w.instance.runtime_data=w.instance.runtime_data or {}
  w.instance.runtime_data.affix_growth=w.instance.runtime_data.affix_growth or {siphon=0,misses=0,bomb_kills=0,life_kills=0}
  w.growth=w.instance.runtime_data.affix_growth
  w.combo={frames=0,epoch=0,last_persistent_hit=-1000,persistent=false}
  for _,a in ipairs(w.random_affixes) do if Catalog.by_id[a.id] then self.entries[#self.entries+1]={weapon=w,id=a.id,value=Catalog.value(a),level=a.level or 1} end end
 end
 g.maximum=100+self:sum("capacity"); g.value=g.maximum
 g.progress_maximum=100+self:sum("thirst")
 g.rest_delay=self:sum("quick_rest")>0 and 30 or 60
 g.hot_duration=math.max(0,300-self:sum("cooling"))
 self.frost_level=self:max("frost")
 self.frost_max=({0,33.3,66.6,76.6})[self.frost_level+1]
 for _,e in ipairs(self.entries) do if e.id=="pickup" then self.pickup_multiplier=self.pickup_multiplier*(1+e.value) end end
 g:on("restored",function(data)
  if data.source=="pickup" and data.amount>0 and data.before<100 and data.after>=100 then
   local duration=self:sum("bread")
   if duration>0 then self.bread[#self.bread+1]=duration; if self.on_bread then self.on_bread(self.player,self.bread) end end
  elseif data.source=="pickup" and data.amount>0 and data.before>=100 and self:sum("bread")>0 then
   self.bread[#self.bread+1]=self:sum("bread"); if self.on_bread then self.on_bread(self.player,self.bread) end
  end
 end)
 return self
end
function A:sum(id,weapon)
 local v=0; for _,e in ipairs(self.entries) do if e.id==id and (not weapon or e.weapon==weapon) then v=v+e.value end end; return v
end
function A:max(id)
 local v=0; for _,e in ipairs(self.entries) do if e.id==id then v=math.max(v,e.value) end end; return v
end
function A:cost(weapon) return math.max(0,1-self:sum("economy",weapon)) end
function A:reset_combo(w) w.combo.frames=0;w.combo.epoch=w.combo.epoch+1;w.combo.last_persistent_hit=-1000;w.combo.persistent=false end
function A:update(mode,firing,allowed)
 self.frame=self.frame+1; self.mode=mode
 self.shield=math.max(0,self.shield-1); self.bomb_frames=math.max(0,self.bomb_frames-1)
 for i=#self.bread,1,-1 do self.bread[i]=self.bread[i]-1; if self.bread[i]<=0 then table.remove(self.bread,i) end end
 self.frost_bonus=0
 if self.frost_level>0 then
  if firing and allowed then
   if self.frost>0 then self.frost_bonus=self.frost>33.3 and 0.30 or 0.15 end
   self.frost=math.max(0,self.frost-5/60)
  elseif not firing and allowed then self.frost=math.min(self.frost_max,self.frost+11.1/60) end
 end
 for _,w in ipairs(self.driver.weapon_manager.weapons) do
  if self:sum("combo",w)>0 then
   if not firing or not allowed or not w:is_active(mode) or self.shield>0 then self:reset_combo(w)
   else
    w.combo.frames=w.combo.frames+1
    if ((w.definition.metadata or {}).beam or w.combo.persistent) and w.combo.frames%60==0 and w.combo.last_persistent_hit<self.frame-59 then self:reset_combo(w) end
    if w.combo.frames>=300 then
     self.shield=600
     for _,other in ipairs(self.driver.weapon_manager.weapons) do self:reset_combo(other) end
    end
   end
  end
 end
end
function A:multiplier(kind)
 local g=self.driver.p_gauge; local v=1
 for _,e in ipairs(self.entries) do
  if (e.id=="high_p" and g.value>g.maximum*0.9) or (e.id=="low_p" and g.value<30) then v=v*(1+e.value) end
 end
 local mode_bonus=self:sum(self.mode=="LOW" and "low_fire" or "high_fire")
 local growth=0;for _,w in ipairs(self.driver.weapon_manager.weapons) do growth=growth+w.growth.misses*self:sum("unyielding",w) end
 v=v*(1+mode_bonus)*(1+growth)*(1+(self.frost_bonus or 0))
 if kind=="support" then v=v*(1+self:sum("support_fire")) end
 if self.bomb_frames>0 then v=v*(1+self:sum("bomb_attack")) end
 return v
end
function A:decorate(shot,weapon)
 shot.metadata=shot.metadata or {}
 shot.damage=shot.damage*self:multiplier(shot.source_type)
 if weapon then
  shot.damage=shot.damage*(1+weapon.growth.siphon)
  local tracking=self:sum("tracking",weapon)
  if tracking>0 and not shot.metadata.beam then
   -- Affix grants weak guidance to straight bullets, then improves its turn rate.
   if not shot.metadata.homing then shot.metadata.homing_turn_ratio=0.5 end
   shot.metadata.homing=true
   shot.metadata.homing_turn_multiplier=(shot.metadata.homing_turn_multiplier or 1)*(1+tracking)
  end
  shot.metadata.combo_epoch=weapon.combo.epoch
  shot.metadata.combo_eligible=self.shield==0 and weapon.combo.frames>0
  if shot.metadata.combo_eligible and (shot.metadata.beam or shot.metadata.is_wind_field) then weapon.combo.persistent=true end
 end
end
function A:hit(weapon,projectile)
 self.driver.p_gauge:add_points(self:sum("hit_p",weapon),"weapon_hit")
 if (projectile.beam or projectile.field) and projectile.metadata.combo_eligible
  and projectile.metadata.combo_epoch==weapon.combo.epoch then
  weapon.combo.last_persistent_hit=self.frame;weapon.combo.persistent=true
 end
end
function A:projectile_end(weapon,p)
 if p.metadata.combo_eligible and p.metadata.combo_epoch==weapon.combo.epoch and self.shield==0
  and not p.beam and not p.field and p.hit_count==0 then self:reset_combo(weapon) end
end
function A:resource(kind,amount)
 if amount<=0 then return end
 if self.on_resource then self.on_resource(kind,amount);return end
 self.session["add_"..kind](self.session,self.driver.player_id,amount,"weapon_affix")
end
function A:kill(weapon,target)
 -- A native boss reuses one object for its cards; only its final defeat counts.
 if target and target._bosssys and not target.is_final then return end
 if target and target._tnr_affix_killed then return end
 if target then target._tnr_affix_killed=true end
 if weapon then
  self:resource("money",self:sum("coin",weapon))
  weapon.growth.siphon=weapon.growth.siphon+self:sum("siphon",weapon)
 end
 for _,w in ipairs(self.driver.weapon_manager.weapons) do
  for _,entry in ipairs(w.random_affixes) do
   if entry.id=="bomb_meter" or entry.id=="life_meter" then
    local key=entry.id=="bomb_meter" and "bomb_kills" or "life_kills"
    w.growth[key]=w.growth[key]+1
    local threshold=Catalog.value(entry)
    if w.growth[key]>=threshold then w.growth[key]=w.growth[key]-threshold;self:resource(entry.id=="bomb_meter" and "bomb" or "life",1) end
   end
  end
 end
end
function A:bomb() if self:sum("bomb_attack")>0 then self.bomb_frames=1200 end end
function A:miss()
 for _,w in ipairs(self.driver.weapon_manager.weapons) do if self:sum("unyielding",w)>0 then w.growth.misses=w.growth.misses+1 end;self:reset_combo(w) end
 self.shield=0
end
function A:defend(lives)
 if self.shield>0 then self.shield=0;for _,w in ipairs(self.driver.weapon_manager.weapons) do self:reset_combo(w) end;return true end
 for _,e in ipairs(self.entries) do
  if e.id=="dodge" or (e.id=="last_dodge" and lives<=0) then if self.rng:next_float()<e.value then return true end end
 end
 return false
end
-- Active status descriptors only; the HUD packs this array afresh every frame.
-- Amounts of damage never enter the combat HUD. Kill meters are progress bars,
-- not a second resource counter.
function A:statuses()
 local result={}
 local function add(id,icon,label,ratio,badge)
  result[#result+1]={id=id,icon=icon,label=label,ratio=ratio,badge=badge}
 end
 local g=self.driver.p_gauge
 if g.hot_frames>0 then add("hot",14,"super hot",g.hot_frames/math.max(1,g.hot_duration),string.format("%.1f",g.hot_frames/60)) end
 if #self.bread>0 then
  add("bread",1,"bread",nil,tostring(#self.bread))
 end
 if self.frost_level>0 and self.frost>0 then add("frost",self.frost>66.6 and 4 or self.frost>33.3 and 3 or 2,"寒气",self.frost/self.frost_max) end
 local combo=0;for _,w in ipairs(self.driver.weapon_manager.weapons) do combo=math.max(combo,w.combo.frames) end
 if self.shield>0 then add("shield",5,"护盾",self.shield/600,string.format("%.1f",self.shield/60))
 elseif combo>0 then add("combo",5,"连击",combo/300) end
 if self.bomb_frames>0 then add("bomb_attack",6,"Bomb增益",self.bomb_frames/1200) end
 if g.value>g.maximum*.9 and self:sum("high_p")>0 then add("high_p",15,"高P") end
 if g.value<30 and self:sum("low_p")>0 then add("low_p",16,"低P") end
 local defiance,siphon=0,0
 for _,w in ipairs(self.driver.weapon_manager.weapons) do defiance=defiance+w.growth.misses*self:sum("unyielding",w);siphon=siphon+w.growth.siphon end
 if defiance>0 then add("unyielding",7,"不甘") end
 if siphon>0 then add("siphon",8,"汲取") end
 for i,e in ipairs(self.entries) do
  if e.id=="bomb_meter" and e.weapon.growth.bomb_kills>0 then add("bomb_meter_"..i,6,"Bomb积累",e.weapon.growth.bomb_kills/e.value) end
  if e.id=="life_meter" and e.weapon.growth.life_kills>0 then add("life_meter_"..i,10,"残机积累",e.weapon.growth.life_kills/e.value) end
 end
 return result
end
function A:to_table()
 local copy=require("tnr.core.immutable").copy
 local result={frame=self.frame,mode=self.mode,bread=copy(self.bread),frost=self.frost,
  frost_bonus=self.frost_bonus,shield=self.shield,bomb_frames=self.bomb_frames,rng_state=self.rng.state,weapons={}}
 for i,w in ipairs(self.driver.weapon_manager.weapons) do result.weapons[i]={growth=copy(w.growth),combo=copy(w.combo)} end
 return result
end
function A:apply_snapshot(data)
 local copy=require("tnr.core.immutable").copy
 for _,k in ipairs({"frame","mode","frost","frost_bonus","shield","bomb_frames"}) do self[k]=data[k] end
 self.bread=copy(data.bread or {});self.rng=RNG.new(data.rng_state)
 for i,item in ipairs(data.weapons or {}) do
  local w=self.driver.weapon_manager.weapons[i]
  if w then w.growth=copy(item.growth);w.instance.runtime_data.affix_growth=w.growth;w.combo=copy(item.combo) end
 end
end
return A
