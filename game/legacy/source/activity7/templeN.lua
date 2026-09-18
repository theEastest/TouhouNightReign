templeN_background=Class(object)

function templeN_background:init()
	background.init(self,false)
	LoadImageFromFile('tn_tree','tn_tree.png')
        SetImageState('tn_tree','',Color(100,255,255,255))
        LoadImageFromFile('tn_tree2','tn_tree2.png')
        SetImageState('tn_tree2','',Color(100,255,255,255))
	LoadImageFromFile('tn_ground','tn_ground.png')
	--set camera
	Set3D('eye',0.00,1.60,-1.40)
	Set3D('at',0.00,0.00,-0.20)
	Set3D('up',0.00,1.00,0.00)
	Set3D('fovy',0.62)
	Set3D('z',1.00,3.70)
	Set3D('fog',2.50,4.00,Color(0,255,0,255))
	--
	self.zos=0
	self.speed=0.004
	--
	--New(camera_setter)
end

function templeN_background:frame()
	self.zos=self.zos+self.speed
        if self.timer>100 then
		Set3D('eye',0.1*sin((self.timer-100)/4),1.60,-1.40)
	end
end

function templeN_background:render()
	SetViewMode'3d'

	local showboss = IsValid(_boss)
	if showboss then
        PostEffectCapture()
    end
	
        RenderClear(lstg.view3d.fog[3])
	local z=self.zos%1
	for i=-1,2 do
		Render4V('tn_ground',1.5,-0.6,1-z+i, 0,-0.6,1-z+i, 0,-0.6,0-z+i,1.5,-0.6,0-z+i)
		Render4V('tn_ground',-1.5,-0.6,1-z+i,0,-0.6,1-z+i,0,-0.6,0-z+i,-1.5,-0.6,0-z+i)
	end
	z=self.zos%2
	for i=-2,2 do
		Render4V('tn_tree',-1,0.4,2-z+i,0,0.4,2-z+i,0,0.4,1-z+i,-1,0.4,1-z+i)
                Render4V('tn_tree',-1,0.4,1-z+i,0,0.4,1-z+i,0,0.4,0-z+i,-1,0.4,0-z+i)
                Render4V('tn_tree2',-1,0.6,1-z+i,0,0.6,1-z+i,0,0.6,0-z+i,-1,0.6,0-z+i)
                Render4V('tn_tree2',-1,0.6,2-z+i,0,0.6,2-z+i,0,0.6,1-z+i,-1,0.6,1-z+i)
		Render4V('tn_tree', 1,0.4,0-z+i,0,0.4,0-z+i,0,0.4,1-z+i, 1,0.4,1-z+i)
                Render4V('tn_tree', 1,0.4,1-z+i,0,0.4,1-z+i,0,0.4,2-z+i, 1,0.4,2-z+i)
		Render4V('tn_tree2', 1,0.6,0-z+i,0,0.6,0-z+i,0,0.6,1-z+i, 1,0.6,1-z+i)
                Render4V('tn_tree2', 1,0.6,1-z+i,0,0.6,1-z+i,0,0.6,2-z+i, 1,0.6,2-z+i)
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
