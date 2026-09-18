wuer_player=Class(player_class)

function wuer_player:init()
	LoadTexture('wuer_player','THlib\\player\\wuer\\wuer.png')
	LoadImageGroup('wuer_player','wuer_player',0,0,32,48,8,3,0.5,0.5)
	LoadImage('wuer_knife','wuer_player',16,192,48,16,16,16)
	SetImageCenter('wuer_knife',20,8)
	LoadImage('wuer_knife_ef','wuer_player',0,192,16,16,0,0)
	LoadImage('wuer_support_blue','wuer_player',64,144,32,32,0,0)
	LoadImage('wuer_support_red','wuer_player',96,144,32,32,0,0)
	LoadImage('wuer_spatula','wuer_player',64,192,64,20,16,16)
	LoadImage('wuer_spoon','wuer_player',64,212,64,20,16,16)
	LoadImage('wuer_fork','wuer_player',64,232,64,20,16,16)
	LoadImage('wuer_support_fire','wuer_player',0,176,64,16,12,12)
	SetImageState('wuer_support_fire','mul+add',Color(0x80FFFFFF))
	SetImageCenter('wuer_support_fire',56,8)
	LoadImageGroup('wuer_support_fire_ef','wuer_player',0,160,16,16,4,1)
	LoadImageFromFile('wuer_pan','THlib\\player\\wuer\\er_pan.png')
	LoadAniFromFile('wuer_fire','THlib\\player\\wuer\\er_fire.png',true,3,1,2)
	LoadImageGroupFromFile('wuer_frying_pan','THlib\\player\\wuer\\wuer_fryingpan.png',true,1,2)
	SetImageCenter('wuer_frying_pan1',0,48)
	SetImageCenter('wuer_frying_pan2',0,48)
	LoadImageFromFile('wuer_Ingredient','THlib\\player\\wuer\\wuer_Ingredient.png')
	LoadImageFromFile('wuer_spell_mask_A','THlib\\player\\wuer\\wuer_spell_mask_A.png')
	LoadSound('fry','THlib\\player\\wuer\\fry.wav')
	LoadImageFromFile('wuer_black_mask','THlib\\player\\wuer\\wuer_black_mask.png')
	LoadImageFromFile('wuer_pot','THlib\\player\\wuer\\wuer_pot.png')
	LoadImageGroup('wuer_drawring','boss',64,0,16,8,1,16)
	for i=1,16 do SetImageState('wuer_drawring'..i,'mul+add',Color(0x80FFFFFF)) end
	-----------------------------------------
	player_class.init(self)
	self.name='Wuer'
	self.hspeed=4.5
	self.imgs={}
	self.A=0.5 self.B=0.5
	lstg.var.block_spell=false
	for i=1,24 do self.imgs[i]='wuer_player'..i end
	self.slist=
	{
		{nil,nil,nil,nil},
		{{0,36,0,24}     ,           nil,         nil,           nil},
		{{-32,0,-12,24}    ,{32,0,12,24}    ,         nil,           nil},
		{{-32,-8,-16,20}   ,{0,-32,0,28}  ,{32,-8,16,20} ,           nil},
		{{-36,-12,-16,20},{-16,-32,-6,28},{16,-32,6,28},{36,-12,16,20}},
		{{-36,-12,-16,20},{-16,-32,-6,28},{16,-32,6,28},{36,-12,16,20}},
	}
	self.anglelist=
	{
		{90,90,90,90},
		{90,90,90,90},
		{100,80,90,90},
		{100,90,80,90},
		{110,100,80,70},
	}
	self._slist={{-150,-144},{-50,-120},{50,-120},{150,-144}}
	self.sp_pan=0
	self.hyper=0
end
-------------------------------------------------------
function wuer_player:shoot()
	PlaySound('plst00',0.3,self.x/1024)
	self.nextshoot=4
	New(wuer_bullet_knife,'wuer_knife',self.x+8,self.y,24,90,1.5)
	New(wuer_bullet_knife,'wuer_knife',self.x-8,self.y,24,90,1.5)
	if self.slow==0 then
		local num=int(lstg.var.power/100)+1
		local dmg=0.4
		if IsValid(_boss) then dmg=0.6 end--8f_max=dmg*8*2
		if self.timer%8<4 then
		if IsValid(self.target) and self.target.colli then
			for i=-1,1,2 do
			New(wuer_locked_bullet,'wuer_fork'		,self._slist[1][1]+i*5,self._slist[1][2],24,Angle(self._slist[1][1],self._slist[1][2],self.target.x,self.target.y),dmg)
			New(wuer_locked_bullet,'wuer_spatula'	,self._slist[2][1]+i*5,self._slist[2][2],24,Angle(self._slist[2][1],self._slist[2][2],self.target.x,self.target.y),dmg)
			New(wuer_locked_bullet,'wuer_spatula'	,self._slist[3][1]+i*5,self._slist[3][2],24,Angle(self._slist[3][1],self._slist[3][2],self.target.x,self.target.y),dmg)
			New(wuer_locked_bullet,'wuer_spoon'		,self._slist[4][1]+i*5,self._slist[4][2],24,Angle(self._slist[4][1],self._slist[4][2],self.target.x,self.target.y),dmg)
			end
		end end
	end
