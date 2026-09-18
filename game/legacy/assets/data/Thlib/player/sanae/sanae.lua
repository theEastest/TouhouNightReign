sanae_player=Class(player_class)

function sanae_player:init()
	LoadTexture('sanae_player','THlib\\player\\sanae\\sanae.png')
	LoadImageGroup('sanae_player','sanae_player',0,0,32,48,8,3,0,0)
	LoadImage('sanae_support','sanae_player',64,144,16,16)
--------------------------------------------------------------------
	LoadTexture('sanae_bs','THlib\\player\\sanae\\sanae_bs.png')
	LoadImage('sanae_bs','sanae_bs',0,0,1024,1024)
	LoadTexture('sanae_bf','THlib\\player\\sanae\\sanae_bf.png')
	LoadImage('sanae_bf','sanae_bf',0,0,256,256,72,72)
--------------------------------------------------------------------
	LoadTexture('sanae_wind','THlib\\player\\sanae\\sanae_wind.png')
	LoadImage('sanae_wind','sanae_wind',0,0,128,128,128,128)
--------------------------------------------------------------------
	LoadTexture('sanae_wind2','THlib\\player\\sanae\\sanae_wind2.png')
	LoadImage('sanae_wind2','sanae_wind2',0,0,16,128,16,128)
--------------------------------------------------------------------
	LoadImageFromFile('sanae_ji','THlib\\player\\sanae\\sanae_ji.png')
	LoadImageFromFile('sanae_daji','THlib\\player\\sanae\\sanae_daji.png')
	LoadImageFromFile('sanae_xiong','THlib\\player\\sanae\\sanae_xiong.png')
	LoadImageFromFile('sanae_daxiong','THlib\\player\\sanae\\sanae_daxiong.png')
	LoadImageFromFile('sanae_eff','THlib\\player\\sanae\\sanae_eff.png')
	LoadImageGroup('sanae_drawring','boss',64,0,16,8,1,16)
	for i=1,16 do SetImageState('sanae_drawring'..i,'mul+add',Color(0x80FFFFFF)) end
	LoadSound('sanae_lucky','THlib\\player\\sanae\\sanae_lucky.wav')
	LoadSound('sanae_unlucky','THlib\\player\\sanae\\sanae_unlucky.wav')
--------------------------------------------------------------------
	player_class.init(self)
	self.imgs={}
	for i=1,24 do self.imgs[i]='sanae_player'..i end
	self.hspeed=4.5
	self.lspeed=2
	self.st=60
	self.x0=self.x
	self.y0=self.y
	self.x1=self.x
	self.y1=self.y
	self.name='Sanae'
	self.slist=
	{
		{     nil,    nil,      nil,     nil},
		{{0,0,0,0},    nil,      nil,     nil},
		{{0,0,0,0},{0,0,0,0},     nil,     nil},
		{{0,0,0,0},{0,0,0,0},{0,0,0,0},     nil},
		{{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0}},
		{{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0}},
	}
	self.zao={70,70}
	self.zao_num=1
end

function sanae_player:shoot()
	if self.timer%4==0 then PlaySound('plst00',0.3,self.x/1024) end
	if self.support>0 then
		local t=self.timer*4
		local a=360/self.support
		if self.slow==0 then
			for i=1,4 do if self.sp[i] then
				if self.timer%4==0 then
					New(sanae_wind,self.st*cos(t+i*a)+self.x,self.st*sin(t+i*a)+self.y,0.25)
				end
				if self.timer%8==0 then
					New(sanae_wind2,self.st*cos(t+i*a)+self.x,self.st*sin(t+i*a)+self.y,t+i*a,6,0.10)
				end
			end end
		else
			if self.timer%8==0 then
				New(sanae_wind3,self.x,self.y,90,9,0.6)
			end
			local dmg=0.03
			if IsValid(_boss) then dmg=0.04 end
			for i=1,4 do if self.sp[i] then
				if self.timer%4==0 then
					New(sanae_wind,
					self.st*cos(t+i*a)+self.x0,
					self.st*sin(t+i*a)+self.y0,dmg)
				end
			end end
		end
	end
