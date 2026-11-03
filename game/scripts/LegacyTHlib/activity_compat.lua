-- Initialization normally performed by the reference campaign launcher.
function InitActivityScoreData()
scoredata = scoredata or {}
local function zeros(name, count)
    scoredata[name] = scoredata[name] or {}
    for i=1,count do if scoredata[name][i] == nil then scoredata[name][i]=0 end end
end
zeros("achi", 36); zeros("achi_common", 37)
zeros("wuer_achi", 6); zeros("ae_card", 2); zeros("qxs_stage", 4)
zeros("group_clear", 2)
scoredata.achi_var = scoredata.achi_var or {}
for _, name in ipairs({"miss","spell","graze","bomb_waste"}) do
    scoredata.achi_var[name] = scoredata.achi_var[name] or 0
end
for _, name in ipairs({"play_timer","dialog_jump","give_me_five","angry",
        "er_pot_time","reimu_c_time","reimu_cjuesi","marisa_c_time","marisa_missle"}) do
    scoredata[name] = scoredata[name] or 0
end

scoredata.stage_clear = scoredata.stage_clear or {{},{}}
for difficulty=1,2 do
    scoredata.stage_clear[difficulty] = scoredata.stage_clear[difficulty] or {}
    for i=1,17 do scoredata.stage_clear[difficulty][i]=scoredata.stage_clear[difficulty][i] or 0 end
end
end
lstg.DoFile("Thlib/achi.lua")
LoadSound("trophy", "Thlib/se/se_trophy.wav")
achievement_obj=Class(object)
function achievement_obj:init(mode,num,h)
  LoadImageFromFile('achi_img','THlib\\UI\\achi_img.png')
  self.bound=false
  self.img='achi_img'
  self.layer=LAYER_TOP+15
  self.group=GROUP_GHOST
  self.x=550 self.y=-40
  h=h or 1
  if mode==1 then
    self.text=_achi_table[num][1]
    if scoredata.achi[num]~=1 then
      scoredata.achi[num]=1
    else
      Del(self)
    end
  else
    self.text=_achi_table_common[num][1]
    if scoredata.achi_common[num]~=1 then
      scoredata.achi_common[num]=1
    else
      Del(self)
    end
  end
  task.New(self,function()
    task.Wait((h-1)*180)
    PlaySound('trophy',1)
    for i=1,30 do self.y=self.y+8/3 task.Wait(1) end
    task.Wait(180)
    for i=1,30 do self.y=self.y-8/3 task.Wait(1) end
    Del(self)
  end)
end
function achievement_obj:frame()
  task.Do(self)
end
function achievement_obj:render()
  SetViewMode'ui'
  SetImageState('white','',Color(0x80000000))
--  RenderRect('white',self.x-70,self.x+70,self.y-40,self.y+40)
  Render(self.img,self.x,self.y)
  RenderTTF('Sans','完成成就'..string.format('\n')..self.text,self.x+1,self.x+1,self.y-1,self.y-1,Color(0xFF000000),'centerpoint')
  RenderTTF('Sans','完成成就'..string.format('\n')..self.text,self.x,self.x,self.y,self.y,Color(0xFFFFFFFF),'centerpoint')
  SetViewMode'world'
end