end
-------------------------------------------------------
function wuer_player:spell()
	self.collect_line=self.collect_line-500
	New(tasker,function()
		task.Wait(90)
		self.collect_line=self.collect_line+500
	end)
	if self.slow==1 then
		PlaySound('nep00',0.8)
		PlaySound('cat00',0.8)
		misc.ShakeScreen(240,2)
		New(wuer_spell_mask,255,255,255,30,270,30)
		New(wuer_frying_pan,300)
		local x=0
		for i,o in ObjList(GROUP_ENEMY_BULLET) do
			x=x+1
			if o._index then
				New(wuer_frying_item,o.x,o.y,o._index,x)
			else
				New(wuer_frying_item,o.x,o.y,16,x)
			end
			Del(o)
		end
		self.nextshoot=300
		self.nextspell=360
		self.protect=420
	else
		PlaySound('slash',0.8)
		New(player_spell_mask,128,64,255,30,150,30)
		for i,o in ObjList(GROUP_ENEMY_BULLET) do
			Kill(o)
		end
		New(wuer_black_mask)
		New(wuer_pot)
		self.nextspell=180
		self.protect=180
	end
end
function wuer_player:special()
	if lstg.var.power>=200 then
		self.nextsp=180
		self.hyper=900
		lstg.var.power=max(0,lstg.var.power-200)
		PlaySound('hyz_chargeup',0.8)
		New(wuer_drawring,self.x,self.y)
		New(wuer_special_pan,self.x,self.y,self.sp_pan)
		self.sp_pan=self.sp_pan+1
		if scoredata.achi_common[25]~=1 and self.sp_pan==2 then
		New(tasker,function()
			for i=1,900 do
				Print(i,player.sp_pan)
				if IsValid(_wuer_pan) then
					New(achievement_obj,2,25)
					break
				end
				task.Wait()
			end
		end)
		end
	end
end
-------------------------------------------------------
function wuer_player:frame()
	if lstg.var.bomb==8 and lstg.var.lifeleft==8 and scoredata.achi_common[3]~=1 then New(achievement_obj,2,3) end
	if KeyIsDown'shoot' then
		self.no_shoot_time=0
	else
		self.no_shoot_time=self.no_shoot_time+1
	end
	if self.no_shoot_time==10800 then New(achievement_obj,2,30) end
	if self.shoot_time==18000 then New(achievement_obj,2,30) end
	if self.no_shoot_time==10800 then New(achievement_obj,2,31) end
	--find target
	if ((not IsValid(self.target)) or (not self.target.colli)) then player_class.findtarget(self) end
	if not KeyIsDown'shoot' then self.target=nil end
	--
	local dx=0
	local dy=0
	local v=self.hspeed
	if (self.death==0 or self.death>90) and (not self.lock) and not(self.time_stop) then
		--slow
		if KeyIsDown'slow' then self.slow=1 else self.slow=0 end
		--shoot and spell
		if not self.dialog then
			if self.timer%60==0 then lstg.var.power=min(lstg.var.power+1,400) end
			if KeyIsDown'shoot' and self.nextshoot<=0 then self.class.shoot(self) end
			if KeyIsDown'spell' and self.nextspell<=0 and not(IsValid(_wuer_black_mask)) and lstg.var.bomb>0 and not lstg.var.block_spell then
				item.PlayerSpell()
				lstg.var.bomb=lstg.var.bomb-1
				self.class.spell(self)
				self.death=0
				self.nextcollect=90
			end
			if KeyIsDown'special' and self.nextsp<=0 then self.class.special(self) end
		else self.nextshoot=15 self.nextspell=30
		end
		--move
		if self.death==0 and not self.lock then
		if self.slowlock then self.slow=1 end
		if self.slow==1 then v=self.lspeed end
		if KeyIsDown'up' then dy=dy+1 end
		if KeyIsDown'down' then dy=dy-1 end
		if KeyIsDown'left' then dx=dx-1 end
		if KeyIsDown'right' then dx=dx+1 end
		if dx*dy~=0 then v=v*SQRT2_2 end
		self.x=self.x+v*dx
		self.y=self.y+v*dy
		self.x=math.max(math.min(self.x,lstg.world.pr-8),lstg.world.pl+8)
		self.y=math.max(math.min(self.y,lstg.world.pt-32),lstg.world.pb+16)
		end
		--fire
		if KeyIsDown'shoot' and not self.dialog then self.fire=self.fire+0.16 else self.fire=self.fire-0.16 end
		if self.fire<0 then self.fire=0 end
		if self.fire>1 then self.fire=1 end
		--item
		if self.y>self.collect_line then
			if not(self.itemed) and not(self.collecting) then
				self.itemed=true
				self.collecting=true
