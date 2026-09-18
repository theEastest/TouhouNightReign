LoadTexture('enemy1','THlib\\enemy\\enemy1.png')
LoadImageGroup('enemy1_','enemy1',0,384,32,32,12,1,8,8)
LoadImageGroup('enemy2_','enemy1',0,416,32,32,12,1,8,8)
LoadImageGroup('enemy3_','enemy1',0,448,32,32,12,1,8,8)
LoadImageGroup('enemy4_','enemy1',0,480,32,32,12,1,8,8)
LoadImageGroup('enemy5_','enemy1',0,0,48,32,4,3,8,8)
LoadImageGroup('enemy6_','enemy1',0,96,48,32,4,3,8,8)
LoadImageGroup('enemy7_','enemy1',320,0,48,48,4,3,16,16)
LoadImageGroup('enemy8_','enemy1',320,144,48,48,4,3,16,16)
LoadImageGroup('enemy9_','enemy1',0,192,64,64,4,3,16,16)
LoadImageGroup('kedama','enemy1',256,320,32,32,2,2,8,8)
LoadImageGroup('enemy_x','enemy1',192,32,32,32,4,1,8,8)
LoadImageGroup('enemy_orb','enemy1',192,64,32,32,4,1,8,8)
LoadImageGroup('enemy_orb_ring','enemy1',192,96,32,32,4,1)
for i=1,4 do SetImageState('enemy_orb_ring'..i,'add+add',Color(0xFF404040)) end
LoadImageGroup('enemy_aura','enemy1',192,32,32,32,4,1)
for i=1,4 do SetImageState('enemy_aura'..i,'',Color(0x80FFFFFF)) end

LoadTexture('enemy2','THlib\\enemy\\enemy2.png')
LoadImageGroup('enemy10_','enemy2',0,0,32,32,12,1,8,8)
LoadImageGroup('enemy11_','enemy2',0,32,32,32,12,1,8,8)
LoadImageGroup('enemy12_','enemy2',0,64,32,32,12,1,8,8)
LoadImageGroup('enemy13_','enemy2',0,96,32,32,12,1,8,8)
LoadImageGroup('enemy14_','enemy2',0,128,64,64,6,2,16,16)
LoadImageGroup('enemy15_','enemy2',0,288,32,32,12,1,8,8)
LoadImageGroup('enemy16_','enemy2',0,352,32,32,12,1,8,8)
LoadImageGroup('enemy17_','enemy2',0,416,32,32,12,1,8,8)
LoadImageGroup('enemy18_','enemy2',0,480,32,32,12,1,8,8)
LoadPS('ghost_fire_r','THlib\\enemy\\ghost_fire_r.psi','parimg1',8,8)
LoadPS('ghost_fire_b','THlib\\enemy\\ghost_fire_b.psi','parimg1',8,8)
LoadPS('ghost_fire_g','THlib\\enemy\\ghost_fire_g.psi','parimg1',8,8)
LoadPS('ghost_fire_y','THlib\\enemy\\ghost_fire_y.psi','parimg1',8,8)

LoadTexture('enemy3','THlib\\enemy\\enemy3.png')
LoadImageGroup('Ghost1','enemy3',0, 0,32,32,8,1,8,8)
LoadImageGroup('Ghost3','enemy3',0,32,32,32,8,1,8,8)
LoadImageGroup('Ghost2','enemy3',0,64,32,32,8,1,8,8)
LoadImageGroup('Ghost4','enemy3',0,96,32,32,8,1,8,8)

LoadImageFromFile('ring_eff','THlib\\enemy\\ring00.png')
LoadImage('white_leaf','misc',0,0,32,32)

enemybase=Class(object)

function enemybase:init(hp, nontaijutsu)
	self.layer=LAYER_ENEMY
	self.group=GROUP_ENEMY
	if nontaijutsu then self.group = GROUP_NONTJT end
	self.bound=false
	self.colli=false
	self.maxhp=hp or 1
	self.hp=hp or 1
	setmetatable(self,{__index=GetAttr,__newindex=enemy_meta_newindex})
	self.colli=true
	self._servants={}
	self.dmgdirection=ran:Float(0,360)
end

function enemy_meta_newindex(t,k,v)
	if k=='colli' then rawset(t,'_colli',v)
	else SetAttr(t,k,v) end
end

function enemybase:frame()
	SetAttr(self,'colli',BoxCheck(self,lstg.world.boundl,lstg.world.boundr,lstg.world.boundb,lstg.world.boundt) and self._colli)
	if self.hp<=0 then Kill(self) end
	task.Do(self)
end

