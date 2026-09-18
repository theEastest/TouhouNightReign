cave_background=Class(object)

function cave_background:init()
	background.init(self,false)
	LoadTexture('cave_img_tex','Thlib\\background\\cave\\cave_img.png')
	LoadImageGroup('cave_img','cave_img_tex',0,0,64,64,4,4)
	LoadImageFromFile('cave_fog','Thlib\\background\\cave\\cave_fog.png')
	--set camera
	Set3D('eye',0.00,-2.10,0.50)
	Set3D('at',0.00,-2.00,1.00)
	Set3D('up',0.00,1.00,0.00)
	Set3D('fovy',1.57)
	Set3D('z',0.01,10.00)
	Set3D('fog',1.00,10.00,Color(100,10,10,50))
	--
	self.zos=0
	self.speed=0.015
	--
end

function cave_background:frame()
	self.zos=self.zos+self.speed
end

function cave_background:render()
	SetViewMode'3d'
	local showboss = IsValid(_boss)
	if showboss then
        PostEffectCapture()
    end
	local dy={0,-0.15,-0.45,-0.9,-1.5,-2.25,-3.15,-4.2,-5.4,-6.75}
	local z=-3*self.zos%4
	RenderClear(lstg.view3d.fog[3])
	for dz=-2,7 do
		for i=-5,2 do
			Render4V('cave_fog',
					4*i+z		,2.5	,4*dz+z	,
					4*i+4+z		,2.5	,4*dz+z	,
					4*i+4+z		,2.5	,4+4*dz+z	,
					4*i+z		,2.5	,4+4*dz+z	)
		end
	end
	local z=-self.zos%4
	local mz=14
	for dz=-4,4,8 do--zmax=12
	for i=0,7 do
		for j=0,7 do--xmax/2=8
			Render4V('cave_img'..((j%4)+4*(i%4)+1),
					j	,2+dy[j+1]	,i+z+dz	,
					j+1	,2+dy[j+2]	,i+z+dz	,
					j+1	,2+dy[j+2]	,i+1+z+dz	,
					j	,2+dy[j+1]	,i+1+z+dz	)
			Render4V('cave_img'..((j%4)+4*(i%4)+1),
					-j	,2+dy[j+1]	,i+z+dz	,
					-j-1,2+dy[j+2]	,i+z+dz	,
					-j-1,2+dy[j+2]	,i+1+z+dz	,
					-j	,2+dy[j+1]	,i+1+z+dz	)
		end
	end end
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