--				lstg.var.collectitem=0
				self.nextcollect=15
			end
			for i,o in ObjList(GROUP_ITEM) do o.attract=8 o.num=self.item end
		-----
		else
			self.nextcollect=0
			if KeyIsDown'slow' then
				for i,o in ObjList(GROUP_ITEM) do
					if Dist(self,o)<48 then o.attract=max(o.attract,3) end
				end
			else
				for i,o in ObjList(GROUP_ITEM) do
					if Dist(self,o)<24 then o.attract=max(o.attract,3) end
				end
			end
		end
		if self.nextcollect<=0 and self.itemed then
			item.playercollect(self.item)
			self.item=self.item%6+1
--			lstg.var.collectitem=0
			self.itemed=false
			self.collecting=false
		end
		if self.collecting and not(self.itemed) then end
	elseif self.death==90 then
		if self.time_stop then self.death=self.death-1 end
		item.PlayerMiss()
		self.deathee={}
		self.deathee[1]=New(deatheff,self.x,self.y,'first')
		self.deathee[2]=New(deatheff,self.x,self.y,'second')
		New(player_death_ef,self.x,self.y)
	elseif self.death==84 then
		if self.time_stop then self.death=self.death-1 end
		self.hide=true
		self.support=4
	elseif self.death==50 then
		if self.time_stop then self.death=self.death-1 end
		self.x=0
		self.supportx=0
		self.y=-236
		self.supporty=-236
		self.hide=false
		New(bullet_deleter,self.x,self.y)
	elseif self.death<50 and not(self.lock) and not(self.time_stop) then
		self.y=-176-1.2*self.death
	end
	--img
	---加上time_stop的限制来实现图像时停
	if not(self.time_stop) then
	if abs(self.lr)==1 then
		self.img=self.imgs[int(self.ani/4)%8+1]
	elseif self.lr==-6 then
		self.img=self.imgs[int(self.ani/4)%4+13]
	elseif self.lr== 6 then
		self.img=self.imgs[int(self.ani/4)%4+21]
	elseif self.lr<0 then
		self.img=self.imgs[7-self.lr]
	elseif self.lr>0 then
		self.img=self.imgs[15+self.lr]
	end
	--------------------
	self.a=self.A
	self.b=self.B
	--some status
	self.lr=self.lr+dx;
	if self.lr> 6 then self.lr= 6 end
	if self.lr<-6 then self.lr=-6 end
	if self.lr==0 then self.lr=self.lr+dx end
	if dx==0 then
		if self.lr> 1 then self.lr=self.lr-1 end
		if self.lr<-1 then self.lr=self.lr+1 end
	end

	self.lh=self.lh+(self.slow-0.5)*0.3
	if self.lh<0 then self.lh=0 end
	if self.lh>1 then self.lh=1 end

	if self.nextshoot>0 then self.nextshoot=self.nextshoot-1 end
	if self.nextspell>0 then self.nextspell=self.nextspell-1 end
	if self.nextsp>0 then self.nextsp=self.nextsp-1 end
	if self.nextcollect>0 then self.nextcollect=self.nextcollect-1 end--HZC收点系统
	self.hyper=max(0,self.hyper-1)

--	if self.support>int(lstg.var.power/100) then self.support=self.support-0.0625
--	elseif self.support<int(lstg.var.power/100) then self.support=self.support+0.0625 end
--	if abs(self.support-int(lstg.var.power/100))<0.0625 then self.support=int(lstg.var.power/100) end

	self.supportx=self.x+(self.supportx-self.x)*0.6875
	self.supporty=self.y+(self.supporty-self.y)*0.6875

	if self.protect>0 then self.protect=self.protect-1 end
	if self.death>0 then self.death=self.death-1 end

	lstg.var.pointrate=item.PointRateFunc(lstg.var)
	--update supports
		if self.slist then
			self.sp={}
			if self.support==5 then
				for i=1,4 do self.sp[i]=MixTable(self.lh,self.slist[6][i]) self.sp[i][3]=1 end
			else
				local s=int(self.support)+1
				local t=self.support-int(self.support)
				for i=1,4 do
					if self.slist[s][i] and self.slist[s+1][i] then
						self.sp[i]=MixTable(t,MixTable(self.lh,self.slist[s][i]),MixTable(self.lh,self.slist[s+1][i]))
						self.sp[i][3]=1
					elseif self.slist[s+1][i] then
						self.sp[i]=MixTable(self.lh,self.slist[s+1][i])
						self.sp[i][3]=t
					end
				end
			end
		end
	--
	end---time_stop
	if self.time_stop then self.timer=self.timer-1 end
	if KeyIsDown'shoot' and KeyIsDown'slow' and player.death<10 and not(player.dialog) and not(IsValid(_wuer_pan)) then New(wuer_pan_shoot) end
	self._slist=
	{
		{-150+6*cos(self.timer),-144+6*sin(self.timer)},
		{-50+6*cos(self.timer+180),-120+6*sin(self.timer+180)},
		{50+6*cos(-self.timer),-120+6*sin(-self.timer)},
		{150+6*cos(-self.timer+180),-144+6*sin(-self.timer+180)}
	}
