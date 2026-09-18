LoadPS('player_death_ef','THlib\\player\\player_death_ef.psi','parimg1')
LoadPS('graze','THlib\\player\\graze.psi','parimg6')
LoadPS('itembar_par1','THlib\\player\\itembar_par1.psi','parimg2')
LoadPS('itembar_par2','THlib\\player\\itembar_par2.psi','parimg2')
LoadPS('itembar_par3','THlib\\player\\itembar_par3.psi','parimg2')
LoadImageFromFile('player_spell_mask','THlib\\player\\spellmask.png')
LoadImageFromFile('itembar','THlib\\player\\itembar.png')
----Base class of all player characters (abstract)----

item_bar=Class(object)
function item_bar:init()
	self.group=GROUP_GHOST
	self.layer=LAYER_TOP
	self.img='itembar_par1'
	self.x=-140
	self.y=-200
	self.par=0
	self.r=255 self.g=255 self.b=255
end
function item_bar:frame()
	local l1,l2,l3=lstg.var.itembar[1],lstg.var.itembar[2],lstg.var.itembar[3]
	local m=max(l1,max(l2,l3))
	local x,y=-141,-200
	if l1+l2+l3>=300 then
		if (l1~=l2 and l1~=l3) or (l1==l3 and l1<l2) or (l1==l2 and l1<l3) or (l2==l3 and l2<l1) then
			if m==l1 then Getlife(0.25*l1) New(bonus_par,x,y,1)
			elseif m==l2 then Getbomb(0.25*l2) New(bonus_par,x,y,2)
			elseif m==l3 then lstg.var.score=lstg.var.score+lstg.var.pointrate*l3 New(bonus_par,x,y,3) end
		end
		if l1==l2 and l1>l3 then
			Getlife(0.25*l1) New(bonus_par,x-24,y,1)
			Getbomb(0.25*l2) New(bonus_par,x+24,y,2)
		end
		if l1==l3 and l1>l2 then
			Getlife(0.25*l1) New(bonus_par,x-24,y,1)
			lstg.var.score=lstg.var.score+lstg.var.pointrate*l3 New(bonus_par,x+24,y,3)
		end
		if l2==l3 and l2>l1 then
			Getbomb(0.25*l2) New(bonus_par,x-24,y,2)
			lstg.var.score=lstg.var.score+lstg.var.pointrate*l3 New(bonus_par,x+24,y,3)
		end
		if l1==100 and l2==100 then
			Getlife(0.25*l1) New(bonus_par,x-36,y,1)
			Getbomb(0.25*l2) New(bonus_par,x,y,2)
			lstg.var.score=lstg.var.score+lstg.var.pointrate*l3 New(bonus_par,x+36,y,3)
		end
		PlaySound('astralup',0.8)
		lstg.var.itembar={0,0,0}
	end
end
function item_bar:render()
	SetViewMode'ui'
	local x,y=38,40
--	local alpha,dist=1,Dist(self.x,self.y,player.x,player.y)
	local ax,ay=0,0
	ax=max(min((lstg.player.x+60)*0.05,0),-0.9)
	ay=max(min((lstg.player.y+160)*0.05,0),-0.9)
	local alpha=1-ax*ay
--	if dist<128 then alpha=0.25+dist/170 end
	local var=lstg.var
	local l1,l2,l3=lstg.var.itembar[1]*0.3,lstg.var.itembar[2]*0.3,lstg.var.itembar[3]*0.3
	local n1,n2,n3=lstg.var.itembar[1],lstg.var.itembar[2],lstg.var.itembar[3]
--[[	SetImageState('white','',Color(alpha*255,209,095,238))
	RenderRect('white',self.x,self.x+l1,self.y-6.5,self.y+6.5)
	SetImageState('white','',Color(alpha*255,000,222,000))
	RenderRect('white',self.x+l1,self.x+l1+l2,self.y-6.5,self.y+6.5)
	SetImageState('white','',Color(alpha*255,028,134,238))
	RenderRect('white',self.x+l1+l2,self.x+l1+l2+l3,self.y-6.5,self.y+6.5)]]
	local n=n1+n2+n3