end

function sanae_player:spell()
	PlaySound('nep00',1.0)
	misc.ShakeScreen(270,4)
	self.collect_line=self.collect_line-500
	New(tasker,function()
		task.Wait(90)
		self.collect_line=self.collect_line+500
	end)
	if self.slow==0 then
		New(player_spell_mask,50,50,255,16,224,16)
		New(sanae_bf,self.x,self.y,2,self)
		New(tasker,function()
			for i=1,240 do
				task.Wait(1)
				New(bomb_bullet_killer,self.x1,self.y1,120*1.5,120*1.5,false)
			end
		end)
	else
		New(player_spell_mask,200,200,200,16,224,16)
		New(sanae_dmg,1.5)
		for i=0,8 do
			New(sanae_bs,-1024*i)
		end
		New(tasker,function()
			for i=1,240 do
				task.Wait(1)
				New(bullet_killer,self.x,self.y)
			end
		end)
	end
	New(tasker,function()
		task.Wait(240)
		PlaySound('slash',1.0)
	end)
	self.nextspell=300
	self.protect=360
end

function sanae_player:special()
	if lstg.var.power>=200 then
		lstg.var.power=max(0,lstg.var.power-200)
		New(tasker,function()
			self.nextsp=180
			PlaySound('hyz_chargeup',0.8)
			New(sanae_drawring)
			task.Wait(60)
			local zao=ran:Float(0,100)
			New(sanae_draw,self.x,self.y+30,zao)
			self.zao[self.zao_num]=zao
			local achi_zao=self.zao[1]+self.zao[2]
			task.Wait(30)
			self.zao_num=(self.zao_num)%2+1
			New(achievement_obj,2,24)
			if scoredata.draw==5 then
				if zao<=30 then scoredata.draw=1
				elseif zao<=60 then scoredata.draw=2
				elseif zao<=85 then scoredata.draw=3
				else scoredata.draw=4
				end
			end
			if achi_zao<=60 then  New(achievement_obj,2,22)end
			if achi_zao>=172 then  New(achievement_obj,2,23)end
		end)
	end
end

function sanae_player:render()
	player_class.render(self)
--	for i=1,24 do self.imgs[i]='sanae_player'..i end
	local t=self.timer*4
	local a=360/max(self.support,1)
	if lstg.var.power>=200 then
		SetImageState('sanae_support','',Color(0xFF80FF80))
	else
		SetImageState('sanae_support','',Color(0xFFFFFFFF))
	end
	for i=1,4 do if self.sp[i] then
		Render('sanae_support',
		self.st*cos(i*a+t)+self.x0,
		self.st*sin(i*a+t)+self.y0)
	end end
end

function sanae_player:frame()
	player_class.frame(self)
	local t=self.timer*4
	if IsValid(self.target) and self.target.colli and self.slow==1 then
		self.x0=self.target.x+(self.x0-self.target.x)*0.95
		self.y0=self.target.y+(self.y0-self.target.y)*0.95
		self.st=max(self.st-3,9)
	else
		self.x0=self.x0+(self.x-self.x0)*0.08
		self.y0=self.y0+(self.y-self.y0)*0.08
		self.st=min(self.st+3,75)
	end
	self.x1=self.x+(self.x1-self.x)*0.95
	self.y1=self.y+(self.y1-self.y)*0.95
end
---------------------------C----------------------------------------
sanae_draw=Class(object)
function sanae_draw:init(x,y,zao)
	self.x=x self.y=y self.group=GROUP_GHOST self.layer=LAYER_PLAYER_BULLET-1
	self.zao=zao
	self.x0=x self.y0=y
	if zao<=30 then self.img='sanae_daji' PlaySound('sanae_lucky',0.8)
	elseif zao<=60 then self.img='sanae_ji' PlaySound('sanae_lucky',0.8)
	elseif zao<=85 then self.img='sanae_xiong' PlaySound('sanae_unlucky',0.8)
	else self.img='sanae_daxiong' PlaySound('sanae_unlucky',0.8) end