end
-------------------------------------------------------
function wuer_player:render()
	if lstg.var.power>=200 then
		SetImageState('wuer_support_red','mul+add',Color(192+63*sin(self.timer*3),255,255,255))
		for i=1,4 do
			Render('wuer_support_red',self._slist[i][1],self._slist[i][2],9*sin(self.timer*3),2.25)
		end
	end
	for i=1,4 do
		Render('wuer_support_blue',self._slist[i][1],self._slist[i][2],9*sin(self.timer*3),1.5)
	end
	player_class.render(self)
end
-------------------------------------------------------
function wuer_player:colli(other)
	if self.death==0 and not self.dialog and not cheat then
		if self.protect==0 then
			PlaySound('pldead00',0.5)
			if IsValid(_wuer_black_mask) then
				self.protect=180
				_wuer_black_mask.delflag=true
				lstg.var.chip_bonus=false
				if lstg.var.sc_bonus then lstg.var.sc_bonus=0 end
				for i,o in ObjList(GROUP_ENEMY_BULLET) do
					Kill(o)
				end
				PlaySound('slash',0.5)
			else self.death=100 end
		end
		if other.group==GROUP_ENEMY_BULLET then Del(other) end
	end
end
-------------------------------------------------------
wuer_special_pan=Class(object)
function wuer_special_pan:init(x,y,sp,mode)
	self.x=0 self.y=-60 self.group=GROUP_GHOST self.layer=LAYER_PLAYER_BULLET
	self.img='wuer_support_red' self.target=nil self.hscale=1.5 self.vscale=1.5
	self.sp=sp

end
function wuer_special_pan:frame()
	self.target=nil
	local maxpri=-1
	for i,o in ObjList(GROUP_NONTJT) do
		if o.colli then
			local dx=self.x-o.x
			local dy=self.y-o.y
			local pri=abs(dy)/(abs(dx)+0.01)
			if pri>maxpri then maxpri=pri self.target=o end
		end
	end
	for i,o in ObjList(GROUP_ENEMY) do
		if o.colli then
			local dx=self.x-o.x
			local dy=self.y-o.y
			local pri=abs(dy)/(abs(dx)+0.01)
			if pri>maxpri then maxpri=pri self.target=o end
		end
	end
	if self.sp==0 then
		local dmg=0.5
		if IsValid(_boss) then dmg=0.25 end
		if IsValid(self.target) then
			for i=-1,1 do
			if player.nextshoot==1 then
				New(wuer_support_fire,'wuer_support_fire',100*i-6,-60,24,Angle(100*i,-60,self.target.x,self.target.y),dmg)
				New(wuer_support_fire,'wuer_support_fire',100*i+6,-60,24,Angle(100*i,-60,self.target.x,self.target.y),dmg)
			end
			end
		end
	else
		local dmg=0.4
		if IsValid(_boss) then dmg=0.2 end
		if IsValid(self.target) then
			for i=-1,1,2 do
			if player.nextshoot==1 then
				New(wuer_support_fire,'wuer_support_fire',180*i-6,-80,24,Angle(180*i,-80,self.target.x,self.target.y),dmg)
				New(wuer_support_fire,'wuer_support_fire',180*i+6,-80,24,Angle(180*i,-80,self.target.x,self.target.y),dmg)
				New(wuer_support_fire,'wuer_support_fire',65*i-6,-10,24,Angle(65*i,-10,self.target.x,self.target.y),dmg)
				New(wuer_support_fire,'wuer_support_fire',65*i+6,-10,24,Angle(65*i,-10,self.target.x,self.target.y),dmg)
			end
			end
		end
	end
	if self.timer>900 then player.sp_pan=player.sp_pan-1 Del(self) end
end
function wuer_special_pan:render()
	SetImageState(self.img,'',Color(0xFFFFFFFF))
	if self.sp==0 then
		for i=-1,1 do
			Render(self.img,100*i,-60,9*sin(self.timer*3),1.5)
		end
	else
		for i=-1,1,2 do
			Render(self.img,180*i,-80,9*sin(self.timer*3),1.5)
			Render(self.img,65*i,-10,9*sin(self.timer*3),1.5)
		end
	end
end
wuer_support_fire=Class(player_bullet_straight)

function wuer_support_fire:kill()
	New(wuer_support_fire_ef,self.x,self.y,self.rot)
end
--
wuer_support_fire_ef=Class(object)

function wuer_support_fire_ef:init(x,y,rot)
	self.x=x self.y=y self.rot=rot self.img='wuer_support_fire_ef1' self.layer=LAYER_PLAYER_BULLET+50 self.group=GROUP_GHOST
	self.vx=2*cos(rot) self.vy=2*sin(rot)
end

function wuer_support_fire_ef:frame()
	self.img='wuer_support_fire_ef'..int(self.timer/4)%4+1
	if self.timer>16 then Del(self) end
end
function wuer_support_fire_ef:render()
	SetImageState(self.img,'mul+add',Color(255-255*self.timer/16,160,160,160))
	object.render(self)
	SetImageState(self.img,'mul+add',Color(255,255,255,255))