function enemybase:colli(other)
	if other.dmg then
		self.dmgdirection=Angle(self,other)
		lstg.var.score=lstg.var.score+10
		Damage(self,other.dmg)
		if self._master and self._dmg_transfer and IsValid(self._master) then
			Damage(self._master,other.dmg*self._dmg_transfer)
		end
	end
	if other.buffcolli then
		other.buffcolli=5 other.colli=false other.eff_tar=self
		New(wuer_pan_dmg_obj,other.x,other.y,other.DMG)
	end
	other.killerenemy=self
	if not(other.killflag) then
		Kill(other)
	end
	if not other.mute then
		if self.dmg_factor then
			if self.hp>100 then PlaySound('damage00',0.4,self.x/200)
			else PlaySound('damage01',0.6,self.x/200) end
		else
			if self.maxhp>60 then
				if self.hp>self.maxhp*0.2 then PlaySound('damage00',0.4,self.x/200)
				else PlaySound('damage01',0.6,self.x/200) end
			else PlaySound('damage00',0.35,self.x/200,true)
			end
		end
	end
end

function enemybase:del()
	_del_servants(self)
end

function Damage(obj,dmg)
	if obj.class.base.take_damage then obj.class.base.take_damage(obj,dmg) end
end

enemy=Class(enemybase)

_enemy_aura_tb={1,2,3,4,3,1,nil,nil,nil,3,1,4,1,nil,3,1,2,4,3,1,2,4,1,2,3,4,nil,nil,nil,nil,1,3,2,1}
_death_ef_tb  ={	1,2,3,4,
					3,1,5,5,
					6,
					3,1,4,1,
					6,
					3,1,2,4,
					3,1,2,4,
					1,2,3,4,
					1,3,2,4,
					1,3,2,4}
_death_color_tb = {	[1]={96,255,128,0},
					[2]={96,0,255,0},
					[3]={96,0,128,255},
					[4]={96,255,255,0}
					}
_death_color2_tb ={	[1]={96,255,64,64},
					[2]={96,64,255,64},
					[3]={96,64,128,255},
					[4]={96,255,255,64}
					}
_death_color3_tb ={	[1]={128,255,32,32},
					[2]={128,32,255,32},
					[3]={128,32,96,255},
					[4]={128,255,255,32}
					}

function enemy:init(style,hp,clear_bullet,auto_delete,nontaijutsu)
	enemybase.init(self,hp,nontaijutsu)
	self.clear_bullet=clear_bullet
	self.auto_delete=auto_delete
	self.style=style
	self.aura=_enemy_aura_tb[style]
	self.death_ef=_death_ef_tb[style]
	if style<=18 then
		self.imgs={}
		for i=1,12 do self.imgs[i]='enemy'..style..'_'..i end
		self.ani_intv=8
		self.lr=1
	elseif style<=22 then
		self.img='kedama'..(style-18)
		self.omiga=12
	elseif style<=26 then
		self.img='enemy_orb'..(style-22)
		self.omiga=6
	elseif style==27 or style==31 then
		self.img='ghost_fire_r'
		self.rot=-90
	elseif style==28 or style==32 then
		self.img='ghost_fire_b'
		self.rot=-90
	elseif style==29 or style==33 then
		self.img='ghost_fire_g'
		self.rot=-90
	elseif style==30 or style==34 then
		self.img='ghost_fire_y'
		self.rot=-90
	end
end

function enemy:frame()
	enemybase.frame(self)
	if self.style<=18 then
		if self.dx>0.5 then dx=1 elseif self.dx<-0.5 then dx=-1 else dx=0 end
		self.lr=self.lr+dx
		if self.lr> 18 then self.lr= 18 end
		if self.lr<-18 then self.lr=-18 end
		if self.lr==0 then self.lr=self.lr+dx end
		if dx==0 then
			if self.lr> 1 then self.lr=self.lr-1 end
			if self.lr<-1 then self.lr=self.lr+1 end
		end
		if abs(self.lr)==1 then
			self.img=self.imgs[int(self.ani/self.ani_intv)%4+1]
		elseif abs(self.lr)==18 then
			self.img=self.imgs[int(self.ani/self.ani_intv)%4+9]
		else
			self.img=self.imgs[int((abs(self.lr)-2)/4)+5]
		end
		self.hscale=sign(self.lr)
	end
	if self.auto_delete and BoxCheck(self,lstg.world.boundl,lstg.world.boundr,lstg.world.boundb,lstg.world.boundt) then self.bound=true end
end

