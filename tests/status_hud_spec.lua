local Art=require("tnr.character.runtime.status_art")
local Affixes=require("tnr.equipment.runtime.affix_runtime")
local Gauge=require("tnr.character.runtime.p_gauge")
return function(eq,yes)
 local entries={};for i=1,103 do entries[i]={id=i,icon=1} end
 local cells=Art.layout(entries,10,500,180)
 eq(#cells,103,"status grid has no row cap")
 eq(cells[5].y,cells[1].y,"five icons fit first row")
 eq(cells[6].x,cells[1].x,"sixth icon starts next row")
 eq(cells[6].y,cells[1].y-42,"row wraps")
 table.remove(entries,1)
 local compact=Art.layout(entries,10,500,180)
 eq(compact[1].entry.id,2,"expired first icon removed")
 eq(compact[1].x,cells[1].x,"following icon fills first slot")
 eq(compact[5].entry.id,6,"next row moves into previous row")
 local old_icon=Art.icon;local rendered={}
 Art.icon=function(id,x,y,size) rendered[#rendered+1]={id=id,x=x,y=y,size=size} end
 Art.resources(10,12,0,180,300,22)
 eq(#rendered,12,"one resource icon per life")
 for _,item in ipairs(rendered) do eq(item.y,300,"resources stay in one row");yes(item.x<=180,"row stays within HUD") end
 rendered={};Art.resources(6,0,0,180,300,22);eq(#rendered,0,"zero Bomb renders no numeric substitute")
 Art.icon=old_icon
 local w={instance={runtime_data={}},definition={metadata={}},is_active=function() return true end,
  random_affixes={{id="bread"},{id="combo"},{id="bomb_attack"},{id="frost",level=3},{id="high_p"}}}
 local d={player_id=1,p_gauge=Gauge.new(),weapon_manager={weapons={w}}}
 local a=Affixes.new(d,{}, {run_seed=1})
 a.bread={1};a:bomb();a.shield=1;a.frost=20
 local before=a:statuses();local by_id={}
 for _,s in ipairs(before) do by_id[s.id]=true;eq(s.text,nil,"no status names/attack text in renderer payload") end
 yes(by_id.bread and by_id.shield and by_id.frost and by_id.bomb_attack,"active effects visible")
 a:update("HIGH",false,true)
 local after=a:statuses();by_id={};for _,s in ipairs(after) do by_id[s.id]=true end
 eq(by_id.bread,nil,"expired bread icon disappears")
 eq(by_id.shield,nil,"expired shield icon disappears")
 eq(by_id.combo,nil,"inactive combo does not occupy a slot")
 d.p_gauge.value=40
 for _,s in ipairs(a:statuses()) do yes(s.id~="high_p","high P icon disappears when condition ends") end
end