end
wuer_drawring=Class(object)
function wuer_drawring:init()
	self.x=player.x self.y=player.y self.group=GROUP_GHOST self.layer=LAYER_PLAYER-1
	self.omiga=8 self.r=120
end
function wuer_drawring:frame()
	self.x=player.x self.y=player.y
	if self.timer<900 then self.r=self.r-120/900 else Del(self) end
end
function wuer_drawring:render()
	misc.RenderRing('wuer_drawring',self.x,self.y,self.r-6,self.r+6, self.ani*3,32,16)
end
------------------spell-A------------------------------
wuer_frying_pan=Class(object)
function wuer_frying_pan:init(t)
	wuer_pan=self
	New(wuer_frying_pan2)
	self.t=t
	self.killflag=true
	self.a=1000 self.b=1000
	self.hscale=1.7 self.vscale=1.7
	self.x=-210 self.y=-200 self.layer=LAYER_PLAYER_BULLET-6 self.group=GROUP_PLAYER_BULLET self.bound=false
	self.dmg=12
	self.img1='wuer_frying_pan1'
	self.img2='wuer_frying_pan2'
	local oy=self.y
	task.New(self,function()
        do local x,_d_x=(-200),(400/6) for _=1,6 do
            last=New(wuer_frying_pan_fire,x,-260)
            task.Wait(3)
        x=x+_d_x end end
    end)
	task.New(self,function()
        self.rot=-15
        do for _=1,_infinite do
            task.New(self,function()
                do local y,_d_y=(oy),(60/30) for _=1,31 do
                    self.y=y
                    task.Wait(1)
                y=y+_d_y end end
                do return end
            end)
            task.Wait(20)
            task.New(self,function()
                do local rot,_d_rot=(-15),(30/15) for _=1,16 do
                    self.rot=rot
                    task.Wait(1)
                rot=rot+_d_rot end end
                PlaySound("fry",0.5,0,false)
                do return end
            end)
            task.Wait(10)
            task.New(self,function()
                do local y,_d_y=(oy+60),(-60/30) for _=1,31 do
                    self.y=y
                    task.Wait(1)
                y=y+_d_y end end
                do return end
            end)
            task.Wait(20)
            task.New(self,function()
                do local rot,_d_rot=(15),(-30/15) for _=1,16 do
                    self.rot=rot
                    task.Wait(1)
                rot=rot+_d_rot end end
                do return end
            end)
            task.Wait(10)
        end end
    end)
end
function wuer_frying_pan:frame()
	task.Do(self)
	if self.timer%5==0 then self.colli=true else self.colli=false end
	if self.timer>self.t then
		New(bomb_bullet_killer,0,0,600,600,false)
		PlaySound('slash',0.8)
		Del(self)
	end
end
function wuer_frying_pan:render()
	Render(self.img2,self.x,self.y,self.rot,self.hscale)
--	Render(self.img1,self.x,self.y,self.rot,self.hscale)
end
wuer_frying_pan2=Class(object)
function wuer_frying_pan2:init()
	self.hscale=1.7 self.vscale=1.7 self.img='wuer_frying_pan1'
	self.x=-210 self.y=-200 self.layer=LAYER_PLAYER_BULLET+6 self.group=GROUP_GHOST self.bound=false
end
function wuer_frying_pan2:frame()
	if IsValid(wuer_pan) then
		self.x=wuer_pan.x self.y=wuer_pan.y
		self.rot=wuer_pan.rot
	else
		Del(self)
	end
end
--
wuer_frying_item=Class(object)
function wuer_frying_item:init(x,y,_index,i)
	if i>600 then Del(self) end
	self.img='wuer_Ingredient'
	self.co={	Color(0xc0FF5050),
				Color(0xc0FFFF50),
				Color(0xc050FF50),
				Color(0xc0FFFFFF)
			}
	local index=_index
	if index<=4 then self.index=1 end
	if index>=15 or (index>=5 and index<=8) then self.index=4 end
	if index>=9 and index<=11 then self.index=3 end
	if index>=12 and index<=14 then self.index=2 end
	self.cof=self.co[self.index]
	self.x=x self.y=y self.layer=LAYER_PLAYER_BULLET self.group=GROUP_GHOST
	self.bound=false
    SetV2(self,ran:Float(2,4),-90,true,false)
	local maxspeed=ran:Float(2,5.5)
    local vx,vy=0,-ran:Float(1,3)
    local oldAngle=wuer_pan.rot or 0
    local oldfy=wuer_pan.y or 0
    local tempvx,tempvy=0,0
	self.navi=true
    task.New(self,function()
        do for _=1,_infinite do
            tempvy=tempvy-0.05
            local frAngle=wuer_pan.rot
            local fy=wuer_pan.y
            local vx1=x-wuer_pan.x
            local vy1=y-fy
            local vx2=cos(frAngle)
            local vy2=sin(frAngle)
            local outer=vx1*vy2-vx2*vy1
            local inner=vx1*vx2+vy1*vy2
            if outer>0 then
            	local vfrAngle=frAngle-90
            	x=x-outer*cos(vfrAngle)
            	y=y-outer*sin(vfrAngle)
            	local accel=0
            	local speed=Dist(0,0,vx,vy)
            	if vy<=0 then
            	local refAngle=2*vfrAngle-atan2(-vy,-vx)
            	vx=speed*cos(refAngle)
            	vy=0.3*speed*sin(refAngle)
            	else
            	accel=accel-speed
            	end
            accel=accel+oldfy-fy+inner*tan(oldAngle-frAngle)
            tempvx=tempvx+accel*cos(vfrAngle)
            tempvy=tempvy+accel*sin(vfrAngle)
            end
            oldAngle=frAngle
            oldfy=fy
            if x>192 then x=192 vx=-0.8*abs(vx) end
            if x<-192 then x=-192 vx=0.8*abs(vx) end
            if y>224 then y=224 vy=-0.8*abs(vy) end
            vx=vx+tempvx
            vy=vy+tempvy
            tempvx=0 tempvy=0
            local speed=Dist(0,0,vx,vy)
            if speed>maxspeed then
            local ratio=maxspeed/speed
            vx=vx*ratio vy=vy*ratio
            end
            x=x+vx y=y+vy
            self.x=x self.y=y
            task._Wait(1)
        end end
    end)