function enemy:render()
	if self._blend then
		SetImgState(self,self._blend,self._a,self._r,self._g,self._b)
	end
	if self.aura and not(self.hide_aura) then
		if self._blend then
			SetImageState('enemy_aura'..self.aura,self._blend,Color(self._a,self._r,self._g,self._b))
		end
		Render('enemy_aura'..self.aura,self.x,self.y,self.timer*3,1.25+0.15*sin(self.timer*6))
		if self._blend then
			SetImageState('enemy_aura'..self.aura,'',Color(0x80FFFFFF))
		end
	end
	object.render(self)
	if self.style>22 and self.style<=26 then
		if self._blend then
			SetImageState('enemy_orb_ring'..self.aura,'add+add',Color(self._a/2,self._r/4,self._g/4,self._b/4))
		end
		Render('enemy_orb_ring'..self.aura,self.x,self.y,-self.timer*6,self.hscale,self.vscale)
		Render('enemy_orb_ring'..self.aura,self.x,self.y,self.timer*4,1.4*self.hscale)
		if self._blend then
			SetImageState('enemy_orb_ring'..self.aura,'add+add',Color(0xFF404040))
		end
	end
	if self.style>27 and self.style<=30 then
		if self._blend then
			SetImageState('Ghost'..(self.style-26)..int((self.timer/4)%8)+1,self._blend,Color(self._a,self._r,self._g,self._b))
		end
		Render('Ghost'..(self.style-26)..int((self.timer/4)%8)+1,self.x,self.y,90)
		if self._blend then
			SetImageState('Ghost'..(self.style-26)..int((self.timer/4)%8)+1,'',Color(0xFFFFFFFF))
		end
	end
	if self.style>30 then
		if self._blend then
			SetImageState('Ghost'..(self.style-30)..int((self.timer/4)%8)+1,self._blend,Color(self._a,self._r,self._g,self._b))
		end
		Render('Ghost'..(self.style-30)..int((self.timer/4)%8)+1,self.x,self.y,90)
		if self._blend then
			SetImageState('Ghost'..(self.style-30)..int((self.timer/4)%8)+1,'',Color(0xFFFFFFFF))
		end
	end
	if self._blend then
		SetImgState(self,'',255,255,255,255)
	end
--	SetFontState('bonus','',Color(255,255,255,255))
--	RenderText('bonus',int(max(0,self.hp))..'/'..self.maxhp,self.x,self.y-28,0.5,'centerpoint')
end

function enemy:take_damage(dmg)
	if not self.protect then
		self.hp=self.hp-dmg
	end
end

function enemy:kill()
	New(enemy_death_ef,self.death_ef,self.x,self.y,self.dmgdirection)
	if self.drop then item.DropItem(self.x,self.y,self.drop) end
	if self.clear_bullet then New(bullet_killer,lstg.player.x,lstg.player.y,false) end
	_kill_servants(self)
end
--
local LilY_Color={}
LilY_Color[1]={r=241,g= 34,b=34}
LilY_Color[2]={r= 62,g=223,b= 48}
LilY_Color[3]={r= 50,g=104,b=221}
LilY_Color[4]={r=255,g=219,b= 28}
--

enemy_death_ef=Class(object)

