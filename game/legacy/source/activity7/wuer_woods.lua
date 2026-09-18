wuer_woods_background=Class(object)

function wuer_woods_background:init()
	--
	background.init(self,false)
	--resource
	LoadImageFromFile('woods_ground','er_3-1.png')
	LoadImageFromFile('_woods_leaf','er_woods_leaf.png')
	SetImageState('woods_ground','',Color(255,200,200,200))
--	LoadImage('bamboo_ground','bamboo_ground',0,0,256,256,0,0)
	LoadImageFromFile('tree1','er_tree1.png')
	LoadImageFromFile('tree2','er_tree2.png')
	LoadImageFromFile('tree3','er_tree3.png')
--	LoadImageFromFile('gate','wuer_gate.png')
	LoadTexture('woods','er_forest1.png')
	LoadImage('grass1','woods',0,0,512,256,0,0)
	LoadImage('grass2','woods',0,256,512,256,0,0)
	SetImageState('grass1','',Color(255,200,200,200))
	SetImageState('grass2','',Color(255,200,200,200))
	--set 3d camera and fog
	Set3D('eye',1.5,0.4,-5)
	Set3D('at',1.5,-0.8,0)
	Set3D('up',0,1,0)
	Set3D('z',1,24)
	Set3D('fovy',0.65)
	Set3D('fog',8.3,20,Color(255,144,144,144))
	--
	self.list={0,0,0,0,0,0,0,0}
	self.liststart=1
	self.listend=0
	self.imgs={'tree1','tree2','tree3','grass1','grass2'}
	self.speed=0.05
	self.interval=0.5
	self.acc=self.interval
	self.al=255
	for i=1,400 do woods_background.frame(self) end
	self.al=255
	self._eye,self._at={},{}
	for i=1,3 do
		self._eye[i]=lstg.view3d.eye[i]
		self._at[i]=lstg.view3d.at[i]
	end
	self.high=0
	self.true_boss=false
	self.leaf=true
	woods_bg=self
end

rnd=math.random

function wuer_woods_background:frame()
	task.Do(self)
	if self.timer>240 then self.layer=LAYER_BG-0.2 end
	if self.note then
		for i=1,3 do
			self._eye[i]=lstg.view3d.eye[i]
			self._at[i]=lstg.view3d.at[i]
		end
		self.note=nil
	end
	if self.true_boss then Set3D('eye',1.5+0.3*sin(self.timer/2),12.5+0.3*sin(self.timer/3),-5) end
	if self.follow then
		lstg.view3d.eye[1]=self._eye[1]+0.7*player.x/192
		lstg.view3d.at[1]=self._at[1]+0.7*player.x/192
		if KeyIsDown'up' and player.death<=0 then self.high=self.high+2-1*player.slow end
		if KeyIsDown'down' and player.death<=0 then self.high=self.high-2+1*player.slow end
		lstg.view3d.eye[2]=max(3.5,self._eye[2]+self.high/300)--3.5
		lstg.view3d.at[2]=max(1.6,self._at[2]+self.high/300)--1.6
		if self.timer%60==0 then print(self.high) end
	end
	if self.timer<120 then self.al=self.al-255/120 end
	self.acc=self.acc+self.speed
	if self.acc>=self.interval then
		self.acc=self.acc-self.interval
		self.listend=self.listend+1
		self.list[self.listend]={ran:Int(1,3), 0.9+rnd()*3,0,rnd()*0.2-0.2,0.7+0.3*rnd(),24+0.1*rnd(),ran:Float(-0.5,1.5)+1.5,-2+6,3}--rnd()*0.4-0.2
		self.listend=self.listend+1
		self.list[self.listend]={ran:Int(1,3),-0.9-rnd()*3,0,rnd()*0.2-0.2,0.7+0.3*rnd(),24+0.1*rnd(),ran:Float(-1.5,0.5)-1.5,-2+6,3}
		self.acc=self.acc-self.interval
		self.listend=self.listend+1
		self.list[self.listend]={ran:Int(4,5), 1.5+rnd()*2,-1.8+rnd(),rnd()*0.6-0.3,-0.7-0.3*rnd(),24+0.1*rnd(),ran:Float(-0.5,1.5)+2,-2+1,2}--2=1.6
		self.listend=self.listend+1
		self.list[self.listend]={ran:Int(4,5),-1.5-rnd()*2,-1.8+rnd(),rnd()*0.6-0.3, 0.7+0.3*rnd(),24+0.1*rnd(),ran:Float(-1.5,0.5)-1,-2+1,2}
	end
	for i=self.liststart,self.listend do
		self.list[i][6]=self.list[i][6]-self.speed
	end
	while true do
		if self.list[self.liststart][6]<-6 then
			self.list[self.liststart]=nil
			self.liststart=self.liststart+1
		else break
		end
	end
