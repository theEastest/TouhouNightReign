LoadTexture('item','THlib\\item\\item.png')
LoadImageGroup('item','item',0,0,32,32,2,5,8,8)
LoadImageGroup('item_up','item',64,0,32,32,2,5)
SetImageState('item8','mul+add',Color(0xC0FFFFFF))
LoadTexture('bonus1','THlib\\item\\item.png')
LoadTexture('bonus2','THlib\\item\\item.png')
LoadTexture('bonus3','THlib\\item\\item.png')

lstg.var.collectingitem=0

item=Class(object)

function item:init(x,y,t,v,angle)
	local w=lstg.world
	x=min(max(x,w.l+16),w.r-16)
	self.x=x
	self.y=y
	angle=angle or 90
	v=v or 1.5
	SetV(self,v,angle)
	self.v=v
	self.group=GROUP_ITEM
	self.layer=LAYER_ITEM
	self.bound=false
	self.img='item'..t
	self.imgup='item_up'..t
	self.attract=0
end

function item:render()
	local w=lstg.world
	if self.y>224 then Render(self.imgup,self.x,216) else object.render(self) end
end

function item:frame()
	local w=lstg.world
	self.x=min(max(self.x,w.l+16),w.r-16)
	if self.timer<24 then
		self.rot=self.rot+45
		self.hscale=(self.timer+25)/48
		self.vscale=self.hscale
		if self.timer==22 then self.vy=min(self.v,2) self.vx=0 end
	elseif self.attract>0 then
		local a=Angle(self,player)
		self.vx=self.attract*cos(a)+player.dx*0.5
		self.vy=self.attract*sin(a)+player.dy*0.5
	else self.vy=max(self.dy-0.03,-1.7) end
	if self.y<-256 then Del(self) end
	if self.attract>=8 then self.collected=true end
end

function item:colli(other)
	if other==player then
		if self.class.collect then self.class.collect(self) end
		Kill(self)
		PlaySound('item00',0.3,self.x/200)
	end
end

function GetPower(v)
	local before=int(lstg.var.power/100)
	lstg.var.power=min(400,lstg.var.power+v)
	local after=int(lstg.var.power/100)
	if after>before then PlaySound('powerup1',0.5) end
	if lstg.var.power>=400 then
		lstg.var.score=lstg.var.score+v*100
	end
--	if lstg.var.power==500 then
--		for i,o in ObjList(GROUP_ITEM) do
--			if o.class==item_power or o.class==item_power_large then
--				o.class=item_faith
--				o.img='item5'
--				o.imgup='item_up5'
--				New(bubble,'parimg12',o.x,o.y,16,0.5,1,Color(0xFF00FF00),Color(0x0000FF00),LAYER_ITEM+50)
--			end
--		end
--	end
end

function Getlife(v)
	if v>=100 then v=v-99 Getlife(99) end
	local var=lstg.var
	var.chip=var.chip+v
	if var.chip>=100 and var.lifeleft<8 then
		var.chip=var.chip-100
		var.lifeleft=var.lifeleft+1
		PlaySound('extend',0.5)
		New(hinter,'hint.extend',0.6,0,112,15,120)
	end
	if var.chip>=100 and var.lifeleft>=8 then
		var.chip=99.9
		New(float_text,'item',10000,player.x,player.y+6,0.75,90,60,0.5,0.5,Color(0x80FFFFFF),Color(0x00FFFFFF))
		var.score=var.score+10000
	end
end

function Getbomb(v)
	if v>=100 then v=v-99 Getbomb(99) end
	local var=lstg.var
	var.bombchip=var.bombchip+v
	if var.bombchip>=100 and var.bomb<8 then
		var.bomb=var.bomb+1
		var.bombchip=var.bombchip-100
		PlaySound('cardget',0.8)
	end
	if var.bombchip>=100 and var.bomb>=8 then
		var.bombchip=99.9
		New(float_text,'item',10000,player.x,player.y+6,0.75,90,60,0.5,0.5,Color(0x80FFFFFF),Color(0x00FFFFFF))
		var.score=var.score+10000
	end