function enemy_death_ef:init(index,x,y,direc)
	self.rd_tb_angle={}
	self.rd_tb_r={}
	self.rd_tb_v={}
	self.rd_tb_x={}
	self.rd_tb_y={}
	self.rd2_tb_angle={}
	self.rd2_tb_r={}
	self.rd2_tb_v={}
	self.rd2_tb_x={}
	self.rd2_tb_y={}
	self.rd2_tb_rot={}
	self.rd2_tb_xrot={}
	self.rd2_tb_yrot={}
	self.rd2_tb_xrotv={}
	self.rd2_tb_yrotv={}
	self.rd3_tb_x={}
	self.rd3_tb_y={}
	self.rd3_tb_rot={}
	self.direc=direc or ran:Float(0,360)
	self.x=x self.y=y self.rot=self.direc+ran:Float(-22.5,22.5)
	if index ~= 6 and index ~=5 then self.img='bubble'..index else self.img='bubble'..1 end
	if index==6 then
		for i=1,12 do
			self.rd_tb_angle[i]=180+ran:Float(-2.5,2.5)
			if i==4 or i==8 or i==12 then self.rd_tb_r[i]=ran:Float(80,96) else self.rd_tb_r[i]=ran:Float(64,72) end
			self.rd_tb_v[i]=ran:Float(0,0.6)
			self.rd_tb_x[i]=ran:Int(-10,10)
			self.rd_tb_y[i]=ran:Int(-10,10)
		end
		for i=1,27 do
			self.rd2_tb_angle[i]=180+ran:Float(-30,30)
			self.rd2_tb_r[i]=ran:Float(3,4)
			self.rd2_tb_v[i]=ran:Float(0.5+((i-1)%9)*1.25,1+((i-1)%9)*1.25)
			self.rd2_tb_x[i]=ran:Int(-8,8)
			self.rd2_tb_y[i]=ran:Int(-8,8)
			self.rd2_tb_rot[i]=ran:Float(0,360)
			self.rd2_tb_xrot[i]=ran:Float(0,360)
			self.rd2_tb_yrot[i]=ran:Float(0,360)
			self.rd2_tb_xrotv[i]=ran:Float(2,4)
			self.rd2_tb_yrotv[i]=ran:Float(2,4)
		end
		for i=1,24 do
			if i==1 or i==9 or i==17 then
				self.rd3_tb_x[i]=self.x+ran:Int(-20,20)
				self.rd3_tb_y[i]=self.y+ran:Int(-20,20)
				self.rd3_tb_rot[i]=ran:Float(0,360)
			else
				self.rd3_tb_x[i]=self.rd3_tb_x[i-1]+ran:Float(15,16)*cos(180+self.rot+ran:Float(-30,30))
				self.rd3_tb_y[i]=self.rd3_tb_y[i-1]+ran:Float(15,16)*sin(180+self.rot+ran:Float(-30,30))
				self.rd3_tb_rot[i]=self.rd3_tb_rot[i-1]+153
			end
		end
	elseif index==5 then
		for i=1,8 do
			self.rd_tb_angle[i]=180+ran:Float(-2.5,2.5)
			if i==4 or i==8 then self.rd_tb_r[i]=ran:Float(80,96) else self.rd_tb_r[i]=ran:Float(64,72) end
			self.rd_tb_v[i]=ran:Float(0,0.6)
			self.rd_tb_x[i]=ran:Int(-10,10)
			self.rd_tb_y[i]=ran:Int(-10,10)
		end
		for i=1,18 do
			self.rd2_tb_angle[i]=180+ran:Float(-30,30)
			self.rd2_tb_r[i]=ran:Float(3,4)
			self.rd2_tb_v[i]=ran:Float(0.5+((i-1)%9)*1.25,1+((i-1)%9)*1.25)
			self.rd2_tb_x[i]=ran:Int(-8,8)
			self.rd2_tb_y[i]=ran:Int(-8,8)
			self.rd2_tb_rot[i]=ran:Float(0,360)
			self.rd2_tb_xrot[i]=ran:Float(0,360)
			self.rd2_tb_yrot[i]=ran:Float(0,360)
			self.rd2_tb_xrotv[i]=ran:Float(2,4)
			self.rd2_tb_yrotv[i]=ran:Float(2,4)
		end
		for i=1,16 do
			if i==1 or i==9 then
				self.rd3_tb_x[i]=self.x+ran:Int(-20,20)
				self.rd3_tb_y[i]=self.y+ran:Int(-20,20)
				self.rd3_tb_rot[i]=ran:Float(0,360)
			else
				self.rd3_tb_x[i]=self.rd3_tb_x[i-1]+ran:Float(15,16)*cos(180+self.rot+ran:Float(-30,30))
				self.rd3_tb_y[i]=self.rd3_tb_y[i-1]+ran:Float(15,16)*sin(180+self.rot+ran:Float(-30,30))
				self.rd3_tb_rot[i]=self.rd3_tb_rot[i-1]+153
			end
		end
	else
		for i=1,4 do
			self.rd_tb_angle[i]=180+ran:Float(-2.5,2.5)
			if i==4 then self.rd_tb_r[i]=ran:Float(80,96) else self.rd_tb_r[i]=ran:Float(64,72) end
			self.rd_tb_v[i]=ran:Float(0,0.6)
			self.rd_tb_x[i]=ran:Int(-10,10)
			self.rd_tb_y[i]=ran:Int(-10,10)
		end
		for i=1,9 do
			self.rd2_tb_angle[i]=180+ran:Float(-30,30)
			self.rd2_tb_r[i]=ran:Float(3,4)
			self.rd2_tb_v[i]=ran:Float(0.5+(i-1)*1.25,1+(i-1)*1.25)
			self.rd2_tb_x[i]=ran:Int(-8,8)
			self.rd2_tb_y[i]=ran:Int(-8,8)
			self.rd2_tb_rot[i]=ran:Float(0,360)
			self.rd2_tb_xrot[i]=ran:Float(0,360)
			self.rd2_tb_yrot[i]=ran:Float(0,360)
			self.rd2_tb_xrotv[i]=ran:Float(2,4)
			self.rd2_tb_yrotv[i]=ran:Float(2,4)
		end
		for i=1,8 do
			if i==1 then
				self.rd3_tb_x[i]=self.x+ran:Int(-20,20)
				self.rd3_tb_y[i]=self.y+ran:Int(-20,20)
				self.rd3_tb_rot[i]=ran:Float(0,360)
			else
				self.rd3_tb_x[i]=self.rd3_tb_x[i-1]+ran:Float(15,16)*cos(180+self.rot+ran:Float(-30,30))
				self.rd3_tb_y[i]=self.rd3_tb_y[i-1]+ran:Float(15,16)*sin(180+self.rot+ran:Float(-30,30))
				self.rd3_tb_rot[i]=self.rd3_tb_rot[i-1]+153
			end
		end
	end
	self.index=index
	self.layer=LAYER_ENEMY+50
	self.group=GROUP_GHOST
	self.rd=ran:Int(1,3)
	self.rd2=ran:Float(-7.5,7.5)
	PlaySound('enep00',0.3,self.x/200,true)
