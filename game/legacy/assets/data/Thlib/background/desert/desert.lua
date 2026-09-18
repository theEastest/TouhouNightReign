desert_background=Class(object)

function desert_background:init()
	background.init(self,false)
	--resource
	LoadImageFromFile('sha_bg','sha_bg.png')
	LoadImageFromFile('sha_ground','sha_ground.png')
	LoadImageFromFile('sha_mist','sha_mist.png')
	SetImageState('sha_mist','',Color(0x80FFFFFF))
	LoadTexture('sha_tree','sha_tree.png')
	LoadImage('sha_tree1','sha_tree',0,0,172,328,0,0)
	LoadImage('sha_tree2','sha_tree',172,0,325,328,0,0)
	LoadImage('sha_tree3','sha_tree',497,0,289,328,0,0)
	--set 3d camera and fog
	Set3D('eye',1.5,0.4,-5)
	Set3D('at',1.5,-1.4,0)
	Set3D('up',0,1,0)
	Set3D('z',1,24)
	Set3D('fovy',0.7)
	Set3D('fog',5.3,20,Color(128,255,186,0))
	--
	self.list={0,0,0,0,0,0,0,0}
	self.liststart=1
	self.listend=0
	self.bg_z=14
	self.imgs={'sha_tree1','sha_tree2','sha_tree3'}
	self.speed=0.07
	self.interval=3
	self.acc=self.interval
	for i=1,400 do desert_background.frame(self) end
end

function desert_background:frame()
	self.acc=self.acc+self.speed
	if self.acc>=self.interval then
		self.acc=self.acc-self.interval
		self.listend=self.listend+1
		self.list[self.listend]={rnd(1,3), 0.9+rnd()*3,0,rnd()*0.2-0.2,0.7+0.3*rnd(),24+0.1*rnd(),ran:Float(-0.5,1.5)+1.8,-2+6,3}--rnd()*0.4-0.2
		self.listend=self.listend+1
		self.list[self.listend]={rnd(1,3),-0.9-rnd()*3,0,rnd()*0.2-0.2,0.7+0.3*rnd(),24+0.1*rnd(),ran:Float(-1.5,0.5)-1.8,-2+6,3}
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
end

function desert_background:render()
	SetViewMode'3d'
	local showboss = IsValid(_boss)
	if showboss then
        PostEffectCapture()
    end
	
	RenderClear(lstg.view3d.fog[3])
	Render4V('sha_bg',-5,1,self.bg_z,8,1,self.bg_z,8,-5,self.bg_z,-5,-5,self.bg_z)
	for j=0,4 do
		local dz=j*8-math.mod(self.timer*self.speed,8)
		for i=-3,1 do
			Render4V('sha_ground',i*5,-2,dz,5+i*5,-2,dz,5+i*5,-2,-8+dz,i*5,-2,-8+dz)
		end
	end
	local t=((self.timer+0.8*sin(self.timer))*0.02)%5
	for i=-2,2 do
		Render4V('sha_mist',i*5+t,-1.8,15,i*5+5+t,-1.8,15,i*5+5+t,-1.8,-5,i*5+t,-1.8,-5)
	end
	local dz=0*4-math.mod(self.timer*self.speed,4)
	for i=self.listend,self.liststart,-1 do
		local p=self.list[i]
		if p[6]>8 then SetImageState(self.imgs[p[1]],'',Color(255-255*min(p[6]-8,6)/6,255,255,255))
		else SetImageState(self.imgs[p[1]],'',Color(255,255,255,255)) end
		Render4V(self.imgs[p[1]],p[7],p[8],p[6],p[7]+p[9],p[8],p[6],p[7]+p[9],-2,p[6],p[7],-2,p[6])
	end
	if showboss then
		local x,y = WorldToScreen(_boss.x,_boss.y)
		local x1 = x * screen.scale
		local y1 = (screen.height - y) * screen.scale
		local fxr = _boss.fxr or 163
		local fxg = _boss.fxg or 73
		local fxb = _boss.fxb or 164
		PostEffectApply("boss_distortion", "", {
			centerX = x1,
			centerY = y1,
			size = _boss.aura_alpha*200*lstg.scale_3d,
			color = Color(125,fxr,fxg,fxb),
			colorsize = _boss.aura_alpha*200*lstg.scale_3d,
			arg=1500*_boss.aura_alpha/128*lstg.scale_3d,
			timer = self.timer
        })
	end
	SetViewMode'world'
end