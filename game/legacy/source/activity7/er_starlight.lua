er_starlight_background=Class(object)

function er_starlight_background:init()
	--
	self.group=GROUP_GHOST
	self.layer=LAYER_BG-0.1
	self.alpha=1
	er_starlight=self
	--resource
	LoadTexture('starlight_ground','THlib\\background\\starlight\\ground.png')
	LoadImage('starlight_ground','starlight_ground',0,0,256,256,0,0)
	LoadTexture('starlight','THlib\\background\\starlight\\starlight.png')
	LoadImage('noir','starlight',488,0,22,512,0,0)
	SetImageCenter('noir',12,512)
	LoadImage('star1','starlight',60,40,60,60,0,0)
	LoadImage('star2','starlight',110,360,64,64,0,0)
	LoadImageFromFile('stair','THlib\\background\\starlight\\stair.png')
	LoadImageFromFile('window','THlib\\background\\starlight\\windows.png')
	SetImageState('noir','mul+add')
	SetImageState('star1','mul+add')
	SetImageState('star2','mul+add')
	SetImageState('stair','mul+alpha',Color(255,255,255,255))
	--set 3d camera and fog
	Set3D('eye',0.6,-1.8,-22.4+30)
	Set3D('at',0.4,-1.6,-12.1+30)
	Set3D('up',1.24,1.1,0.1)
	Set3D('z',2.1,1000)
	Set3D('fovy',0.7)
	Set3D('fog',7,1000,Color(200,10,10,27))
	self.list={}
	self.liststart=1
	self.listend=0
	self.imgs={'noir','star1','star2','stair'}
	self.speed=0.9+2
	self.interval=0.5
	self.acc=self.interval
	self.angle=0
	self.z=0
	for i=1,800 do starlight_background.frame(self) end
--[[	for j=1,200 do
		local z=-3+0.04*self.angle
		self.listend=self.listend+1
		self.list[self.listend]={4,self.angle,0,0,0,z}
		self.angle=self.angle+10
	end]]
end

rnd=math.random

function er_starlight_background:frame()
	if self.timer>240 then self.layer=LAYER_BG-0.2 end
	self.z=self.z+self.speed*50
	---Set3D('eye',3.35*cos(self.timer/4),3.35*sin(self.timer/4),-8.6)
	---Set3D('up',2*sin(self.timer/20),1.1,0.1)
	self.acc=self.acc+self.speed
	if self.acc>=self.interval then
		self.acc=self.acc-self.interval
		self.acc=self.acc-self.interval
		local a=0
		local R=rnd(6,60)--1.4,60
		for _=1,3 do
			a=rnd(0,360)--0,2
			x=0.6+R*cos(a)
			y=-1.8+R*sin(a)
			self.listend=self.listend+1
			self.list[self.listend]={rnd(2,3), x,y,rnd()*0.6-0.3,-0.4-0.1*rnd(),rnd(180,200)}
		end
		---if self.timer%2==0 then
--[[		local z=-3+0.04*self.angle
		self.listend=self.listend+1
		self.list[self.listend]={4,self.angle,0,0,0,z}
		self.angle=self.angle+10
		---end]]
	end
	for i=self.liststart,self.listend do
		if self.list[i][1]~=4 then
			self.list[i][6]=self.list[i][6]-self.speed
		else
			self.list[i][6]=self.list[i][6]-self.speed/4
		end
	end
	while true do
		if self.list[self.liststart][6]<-6 then
			self.list[self.liststart]=nil
			self.liststart=self.liststart+1
		else break
		end
--[[		if self.list[self.liststart][1]==4 then
			if self.list[self.liststart][6]>4 then
				self.list[self.liststart]=nil
				self.liststart=self.liststart+1
			else break
			end
		end]]
	end
	Print(self.liststart,self.listend,self.liststart-self.listend)
end

function er_starlight_background:render()
	Set3D('eye',0.6,-1.8,-22.4+30)
	Set3D('at',0.4,-1.6,-12.1+30)
	Set3D('up',1.24,1.1,0.1)
	Set3D('z',2.1,1000)
	if self.timer<60 then
		Set3D('fovy',2.3)
	elseif self.timer>180 then
		Set3D('fovy',0.7)
	else
		Set3D('fovy',2.3-1.6*sin((self.timer-60)*0.75))
	end
	Set3D('fog',7,1000,Color(200,10,10,27))
	SetViewMode'3d'
	local showboss = IsValid(_boss)
	if showboss then
        PostEffectCapture()
    end

	RenderClear(lstg.view3d.fog[3])
--	for j=0,20 do
--		local dz=j*40-math.mod(self.z,40)
--		starlight_background.draw_windows(0,0,-5+dz,35+dz)
--	end
	for i=self.listend,self.liststart,-1 do
		local p=self.list[i]
		if p[1]~=4 then
--			Render(self.imgs[p[1]],p[2]+rnd(-0.1,0.1),p[3]+rnd(-0.1,0.1),p[4]*57,p[5]/2,abs(p[5]/2),p[6])
			Render(self.imgs[p[1]],p[2],p[3],p[4]*57,p[5]/2,abs(p[5]/2),p[6])
			Render(self.imgs[p[1]],p[2],p[3],p[4]*57,p[5]/2,abs(p[5]/2),p[6]-0.8*self.speed)
			Render(self.imgs[p[1]],p[2],p[3],p[4]*57,p[5]/2,abs(p[5]/2),p[6]-1.6*self.speed)
		else
--			Render_4_point(p[2],6,10,2,'stair',p[6])
		end
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




function Render_4_point(angle,r,angle_offset,r_,imagename,z)
	local A_1 = angle+angle_offset
	local R_1 = r-r_
	local x1,x2,x3,x4,y1,y2,y3,y4
	x1=(r)*cos(A_1)
	y1=(r)*sin(A_1)

	x2=(r)*cos(angle)
	y2=(r)*sin(angle)

	x3=(R_1)*cos(angle)
	y3=(R_1)*sin(angle)

	x4=(R_1)*cos(A_1)
	y4=(R_1)*sin(A_1)
	Render4V(imagename,x1,y1,z,x2,y2,z,x3,y3,z,x4,y4,z)
end


function er_starlight_background.draw_windows(x,y,z1,z2)
	local r=45
	local a=0
	for _=1,12 do
		Render4V('window',
		x+r*cos(a-15),y+r*sin(a-15),z1,
		x+r*cos(a+15),y+r*sin(a+15),z1,
		x+r*cos(a+15),y+r*sin(a+15),z2,
		x+r*cos(a-15),y+r*sin(a-15),z2)
		a=a+30
	end
end
