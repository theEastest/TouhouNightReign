local C = {}
C.definitions = {
 {id="hit_p",name="命中回复P",values={0.5,1,1.5}},
 {id="capacity",name="P槽上限提升",values={10,20,40}},
 {id="thirst",name="更不容易渴血",values={20}},
 {id="coin",name="抢夺金币",values={1,2,3}},
 {id="pickup",name="拾取加强",values={0.1,0.2,0.3}},
 {id="high_p",name="高P攻击强化",values={0.07,0.14,0.21}},
 {id="last_dodge",name="无残机闪避",values={0.3,0.5,0.7}},
 {id="low_p",name="低P攻击强化",values={0.1,0.2,0.3}},
 {id="low_fire",name="低速火力",values={0.05,0.1,0.15}},
 {id="high_fire",name="高速火力",values={0.05,0.1,0.15}},
 {id="support_fire",name="子机火力",values={0.05,0.1,0.15}},
 {id="bread",name="爱吃面包",values={60,120,180}},
 {id="frost",name="寒气炼成",values={1,2,3}},
 {id="tracking",name="追踪力",values={0.25,0.5,1},no_beam=true},
 {id="combo",name="连击护盾",values={1}},
 {id="bomb_attack",name="Bomb后攻击强化",values={0.2,0.25,0.3}},
 {id="unyielding",name="不甘",values={0.03}},
 {id="dodge",name="闪避",values={0.3,0.4,0.5}},
 {id="bomb_meter",name="击杀Bomb量表",values={100,75,50}},
 {id="life_meter",name="击杀残机量表",values={300,200,100}},
 {id="quick_rest",name="快速回复准备",values={30}},
 {id="cooling",name="过热时间缩短",values={60,90,120}},
 {id="siphon",name="击杀汲取",values={0.005,0.01,0.015}},
 {id="economy",name="P消耗降低",values={0.2,0.3,0.5}},
}
C.by_id = {}; for _,d in ipairs(C.definitions) do C.by_id[d.id]=d end
C.exclusive = { hakurei_dream_sealing_needle={id="sealing_streak",name="妖怪封针·连击增伤"},
 marisa_master_spark_weapon={id="mini_master_spark",name="极限火花·光束变身"},
 sanae_yasaka_divine_wind={id="wind_field",name="八坂神风·命中旋风"} }
function C.eligible(d) return d and d.equipment_type=="WEAPON" and not d.starter_only and not d.internal_only and not d.test_only end
function C.roll(d,seed)
 if not C.eligible(d) then return {} end
 local hash=17; local text=tostring(seed or d.weapon_id)
 for i=1,#text do hash=(hash*31+text:byte(i))%2147483647 end
 local rng=require("tnr.core.rng").new(hash)
 local pool={}; for _,a in ipairs(C.definitions) do if not (a.no_beam and (d.metadata or {}).beam) then pool[#pool+1]=a end end
 local first_index=rng:next_int(1,#pool)
 local a=pool[first_index]
 local result={{id=a.id,level=rng:next_int(1,#a.values)}}
 -- Legendary equipment can carry a second distinct random affix in addition
 -- to its inherent exclusive effect. The offer seed fixes both the count and
 -- the selections, so preview, acquisition and network peers agree.
 if d.rarity=="LEGENDARY" and #pool>1 and rng:next_int(1,2)==2 then
  local index=rng:next_int(1,#pool-1)
  if index>=first_index then index=index+1 end
  local second=pool[index]
  result[#result+1]={id=second.id,level=rng:next_int(1,#second.values)}
 end
 return result
end
function C.roll_support(d,seed)
 if not d or d.equipment_type~="SUPPORT" then return {} end
 local hash=17; local text=tostring(seed or d.support_id)
 for i=1,#text do hash=(hash*31+text:byte(i))%2147483647 end
 local rng=require("tnr.core.rng").new(hash)
 local ids={"support_fire","high_fire","low_fire","tracking"}
 local result={}
 local first=rng:next_int(1,#ids)
 local function add(index)
  local definition=C.by_id[ids[index]]
  result[#result+1]={id=definition.id,level=rng:next_int(1,#definition.values)}
 end
 add(first)
 if d.rarity=="LEGENDARY" and rng:chance(0.5) then
  local second=rng:next_int(1,#ids-1)
  if second>=first then second=second+1 end
  add(second)
 end
 return result
end
function C.value(a)
 local d=C.by_id[a.id]; return d and d.values[math.max(1,math.min(#d.values,tonumber(a.level) or 1))] or 0
end
function C.label(a)
 local d=C.by_id[a.id]; if not d then return tostring(a.id) end
 local v=C.value(a)
 local details={
  hit_p=string.format("本武器每次命中回复 %.1f P",v),
  capacity=string.format("上限 +%g%%（加算）",v), thirst=string.format("渴血上限 +%g%%",v),
  coin=string.format("本武器击杀 +%g 金币",v),pickup=string.format("半径 +%g%%（乘算）",v*100),
  high_p=string.format("P>上限90%%：攻击 +%g%%",v*100),low_p=string.format("P<30：攻击 +%g%%",v*100),
  last_dodge=string.format("无残机时 %g%% 概率",v*100),dodge=string.format("%g%% 概率（独立判定）",v*100),
  low_fire=string.format("低速攻击 +%g%%",v*100),high_fire=string.format("高速攻击 +%g%%",v*100),
  support_fire=string.format("子机攻击 +%g%%",v*100),bread=string.format("P点回至100：bread %gs/层",v/60),
  frost=string.format("停火充能；最高%d级，增伤%d%%",math.max(1,math.min(3,tonumber(a.level) or 1)),(tonumber(a.level) or 1)==1 and 15 or 30),tracking=string.format("转向速度 +%g%%；直射获得弱追踪",v*100),
  combo="连续命中5秒：10秒一次护盾；停火清零",bomb_attack=string.format("Bomb后20秒攻击 +%g%%",v*100),
  unyielding="每次miss永久攻击 +3%（装备时生效）",bomb_meter=string.format("每击杀%g敌人 +1 Bomb",v),
  life_meter=string.format("每击杀%g敌人 +1 残机",v),quick_rest="静止停火0.5秒进入快速回复",
  cooling=string.format("过热禁火 -%gs（最低0）",v/60),siphon=string.format("本武器每击杀永久攻击 +%g%%",v*100),
  economy=string.format("本武器P消耗 -%g%%",v*100),
 }
 return d.name.." · "..details[a.id]
end
function C.tier_color(a)
 local d=C.by_id[a.id]
 local count=d and #d.values or 1
 local level=math.max(1,math.min(count,math.floor(tonumber(a.level) or 1)))
 if level==count then return {255,255,214,78} end
 if level==count-1 then return {255,240,240,240} end
 return {255,155,160,170}
end
return C