end
function wuer_frying_item:frame()
	if IsValid(wuer_pan) then
		task.Do(self)
		if Dist(self,player)<30 then lstg.var.faith=lstg.var.faith+1 PlaySound('item00',0.3,self.x/200) Del(self) end
	else
		local a=Angle(self,player)
		self.vx=6*cos(a) self.vy=6*sin(a)
		if Dist(self,player)<30 then lstg.var.faith=lstg.var.faith+5 PlaySound('item00',0.3,self.x/200) Del(self) end
	end
end
function wuer_frying_item:render()
	SetImageState(self.img,'mul+add',self.cof)
	object.render(self)
end
--
wuer_frying_pan_fire=Class(object)
function wuer_frying_pan_fire:init(x,y)
	self.x=x self.y=y
	self.img='wuer_fire'
	self.layer=LAYER_PLAYER_BULLET+10 self.group=GROUP_GHOST self.bound=false
	task.New(self,function()
        self.hscale=4
        self.vscale=2.25
        local dy=ran:Float(-5,5)
        do for _=1,_infinite do
            if IsValid(wuer_pan) then
                self.y=wuer_pan.y-60+dy+1.5*wuer_pan.rot
                self.vscale=2.25+max(0,(self.x/500))
            else
				Del(self)
            end
            task.Wait(1)
        end end
    end)
end
function wuer_frying_pan_fire:frame()
	task.Do(self)
end
function wuer_frying_pan_fire:render()
	SetImgState(self,'mul+add',255,255,255,255)
	object.render(self)
end
--
wuer_spell_mask=Class(object)
function wuer_spell_mask:init(r,g,b,t1,t2,t3)
	self.x=0
	self.y=-150
	self.bound=false
	self.group=GROUP_GHOST
	self.layer=LAYER_BG+1
	self.img='wuer_spell_mask_A'
	self.red=r
	self.green=g
	self.blue=b
	self.vy=3
	SetImageState(self.img,'mul+add',Color(0,r,g,b))
	task.New(self,function()
		for i=1,t1 do
			SetImageState(self.img,'mul+add',Color(i*255/t1,r,g,b))
			task.Wait(1)
		end
		task.Wait(t2)
		for i=t3,1,-1 do
			SetImageState(self.img,'mul+add',Color(i*255/t3,r,g,b))
			task.Wait(1)
		end
		Del(self)
	end)
end

function wuer_spell_mask:frame()
	task.Do(self)
end
function wuer_spell_mask:render()
	for i=-2,2 do
		Render(self.img,self.x,self.y+430*i)
	end
end
-------------------------------------------------------
------------------spell-B------------------------------
wuer_black_mask=Class(object)
function wuer_black_mask:init()
	_wuer_black_mask=self
	self.x=player.x self.y=player.y
	self.hscale=10 self.vscale=10
	self.layer=LAYER_TOP-1 self.group=GROUP_GHOST
	self.img='wuer_black_mask'
end
function wuer_black_mask:frame()
	if not ext.replay.IsReplay() then scoredata.er_pot_time=scoredata.er_pot_time+1 end
	if scoredata.er_pot_time==18000 then New(achievement_obj,2,26) end
	if self.timer<180 then self.hscale=10-7*sin(self.timer*0.5) self.vscale=self.hscale end
	if self.timer>600 and not self.delflag then self.hscale=max(self.hscale-0.001,1) self.vscale=self.hscale end
	self.x=player.x self.y=player.y
	if self.delflag then
		self.hscale=self.hscale+0.25 self.vscale=self.vscale+0.5
		if self.hscale>12 then Del(self) end
	end
end
--
wuer_pot=Class(object)
function wuer_pot:init()
	self.x=player.x self.y=player.y
	self.layer=LAYER_PLAYER_BULLET-1 self.group=GROUP_GHOST
	self.img='wuer_pot'
	self.hscale=0.75 self.vscale=self.hscale
