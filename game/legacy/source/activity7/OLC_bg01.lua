OLC_bg01_background=Class(object)

function OLC_bg01_background:init()
	background.init(self,false)
	LoadImageFromFile('OLC_bg_01','OLC_bg_01.png')
	--set camera
	Set3D('eye',0.00,0.0,0)
	Set3D('at',0.00,0,1)
	Set3D('up',0.00,0,0)
	Set3D('fovy',1.52)
	Set3D('z',0.01,10.0)
	Set3D('fog',1.00,10.0,Color(0,0,0,0))
	--
	self.zos=0
	self.speed=0.025
	--
	SetImageState('OLC_bg_01','',Color(127,255,0,0))
	CreateRenderTarget('OLC_bg01_nq')
end

function OLC_bg01_background:frame()
	self.zos=self.zos-self.speed
	Set3D('up',cos(-self.timer/3),sin(-self.timer/3),0)
	local bg_timer = self.timer % 420
	if bg_timer >= (420/7)*0 and bg_timer < (420/7)*1 and self.flag then
		SetImageState('OLC_bg_01','',Color(127,255,(255/(420/7))*(bg_timer%(420/7)),0))
	elseif bg_timer >= (420/7)*1 and bg_timer < (420/7)*2 then
		SetImageState('OLC_bg_01','',Color(127,255,(255/(420/7))*(bg_timer%(420/7)),0))
	elseif bg_timer >= (420/7)*2 and bg_timer < (420/7)*3 then
		SetImageState('OLC_bg_01','',Color(127,255-(255/(420/7))*(bg_timer%(420/7)),255,0))
	elseif bg_timer >= (420/7)*3 and bg_timer < (420/7)*4 then
		SetImageState('OLC_bg_01','',Color(127,0,255,(255/(420/7))*(bg_timer%(420/7))))
	elseif bg_timer >= (420/7)*4 and bg_timer < (420/7)*5 then
		SetImageState('OLC_bg_01','',Color(127,0,255-(255/(420/7))*(bg_timer%(420/7)),255))
	elseif bg_timer >= (420/7)*5 and bg_timer < (420/7)*6 then
		SetImageState('OLC_bg_01','',Color(127,(255/(420/7))*(bg_timer%(420/7)),0,255))
	elseif bg_timer >= (420/7)*6 and bg_timer < (420/7)*7 then
		SetImageState('OLC_bg_01','',Color(127,255,0,255-(255/(420/7))*(bg_timer%(420/7))))
	end
end

function OLC_bg01_background:render()
	SetViewMode'3d'
	local showboss = IsValid(_boss)
	if showboss then
		PostEffectCapture()
	end
	PushRenderTarget('OLC_bg01_nq')
	
	RenderClear(lstg.view3d.fog[3])
	local z=self.zos%1
	local d=0.5
	for i=-5,12 do
		Render4V('OLC_bg_01',-d*1.5,-d*1.5,2+z+i,d*1.5,-d*1.5,2+z+i,d*1.5,-d*1.5,-2+z+i,-d*1.5,-d*1.5,-2+z+i)
		Render4V('OLC_bg_01',-d*1.5,d*1.5,2+z+i,-d*1.5,-d*1.5,2+z+i,-d*1.5,-d*1.5,-2+z+i,-d*1.5,d*1.5,-2+z+i)
		Render4V('OLC_bg_01',-d*1.5,d*1.5,2+z+i,d*1.5,d*1.5,2+z+i,d*1.5,d*1.5,-2+z+i,-d*1.5,d*1.5,-2+z+i)
		Render4V('OLC_bg_01',d*1.5,d*1.5,2+z+i,d*1.5,-d*1.5,2+z+i,d*1.5,-d*1.5,-2+z+i,d*1.5,d*1.5,-2+z+i)
	end
	PopRenderTarget('OLC_bg01_nq')
	local px,py = WorldToScreen(0,0)
	local px1 = px * screen.scale
	local py1 = (screen.height - py) * screen.scale
	PostEffect('OLC_bg01_nq','boss_distortion','',{
		centerX = px1,
		centerY = py1,
		size = 127*200*lstg.scale_3d,
		color = Color(125,163,73,164),
		colorsize = 255*200*lstg.scale_3d,
		arg=1500*255/128*lstg.scale_3d,
		timer = self.timer
	})
			
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
