-- Opt-in native integration / HUD fixture. Never changes ordinary loadouts.
local Smoke={}
function Smoke.prepare(d)
 if d.affix_smoke_ready then return end
 d.affix_smoke_ready=true
 local w=d.weapon_manager.weapons[1]
 w.random_affixes={{id="frost",level=3},{id="combo"},{id="bread",level=3},
  {id="bomb_attack",level=3},{id="unyielding"},{id="siphon",level=3},
  {id="bomb_meter",level=3},{id="life_meter",level=3},{id="hit_p",level=3},{id="coin",level=3}}
end
function Smoke.update(d,p)
 p.protect=999
 local a,g=d.affixes,d.p_gauge
 d.affix_smoke_frame=(d.affix_smoke_frame or 0)+1
 if d.affix_smoke_frame==1 then
  local w=d.weapon_manager.weapons[1]
  g.value=95;item_power.collect();assert(#a.bread==1,"real P pickup grants bread")
  a:bomb();a:miss()
  local Dummy=Class(enemy)
  function Dummy:init() enemy.init(self,1,1,false,false,false);self.x=0;self.y=0;self.protect=false end
  function Dummy:frame() end
  function Dummy:render() end
  if lstg.RegisterGameObjectClass then lstg.RegisterGameObjectClass(Dummy) end
  local function hit(source)
   local target=New(Dummy)
   local provider=function() return {{object=target,x=0,y=0,hp=target.hp,radius=8,colli=true}} end
   local shot={x=0,y=-1,angle=90,speed=1,damage=10,owner_player_id=d.player_id,
    source_instance_id=source and source.instance_id,source_type=source and "weapon" or "support",
    projectile_type="reimu_bullet_red",metadata={}}
   local bullet=require("tnr.character.runtime.native_projectile").spawn(shot,source,provider,a)
   bullet.class.frame(bullet)
   assert(target.hp<=0,"native projectile reaches actual enemy collision")
   Del(target)
  end
  g.value=50;w.growth.bomb_kills=49;w.growth.life_kills=99
  local bombs,lives,money=lstg.var.bomb,lstg.var.lifeleft,lstg.var.tnr_stage_money or 0
  hit(w)
  assert(g.value==51.5,"native hit restores source P")
  assert(w.growth.siphon==.015,"native final blow grows source weapon")
  assert(lstg.var.bomb==bombs+1 and lstg.var.lifeleft==lives+1,"native kill meters award resources")
  assert(lstg.var.tnr_stage_money==money+3,"native source coin bonus")
  w.growth.bomb_kills=49;w.growth.life_kills=99
  hit(nil)
  assert(lstg.var.bomb==bombs+2 and lstg.var.lifeleft==lives+2,"native support kill meters")
  assert(g.value==51.5 and w.growth.siphon==.015 and lstg.var.tnr_stage_money==money+3,"support cannot steal source-only effects")
  w.growth.bomb_kills=1;w.growth.life_kills=1
 end
 -- Hold representative statuses long enough for visual inspection.
 a.frost=70;a.shield=600;a.bomb_frames=1200;a.bread={180,120}
 if d.affix_smoke_frame==120 then
  local f=assert(io.open("affix_smoke_result.txt","w"))
  f:write("passed: real native projectile collisions, weapon/support kill attribution, P pickup/hit, coin, Bomb/life rewards, growth, status grid\n");f:close()
 end
end
return Smoke