end
function wuer_pot:frame()
	if self.timer>164 then Del(self) end
	self.x=player.x self.y=player.y
end
function wuer_pot:render()
	SetImageState(self.img,'',Color(180-180*self.timer/165,255,255,255))
	object.render(self)
end
------------------main shoot---------------------------
wuer_bullet_knife=Class(player_bullet_straight)

function wuer_bullet_knife:kill()
	New(wuer_bullet_knife_ef1,self.x,self.y)
	New(wuer_bullet_knife_ef1,self.x,self.y)
	New(wuer_bullet_knife_ef2,self.x,self.y+8)
end
--
wuer_bullet_knife_ef1=Class(object)

function wuer_bullet_knife_ef1:init(x,y)
	self.x=x self.y=y self.rot=ran:Float(0,360) self.img='wuer_knife_ef' self.layer=LAYER_PLAYER_BULLET+50 self.group=GROUP_GHOST
	local angle,v=ran:Float(-110,-70),ran:Float(1.5,2) self.vx=v*cos(angle) self.vy=v*sin(angle)
	self.omiga=ran:Float(9,18)*ran:Sign() self.hscale=1.6 self.vscale=1.6
end

function wuer_bullet_knife_ef1:frame()
	if self.timer>=32 then Del(self) end
end
function wuer_bullet_knife_ef1:render()
	SetImageState('wuer_knife_ef','mul+add',Color(255-255*self.timer/32,160,160,160))
	object.render(self)
	SetImageState('wuer_knife_ef','mul+add',Color(255,255,255,255))
end
--
wuer_bullet_knife_ef2=Class(object)

function wuer_bullet_knife_ef2:init(x,y)
	self.x=x self.y=y self.rot=90 self.img='wuer_knife_ef' self.layer=LAYER_PLAYER_BULLET+50 self.group=GROUP_GHOST
	self.vy=2.5
end
function wuer_bullet_knife_ef2:frame()
	if self.timer>14 then Del(self) end
end
-------------------------------------------------------
-------------------support shoot--------------------------
wuer_locked_bullet=Class(object)

function wuer_locked_bullet:init(img,x,y,v,a,dmg)
	self.x=x self.y=y self.rot=a self.vx=v*cos(a) self.vy=v*sin(a)
	self.layer=LAYER_PLAYER_BULLET self.group=GROUP_PLAYER_BULLET
	self.dmg=dmg self.img=img
	self.hscale=1 self.vscale=1
	self.a=12 self.b=12
end
function wuer_locked_bullet:render()
	SetImageState(self.img,'',Color(0x70FFFFFF))
	object.render(self)
end
function wuer_locked_bullet:kill()
	New(wuer_locked_bullet_ef,self.img,self.x,self.y,self.rot)
end
--
wuer_locked_bullet_ef=Class(object)
function wuer_locked_bullet_ef:init(img,x,y,rot)
	self.x=x self.y=y self.rot=rot self.img=img self.layer=LAYER_PLAYER_BULLET+50 self.group=GROUP_GHOST
	self.vx=2*cos(self.rot) self.vy=2*sin(self.rot)
	self.hscale=0.75 self.vscale=0.75
end
function wuer_locked_bullet_ef:frame()
	if self.timer>=16 then Del(self) end
end
function wuer_locked_bullet_ef:render()
	SetImageState(self.img,'mul+add',Color(0xFFFFFFFF))
	object.render(self)
	SetImageState(self.img,'',Color(0xFFFFFFFF))
end
-------------------------------------------------------
-------------------slow shoot--------------------------
wuer_pan_shoot=Class(object)
function wuer_pan_shoot:init()
	_wuer_pan=self
	self.img='wuer_pan'
	self.a=80
	self.b=80
	self.omiga=-20
	self.vscale=1.3
	self.hscale=1.3
	self.killflag=1
	self.bound=false
	self.layer=LAYER_PLAYER_BULLET
	self.group=GROUP_PLAYER_BULLET
	self.target=nil
	self.collitime=15
	player_class.findtarget(self)
	self.x=player.x
	self.y=player.y
	local fa=90
	if IsValid(self.target) then fa=Angle(self,self.target) end
	self.x=player.x+45*cos(fa)
	self.y=player.y+45*sin(fa)
	self.navi=false
	--self.circler=0
	--self.p=101
	self.dmg=0
	self.DMG=7
	self.hide=false
	self.first_time=0
	self.buffcolli=0
	self.eff_tar=nil
	task.New(self,function()
        if IsValid(self.target) and Dist(self,self.target)<180 then
            SetV2(self,8,Angle(self,self.target),false,false)
        else
            SetV2(self,8,90,false,false)
        end
        do local scale,_d_scale=(0),(1.5/9) for _=1,10 do
            self.hscale=scale
            task.Wait(1)
        scale=scale+_d_scale end end
        do for _=1,10 do
            if not(IsValid(self.target)) then break end
            self.vy=self.vy-0.8
            task.Wait(1)
        end end
        if IsValid(self.target) and self.target.colli then
            local aa=Angle(self,self.target)
            SetV2(self,self.vy/2,aa,false,false)
        else
        end
    end)
    task.New(self,function()
        task.Wait(8)
        do for _=1,_infinite do
            if IsValid(self.target) and self.target.colli then
                if KeyIsDown'shoot' and KeyIsDown'slow' then
                    self.collitime=15
                else
                end
				local tar=self.target
				if IsValid(self.eff_tar) then tar=self.eff_tar end
                local a=Angle(self,tar)
                local d=Dist(self,tar)
                if self.buffcolli==5 then
					for _=1,8 do
					local D=min(self.a,d/2)
					New(wuer_pan_ef,self.x+D*cos(a)+ran:Float(-8,8),self.y+D*sin(a)+ran:Float(-8,8),
									ran:Float(0,360),ran:Float(1.25,2.5),ran:Float(0,360),0)
					end
					if self.target==_boss then
						if d>self.a*0.9 then
							SetV2(self,0.8,a+180,false,false)
							self.DMG=7
						else
							SetV2(self,0.4,a+180,false,false)
							self.DMG=4
						end
					else
						SetV2(self,0.4,a+180,false,false)
						self.DMG=6
					end
                else
                end
                if self.buffcolli<=0 then
                    _set_a(self,0.15,a,false)
                else
                end
            else
                SetV2(self,0,0,false,false)
            end
            task.Wait(1)
        end end
    end)