--[[	local r,g,b=	(n1*209+n2*0+n3*28)/n,
					(n1*95+n2*222+n3*134)/n,
					(n1*238+n2*0+n3*238)/n]]
	if n1>=n/3 then self.r=min(255,self.r+2.5) else self.r=max(30,self.r-2.5) end
	if n2>=n/3 then self.g=min(255,self.g+2.5) else self.g=max(30,self.g-2.5) end
	if n3>=n/3 then self.b=min(255,self.b+2.5) else self.b=max(30,self.b-2.5) end
	local r,g,b=self.r,self.g,self.b
	SetImageState('white','',Color(alpha*255,r,g,b))
	RenderRect('white',x,x+l1+l2+l3,y-6.5,y+6.5)
	SetImageState('itembar','',Color(alpha*255,255,255,255))
	SetImageState('item1','',Color(alpha*255,255,255,255))
	SetImageState('item5','',Color(alpha*255,255,255,255))
	SetImageState('item2','',Color(alpha*255,255,255,255))
	Render('itembar',x+45,y)
	Render('item1',x+4,y-16)
	Render('item5',x+36,y-16)
	Render('item2',x+68,y-16)
	SetFontState('bonus','',Color(alpha*255,0,0,0))
	RenderText('bonus','X'..var.itembar[1],x+13,y-11,0.35,'left')
	RenderText('bonus','X'..var.itembar[2],x+46,y-11,0.35,'left')
	RenderText('bonus','X'..var.itembar[3],x+77,y-11,0.35,'left')
	SetFontState('bonus','',Color(alpha*255,255,255,255))
	RenderText('bonus','X'..var.itembar[1],x+12,y-10,0.35,'left')
	RenderText('bonus','X'..var.itembar[2],x+45,y-10,0.35,'left')
	RenderText('bonus','X'..var.itembar[3],x+76,y-10,0.35,'left')
	SetImageState('item1','',Color(255,255,255,255))
	SetImageState('item5','',Color(255,255,255,255))
	SetImageState('item2','',Color(255,255,255,255))
	SetViewMode'world'
end

bonus_par=Class(object)
function bonus_par:init(x,y,n)
	self.x=x self.y=y
	self.img='itembar_par'..n
	self.group=GROUP_GHOST
	self.layer=LAYER_TOP
end
function bonus_par:frame()
	if self.timer>8 then ParticleStop(self) end
	if self.timer>60 then Del(self) end
end
function bonus_par:render()
	object.render(self)
end

player_class=Class(object)

function player_class:init()
	self.group=GROUP_PLAYER
	self.y=-176
	self.supportx=0
	self.supporty=self.y
	self.hspeed=4
	self.lspeed=2
	self.collect_line=96
	self.slow=0
	self.layer=LAYER_PLAYER
	self.lr=1
	self.lh=0
	self.fire=0
	self.lock=false
	self.dialog=false
	self.bound=false
	self.nextshoot=0
	self.nextspell=0
	self.nextsp=0
	self.A=0        --自机判定大小
	self.B=0
	self.nextcollect=0--HZC收点系统
	self.item=1
	self.death=0
	self.protect=120
	lstg.player=self
	player=self
	self.grazer=New(grazer)
	if not lstg.var.init_player_data then error('Player data has not been initialized. (Call function item.PlayerInit.)') end
	self.support=4
	self.sp={}
	self.time_stop=false
	self.item_bar=New(item_bar)
	self.no_shoot_time=0
	self.first_blood=0
	self.miss_with_no_bomb=0
end

function player_class:frame()
	if lstg.var.bomb==8 and lstg.var.lifeleft==8 and scoredata.achi_common[3]~=1 then New(achievement_obj,2,3) end
	if KeyIsDown'shoot' then
		self.no_shoot_time=0
	else
		self.no_shoot_time=self.no_shoot_time+1
	end
	if self.no_shoot_time==10800 then New(achievement_obj,2,30) end
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
			lstg.var.power=min(lstg.var.power+1/45,400)
			if KeyIsDown'shoot' and self.nextshoot<=0 then self.class.shoot(self) end
			if KeyIsDown'spell' and self.nextspell<=0 and lstg.var.bomb>0 and not lstg.var.block_spell then
				item.PlayerSpell()
				lstg.var.bomb=lstg.var.bomb-1
				self.class.spell(self)
				self.death=0
				self.nextcollect=90
			end
			if KeyIsDown'special' and self.nextsp<=0 and self.death==0 then self.class.special(self) end
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
	elseif self.death==84 then
		if self.time_stop then self.death=self.death-1 end
		self.hide=true