end
function sanae_draw:frame()
	if self.timer<30 then self.vy=4.8-4.65*self.timer/29 end
	if self.timer==60 then
		if self.zao<=30 then
			New(item_chip,self.x-24,self.y) New(item_chip,self.x+24,self.y) New(item_chip,self.x,self.y+42) PlaySound('bonus',0.6)
		elseif self.zao<=60 then
			New(item_bombchip,self.x-24,self.y) New(item_bombchip,self.x+24,self.y) PlaySound('bonus2',0.6)
		elseif self.zao<=85 then
			local a=ran:Float(0,360)
			PlaySound('tan00',0.6)
			for i=1,60 do
				New(straight,grain_a,10,true,self.x,self.y,1.5,a+6*i,0)
			end
		else
			local a=ran:Float(0,360)
			PlaySound('tan00',0.6)
			for i=1,60 do
				if i%2==0 then
					New(straight,grain_a,10,true,self.x-31,self.y+45,1.2,a+6*i,0)
					New(straight,grain_a,10,true,self.x+22,self.y-12,1.2,a+6*i,0)
				end
				New(straight,grain_a,10,true,self.x-31,self.y+45,1.5,a+6*i,0)
				New(straight,grain_a,10,true,self.x+22,self.y-12,1.5,a+6*i,0)
			end
		end
	end
	if self.timer>=120 then Del(self) end
end
function sanae_draw:render()
	if self.timer<=60 then
		SetImageState(self.img,'mul+add',Color(0xC0FFFFFF))
	else
		SetImageState(self.img,'mul+add',Color(192-192*(self.timer-60)/60,255,255,255))
	end
	if self.zao<=30 and self.timer<90 then
		SetImageState('sanae_eff','mul+add',Color(max(0,255-255*self.timer/90),255,255,255))
		Render('sanae_eff',self.x0,self.y0+60,0,min(1,self.timer/15))
	end
	if self.zao>30 and self.zao<=60 and self.timer<90 then
		SetImageState('sanae_eff','mul+add',Color(max(0,255-255*self.timer/90),255,255,255))
		Render('sanae_eff',self.x0,self.y0+60,0,min(0.6,0.6*self.timer/15))
	end
	object.render(self)
end
sanae_drawring=Class(object)
function sanae_drawring:init()
	self.x=player.x self.y=player.y self.group=GROUP_GHOST self.layer=LAYER_PLAYER-1
	self.omiga=8 self.r=90
end
function sanae_drawring:frame()
	self.x=player.x self.y=player.y
	if self.timer<60 then self.r=self.r-1.5 else Del(self) end
end
function sanae_drawring:render()
	misc.RenderRing('sanae_drawring',self.x,self.y,self.r-6,self.r+6, self.ani*3,32,16)
end
--------------------------------------------------------------------
sanae_bf=Class(object)

function sanae_bf:init(x,y,dmg,master)
	self.x=x
	self.y=y
	self.img='sanae_bf'
	self.dmg=dmg
	self.group=GROUP_PLAYER_BULLET
	self.layer=LAYER_PLAYER_BULLET
	self.killflag=true
	self.rect=false
	self.bound=false
	local s=1.5
	self.hscale=s
	self.vscale=s
	self.a=120*s
	self.b=120*s
	self.a1=0
	self.master=master
end

function sanae_bf:frame()
	self.x=self.master.x+(self.x-self.master.x)*0.95
	self.y=self.master.y+(self.y-self.master.y)*0.95
	if self.timer<=80 then
		self.a1=self.a1+8/80
		self.rot=self.rot+self.a1
	end
	if self.timer<=16 then
		SetImgState(self,'mul+add',self.timer*255/16,255,255,255)
	end
	if self.timer==16 then
		SetImgState(self,'mul+add',255,255,255,255)
	end
	if self.timer>80 then
		self.rot=self.rot+8
	end
	if self.timer>=240 and self.timer<256 then
		SetImgState(self,'mul+add',255-self.timer*255/16,255,255,255)
	end
	if self.timer==256 then Del(self) end
end
--------------------------------------------------------------------
sanae_dmg=Class(object)

