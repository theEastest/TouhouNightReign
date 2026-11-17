local Art={loaded=false, atlases={}}
-- The default remains the original atlas for legacy replay. Ordinary game
-- callers opt in explicitly to the moonlit art, keeping both resources alive.
function Art.load(style)
 local key=style=="ordinary" and "ordinary" or "legacy"
 if Art.atlases[key] then return Art.atlases[key] end
 local old=lstg.GetResourceStatus();lstg.SetResourceStatus("global")
 local texture=key=="ordinary" and "tnr-affix-moonlit-atlas" or "tnr-affix-atlas"
 local prefix=key=="ordinary" and "tnr-status-moonlit-" or "tnr-status-"
 local path=key=="ordinary" and "assets/ui/status/affixes-moonlit.png" or "assets/ui/status/affixes.png"
 lstg.LoadTexture(texture,path,false)
 local w,h=lstg.GetTextureSize(texture)
 local atlas={cellw=w/4,cellh=h/4,prefix=prefix}
 for i=1,16 do lstg.LoadImage(prefix..i,texture,((i-1)%4)*w/4,math.floor((i-1)/4)*h/4,w/4,h/4) end
 lstg.SetResourceStatus(old);Art.atlases[key]=atlas
 if key=="legacy" then Art.loaded=true;Art.cellw,Art.cellh=atlas.cellw,atlas.cellh end
 return atlas
end
function Art.icon(id,x,y,size,style)
 local atlas=Art.load(style)
 local image=atlas.prefix..id
 lstg.SetImageState(image,"",lstg.Color(255,255,255,255))
 lstg.Render(image,x,y,0,size/atlas.cellw,size/atlas.cellh)
end
-- No reserved cells or row limit. Removing an entry closes its gap immediately.
function Art.layout(entries,left,top,width)
 local cells={};local pitch=width/5
 for i,entry in ipairs(entries) do
  cells[i]={entry=entry,x=left+pitch*((i-1)%5+.5),y=top-math.floor((i-1)/5)*42,size=math.min(26,pitch-6)}
 end
 return cells
end
function Art.grid(entries,left,top,width,affixes,text,style)
 for _,cell in ipairs(Art.layout(entries,left,top,width)) do
  local e,x,y=cell.entry,cell.x,cell.y
  Art.icon(e.icon,x,y,cell.size,style)
  if e.id=="frost" and affixes then Art.frost(affixes,x-13,x+13,y-16)
  elseif e.ratio then
   lstg.SetImageState("tnr-white","",lstg.Color(230,35,40,55));lstg.RenderRect("tnr-white",x-13,x+13,y-17,y-14)
   lstg.SetImageState("tnr-white","",lstg.Color(255,125,220,255));lstg.RenderRect("tnr-white",x-13,x-13+26*math.max(0,math.min(1,e.ratio)),y-17,y-14)
  end
  local badge=e.badge or (e.ratio and string.format("%.0f%%",e.ratio*100))
  if badge and text then text(badge,x+cell.size*.5,y-cell.size*.35) end
 end
 lstg.SetImageState("tnr-white","",lstg.Color(255,255,255,255))
end
function Art.resources(icon,count,left,right,y,size,style)
 count=math.max(0,math.floor(tonumber(count) or 0))
 -- All resources remain in one row, shrinking spacing when needed.
 local pitch=math.min(size+3,(right-left)/math.max(1,count))
 local icon_size=math.min(size,pitch)
 for i=1,count do Art.icon(icon,left+(i-.5)*pitch,y,icon_size,style) end
end
function Art.ring(a,p)
 local progress=0
 for _,w in ipairs(a.driver.weapon_manager.weapons) do progress=math.max(progress,w.combo.frames/300) end
 if a.shield>0 then progress=1 end
 if progress<=0 then return end
 lstg.SetImageState("tnr-white","",lstg.Color(230,130,230,255))
 local n=math.max(1,math.ceil(progress*64))
 for i=0,n-1 do
  local first=math.rad(270-progress*180+i/n*progress*360)
  local second=math.rad(270-progress*180+(i+1)/n*progress*360)
  local inner,outer=29,31
  lstg.Render4V("tnr-white",p.x+math.cos(first)*inner,p.y+math.sin(first)*inner,0.5,
   p.x+math.cos(second)*inner,p.y+math.sin(second)*inner,0.5,
   p.x+math.cos(second)*outer,p.y+math.sin(second)*outer,0.5,
   p.x+math.cos(first)*outer,p.y+math.sin(first)*outer,0.5)
 end
 lstg.SetImageState("tnr-white","",lstg.Color(255,255,255,255))
end
function Art.frost(a,left,right,y)
 local widths=a.frost_level==3 and {0.5,0.34,0.16} or a.frost_level==2 and {0.6,0.4} or {1}
 local caps={33.3,33.3,10};local colors={{140,220,255},{35,105,255},{175,70,240}}
 local remaining=a.frost;local x=left
 for i,width in ipairs(widths) do
  local edge=x+(right-left)*width
  lstg.SetImageState("tnr-white","",lstg.Color(200,24,28,42));lstg.RenderRect("tnr-white",x,edge-1,y,y+3)
  local fill=math.min(1,math.max(0,remaining/caps[i]));local c=colors[i]
  if fill>0 then lstg.SetImageState("tnr-white","",lstg.Color(255,c[1],c[2],c[3]));lstg.RenderRect("tnr-white",x,x+(edge-x-1)*fill,y,y+3) end
  remaining=remaining-caps[i];x=edge
 end
 lstg.SetImageState("tnr-white","",lstg.Color(255,255,255,255))
end
return Art
