flame_background=Class(object)

function flame_background:init()
	background.init(self,false)
	LoadImageFromFile('flameground','flameground.png')


	LoadImageFromFile('mask1','mask1.png')
	Set3D('z',1,20)
	Set3D('eye',0.25,-2.2,1.1)
	Set3D('at',0,0,0)
	Set3D('up',0,0,1)
	Set3D('fovy',0.35)
	Set3D('fog',0,0,Color(0xFF2C5B1))
	self.yos=0
	self.speed=0.004
end

function flame_background:frame()
	self.yos=self.yos+self.speed
end
function flame_background:frame()
	if self.timer<500 then
		Set3D('eye',0.25,-0.2+2*cos(60+self.timer/3),1.1)
	end

	self.yos=self.yos+self.speed
end

function flame_background:render()
	SetViewMode'3d'

	local showboss = IsValid(_boss)
	if showboss then
        PostEffectCapture()
    end

	RenderClear(lstg.view3d.fog[3])
	local y=self.yos%1
	for i=-1,2 do
		Render4V('flameground',0,0-y+i,0,0,1-y+i,0,1,1-y+i,0,1,-y+i,0)
		Render4V('flameground',-1,0-y+i,0,-1,1-y+i,0,0,1-y+i,0,0,-y+i,0)
	end
	for i=-1,3 do
		Render4V('mask1',0,0-y+i,-0.2,0,1-y+i,-0.2,1,1-y+i,-0.2,1,-y+i,-0.2)
		Render4V('mask1',-1,0-y+i,-0.2,-1,1-y+i,-0.2,0,1-y+i,-0.2,0,-y+i,-0.2)
	end

	if showboss then
		local x,y = WorldToScreen(_boss.x,_boss.y)
		local x1 = x * screen.scale
		local y1 = (screen.height - y) * screen.scale
		local fxr = _boss.fxr or 200
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