function sanae_dmg:init(dmg)
	self.x=0
	self.y=0
	self.dmg=dmg
	self.a=900
	self.b=900
	self.group=GROUP_PLAYER_BULLET
	self.killflag=true
end

function sanae_dmg:frame()
	if self.timer==256 then Del(self) end
	if self.timer%4==0 then self.mute=true else self.mute=false end
end

sanae_bs=Class(object)

function sanae_bs:init(x)
	self.x=x
	self.y=0
	self.vx=24
	self.bound=false
	self.img='sanae_bs'
end

function sanae_bs:frame()
	if self.timer<=16 then
		SetImgState(self,'mul+add',self.timer*255/16,255,255,255)
	end
	if self.timer==16 then
		SetImgState(self,'mul+add',255,255,255,255)
	end
	if self.timer>=240 and self.timer<256 then
		SetImgState(self,'mul+add',255-self.timer*255/16,255,255,255)
	end
	if self.timer==256 then Del(self) end
end
--------------------------------------------------------------------
sanae_wind=Class(object)

function sanae_wind:init(x,y,dmg)
	self.x=x
	self.y=y
	self.img='sanae_wind'
	self.dmg=dmg
	self.group=GROUP_PLAYER_BULLET
	self.layer=LAYER_PLAYER_BULLET
	self.a=40
	self.b=40
	self.hscale=0
	self.vscale=0
	self.rot=ran:Float(0,360)
	self.killflag=true
end

function sanae_wind:frame()
	if self.timer%4==0 then self.mute=true else self.mute=false end
	self.hscale=self.hscale+1.6/15
	self.vscale=self.vscale+1.6/15
--	self.a=self.a+32/15
--	self.b=self.b+32/15
	if self.timer==16 then
		Del(self)
	end
end

function sanae_wind:render()
	SetImageState(self.img,'',Color(120-self.timer*120/16,255,255,255))
	object.render(self)
end
--------------------------------------------------------------------
sanae_wind2=Class(object)

function sanae_wind2:init(x,y,a,v,dmg)
	self.x=x
	self.y=y
	self.rot=a
	self.vx=v*cos(a)
	self.vy=v*sin(a)
	self.dmg=5*dmg
	self.img='sanae_wind2'
	self.group=GROUP_PLAYER_BULLET
	self.layer=LAYER_PLAYER_BULLET
	self.killflag=true
	self.df=dmg
	self.rect=true
	self.bound=false
end

function sanae_wind2:frame()
	if self.timer%4==0 then self.mute=true else self.mute=false end
	self.hscale=1+self.timer/90
	self.vscale=1+self.timer/90
	self.a=16*self.hscale
	self.b=72*self.vscale
	if self.timer<=30 then
		self.dmg=max(self.df,self.dmg-self.df*4/30)
	end
	if self.timer>64 then self.bound=true end
end

function sanae_wind2:render()
	if self.timer<16 then
		SetImageState(self.img,'',Color(self.timer*120/16,255,255,255))
	else
		SetImageState(self.img,'',Color(120,255,255,255))
	end
	object.render(self)
end
--------------------------------------------------------------------
sanae_wind3=Class(object)

function sanae_wind3:init(x,y,a,v,dmg)
	self.x=x
	self.y=y
	self.rot=a
	self.vx=v*cos(a)
	self.vy=v*sin(a)
	self.dmg=dmg
	self.img='sanae_wind2'
	self.group=GROUP_PLAYER_BULLET
	self.layer=LAYER_PLAYER_BULLET
	self.killflag=true
	self.df=dmg
	self.rect=true
end

function sanae_wind3:frame()
	if self.timer%4==0 then self.mute=true else self.mute=false end
	self.hscale=0.75+self.timer/60
	self.vscale=0.75+self.timer/60
	self.a=16*self.hscale
	self.b=72*self.vscale
end

function sanae_wind3:render()
	if self.timer<16 then
		SetImageState(self.img,'',Color(self.timer*120/16,255,255,255))
	else
		SetImageState(self.img,'',Color(120,255,255,255))
	end
	object.render(self)
end