end
item_power=Class(item)
function item_power:init(x,y,v,a) item.init(self,x,y,1,v,a) end
function item_power:collect()
	if self.attract>=8 then
		lstg.var.collectitem[self.num]=lstg.var.collectitem[self.num]+1
		if player.nextcollect>0 and player.nextcollect<15 and self.collected and player.itemed then player.nextcollect=15 end
	end
	Getlife(0.25)
	local var=lstg.var
	var.itembar[1]=var.itembar[1]+1
--	GetPower(1)
end

item_power_large=Class(item)
function item_power_large:init(x,y,v,a) item.init(self,x,y,6,v,a) end
function item_power_large:collect() GetPower(100)  end

item_power_full=Class(item)
function item_power_full:init(x,y) item.init(self,x,y,4) end
function item_power_full:collect() GetPower(400)  end

item_extend=Class(item)
function item_extend:init(x,y) item.init(self,x,y,7) end
function item_extend:collect()
	lstg.var.lifeleft=min(lstg.var.lifeleft+1,8)
	PlaySound('extend',0.5)
	New(hinter,'hint.extend',0.6,0,112,15,120)
end

item_chip=Class(item)
function item_chip:init(x,y) item.init(self,x,y,3)
--	PlaySound('bonus',0.8)
end
function item_chip:collect()
	Getlife(10)
end
----------------------------
item_bombchip=Class(item)
function item_bombchip:init(x,y) item.init(self,x,y,9)
--	PlaySound('bonus2',0.8)
end
function item_bombchip:collect()
	Getbomb(10)
end
item_bomb=Class(item)
function item_bomb:init(x,y)  item.init(self,x,y,10)
end
function item_bomb:collect()
	lstg.var.bomb=min(lstg.var.bomb+1,8)
	PlaySound('cardget',0.8)
end
----------------------------
item_faith=Class(item)
function item_faith:init(x,y) item.init(self,x,y,5) end
function item_faith:collect()
	if self.attract>=8 then
		lstg.var.collectitem[self.num]=lstg.var.collectitem[self.num]+1
		if player.nextcollect>0 and player.nextcollect<15 and self.collected and player.itemed then player.nextcollect=15 end
	end
	local var=lstg.var
	Getbomb(0.25)
	var.itembar[2]=var.itembar[2]+1
--	New(float_text,'item','10000',self.x,self.y+6,0.75,90,60,0.5,0.5,Color(0x8000C000),Color(0x0000C000))
--	var.faith=var.faith+4
--	var.score=var.score+10000
end

item_faith_minor=Class(object)
function item_faith_minor:init(x,y)
	self.x=x self.y=y
	self.img='item'..8
	self.group=GROUP_GHOST
	self.layer=LAYER_ITEM
	if not BoxCheck(self,lstg.world.l,lstg.world.r,lstg.world.b,lstg.world.t) then RawDel(self) end
	self.vx=ran:Float(-0.15,0.15)
	self._vy=ran:Float(3.25,3.75)
	self.flag=1
	self.attract=0
	self.bound=false
end
function item_faith_minor:frame()
	if player.death>80 and player.death<90 then self.flag=0 self.attract=0 end
	if self.timer<45 then
		self.vy=self._vy-self._vy*self.timer/45
	end
	if self.timer>=54 and self.flag==1 then
		SetV(self,8,Angle(self,player))
	end
	if self.timer>=54 and self.flag==0 then
		if self.attract>0 then
			local a=Angle(self,player)
			self.vx=self.attract*cos(a)+player.dx*0.5
			self.vy=self.attract*sin(a)+player.dy*0.5
		else self.vy=max(self.dy-0.03,-2.5) self.vx=0
		end
		if self.y<-256 then Del(self) end
	end
	if Dist(self,player)<10 then
		PlaySound('item00',0.3,self.x/200)
		if player.name=='Sanae' then
			lstg.var.faith=lstg.var.faith+0.4
		else lstg.var.faith=lstg.var.faith+0.2
		end
		Del(self)
	end
	if player.y>player.collect_line then self.flag=1 end