--[[	if IsValid(_boss) and _boss.cards[_boss.card_num] and _boss.cards[_boss.card_num].is_sc then
	else
		if self.timer%30==0 and self.timer>120 and self.leaf then
			for i=1,ran:Int(2,7) do
				local size=ran:Float(0.5,1.5)
				local x=ran:Float(-240,240)
				local y=ran:Float(240,300)
				local color=Color(ran:Float(80,150),255,255,255)
				New(woods_leaf,x,y,size,color)
			end
		end
	end]]
--	self.list[self.timer%5+1]=ran:Float(-0.2,0.2)
end

function wuer_woods_background:render()
	if self.timer<120 then
		Set3D('eye',1.5,1,-5)
		Set3D('at',1.5,1.8,0)
	--	self.speed=0.12
	elseif self.timer>180 then
		Set3D('eye',1.5,0.4,-5)
		Set3D('at',1.5,-0.4,0)
		self.speed=0.05
	else
		Set3D('eye',1.5,1-0.6*sin((self.timer-120)*1.5),-5)
		Set3D('at',1.5,1.8-2.2*sin((self.timer-120)*1.5),0)
	--	self.speed=0.12-0.07*(self.timer-120)/60
	end
	Set3D('up',0.05*sin(0.5*self.timer),1,0)
	Set3D('z',1,24)
	Set3D('fovy',0.65)
	Set3D('fog',8.3,20,Color(255,244,244,244))
	SetViewMode'3d'
	RenderClear(lstg.view3d.fog[3])
	for j=0,6 do
		local dz=j*4-math.mod(self.timer*self.speed,4)
		for i=-3,1 do Render4V('woods_ground',i*4,-1.7,dz,4+i*4,-1.7,dz,4+i*4,-1.7,-4+dz,i*4,-1.7,-4+dz) end
	end
--[[	for j=0,6 do
		local dz=j*4-math.mod(self.timer*self.speed,4)
		for i=-2,1 do
		Render4V('tree1',self.list[i+3],4,-4+dz,self.list[i+3]+1,4,-4+dz,self.list[i+3]+1,0,-4+dz,self.list[i+3],0,-4+dz) end
	end]]
	local dz=0*4-math.mod(self.timer*self.speed,4)
--	Render4V('grass1',0,2,1,2,2,1,2,0,0,0,0,1)
--	Render4V('tree1',0,2,dz,1,2,dz,1,0,dz,0,0,dz)
	for i=self.listend,self.liststart,-1 do
		local p=self.list[i]
--		Render(self.imgs[p[1]],p[2],p[3],p[4]*57,p[5],abs(p[5]),p[6])
		Render4V(self.imgs[p[1]],p[7],p[8],p[6],p[7]+p[9],p[8],p[6],p[7]+p[9],-2,p[6],p[7],-2,p[6])
		--Render(self.imgs[1],0,0,0,1,1,0)
	end
--	for i=0,11 do
--		local dz=i*2-math.mod(self.timer*self.speed,2)-4
--		Render4V('gate',0,14,dz,3,14,dz,3,11,dz,0,11,dz)
--	end
	SetViewMode'world'
end