end
function enemy_death_ef:frame()
	local k=self.timer/30
	local p=k^0.75
	local q=k^3
	local index=self.index
	if index ==6 then
		for i=1,27 do
			local a,v=self.rd2_tb_angle[i],self.rd2_tb_v[i]
			self.rd2_tb_x[i]=self.rd2_tb_x[i]+v*(1-p)*cos(self.rot+a)
			self.rd2_tb_y[i]=self.rd2_tb_y[i]+v*(1-p)*sin(self.rot+a)
			self.rd2_tb_r[i]=self.rd2_tb_r[i]-4/30
		end
	elseif index==5 then
		for i=1,18 do
			local a,v=self.rd2_tb_angle[i],self.rd2_tb_v[i]
			self.rd2_tb_x[i]=self.rd2_tb_x[i]+v*(1-p)*cos(self.rot+a)
			self.rd2_tb_y[i]=self.rd2_tb_y[i]+v*(1-p)*sin(self.rot+a)
			self.rd2_tb_r[i]=self.rd2_tb_r[i]-4/30
		end
	else
		for i=1,9 do
			local a,v=self.rd2_tb_angle[i],self.rd2_tb_v[i]
			self.rd2_tb_x[i]=self.rd2_tb_x[i]+v*(1-p)*cos(self.rot+a)
			self.rd2_tb_y[i]=self.rd2_tb_y[i]+v*(1-p)*sin(self.rot+a)
			self.rd2_tb_r[i]=self.rd2_tb_r[i]-4/30
		end
	end
	if self.timer==30 then Kill(self) end
