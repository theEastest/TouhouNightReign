local Affixes=require("tnr.equipment.runtime.affix_runtime")
local Gauge=require("tnr.character.runtime.p_gauge")
local Catalog=require("tnr.equipment.affix_catalog")
local Equipment=require("tnr.equipment.phase1_catalog")
local Instance=require("tnr.equipment.equipment_instance")
return function(eq,yes)
 local function near(a,b,label) yes(math.abs(a-b)<1e-7,label..": "..a.." / "..b) end
 local function fixture(list)
  local d={player_id=1,p_gauge=Gauge.new(),weapon_manager={weapons={}}}
  local resources={money=0,bomb=0,life=0}
  for _,a in ipairs(list) do
   local w={instance={runtime_data={}},random_affixes={a},definition={metadata={}},is_active=function() return true end}
   d.weapon_manager.weapons[#d.weapon_manager.weapons+1]=w
  end
  local a=Affixes.new(d,{}, {run_seed=7})
  a.on_resource=function(k,n) resources[k]=resources[k]+n end
  return a,d.p_gauge,d.weapon_manager.weapons,resources
 end
 local seen={}
 for id,d in pairs(Equipment.registry:all()) do
  local i=Instance.new(d,1)
  if Catalog.eligible(d) then
   yes(#i.random_affixes==1 or (d.rarity=="LEGENDARY" and #i.random_affixes==2),"eligible weapon affix count "..id)
  else eq(#i.random_affixes,0,"ineligible weapon has no random affixes "..id) end
  if Catalog.eligible(d) then
   for seed=1,250 do
    local rolled=Catalog.roll(d,seed)[1];seen[rolled.id]=true
    yes(not (rolled.id=="tracking" and d.metadata.beam),"beam excludes tracking")
    eq(Catalog.roll(d,seed)[1].id,rolled.id,"deterministic offer affix")
   end
   local restored=Instance.from_table(i:to_table())
   eq(restored.random_affixes[1].id,i.random_affixes[1].id,"save retains affix")
  end
 end
 for _,d in ipairs(Catalog.definitions) do yes(seen[d.id],"affix reachable: "..d.id) end
 for id,exclusive in pairs(Catalog.exclusive) do eq(Equipment.registry:get(id).exclusive_affix.id,exclusive.id,"legendary extra exclusive") end
 local a,g,w=fixture({{id="capacity",level=3},{id="capacity",level=2},{id="thirst"},{id="thirst"},{id="hit_p",level=3}})
 eq(g.maximum,160,"additive max P");eq(g.value,160,"enter full");eq(g.progress_maximum,140,"additive thirst max")
 g.value=80;a:hit(w[5],{metadata={}});near(g.value,81.5,"hit restores absolute points")
 a:hit(w[1],{metadata={}});near(g.value,81.5,"unaffixed source cannot restore")
 a,g,w=fixture({{id="high_p",level=3},{id="high_p",level=1},{id="capacity",level=3},{id="low_p",level=3},{id="low_p",level=2}})
 a.mode="HIGH";g.value=125;near(a:multiplier(),1,"high threshold moves to126")
 g.value=127;near(a:multiplier(),1.21*1.07,"high P independent multipliers")
 g.value=29;near(a:multiplier(),1.3*1.2,"low threshold absolute30")
 g.value=31;near(a:multiplier(),1,"capacity does not move low threshold")
 a,g,w=fixture({{id="low_fire",level=3},{id="low_fire",level=2},{id="high_fire",level=1},{id="support_fire",level=3},{id="pickup",level=3},{id="pickup",level=2}})
 a.mode="LOW";near(a:multiplier(),1.25,"mode bonus adds");near(a:multiplier("support"),1.25*1.15,"support only multiplier")
 a.mode="HIGH";near(a:multiplier(),1.05,"high mode only");near(a.pickup_multiplier,1.3*1.2,"pickup multiplies")
 a,g,w=fixture({{id="bread",level=1},{id="bread",level=2}})
 g.value=95;g:restore(10,"pickup");eq(a.bread[1],180,"bread durations add")
 a:update("HIGH",false,true);g.value=95;g:restore(10,"pickup")
 eq(#a.bread,2,"bread stacks");eq(a.bread[1],179,"old stack independent");eq(a.bread[2],180,"new independent timer")
 for _=1,179 do a:update("HIGH",false,true) end;eq(#a.bread,1,"old layer expires alone")
 a,g,w=fixture({{id="frost",level=1},{id="frost",level=3}})
 eq(a.frost_max,76.6,"frost strongest only")
 for _=1,60 do a:update("HIGH",false,true) end;near(a.frost,11.1,"frost regen")
 a.frost=70;a:update("HIGH",true,true);near(a.frost,70-5/60,"frost drain");near(a.frost_bonus,.3,"third tier30 percent")
 a.frost=20;a:update("HIGH",true,true);near(a.frost_bonus,.15,"first tier15 percent")
 a,g,w=fixture({{id="combo"}})
 a:update("HIGH",true,true)
 local old={damage=1,metadata={}};a:decorate(old,w[1])
 a:update("HIGH",false,true);eq(w[1].combo.frames,0,"stop resets combo")
 a:update("HIGH",true,true);a:projectile_end(w[1],{metadata=old.metadata,hit_count=0})
 eq(w[1].combo.frames,1,"old projectile cannot reset new window")
 local pending={damage=1,metadata={}};a:decorate(pending,w[1])
 for _=2,300 do a:update("HIGH",true,true) end
 eq(a.shield,600,"shield granted while counted projectile still flying")
 a:projectile_end(w[1],{metadata=pending.metadata,hit_count=0});eq(a.shield,600,"late miss cannot revoke granted shield")
 yes(a:defend(2),"shield blocks hit");eq(a.shield,0,"shield consumed");eq(w[1].combo.frames,0,"fresh combo after shield")
 a:update("HIGH",true,true);local miss={damage=1,metadata={}};a:decorate(miss,w[1]);a:projectile_end(w[1],{metadata=miss.metadata,hit_count=0})
 eq(w[1].combo.frames,0,"current miss resets")
 w[1].definition.metadata.beam=true
 for _=1,60 do a:update("HIGH",true,true) end;eq(w[1].combo.frames,0,"beam no hit in one second resets")
 for n=1,300 do
  a:update("HIGH",true,true)
  local p={damage=1,metadata={beam=true}};a:decorate(p,w[1]);p.beam=true
  if n%30==1 then a:hit(w[1],p) end
 end
 eq(a.shield,600,"beam hits within each second qualify")
 a,g,w=fixture({{id="bomb_attack",level=1},{id="bomb_attack",level=3},{id="unyielding"}})
 a:bomb();a.mode="HIGH";near(a:multiplier(),1.5,"Bomb bonuses add")
 a:miss();near(a:multiplier(),1.5*1.03,"miss permanently improves affix")
 for _=1,1200 do a:update("HIGH",false,true) end;near(a:multiplier(),1.03,"Bomb ends after20s")
 local resources;a,g,w,resources=fixture({{id="coin",level=3},{id="siphon",level=3},{id="bomb_meter",level=3},{id="life_meter",level=3}})
 local target={};a:kill(w[1],target);a:kill(w[1],target);eq(resources.money,3,"final blow coin once")
 for _=2,100 do a:kill(w[2],{}) end
 eq(resources.bomb,2,"50 kills per Bomb");eq(resources.life,1,"100 kills grants life")
 near(w[2].growth.siphon,.015*99,"per-weapon permanent siphon")
 near(w[1].growth.siphon,0,"other weapon cannot gain siphon")
 local snapshot=a:to_table();a:kill(w[2],{});a:apply_snapshot(snapshot)
 near(w[2].growth.siphon,.015*99,"snapshot restores growth")
 eq(w[2].instance.runtime_data.affix_growth,w[2].growth,"growth stored on instance")
 a,g,w=fixture({{id="quick_rest"},{id="quick_rest"},{id="cooling",level=3},{id="cooling",level=3},{id="cooling",level=3},{id="economy",level=1},{id="tracking",level=3}})
 eq(g.rest_delay,30,"rest delay nonstack");eq(g.hot_duration,0,"overheat reduction clamps zero")
 near(a:cost(w[6]),.8,"weapon own P reduction");near(a:cost(w[1]),1,"not global economy")
 local shot={damage=1,metadata={}};a:decorate(shot,w[7]);yes(shot.metadata.homing,"tracking guides straight bullets");eq(shot.metadata.homing_turn_multiplier,2,"tracking turning rate")
 a,g,w=fixture({{id="dodge",level=1},{id="dodge",level=3},{id="last_dodge",level=3}})
 local rolls={.9,.4};a.rng.next_float=function() return table.remove(rolls,1) end
 yes(a:defend(1),"second independent dodge succeeds")
 rolls={.9,.9,.6};yes(a:defend(0),"zero life extra dodge")
 rolls={.9,.9};eq(a:defend(1),false,"last-life dodge inactive with reserves")
 -- Exercise the shared combat path, not just the affix methods.
 local Session=require("tnr.core.game_session")
 local Bridge=require("tnr.character.runtime.character_runtime_bridge")
 local Projectile=require("tnr.character.runtime.projectile_runtime")
 local session=Session.new({run_seed=123}):start_new()
 local definition=Equipment.registry:get("hakurei_dream_sealing_needle")
 local instance=Instance.new(definition,1,{random_affixes={{id="siphon",level=3}}})
 session:get_player(1).loadout:set_slot("high_weapons",1,instance)
 local bridge=Bridge.new(session,1);local runtime=bridge:create_runtime()
 local shots=bridge:update(runtime,"HIGH",true,{x=0,y=0})
 yes(#shots>0,"equipped affix weapon fires through bridge")
 local weapon=runtime.weapon_manager:find(instance.instance_id)
 local p=Projectile.new({x=0,y=0,angle=90,speed=1,damage=10,source_instance_id=instance.instance_id,metadata={}},weapon)
 local target={x=0,y=1,hp=1,radius=2}
 p:update({target},function(t,n) t.hp=t.hp-n;return true end)
 near(instance.runtime_data.affix_growth.siphon,.015,"real projectile kill updates equipment growth")
 local restored=Instance.from_table(instance:to_table())
 near(restored.runtime_data.affix_growth.siphon,.015,"save retains permanent growth")
 local next_runtime=bridge:create_runtime();bridge:update(next_runtime,"HIGH",false,{x=0,y=0})
 near(next_runtime.weapon_manager:find(instance.instance_id).growth.siphon,.015,"next stage retains growth")
 runtime.affixes:kill(weapon,{_bosssys={},is_final=false})
 near(instance.runtime_data.affix_growth.siphon,.015,"intermediate boss card is not a kill")
 local Shop=require("tnr.shop.shop_service");local shop=Shop.new(session)
 local offers=shop:open({id=23,content_seed=7});session.run_state="SHOP"
 local offer=offers[4];yes(shop:purchase(1,4),"buy rolled weapon")
 local owned=session:get_player(1).loadout.inventory
 local found=false
 for _,item in ipairs(owned.items) do
  if item.definition_id==offer.definition_id and item.instance_id~=instance.instance_id then
   eq(item.random_affixes[1].id,offer.random_affixes[1].id,"purchase keeps preview affix");found=true
  end
 end
 yes(found,"purchased weapon found with preview affix")
 -- Support kills advance owner meters without stealing weapon-only benefits.
 local owner,pg,weapons,loot=fixture({{id="coin",level=3},{id="siphon",level=3},{id="bomb_meter",level=3},{id="life_meter",level=3}})
 weapons[3].growth.bomb_kills=49;weapons[4].growth.life_kills=99
 local support=Projectile.new({x=0,y=0,angle=90,speed=1,damage=10,source_type="support",metadata={}},nil,owner)
 local mob={x=0,y=1,hp=1,radius=2}
 support:update({mob},function(t,n) t.hp=t.hp-n;return true end)
 eq(loot.bomb,1,"support final blow advances Bomb meter")
 eq(loot.life,1,"support final blow advances life meter")
 eq(loot.money,0,"support cannot proc weapon-only coin")
 eq(weapons[2].growth.siphon,0,"support cannot proc weapon-only siphon")
 owner:kill(nil,mob);eq(loot.bomb,1,"generic backend death callback cannot duplicate reward")
end