--		self.support=int(lstg.var.power/100)
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
end

function player_class:render()
	if self.protect%3==1 then SetImageState(self.img,'',Color(0xFF0000FF))
	else SetImageState(self.img,'',Color(0xFFFFFFFF)) end
	object.render(self)
end

function player_class:colli(other)
	if self.death==0 and not self.dialog and not cheat then
		if self.protect==0 then
			New(death_kekkai,self.x,self.y)
			New(player_death_ef,self.x,self.y)
			PlaySound('pldead00',0.5)
			self.death=100
		end
		if other.group==GROUP_ENEMY_BULLET then Del(other) end
	end
end

function player_class:findtarget()
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
end

grazer=Class(object)

function grazer:init()
	self.layer=LAYER_ENEMY_BULLET_EF+50
	self.group=GROUP_PLAYER
	self.player=lstg.player
	self.grazed=false
	self.img='graze'
	self.bound=false
	ParticleStop(self)
	self.a=24
	self.b=24
	self.aura=0
end

function grazer:frame()
	self.x=self.player.x
	self.y=self.player.y
	self.hide=self.player.hide
	if not self.player.time_stop then
	self.aura=self.aura+1.5 end
	--
	if self.grazed then
		PlaySound('graze',0.3,self.x/200)
		self.grazed=false
		ParticleFire(self)
	else ParticleStop(self) end
end

function grazer:render()
	object.render(self)
	SetImageState('player_aura','',Color(0xC0FFFFFF)*self.player.lh+Color(0x00FFFFFF)*(1-self.player.lh))
	Render('player_aura',self.x,self.y, self.aura,2-self.player.lh)
	SetImageState('player_aura','',Color(0xC0FFFFFF))
	Render('player_aura',self.x,self.y,-self.aura,self.player.lh)
end

function grazer:colli(other)
	if other.group~=GROUP_ENEMY and (not other._graze) then
		item.PlayerGraze()
		lstg.player.grazer.grazed=true
		other._graze=true
	end
end

player_bullet_straight=Class(object)

function player_bullet_straight:init(img,x,y,v,angle,dmg)
	self.group=GROUP_PLAYER_BULLET
	self.layer=LAYER_PLAYER_BULLET
	self.img=img
	self.x=x
	self.y=y
	self.rot=angle
	self.vx=v*cos(angle)
	self.vy=v*sin(angle)
	self.dmg=dmg
	if self.a~=self.b then self.rect=true end
end

player_bullet_hide=Class(object)

function player_bullet_hide:init(a,b,x,y,v,angle,dmg,delay)
	self.group=GROUP_PLAYER_BULLET
	self.layer=LAYER_PLAYER_BULLET
	self.colli=false
	self.a=a
	self.b=b
	self.x=x
	self.y=y
	self.rot=angle
	self.vx=v*cos(angle)
	self.vy=v*sin(angle)
	self.dmg=dmg
	self.delay=delay or 0
end

function player_bullet_hide:frame()
	if self.timer==self.delay then self.colli=true end
end

player_bullet_trail=Class(object)

function player_bullet_trail:init(img,x,y,v,angle,target,trail,dmg)
	self.group=GROUP_PLAYER_BULLET
	self.layer=LAYER_PLAYER_BULLET
	self.img=img
	self.x=x
	self.y=y
	self.rot=angle
	self.v=v
	self.target=target
	self.trail=trail
	self.dmg=dmg
end

function player_bullet_trail:frame()
	if IsValid(self.target) and self.target.colli then
		local a=math.mod(Angle(self,self.target)-self.rot+720,360)
		if a>180 then a=a-360 end
		local da=self.trail/(Dist(self,self.target)+1)
		if da>=abs(a) then self.rot=Angle(self,self.target)
		else self.rot=self.rot+sign(a)*da end
	end
	self.vx=self.v*cos(self.rot)
	self.vy=self.v*sin(self.rot)