end

function wuer_pan_shoot:frame()
	if self.timer%2==0 then New(wuer_pan_smear,self.x,self.y,self.rot,self) end
	player_class.findtarget(self)
	---task
	task.Do(self)
	---
	self.buffcolli=self.buffcolli-1
    if self.buffcolli<=0 then self.colli=true end
    if not(KeyIsDown'slow') or player.death>10 then
		self.collitime=self.collitime-1
		if self.collitime<=0 then
			Del(self)
			SetImageState(self.img,'',Color(0xD0FFA0FF))
		end
	end
    if not(KeyIsDown'shoot') then
		Del(self)
		SetImageState(self.img,'',Color(0xD0FFA0FF))
	end
	if player.death==89 or player.dialog then Del(self) end
end
function wuer_pan_shoot:render()
	if self.buffcolli>0 then SetImageState(self.img,'',Color(0xDCFF8080)) end
	if self.buffcolli<-10 then SetImageState(self.img,'',Color(0xDCFFFFFF)) end
	object.render(self)
end
function wuer_pan_shoot:del()
	New(wuer_pan_del_ef,self.x,self.y,self.rot,self.omiga)
end
--
wuer_pan_ef=Class(object)
function wuer_pan_ef:init(x,y,rot,v,a,t)
	self.x=x self.y=y self.rot=rot self.img='wuer_fire' self.layer=LAYER_PLAYER_BULLET+50 self.group=GROUP_GHOST
	self.hscale=0.3 self.vscale=0.3 self.t=t
	self.vx=v*cos(a) self.vy=v*sin(a)
end
function wuer_pan_ef:frame()
	if self.timer>15 then
		if self.t~=0 then New(wuer_pan_ef,self.x,self.y,ran:Float(0,360),ran:Float(0.5,1.5),ran:Float(0,360),self.t-1) end
		Del(self)
	end
end
function wuer_pan_ef:render()
	SetImgState(self,'mul+add',255-255*self.timer/16,255,255,255)
	object.render(self)
end
--
wuer_pan_smear=Class(object)
function wuer_pan_smear:init(x,y,rot,mas)
	self.x=x self.y=y self.rot=rot self.layer=LAYER_PLAYER_BULLET-1 self.group=GROUP_GHOST
	self.colli=false self.img='wuer_pan' self.mas=mas
	self.hscale=1.5 self.vscale=1.5
end
function wuer_pan_smear:frame()
	if IsValid(self.mas) then self.x=self.mas.x self.y=self.mas.y else Del(self) end
	if self.timer>11 then Del(self) end
end
function wuer_pan_smear:render()
	SetImageState(self.img,'',Color(220-220*self.timer/12,255,255,255))
	object.render(self)
end
--
wuer_pan_del_ef=Class(object)
function wuer_pan_del_ef:init(x,y,rot,omiga)
	self.x=x self.y=y self.layer=LAYER_PLAYER_BULLET-1 self.group=GROUP_GHOST
	self.rot=rot self.omiga=omiga
	self.img='wuer_pan'
	self.colli=false
end
function wuer_pan_del_ef:frame()
	self.hscale=1.5-1.5*self.timer/20
	self.vscale=1.5-1.5*self.timer/20
	if self.timer>19 then Del(self) end
end
function wuer_pan_del_ef:render()
	SetImageState(self.img,'',Color(0xDCFFFFFF))
	object.render(self)
end
----------
wuer_pan_dmg_obj=Class(object)
function wuer_pan_dmg_obj:init(x,y,dmg)
	self.x=x self.y=y self.mute=true self.dmg=dmg self.a=85 self.b=85
	self.killflag=false self.group=GROUP_PLAYER_BULLET self.hide=true
end
function wuer_pan_dmg_obj:frame()
	if self.timer==2 then Del(self) end
end




