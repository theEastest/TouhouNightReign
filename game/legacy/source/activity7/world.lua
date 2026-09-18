wyj_Newworld=Class(background)

function wyj_Newworld:init()
	background.init(self,false)
	LoadTexture('wyj_blue_line','wyj_blue_line.png')
	LoadTexture('wyj_blue','wyj_blue.png')
	LoadImageFromFile('wyj_zhuzi','wyj_zhuzi.png')
	LoadImage('wyj_blue_line','wyj_blue_line',0,0,512,512)
	LoadImage('wyj_blue','wyj_blue',0,0,512,512)
	SetImageState('wyj_blue','',Color(50,255,255,255))
	--set camera
	Set3D('eye',0.00,0.9,-5.20)
	Set3D('at',0.00,4.3,-3.60)-----(0.0,0.7,-3.6)---
	Set3D('up',0.00,2.90,5.70)
	Set3D('fovy',0.72)
	Set3D('z',0.01,100.0)
	Set3D('fog',1.00,60.0,Color(0,0,0,0))
	--
	self.zos=0
	self.speed=0.015
	self.r=55
	self.g=55
	self.b=55
	--
	Theworld=self
end

function wyj_Newworld:frame()
	if self.timer<=180 then
	Set3D('at',0.00,4.3-3.6*sin(self.timer/2),-3.60)
	Set3D('fovy',0.72)
	end
	self.zos=self.zos+self.speed
	SetImageState('wyj_blue','',Color(50,self.r,self.g,self.b))
	SetImageState('wyj_blue_line','',Color(255,self.r,self.g,self.b))
	SetImageState('wyj_zhuzi','',Color(255,self.r,self.g,self.b))
end

function wyj_Newworld:render()
	SetViewMode'3d'
	local showboss = IsValid(_boss)
	if showboss then
        PostEffectCapture()
    end

	RenderClear(lstg.view3d.fog[3])
	local z=2*self.zos%1
	for i=-3,15 do
		for j=-5,5 do
		Render4V('wyj_blue',-2+j*2,-1,1-z+i, 2+j*2,-1,1-z+i, 2+j*2,-1,-1-z+i,-2+j*2,-1,-1-z+i)
		Render4V('wyj_blue_line',-2+j*2,-1,1-z+i, 2+j*2,-1,1-z+i, 2+j*2,-1,-1-z+i,-2+j*2,-1,-1-z+i)
		end
	end
	local zz=5*self.zos%5
	for i=-3,3 do
		for j=0,5 do
			Render4V('wyj_zhuzi',-16.5+3*j	,1.5	,1-zz+5*i	,-16.5+3*j	,1.5,0.75-zz+5*i, -16.5+3*j	,-1,0.75-zz+5*i	,-16.5+3*j	,-1,1-zz+5*i)
			Render4V('wyj_zhuzi',16.5-3*j	,1.5	,1-zz+5*i	,16.5-3*j	,1.5,0.75-zz+5*i, 16.5-3*j	,-1,0.75-zz+5*i	,16.5-3*j	,-1,1-zz+5*i)
		end
	end
	local zzz=self.zos
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