end
function item_faith_minor:colli(other)
	if other==player then
		if self.class.collect then self.class.collect(self) end
		Kill(self)
		PlaySound('item00',0.3,self.x/200)
	end
end
function item_faith_minor:collect()
	local var=lstg.var
	var.faith=var.faith+1
	var.score=var.score+500
end

item_point=Class(item)
function item_point:init(x,y) item.init(self,x,y,2) end
function item_point:collect()
	if self.attract>=8 then
		lstg.var.collectitem[self.num]=lstg.var.collectitem[self.num]+1
		if player.nextcollect>0 and player.nextcollect<15 and self.collected and player.itemed then player.nextcollect=15 end
	end
	local var=lstg.var
	if self.attract==8 then
		New(float_text,'item',var.pointrate,self.x,self.y+6,0.75,90,60,0.5,0.5,Color(0x80FFFF00),Color(0x00FFFF00))
		var.score=var.score+var.pointrate
	else
		New(float_text,'item',int(var.pointrate/20)*10,self.x,self.y+6,0.75,90,60,0.5,0.5,Color(0x80FFFFFF),Color(0x00FFFFFF))
		var.score=var.score+int(var.pointrate/20)*10
	end
	var.itembar[3]=var.itembar[3]+1
end

function item.DropItem(x,y,drop)
	local m
	if lstg.var.power==400 then
		m = drop[1]
	elseif drop[1] >= 400 then
		m = drop[1]
	else
		m = drop[1] / 100 + drop[1] % 100
	end
	local n=m+drop[2]+drop[3]
	if n<1 then return end
	local r=sqrt(n-1)*5
	--if lstg.var.power==500 then drop[2]=drop[2]+drop[1] drop[1]=0 end
	if drop[1] >= 400 then
		local r2=sqrt(ran:Float(1,4))*r
		local a=ran:Float(0,360)
		New(item_power_full,x+r2*cos(a),y+r2*sin(a))
	else
		drop[4] = drop[1] / 100
		drop[1] = drop[1] % 100
		for i=1,drop[4] do
			local r2=sqrt(ran:Float(1,4))*r
			local a=ran:Float(0,360)
			New(item_power_large,x+r2*cos(a),y+r2*sin(a))
		end
		for i=1,drop[1] do
			local r2=sqrt(ran:Float(1,4))*r
			local a=ran:Float(0,360)
			New(item_power,x+r2*cos(a),y+r2*sin(a))
		end
	end
	for i=1,drop[2] do
		local r2=sqrt(ran:Float(1,4))*r
		local a=ran:Float(0,360)
		New(item_faith,x+r2*cos(a),y+r2*sin(a))
	end
	for i=1,drop[3] do
		local r2=sqrt(ran:Float(1,4))*r
		local a=ran:Float(0,360)
		New(item_point,x+r2*cos(a),y+r2*sin(a))
	end
end

item.sc_bonus_max=10000000
item.sc_bonus_base=5000000

function item.StartChipBonus()
	lstg.var.chip_bonus=true
	lstg.var.bombchip_bonus=true
end

function item.EndChipBonus(x,y)
	if lstg.var.chip_bonus and lstg.var.bombchip_bonus then
			New(item_chip,x-20,y)
			New(item_bombchip,x+20,y)
	else
		if lstg.var.chip_bonus then New(item_chip,x,y) end
		if lstg.var.bombchip_bonus then New(item_bombchip,x,y) end
	end
end

function item.PlayerInit()
	lstg.var.power=100
	lstg.var.lifeleft=2
	lstg.var.bomb=2
	lstg.var.bonusflag=0
	lstg.var.chip=0
	lstg.var.faith=0
	lstg.var.graze=0
	lstg.var.score=0
	lstg.var.bombchip=0
	lstg.var.coun_num=0
	lstg.var.pointrate=item.PointRateFunc(lstg.var)
	lstg.var.collectitem={0,0,0,0,0,0}
	lstg.var.itembar={0,0,0}
	lstg.var.block_spell=false
	lstg.var.chip_bonus=false
	lstg.var.bombchip_bonus=false
	lstg.var.init_player_data=true