------摄像机坐标改变(x,y,z)为终点坐标 false为不改变
function wuer_woods_background.eye_change(x,y,z,self,t,mode)
	local x0=lstg.view3d.eye[1]
	local y0=lstg.view3d.eye[2]
	local z0=lstg.view3d.eye[3]
	local tempx=x0
	local tempy=y0
	local tempz=z0
	local dx,dy,dz
	if x then dx=x-x0 else dx=0 end
	if y then dy=y-y0 else dy=0 end
	if z then dz=z-z0 else dz=0 end
	task.New(self,function()
		if mode==1 then
			for s=1/t,1+0.5/t,1/t do
			s=s*s
			if dx~=0 then x0=tempx+s*dx end
			if dy~=0 then y0=tempy+s*dy end
			if dz~=0 then z0=tempz+s*dz end
			Set3D('eye',x0,y0,z0)
			coroutine.yield()
			end
		elseif mode==2 then
			for s=1/t,1+0.5/t,1/t do
			s=s*2-s*s
			if dx~=0 then x0=tempx+s*dx end
			if dy~=0 then y0=tempy+s*dy end
			if dz~=0 then z0=tempz+s*dz end
			Set3D('eye',x0,y0,z0)
			coroutine.yield()
			end
		elseif mode==3 then
			for s=1/t,1+0.5/t,1/t do
			if s<0.5 then s=s*s*2 else s=-2*s*s+4*s-1 end
			if dx~=0 then x0=tempx+s*dx end
			if dy~=0 then y0=tempy+s*dy end
			if dz~=0 then z0=tempz+s*dz end
			Set3D('eye',x0,y0,z0)
			coroutine.yield()
			end
		else
			for s=1/t,1+0.5/t,1/t do
			if dx~=0 then x0=tempx+s*dx end
			if dy~=0 then y0=tempy+s*dy end
			if dz~=0 then z0=tempz+s*dz end
			Set3D('eye',x0,y0,z0)
			coroutine.yield()
			end
		end
	end)
end
------朝向坐标改变
function wuer_woods_background.at_change(x,y,z,self,t,mode)
	local x0=lstg.view3d.at[1]
	local y0=lstg.view3d.at[2]
	local z0=lstg.view3d.at[3]
	local tempx=x0
	local tempy=y0
	local tempz=z0
	local dx,dy,dz
	if x then dx=x-x0 else dx=0 end
	if y then dy=y-y0 else dy=0 end
	if z then dz=z-z0 else dz=0 end
	task.New(self,function()
		if mode==1 then
			for s=1/t,1+0.5/t,1/t do
			s=s*s
			if dx~=0 then x0=tempx+s*dx end
			if dy~=0 then y0=tempy+s*dy end
			if dz~=0 then z0=tempz+s*dz end
			Set3D('at',x0,y0,z0)
			coroutine.yield()
			end
		elseif mode==2 then
			for s=1/t,1+0.5/t,1/t do
			s=s*2-s*s
			if dx~=0 then x0=tempx+s*dx end
			if dy~=0 then y0=tempy+s*dy end
			if dz~=0 then z0=tempz+s*dz end
			Set3D('at',x0,y0,z0)
			coroutine.yield()
			end
		elseif mode==3 then
			for s=1/t,1+0.5/t,1/t do
			if s<0.5 then s=s*s*2 else s=-2*s*s+4*s-1 end
			if dx~=0 then x0=tempx+s*dx end
			if dy~=0 then y0=tempy+s*dy end
			if dz~=0 then z0=tempz+s*dz end
			Set3D('at',x0,y0,z0)
			coroutine.yield()
			end
		else
			for s=1/t,1+0.5/t,1/t do
			if dx~=0 then x0=tempx+s*dx end
			if dy~=0 then y0=tempy+s*dy end
			if dz~=0 then z0=tempz+s*dz end
			Set3D('at',x0,y0,z0)
			coroutine.yield()
			end
		end
		--task.Clear(self)
	end)
end

woods_leaf=Class(object)
function woods_leaf:init(x,y,size,color)
	self.x=x
	self.y=y
	self.img='_woods_leaf'
	self.size=size
	self.hscale=size
	self.vscale=size
	self.group=GROUP_GHOST
	self.omiga=ran:Float(-3,-2)
	self.layer=LAYER_BG+size
	self.color=color
	self._vx=ran:Float(1,1.7)
	self.bound=false
	self.vx=ran:Float(0.2,0.4)
	self.vy=-size*1.5
end

function woods_leaf:frame()
	task.Do(self)
--	self.hscale=self.hscale+self.size/100
--	self.vscale=self.vscale+self.size/100
	if self.y<-270 then Del(self) end
end

function woods_leaf:render()
	SetImageState(self.img,"",self.color)
	SetViewMode"world"
	object.render(self)
	SetImageState(self.img,"",Color(255,255,255,255))
end