end
function enemy_death_ef:render()
	local alpha=1-self.timer/30
	local k=self.timer/30
	local p=k^0.35
	local q=k^3
	local index=self.index
	alpha=255*alpha^2
	if index == 6 then
		local rd=self.rd
		local rd2=self.rd2
		local rot=self.rot
		for i=1,3 do
			SetImageState('bubble'..(rd+i)%3+1,'mul+add',Color(alpha,255,255,255))
			if i~=2 then Render('bubble'..(rd+i)%3+1,self.x,self.y,rot-10*(i-2),0.4-0.3*p,4*p+0.7) else Render('bubble'..(rd+i)%3+1,self.x,self.y,rot+rd2,0.4-0.3*p,4*p+0.7) end
		end
	elseif index==5 then
		local rot=self.rot
		for i=1,2 do
			SetImageState('bubble'..i,'mul+add',Color(alpha,255,255,255))
			Render('bubble'..i,self.x,self.y,rot-(15+self.rd2)*(2*i-3),0.4-0.3*p,4*p+0.7)
		end
	else
		SetImageState(self.img,'mul+add',Color(alpha,255,255,255))
		Render(self.img,self.x,self.y, self.rot,0.4-0.3*p,4*p+0.7)
	end
	if index ==6 then
		local t=self.timer
		for i=1,8 do --ani
			if t>=2*(i-1) then
				local num=math.ceil(((t+1)-(i-1)*2)/2)
				if num <= 10 then
					SetImageState('white_ani'..num,'mul+alpha',Color(_death_color3_tb[1][1],_death_color3_tb[1][2],_death_color3_tb[1][3],_death_color3_tb[1][4]))
					Render('white_ani'..num,self.rd3_tb_x[i],self.rd3_tb_y[i],self.rd3_tb_rot[i],1,1)
					SetImageState('white_ani'..num,'mul+alpha',Color(_death_color3_tb[2][1],_death_color3_tb[2][2],_death_color3_tb[2][3],_death_color3_tb[2][4]))
					Render('white_ani'..num,self.rd3_tb_x[i+8],self.rd3_tb_y[i+8],self.rd3_tb_rot[i+8],1,1)
					SetImageState('white_ani'..num,'mul+alpha',Color(_death_color3_tb[3][1],_death_color3_tb[3][2],_death_color3_tb[3][3],_death_color3_tb[3][4]))
					Render('white_ani'..num,self.rd3_tb_x[i+16],self.rd3_tb_y[i+16],self.rd3_tb_rot[i+16],1,1)
				end
			end
		end
		for i=1,4 do --ring
			local a,r,v,x,y=self.rd_tb_angle[i],self.rd_tb_r[i],self.rd_tb_v[i],self.rd_tb_x[i],self.rd_tb_y[i]
			local a2,r2,v2,x2,y2=self.rd_tb_angle[i+4],self.rd_tb_r[i+4],self.rd_tb_v[i+4],self.rd_tb_x[i+4],self.rd_tb_y[i+4]
			local a3,r3,v3,x3,y3=self.rd_tb_angle[i+8],self.rd_tb_r[i+8],self.rd_tb_v[i+8],self.rd_tb_x[i+8],self.rd_tb_y[i+8]
			SetImageState('whiteblock','mul+add',Color(_death_color_tb[1][1]*(1-q),_death_color_tb[1][2],_death_color_tb[1][3],_death_color_tb[1][4]))
			misc.UnitRenderRing('whiteblock',self.x+x+t*v*cos(self.rot+a),self.y+y+t*v*sin(self.rot+a),r*p,r*p+1,self.timer*72.5,32)
			SetImageState('whiteblock','mul+add',Color(_death_color_tb[2][1]*(1-q),_death_color_tb[2][2],_death_color_tb[2][3],_death_color_tb[2][4]))
			misc.UnitRenderRing('whiteblock',self.x+x2+t*v2*cos(self.rot+a2),self.y+y2+t*v2*sin(self.rot+a2),r2*p,r2*p+1,self.timer*72.5,32)
			SetImageState('whiteblock','mul+add',Color(_death_color_tb[3][1]*(1-q),_death_color_tb[3][2],_death_color_tb[3][3],_death_color_tb[3][4]))
			misc.UnitRenderRing('whiteblock',self.x+x3+t*v3*cos(self.rot+a3),self.y+y3+t*v3*sin(self.rot+a3),r3*p,r3*p+1,self.timer*72.5,32)
		end
		for i=1,9 do --splash
			local r=self.rd2_tb_r[i]
			local xrot,yrot=self.rd2_tb_xrot[i],self.rd2_tb_yrot[i]
			local xrotv,yrotv=self.rd2_tb_xrotv[i],self.rd2_tb_yrotv[i]
			local r2=self.rd2_tb_r[i+9]
			local xrot2,yrot2=self.rd2_tb_xrot[i+9],self.rd2_tb_yrot[i+9]
			local xrotv2,yrotv2=self.rd2_tb_xrotv[i+9],self.rd2_tb_yrotv[i+9]
			local r3=self.rd2_tb_r[i+18]
			local xrot3,yrot3=self.rd2_tb_xrot[i+18],self.rd2_tb_yrot[i+18]
			local xrotv3,yrotv3=self.rd2_tb_xrotv[i+18],self.rd2_tb_yrotv[i+18]
			SetImageState('whitedot','mul+add',Color(_death_color2_tb[1][1],_death_color2_tb[1][2],_death_color2_tb[1][3],_death_color2_tb[1][4]))
			Render('whitedot',self.x+self.rd2_tb_x[i],self.y+self.rd2_tb_y[i],self.rd2_tb_rot[i]+self.timer*1,max(0,r)*sin(xrot+t*xrotv),max(0,r)*sin(yrot+t*yrotv))
			SetImageState('whitedot','mul+add',Color(_death_color2_tb[2][1],_death_color2_tb[2][2],_death_color2_tb[2][3],_death_color2_tb[2][4]))
			Render('whitedot',self.x+self.rd2_tb_x[i+9],self.y+self.rd2_tb_y[i+9],self.rd2_tb_rot[i+9]+self.timer*1,max(0,r2)*sin(xrot2+t*xrotv2),max(0,r2)*sin(yrot2+t*yrotv2))
			SetImageState('whitedot','mul+add',Color(_death_color2_tb[3][1],_death_color2_tb[3][2],_death_color2_tb[3][3],_death_color2_tb[3][4]))
			Render('whitedot',self.x+self.rd2_tb_x[i+18],self.y+self.rd2_tb_y[i+18],self.rd2_tb_rot[i+18]+self.timer*1,max(0,r3)*sin(xrot3+t*xrotv3),max(0,r3)*sin(yrot3+t*yrotv3))
		end
	elseif index==5 then
		local t=self.timer
		for i=1,8 do --ani
			if t>=2*(i-1) then
				local num=math.ceil(((t+1)-(i-1)*2)/2)
				if num <= 10 then
					SetImageState('white_ani'..num,'mul+alpha',Color(_death_color3_tb[1][1],_death_color3_tb[1][2],_death_color3_tb[1][3],_death_color3_tb[1][4]))
					Render('white_ani'..num,self.rd3_tb_x[i],self.rd3_tb_y[i],self.rd3_tb_rot[i],1,1)
					SetImageState('white_ani'..num,'mul+alpha',Color(_death_color3_tb[2][1],_death_color3_tb[2][2],_death_color3_tb[2][3],_death_color3_tb[2][4]))
					Render('white_ani'..num,self.rd3_tb_x[i+8],self.rd3_tb_y[i+8],self.rd3_tb_rot[i+8],1,1)
				end
			end
		end
		for i=1,4 do --ring
			local a,r,v,x,y=self.rd_tb_angle[i],self.rd_tb_r[i],self.rd_tb_v[i],self.rd_tb_x[i],self.rd_tb_y[i]
			local a2,r2,v2,x2,y2=self.rd_tb_angle[i+4],self.rd_tb_r[i+4],self.rd_tb_v[i+4],self.rd_tb_x[i+4],self.rd_tb_y[i+4]
			SetImageState('whiteblock','mul+add',Color(_death_color_tb[1][1]*(1-q),_death_color_tb[1][2],_death_color_tb[1][3],_death_color_tb[1][4]))
			misc.UnitRenderRing('whiteblock',self.x+x+t*v*cos(self.rot+a),self.y+y+t*v*sin(self.rot+a),r*p,r*p+1,self.timer*72.5,32)
			SetImageState('whiteblock','mul+add',Color(_death_color_tb[2][1]*(1-q),_death_color_tb[2][2],_death_color_tb[2][3],_death_color_tb[2][4]))
			misc.UnitRenderRing('whiteblock',self.x+x2+t*v2*cos(self.rot+a2),self.y+y2+t*v2*sin(self.rot+a2),r2*p,r2*p+1,self.timer*72.5,32)
		end
		for i=1,9 do --splash
			local r=self.rd2_tb_r[i]
			local xrot,yrot=self.rd2_tb_xrot[i],self.rd2_tb_yrot[i]
			local xrotv,yrotv=self.rd2_tb_xrotv[i],self.rd2_tb_yrotv[i]
			local r2=self.rd2_tb_r[i+9]
			local xrot2,yrot2=self.rd2_tb_xrot[i+9],self.rd2_tb_yrot[i+9]
			local xrotv2,yrotv2=self.rd2_tb_xrotv[i+9],self.rd2_tb_yrotv[i+9]
			SetImageState('whitedot','mul+add',Color(_death_color2_tb[1][1],_death_color2_tb[1][2],_death_color2_tb[1][3],_death_color2_tb[1][4]))
			Render('whitedot',self.x+self.rd2_tb_x[i],self.y+self.rd2_tb_y[i],self.rd2_tb_rot[i]+self.timer*1,max(0,r)*sin(xrot+t*xrotv),max(0,r)*sin(yrot+t*yrotv))
			SetImageState('whitedot','mul+add',Color(_death_color2_tb[2][1],_death_color2_tb[2][2],_death_color2_tb[2][3],_death_color2_tb[2][4]))
			Render('whitedot',self.x+self.rd2_tb_x[i+9],self.y+self.rd2_tb_y[i+9],self.rd2_tb_rot[i+9]+self.timer*1,max(0,r2)*sin(xrot2+t*xrotv2),max(0,r2)*sin(yrot2+t*yrotv2))
		end
	else
		local t=self.timer
		for i=1,8 do --ani
			if t>=2*(i-1) then
				local num=math.ceil(((t+1)-(i-1)*2)/2)
				if num <= 10 then
					SetImageState('white_ani'..num,'mul+alpha',Color(_death_color3_tb[index][1],_death_color3_tb[index][2],_death_color3_tb[index][3],_death_color3_tb[index][4]))
					Render('white_ani'..num,self.rd3_tb_x[i],self.rd3_tb_y[i],self.rd3_tb_rot[i],1,1)
				end
			end
		end
		for i=1,4 do --ring
			local a,r,v,x,y=self.rd_tb_angle[i],self.rd_tb_r[i],self.rd_tb_v[i],self.rd_tb_x[i],self.rd_tb_y[i]
			SetImageState('whiteblock','mul+add',Color(_death_color_tb[index][1]*(1-q),_death_color_tb[index][2],_death_color_tb[index][3],_death_color_tb[index][4]))
			misc.UnitRenderRing('whiteblock',self.x+x+t*v*cos(self.rot+a),self.y+y+t*v*sin(self.rot+a),r*p,r*p+1,self.timer*72.5,32)
		end
		for i=1,9 do --splash
			local a,r,v=self.rd2_tb_angle[i],self.rd2_tb_r[i],self.rd2_tb_v[i]
			local xrot,yrot=self.rd2_tb_xrot[i],self.rd2_tb_yrot[i]
			local xrotv,yrotv=self.rd2_tb_xrotv[i],self.rd2_tb_yrotv[i]
			SetImageState('whitedot','mul+add',Color(_death_color2_tb[index][1],_death_color2_tb[index][2],_death_color2_tb[index][3],_death_color2_tb[index][4]))
			Render('whitedot',self.x+self.rd2_tb_x[i],self.y+self.rd2_tb_y[i],self.rd2_tb_rot[i]+self.timer*1,max(0,r)*sin(xrot+t*xrotv),max(0,r)*sin(yrot+t*yrotv))
		end
	end
	--Render(self.img,self.x,self.y, 75,0.4-0.3*p,6*p+0.7)
	--Render(self.img,self.x,self.y,135,0.4-0.3*p,6*p+0.7)
