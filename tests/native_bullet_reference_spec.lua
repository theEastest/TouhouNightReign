return function(eq,yes)
 local function environment()
  local e=setmetatable({images={},textures={},animations={},rendered={}}, {__index=_G})
  e.object={};e.int=math.floor;e.min=math.min;e.max=math.max;e.Color=function(v) return v end
  e.Class=function(base) return setmetatable({base=base},{__index=base}) end
  e.LoadTexture=function(name,path) e.textures[name]=path:gsub("\\","/"):lower() end
  e.LoadImage=function(name,texture,x,y,w,h,a,b,rect) e.images[name]={texture,x,y,w,h,a or 0,b or a or 0,rect or false} end
  e.LoadImageGroup=function(name,tex,x,y,w,h,cols,rows,a,b,rect)
   for i=1,cols*rows do e.LoadImage(name..i,tex,x+(i-1)%cols*w,y+math.floor((i-1)/cols)*h,w,h,a,b,rect) end
  end
  e.LoadAnimation=function(name,...) e.animations[name]={...} end
  e.CopyImage=function(dst,src) e.images[dst]=e.images[src] end
  e.SetImageCenter=function() end;e.SetImageState=function() end;e.SetAnimationState=function() end
  e.Render=function(name) yes(e.images[name]~=nil,"render uses existing sprite: "..name);e.rendered[#e.rendered+1]=name end
  e.GetTextureSize=function() return 256,256 end
  e.Include=function() end
  e.LAYER_ENEMY_BULLET=100;e.LAYER_ENEMY_BULLET_EF=101
  return e
 end
 local function run(path,e)
  local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close()
  local chunk
  if setfenv then chunk=assert(loadstring(s));setfenv(chunk,e) else chunk=assert(load(s,path,"t",e)) end
  chunk()
 end
 local reference=environment();run("game/legacy/source/data/Thlib/bullet/bullet.lua",reference)
 local active=environment()
 for _,file in ipairs({"bullet.lua","legacy_bullet_load_resources.txt","bullet_others.lua","legacy_bullet_styles.lua"}) do
  run("game/scripts/LegacyTHlib/bullet/"..file,active)
 end
 for name,value in pairs(reference) do
  if type(name)=="string" and name:match("^COLOR_") then eq(active[name],value,"reference color constant: "..name) end
 end
 for name,expected in pairs(reference.images) do
  local actual=active.images[name];yes(actual~=nil,"reference image registered: "..name)
  for i=1,9 do eq(actual[i],expected[i],"atlas and hitbox match: "..name.." field "..i) end
 end
 for name,expected in pairs(reference.animations) do
  local actual=active.animations[name];yes(actual~=nil,"reference animation registered: "..name)
  for i=1,#expected do eq(actual[i],expected[i],"animation frame matches: "..name) end
 end
 for _,style in ipairs({"ball_small","grain_a","grain_b","grain_c","star_small","star_big","knife","knife_b","ball_huge","water_drop","music","silence"}) do
  for color=1,16 do
   local old,new={},{}
   reference[style].init(old,color);active[style].init(new,color)
   eq(new.img,old.img,"color mapping matches: "..style..color)
  end
 end
 for color=1,16 do
  local p={_index=color,index=math.floor((color+1)/2),timer=5,x=0,y=0,rot=0,imgclass=active.ball_small}
  active.img_class.render(p)
  eq(active.rendered[#active.rendered],"preimg"..p.index,"fog uses eight-color paired index")
 end
 run("game/scripts/LegacyTHlib/laser/laser.lua",active)
 for color=1,16 do
  local p={index=color};active.laser.ChangeImage(p,1,color)
  eq(p.img5,"ball_mid_b"..math.floor((color+1)/2),"laser recolor head keeps paired index")
  yes(active.images[p.img5]~=nil,"laser head exists")
 end
 active.GetAttr=rawget;active.SetAttr=rawset
 active.BentLaserData=function() return {} end
 run("game/scripts/LegacyTHlib/laser/bent laser.lua",active)
 for _,sample in ipairs({0,2,3,4,8}) do
  local curve={}
  active.laser_bent.init(curve,2,0,0,2,16,sample,0)
  eq(curve.sample,sample==0 and 0 or 4,"legacy curve sample selects a real renderer")
  eq(curve._l,1,"short curves retain a nonzero history length")
 end
 local rendered=false
 active.laser_bent_renderFunc[0]=function() rendered=true end
 active.laser_bent_elec.render({})
 yes(rendered,"electrical class switch uses thunder renderer")
end
