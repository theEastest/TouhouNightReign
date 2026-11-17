local Art = require("tnr.character.runtime.status_art")
return function(eq, yes)
    local previous_lstg = _G.lstg
    local previous_atlases, previous_loaded, previous_w, previous_h = Art.atlases, Art.loaded, Art.cellw, Art.cellh
    local loads, images, draws = {}, {}, {}
    _G.lstg = {
        GetResourceStatus=function() return "stage" end, SetResourceStatus=function() end,
        LoadTexture=function(id, path) loads[id]=path end, GetTextureSize=function() return 1254,1254 end,
        LoadImage=function(name, texture, x, y, w, h) images[name]={texture=texture,x=x,y=y,w=w,h=h} end,
        SetImageState=function() end, Color=function(...) return {...} end,
        Render=function(name,x,y,rot,sx,sy) draws[#draws+1]={name=name,sx=sx,sy=sy} end,
    }
    Art.atlases={};Art.loaded=false
    Art.icon(13, 10, 10, 22, "ordinary")
    Art.icon(13, 10, 10, 22)
    eq(loads["tnr-affix-moonlit-atlas"], "assets/ui/status/affixes-moonlit.png", "ordinary game loads its own atlas")
    eq(loads["tnr-affix-atlas"], "assets/ui/status/affixes.png", "replay keeps its original atlas")
    eq(draws[1].name, "tnr-status-moonlit-13", "ordinary status selects moonlit icon")
    eq(draws[2].name, "tnr-status-13", "default replay status selects old icon")
    for i=1,16 do
        local themed,legacy=images["tnr-status-moonlit-"..i],images["tnr-status-"..i]
        yes(themed ~= nil and legacy ~= nil, "both atlases define slot "..i)
        eq(themed.x,legacy.x,"atlas slot x stays unchanged")
        eq(themed.y,legacy.y,"atlas slot y stays unchanged")
        eq(themed.w,legacy.w,"atlas slot width stays unchanged")
        eq(themed.h,legacy.h,"atlas slot height stays unchanged")
    end
    draws={}; Art.resources(10,2,0,180,100,22,"ordinary")
    eq(draws[1].name,"tnr-status-moonlit-10","ordinary lives use moonlit heart")
    eq(draws[2].name,"tnr-status-moonlit-10","ordinary lives keep one icon per life")
    draws={}; Art.resources(6,1,0,180,100,22)
    eq(draws[1].name,"tnr-status-6","replay bomb keeps original resource")
    _G.lstg=previous_lstg; Art.atlases,Art.loaded,Art.cellw,Art.cellh=previous_atlases,previous_loaded,previous_w,previous_h
end