end
------------------------------------------
function item.PlayerReinit()
	lstg.var.power=400
	lstg.var.lifeleft=2
	lstg.var.chip=0
	lstg.var.bomb=2
	lstg.var.bomb_chip=0
	lstg.var.block_spell=false
	lstg.var.init_player_data=true
	if lstg.var.coun_num==9 then scoredata.achi_common[2]=1 end
	lstg.var.coun_num=min(9,lstg.var.coun_num+1)
	lstg.var.score=lstg.var.coun_num
	--if lstg.var.score % 10 ~= 9 then item.AddScore(1) end
end
------------------------------------------
--HZC的收点系统
function item.playercollect(n)
	New(tasker,function()
		local z=0
		local Z=0
		local var=lstg.var
		local f=0
		local maxpri=-1
		for _=1,300 do
			for i,o in ObjList(GROUP_ITEM) do
				if o.num==n then f=6 end
			end
			if f<=0 then break end
			f=f-1
			task.Wait(1)
		end
--[[		for i,o in ObjList(GROUP_ITEM) do
			if o.num==n and not o.collecting then
				local dx=player.x-o.x
				local dy=player.y-o.y
				local pri=abs(dy)/(abs(dx)+0.01)
				if pri>maxpri then maxpri=pri f=o end
				o.collecting=true
			end
		end
		for _=1,300 do
			if not(IsValid(f)) then break end
			task.Wait(1)
		end]]
		z=lstg.var.collectitem[n]
		local x=min(max(player.x,-160),160)
		local y=min(player.y,120)
		if z>=0 and z<40 then Z=1.0
		elseif z<60 then Z=1.2
		elseif z<80 then Z=1.6
		elseif z<100 then Z=2.4
		elseif z<120 then Z=3.6
		elseif z>=120 then
			Z=5.0
			if not ext.replay.IsReplay() then
				scoredata.give_me_five=scoredata.give_me_five+1
				if scoredata.give_me_five==50 then New(achievement_obj,2,32) end
			end
		end
		local m=1
		if z>=5 and z<20 then
			task.Wait(15)
			New(float_text2,'bonus','NO BONUS',x,y+60,0,90,120,0.5,0.5,Color(0xF0B0B0B0),Color(0x00B0B0B0))
		elseif z>=20 and z<40 then
			PlaySound('pin00',0.8)
			task.Wait(15)
			New(float_text2,'bonus',string.format('BONUS',Z),x,y+70,0,120,120,0.5,0.5,Color(0xFF29E8E8),Color(0x0029E8E8))
			New(float_text2,'bonus',string.format('%d X %.1f',z*m,Z),x,y+60,0,120,120,0.5,0.5,Color(0xFF29E8E8),Color(0x0029E8E8))
			var.faith=var.faith+Z*z*m
		elseif z>=40 and z<60 then
			PlaySound('pin00',0.8)
			task.Wait(15)
			New(float_text2,'bonus',string.format('BONUS',Z),x,y+70,0,120,120,0.5,0.5,Color(0xFF29E8E8),Color(0x0029E8E8))
			New(float_text2,'bonus',string.format('%d X %.1f',z*m,Z),x,y+60,0,120,120,0.5,0.5,Color(0xFF29E8E8),Color(0x0029E8E8))
			var.faith=var.faith+Z*z*m
		elseif z>=60 and z<80 then
			PlaySound('pin00',0.8)
			task.Wait(15)
			New(float_text2,'bonus',string.format('BONUS',Z),x,y+70,0,120,120,0.5,0.5,Color(0xFF44FFA1),Color(0x0044FFA1))
			New(float_text2,'bonus',string.format('%d X %.1f',z*m,Z),x,y+60,0,120,120,0.5,0.5,Color(0xFF44EEA1),Color(0x0044EEA1))
			var.faith=var.faith+Z*z*m
		elseif z>=80 and z<100 then
			PlaySound('pin00',0.8)
			task.Wait(15)
			New(float_text2,'bonus',string.format('BONUS',Z),x,y+70,0,120,120,0.5,0.5,Color(0xFF44FFA1),Color(0x0044FFA1))
			New(float_text2,'bonus',string.format('%d X %.1f',z*m,Z),x,y+60,0,120,120,0.5,0.5,Color(0xFF44FFA1),Color(0x0044FFA1))
			var.faith=var.faith+Z*z*m
		elseif z>=100 and z<120 then
			PlaySound('pin00',0.8)
			task.Wait(15)
			New(float_text2,'bonus',string.format('BONUS',Z),x,y+70,0,120,120,0.5,0.5,Color(0xFFFFFF00),Color(0x00FFFF00))
			New(float_text2,'bonus',string.format('%d X %.1f',z*m,Z),x,y+60,0,120,120,0.5,0.5,Color(0xFFFFFF00),Color(0x00FFFF00))
			var.faith=var.faith+Z*z*m
		elseif z>=120 then
			PlaySound('pin00',0.8)
			task.Wait(15)
			New(float_text2,'bonus',string.format('BONUS',Z),x,y+70,0,120,120,0.5,0.5,Color(0xFFFF4422),Color(0x00FF4422))
			New(float_text2,'bonus',string.format('%d X %.1f',z*m,Z),x,y+60,0,120,120,0.5,0.5,Color(0xFFFF4422),Color(0x00FF4422))
			var.faith=var.faith+Z*z*m
		end
		lstg.var.collectitem[n]=0
	end)

