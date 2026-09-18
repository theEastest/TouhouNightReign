

yahoon_bar_background=Class(background)

function yahoon_bar_background:init()
	background.init(self,false)
	LoadTexture('bar_ground','yahoon-ground.png')
	LoadImage('bar_ground','bar_ground',0,0,527,505)
	LoadTexture('bar_light1','yahoon-light1.png')
	LoadImage('bar_light1','bar_light1',0,0,101,101)
	LoadTexture('bar_light2','yahoon-light2.png')
	LoadImage('bar_light2','bar_light2',0,0,200,600)
	LoadTexture('bar_light3','yahoon-light3.png')
	LoadImage('bar_light3','bar_light3',0,0,101,101)
	SetImageState('bar_light2','mul+add',Color(0,255,255,255))
	SetImageState('bar_light1','mul+add',Color(0,255,255,255))
	SetImageState('bar_light3','mul+add',Color(0,255,255,255))
	Set3D('z',0.5,4.5)
	Set3D('eye',0,-0.4,0.3)
	Set3D('at',0,3.2,-0.6)
	Set3D('up',0,0,1)
	Set3D('fovy',0.45)
	Set3D('fog',1.8,3.3,Color(0x00000000))
	self.yos=0
	self.speed=1/((1+41/100)*60)
	self.T=-90
	self.T2=-90
end

function yahoon_bar_background:frame()
	self.yos=self.yos+self.speed
	if lstg.var.bglight then
    else lstg.var.bglight=1
	end
	if lstg.var.bglight2 then
	    if lstg.var.bglight2==1 and self.T<90 then
		    Set3D('at',0,3.2+0.8*(sin(self.T)/2+1/2),-0.6+0.8*(sin(self.T)/2+1/2))
		    Set3D('eye',0,-0.4-1.4*(sin(self.T)/2+1/2),0.3)
	        self.T=self.T+1/2
		end
	else
	    if self.T<90 then
			Set3D('at',0,3.2+0.8*(sin(self.T)/2+1/2),-0.6+0.8*(sin(self.T)/2+1/2))
			Set3D('eye',0,-0.4-1.4*(sin(self.T)/2+1/2),0.3)
			self.T=self.T+2
		end
	end

end

function yahoon_bar_background:render()
	SetViewMode'3d'
	-- Render can run once before the first object frame after a stage switch.
	-- Keep the reference effect unchanged while avoiding arithmetic on an
	-- uninitialized global brightness value during that first render.
	local bglight = (lstg.var and lstg.var.bglight) or 1

	local showboss = IsValid(_boss)
	if showboss then
        PostEffectCapture()
    end

	RenderClear(lstg.view3d.fog[3])
	local y=self.yos%1
	for i=-1,3 do
		Render4V('bar_ground',-0.5,0-y+i,0,-0.5,1-y+i,0,0.5,1-y+i,0,0.5,-y+i,0)
	end
	for i=-1,3 do
		if 0.5-y+i>1 then
			SetImageState('bar_light2','mul+add',Color(0,255,255,255))
	    	SetImageState('bar_light1','mul+add',Color(0,255,255,255))
	    	SetImageState('bar_light3','mul+add',Color(0,255,255,255))
        end
	    if 0.5-y+i<1 and 0.9<0.5-y+i then
		    self.light=(1-(0.5-y+i))*10
			SetImageState('bar_light2','mul+add',Color(255*self.light*bglight,255,255,255))
	    	SetImageState('bar_light1','mul+add',Color(255*self.light*bglight,255,255,255))
	    	SetImageState('bar_light3','mul+add',Color(255*self.light*bglight,255,255,255))
	    end
	    if 0.9>0.5-y+i then
		    SetImageState('bar_light2','mul+add',Color(255*bglight,255,255,255))
	    	SetImageState('bar_light1','mul+add',Color(255*bglight,255,255,255))
	    	SetImageState('bar_light3','mul+add',Color(255*bglight,255,255,255))
	    end

		Render4V('bar_light1',-0.25,0-y+i,0,-0.25,1-y+i,0,0.25,1-y+i,0,0.25,-y+i,0)
		Render4V('bar_light3',-0.5,0-y+i,0,-0.5,1-y+i,0,0.5,1-y+i,0,0.5,-y+i,0)
		Render4V('bar_light2',-0.25,0.5-y+i,0,0.25,0.5-y+i,0,0.25,0.5-y+i,1,-0.25,0.5-y+i,1)
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