end
--[[
enemy_death_ef=Class(object)

function enemy_death_ef:init(index,x,y)
	self.img='bubble'..index
	self.layer=LAYER_ENEMY+50
	self.group=GROUP_GHOST
	self.x=x self.y=y self.rot=45
	PlaySound('enep00',0.3,self.x/200,true)
end

function enemy_death_ef:render()
	local alpha=1-self.timer/30
	alpha=255*alpha^2
	SetImageState(self.img,'',Color(alpha,255,255,255))
	Render(self.img,self.x,self.y, 15,0.4-self.timer*0.01,self.timer*0.1+0.7)
	Render(self.img,self.x,self.y, 75,0.4-self.timer*0.01,self.timer*0.1+0.7)
	Render(self.img,self.x,self.y,135,0.4-self.timer*0.01,self.timer*0.1+0.7)
end

function enemy_death_ef:frame()
	if self.timer==30 then Kill(self) end
end
]]
Include'THlib\\enemy\\boss.lua'

EnemySimple=Class(enemy)

function EnemySimple:init(style,hp,x,y,drop,pro,clr,bound,tjt,tf)
	enemy.init(self,style,hp,clr,bound,tjt)
	self.x,self.y = x,y
	self.drop = drop
	task.New(self,function() self.protect=true task.Wait(pro) self.protect=false end)
	tf(self)