end

player_spell_mask=Class(object)

function player_spell_mask:init(r,g,b,t1,t2,t3)
	self.x=0
	self.y=0
	self.group=GROUP_GHOST
	self.layer=LAYER_BG+1
	self.img='player_spell_mask'
	self.red=r
	self.green=g
	self.blue=b
	SetImageState('player_spell_mask','mul+add',Color(0,r,g,b))
	task.New(self,function()
		for i=1,t1 do
			SetImageState('player_spell_mask','mul+add',Color(i*255/t1,r,g,b))
			task.Wait(1)
		end
		task.Wait(t2)
		for i=t3,1,-1 do
			SetImageState('player_spell_mask','mul+add',Color(i*255/t1,r,g,b))
			task.Wait(1)
		end
		Del(self)
	end)
end

function player_spell_mask:frame()
	task.Do(self)
end

player_death_ef=Class(object)

function player_death_ef:init(x,y)
	self.x=x self.y=y self.img='player_death_ef' self.layer=LAYER_PLAYER+50
end

function player_death_ef:frame()
	if self.timer==4 then ParticleStop(self) end
	if self.timer==60 then Del(self) end
end

function MixTable(x,t1,t2)
	r={}
	local y=1-x
	if t2 then
		for i=1,#t1 do
			r[i]=y*t1[i]+x*t2[i]
		end
		return r
	else
		local n=int(#t1/2)
		for i=1,n do
			r[i]=y*t1[i]+x*t1[i+n]
		end
		return r
	end
end
--death_ef
deatheff=Class(object)

function deatheff:init(x,y,type_)
	self.x=x
	self.y=y
	self.type=type_
	self.size=0
	self.size1=0
	self.layer=LAYER_TOP-1
	task.New(self,function()
		local size=0
		local size1=0
		if self.type=='second' then task.Wait(30) end
		for i=1,360 do
			self.size=size
			self.size1=size1
			size=size+12
			size1=size1+8
			task.Wait(1)
		end
	end)
end

function deatheff:frame()
	task.Do(self)
	if self.timer>180 then Del(self) end
end

function deatheff:render()
	if self.type=='first' then
		rendercircle(self.x,self.y,self.size,180)
		rendercircle(self.x+35,self.y+35,self.size1,180)
		rendercircle(self.x+35,self.y-35,self.size1,180)
		rendercircle(self.x-35,self.y+35,self.size1,180)
		rendercircle(self.x-35,self.y-35,self.size1,180)
	elseif self.type=='second' then
		rendercircle(self.x,self.y,self.size,180)
	end
end
---
death_kekkai=Class(object)
function death_kekkai:init(x,y)
	self.x=x self.y=y
	self.group=GROUP_GHOST
	self.layer=LAYER_PLAYER+50
	self.img='bubble1'
	self.hscale=0 self.vscale=0
	SetImageState(self.img,'',Color(128,255,255,255))
end
function death_kekkai:frame()
	if self.timer<24 then
		self.hscale=self.timer*0.3
		self.vscale=self.timer*0.3
	end
	if self.timer>60 then Del(self) end
end
function death_kekkai:render()
	if self.timer>=8 then
		SetImageState(self.img,'',Color(max(0,128-128*(self.timer-10)/16),255,255,255))
	end
	object.render(self)
end

---
player_list={
	{'Hakurei Reimu','reimu_player','Reimu'},
	{'Kirisame Marisa','marisa_player','Marisa'},
	{'Kochiya Sanae','sanae_player','Sanae'},
	{'Wuer','wuer_player','Wuer'},
--	{'Shalimar','shababa_player','Shalimar'},
}

Include'THlib\\player\\reimu\\reimu.lua'
Include'THlib\\player\\marisa\\marisa.lua'
Include'THlib\\player\\wuer\\wuer.lua'
Include'THlib\\player\\sanae\\sanae.lua'
--Include'THlib\\player\\shababa\\shababa_player.lua'