end
-----------------------------
function item.PlayerMiss()
	player.first_blood=player.first_blood+1
	lstg.var.chip_bonus=false
	if not ext.replay.IsReplay() then
		player.miss_with_no_bomb=player.miss_with_no_bomb+1
		scoredata.achi_var.miss=scoredata.achi_var.miss+1
		scoredata.achi_var.bomb_waste=scoredata.achi_var.bomb_waste+min(2,lstg.var.bomb)
		if scoredata.achi_var.miss==30 then
			New(achievement_obj,2,4)
		elseif scoredata.achi_var.miss==70 then
			New(achievement_obj,2,5)
		elseif scoredata.achi_var.miss==150 then
			New(achievement_obj,2,6)
		end
		if scoredata.achi_var.bomb_waste>=30 then New(achievement_obj,2,31) end
		if player.miss_with_no_bomb==3 then New(achievement_obj,2,33) end
	end
	if lstg.var.sc_bonus then lstg.var.sc_bonus=0 end
	player.protect=360
	lstg.var.lifeleft=lstg.var.lifeleft-1
--	lstg.var.power=math.max(lstg.var.power-50,100)
	lstg.var.bomb=max(lstg.var.bomb,2)
--	if lstg.var.lifeleft>0 then
--		for i=1,7 do
--			local a=90+(i-4)*18+player.x*0.26
--			New(item_power,player.x,player.y+10,3,a)
--		end
--	else New(item_power_full,player.x,player.y+10) end
end

function item.PlayerSpell()
	player.miss_with_no_bomb=0
	if not ext.replay.IsReplay() then
		scoredata.achi_var.spell=scoredata.achi_var.spell+1
		if scoredata.achi_var.spell==30 then
			New(achievement_obj,2,7)
		elseif scoredata.achi_var.spell==70 then
			New(achievement_obj,2,8)
		elseif scoredata.achi_var.spell==150 then
			New(achievement_obj,2,9)
		end
	end
	if lstg.var.sc_bonus then lstg.var.sc_bonus=0 end
	lstg.var.bombchip_bonus=false
end

function item.PlayerGraze()
	lstg.var.graze=lstg.var.graze+1
	if player.protect>0 then
	else
		lstg.var.power=min(lstg.var.power+1/10,400)
	end
end

function item.PointRateFunc(var)
	local r=5000+int(var.graze/50)*10+int(lstg.var.faith/10)*10
	return r
end