end

death_obj_lily=Class(object)
---´óÐ¡ £¬½Çsu¶È
function death_obj_lily:init(x,y,size,aaa,color)
	self.img='ring_eff'
	self.x=x
	self.y=y
	--color
	self.red=color.r
	self.green=color.g
	self.blue=color.b
	self.alpha=255
	---
	self.layer=LAYER_ENEMY+50
	self.group=GROUP_GHOST
	self.aaa=aaa
	self.hscale=0
	self.vscale=0
	self.bound=false
	self.R_=0
	task.New(self,function()
			local angle,dangle=0,4.5
			for i=1,20 do
				self.R_=size*sin(angle)
				angle=angle+dangle
				task.Wait(1)
			end
			task.Wait(20)
			local alpha,daplha=255,-255/15
			for i=1,15 do
				self.alpha=alpha
				alpha=alpha+daplha
				task.Wait(1)
			end
			self.hide=true
			Del(self)
	end)
end

function death_obj_lily:frame()
	task.Do(self)
	self.hscale=self.R_
	self.vscale=0.6*self.R_+0.4*self.R_*cos(self.timer*1.8*self.aaa)
	self.rot=self.timer*1.8*self.aaa
end

function death_obj_lily:render()
	SetImageState(self.img,'mul+add',Color(self.alpha,self.red,self.green,self.blue))
	object.render(self)
	SetImageState(self.img,'mul+add',Color(255,255,255,255))
end



enemy_death_ef_unit=Class(object)
function enemy_death_ef_unit:init(x,y,v,angle,lifetime,size,color)
	self.x=x self.y=y self.rot=ran:Float(0,360)
	--
	self.red=color.r
	self.green=color.g
	self.blue=color.b
	--
	SetV(self,v,angle)
	self.lifetime=lifetime
	self.omiga=3
	self.layer=LAYER_ENEMY+50
	self.group=GROUP_GHOST
	self.bound=false
	self.img='white_leaf'
	self.hscale=size
	self.vscale=size
end

function enemy_death_ef_unit:frame()
	if self.timer==self.lifetime then Del(self) end
end

function enemy_death_ef_unit:render()
	if self.timer<15 then
		SetImageState('white_leaf','mul+alpha',Color(self.timer*12,self.red,self.green,self.blue))
	else
		SetImageState('white_leaf','mul+alpha',Color(((self.lifetime-self.timer)/(self.lifetime-15))*180,self.red,self.green,self.blue))
	end
	DefaultRenderFunc(self)
end
