return function(eq, yes)
 local function run(path, env)
  local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close()
  local chunk
  if setfenv then chunk=assert(loadstring(s));setfenv(chunk,env)
  else chunk=assert(load(s,path,"t",env)) end
  chunk()
 end
 local e=setmetatable({object={},scoredata={wuer_achi={[2]=1}},
  Class=function() return {} end,LoadSound=function() end,
  lstg={DoFile=function() end}}, {__index=_G})
 run("game/scripts/LegacyTHlib/activity_compat.lua",e)
 e.InitActivityScoreData()
 eq(e.scoredata.wuer_achi[1],0,"new achievement counter initialized")
 eq(e.scoredata.wuer_achi[2],1,"existing achievement preserved")
 eq(e.scoredata.stage_clear[2][17],0,"campaign flags initialized")
 e.scoredata={};e.InitActivityScoreData()
 eq(e.scoredata.ae_card[2],0,"works after score root is replaced")
 eq(e.scoredata.marisa_missle,0,"classic missile counter initialized")
 eq(e.scoredata.reimu_c_time,0,"classic special counter initialized")
 local woods=setmetatable({object={},Class=function() return {} end,
  background={init=function() end},lstg={view3d={eye={1,2,3},at={4,5,6}}},
  LoadImageFromFile=function() end,LoadTexture=function() end,LoadImage=function() end,
  SetImageState=function() end,Set3D=function() end,Color=function() return 0 end}, {__index=_G})
 run("game/legacy/source/activity7/wuer_woods.lua",woods)
 local ticks=0
 woods.wuer_woods_background.frame=function() ticks=ticks+1 end
 woods.wuer_woods_background.init({})
 eq(ticks,400,"woods prewarms its own class without campaign globals")
 local f=assert(io.open("game/scripts/legacy_native_main.lua","rb"))
 local source=f:read("*a");f:close()
 local fn=assert(source:match("(local function build_native_card_sequence.-)\nlocal function native_read_boss_status"))
 local compile=loadstring or load
 local sequence=assert(compile(fn.."\nreturn build_native_card_sequence"))()
 local entrance={is_move=true};local dialog={is_dialog=true};local first={is_combat=true};local selected={is_combat=true}
 local cards=sequence({cards={entrance,dialog,first,selected}},4)
 eq(cards[1],entrance,"late practice preserves original entrance")
 eq(cards[2],selected,"practice does not run earlier attacks")
 local second_move={is_move=true}
 cards=sequence({cards={entrance,second_move,selected}},3)
 eq(cards[1],entrance,"multiple entrance moves retain original order")
 eq(cards[2],second_move,"second entrance move remains second")
 local f=assert(io.open("game/scripts/LegacyTHlib/editor.lua","rb"))
 local editor_source=f:read("*a");f:close()
 local set_a=assert(editor_source:match("(function SetA.-)\nfunction _set_a"))
 local physics=setmetatable({cos=function() return 0 end,sin=function() return -1 end},{__index=_G})
 local chunk
 if setfenv then chunk=assert(loadstring(set_a));setfenv(chunk,physics)
 else chunk=assert(load(set_a,"SetA","t",physics)) end
 chunk()
 local projectile=setmetatable({}, {__newindex=function(t,k,v)
  if k=="ag" or k=="maxv" or k=="maxvy" then yes(type(v)=="number","native physics accepts numeric attributes only") end
  rawset(t,k,v)
 end})
 physics.SetA(projectile,0.05,270,3,nil,0,true)
 eq(projectile.ag,0,"omitted reference gravity means no additional gravity")
 eq(projectile.ay,-0.05,"original acceleration retained")
 eq(projectile.maxv,3,"speed cap retained")
 local smear_source=assert(editor_source:match("(smear.func = function.-)\nfunction smear:init"))
 local pool,loads={},0
 local particle_env=setmetatable({smear={cache={}},lstg={tmpvar={},CheckRes=function(_,name) return pool[name] end},
  LoadPS=function(name) loads=loads+1;pool[name]=true end},{__index=_G})
 if setfenv then chunk=assert(loadstring(smear_source));setfenv(chunk,particle_env)
 else chunk=assert(load(smear_source,"smear","t",particle_env)) end
 chunk()
 local resource=particle_env.smear.func("ball_light1")
 particle_env.smear.func("ball_light1");eq(loads,1,"existing particle cached")
 pool[resource]=nil
 particle_env.smear.func("ball_light1");eq(loads,2,"evicted particle reloaded after room change")
 local f=assert(io.open("game/legacy/source/activity7/_editor_output.lua","rb"))
 local export=f:read("*a");f:close()
 local wing=assert(export:match('(_editor_class%["Shinki%-wing"%]%.init=function.-)\r?\n_editor_class%["Shinki%-wing%-add"%]'))
 local jobs,alive,deleted={},true,false
 local master={ani=7}
 local bound=setmetatable({_editor_class={["Shinki-wing"]={}},_infinite=3,LAYER_ENEMY=0,
  _boss=setmetatable({},{__index=function() error("must not read a stale global Boss") end}),
  task={New=function(_,fn) jobs[#jobs+1]=fn end,_Wait=coroutine.yield},
  IsValid=function(o) return o==master and alive end,
  Del=function() deleted=true end,sin=function(x) return x end,
  _set_rel_pos=function(_,_,y) eq(y,112,"effect follows its own bound Boss animation") end}, {__index=_G})
 if setfenv then chunk=assert(loadstring(wing));setfenv(chunk,bound)
 else chunk=assert(load(wing,"bound_effect","t",bound)) end
 chunk()
 bound._editor_class["Shinki-wing"].init({_master=master,rot=0},0,0)
 local co=coroutine.create(jobs[2]);yes(coroutine.resume(co),"live bound effect updates")
 alive=false
 yes(coroutine.resume(co),"effect survives parent retirement without invalid access")
 yes(deleted,"orphaned effect retires")
 local catalog=require("tnr.training.nonspell_training_catalog")
 for _,card in ipairs(catalog) do yes(not card.legacy_transition,"retirement scripts excluded from practice") end
 eq(#catalog,312,"practice contains actual nonspell attacks only")
end
