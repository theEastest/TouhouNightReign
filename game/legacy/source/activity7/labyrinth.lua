labyrinth_background=Class(object)

function labyrinth_background:init()
	background.init(self,false)
	LoadTexture('labyrinth_bg_tex','labyrinth_bg.png')
	LoadImage('labyrinth_bg','labyrinth_bg_tex',0,0,256,256)
	LoadTexture('bg_map_tex','bg_map.png')
	LoadImageGroup('bg_map','bg_map_tex',0,0,64,64,4,4)
	LoadImageFromFile('labyrinth_bg2','labyrinth_bg2.png')
	LoadImageFromFile('labyrinth_bg3','labyrinth_bg3.png')
	--set camera
	Set3D('eye',0.00,0.50,0.2)--3=-1.8
	Set3D('at',0.00,-0.40,1.1)
	Set3D('up',0.00,1.00,0.00)
	Set3D('fovy',1.57)
	Set3D('z',0.01,10.00)
	Set3D('fog',1.00,5.0,Color(100,10,10,50))
	self.sight={}
	for i=1,3 do self.sight[i]=lstg.view3d.at[i]-lstg.view3d.eye[i] end
	self.shining_num=ran:Int(1,8)
	--
	self.zos=0
	self.speed=0.015
	self.move=1
	--√‘π¨±Ì
	self.laby={}
	self.show={}
	for i=1,4 do self.laby[i]={} self.show[i]={} end
	for i=1,4 do
		for j=1,4 do
			self.laby[i][j]={}
			self.show[i][j]=false
		end
	end
	self.laby[1][1]={1,4}
	self.laby[1][2]={2,4}
	self.laby[1][3]={1,2,4}
	self.laby[1][4]={1,2}
	self.laby[2][1]={1,3,4}
	self.laby[2][2]={1,2,4}
	self.laby[2][3]={2,3,4}
	self.laby[2][4]={2,3}
	self.laby[3][1]={1,3}
	self.laby[3][2]={3,4}
	self.laby[3][3]={1,2,4}
	self.laby[3][4]={1,2}
	self.laby[4][1]={3,4}
	self.laby[4][2]={2,4}
	self.laby[4][3]={2,3,4}
	self.laby[4][4]={2,3}
	--pos=[posy][posx]
	self.posy=4 self.posx=2
	self.show[self.posy][self.posx]=true
	self.pos={}
	self.pos=self.laby[self.posy][self.posx]
	self.p_in=1               -- p_in = player_in
	self.p_out=3
	self.p_rot=1
	self.bgexit=8
	--
	self.change=false
	--
	labyrinth=self
	task.New(self,function()
		for _=1,99999 do
			for _=1,99999 do
				if self.change==true then break end
				task.Wait()
			end
			if self.p_out==2 then--360f
				for i=1,30 do self.speed=0.015-0.015*sin(i*3) task.Wait() end
				local z=-self.zos%2
				local eye=lstg.view3d.eye[3]
				task.New(self,function()
				for s=1/120,1+0.5/120,1/120 do
					if s<0.5 then s=s*s*2 else s=-2*s*s+4*s-1 end
					lstg.view3d.eye[3]=0.2+(1.8+6+z)*s task.Wait()
				end
				do return end
				end)
				task.Wait(60)
				for i=1,30 do self.sight[1]=-0.9*i/30 self.sight[2]=-0.9-0.5*i/30 task.Wait() end
				task.New(self,function()
				for i=1,30 do self.sight[3]=0.9-0.9*i/30 self.sight[2]=-1.4+0.5*i/30 task.Wait() end
				do return end
				end)
				for i=1,60 do lstg.view3d.eye[1]=(-4.2+z)*sin(i*1.5) task.Wait() end
				Set3D('eye',0.00,0.50,0.20)
				Set3D('at',0.00,-0.40,1.10)
				for i=1,3 do self.sight[i]=lstg.view3d.at[i]-lstg.view3d.eye[i] end
				for i=1,60 do self.speed=0.015*sin(i*1.5) task.Wait() end
			elseif self.p_out==4 then--240f+120
				for i=1,30 do self.speed=0.015-0.015*sin(i*3) task.Wait() end
				local z=-self.zos%2
				local eye=lstg.view3d.eye[3]
				task.New(self,function()
				for s=1/120,1+0.5/120,1/120 do
					if s<0.5 then s=s*s*2 else s=-2*s*s+4*s-1 end
					lstg.view3d.eye[3]=0.2+(1.8+6+z)*s task.Wait()
				end
				do return end
				end)
				task.Wait(60)
				for i=1,30 do self.sight[1]=0.9*i/30 self.sight[2]=-0.9-0.5*i/30 task.Wait() end
				task.New(self,function()
				for i=1,30 do self.sight[3]=0.9-0.9*i/30 self.sight[2]=-1.4+0.5*i/30 task.Wait() end
				do return end
				end)
				for i=1,60 do lstg.view3d.eye[1]=(4.2-z)*sin(i*1.5) task.Wait() end
				Set3D('eye',0.00,0.50,0.20)
				Set3D('at',0.00,-0.40,1.10)
				for i=1,3 do self.sight[i]=lstg.view3d.at[i]-lstg.view3d.eye[i] end
				for i=1,60 do self.speed=0.015*sin(i*1.5) task.Wait() end
			elseif self.p_out==3 then--270f+120
				for i=1,30 do self.speed=0.015-0.015*sin(i*3) task.Wait() end
				local z=-self.zos%2
				for s=1/180,1+0.5/180,1/180 do
					if s<0.5 then s=s*s*2 else s=-2*s*s+4*s-1 end
					lstg.view3d.eye[3]=0.2+12*s task.Wait()
				end
				Set3D('eye',0.00,0.50,0.20)
				Set3D('at',0.00,-0.40,1.10)
				for i=1,3 do self.sight[i]=lstg.view3d.at[i]-lstg.view3d.eye[i] end
				for i=1,60 do self.speed=0.015*sin(i*1.5) task.Wait() end
			end
			self.change=false
			self.p_out=(self.p_out-1+self.p_rot-1+4)%4+1
			if self.p_out==1 then self.posy=self.posy+1 end
			if self.p_out==2 then self.posx=self.posx-1 end
			if self.p_out==3 then self.posy=self.posy-1 end
			if self.p_out==4 then self.posx=self.posx+1 end
			self.show[self.posy][self.posx]=true
			self.pos=self.laby[self.posy][self.posx]
			self.p_rot=(self.p_out-1+4+2)%4+1
			self.bgexit=1
			for k=1,#(self.pos) do
				self.bgexit=self.bgexit*((self.pos[k]-1+1-self.p_rot+4)%4+1)
			end
		end
	end)
end

function labyrinth_background:frame()
	task.Do(self)
	for i=1,3 do
		local eye=lstg.view3d.eye[i]
		lstg.view3d.at[i]=eye+self.sight[i]
	end
		self.zos=self.zos+self.speed
end

function labyrinth_background:render()
	SetViewMode'3d'
	local showboss = IsValid(_boss)
	if showboss then
        PostEffectCapture()
    end
	RenderClear(lstg.view3d.fog[3])
	if self.timer%180<30 then
		SetImageState('labyrinth_bg','',Color(255,255,155+100*sin((self.timer%180)*3),155))
	elseif self.timer%180<60 then
		SetImageState('labyrinth_bg','',Color(255,255-100*sin((self.timer%180-30)*3),255,155))
	elseif self.timer%180<90 then
		SetImageState('labyrinth_bg','',Color(255,155,255,155+100*sin((self.timer%180-60)*3)))
	elseif self.timer%180<120 then
		SetImageState('labyrinth_bg','',Color(255,155,255-100*sin((self.timer%180-90)*3),255))
	elseif self.timer%180<150 then
		SetImageState('labyrinth_bg','',Color(255,155+100*sin((self.timer%180-120)*3),155,255))
	elseif self.timer%180<180 then
		SetImageState('labyrinth_bg','',Color(255,255,155,255-100*sin((self.timer%180-150)*3)))
	end
	local z=-self.zos%2
	if self.bgexit==2 or self.bgexit==6 or self.bgexit==8 or self.bgexit==24 then
		for dx=-10,-4,2 do--‘∂¥¶◊Û‘∂«Ω
		Render4V('labyrinth_bg',
				0+dx	,1	,10+z	,
				0+dx	,-1	,10+z	,
				2+dx	,-1	,10+z	,
				2+dx	,1	,10+z	)
		end
		for dx=0,6,2 do--‘∂¥¶◊Ûµÿ∞Â
		Render4V('labyrinth_bg',
				-4-dx	,-1	,8+z	,
				-4-dx	,-1	,10+z	,
				-2-dx	,-1	,10+z	,
				-2-dx	,-1	,8+z	)
		Render4V('labyrinth_bg',
				-4-dx	,-1	,8+z	,
				-4-dx	,-1	,6+z	,
				-2-dx	,-1	,6+z	,
				-2-dx	,-1	,8+z	)
		end
		for dx=0,6,2 do--‘∂¥¶◊ÛΩ¸«Ω
		Render4V('labyrinth_bg',
				-4-dx	,1	,6+z	,
				-4-dx	,-1	,6+z	,
				-2-dx	,-1	,6+z	,
				-2-dx	,1	,6+z	)
		end
	else
		for dz=6,8,2 do--◊Û∑‚«Ω
		Render4V('labyrinth_bg',
				-2	,1	,2+dz+z		,
				-2	,-1	,2+dz+z		,
				-2	,-1	,0+dz+z		,
				-2	,1	,0+dz+z		)
		end
	end

	if self.bgexit==4 or self.bgexit==8 or self.bgexit==12 or self.bgexit==24 then
		for dx=2,8,2 do--‘∂¥¶”“‘∂«Ω
		Render4V('labyrinth_bg',
				2+dx	,1	,10+z	,
				2+dx	,-1	,10+z	,
				0+dx	,-1	,10+z	,
				0+dx	,1	,10+z	)
		end
		for dx=0,6,2 do--‘∂¥¶”“µÿ∞Â
		Render4V('labyrinth_bg',
				4+dx	,-1	,8+z	,
				4+dx	,-1	,10+z	,
				2+dx	,-1	,10+z	,
				2+dx	,-1	,8+z	)
		Render4V('labyrinth_bg',
				4+dx	,-1	,8+z	,
				4+dx	,-1	,6+z	,
				2+dx	,-1	,6+z	,
				2+dx	,-1	,8+z	)
		end
		for dx=0,6,2 do--‘∂¥¶”“Ω¸«Ω
		Render4V('labyrinth_bg',
				4+dx	,1	,6+z	,
				4+dx	,-1	,6+z	,
				2+dx	,-1	,6+z	,
				2+dx	,1	,6+z	)
		end
	else
		for dz=6,8,2 do--”“∑‚«Ω
		Render4V('labyrinth_bg',
				2	,1	,2+dz+z		,
				2	,-1	,2+dz+z		,
				2	,-1	,0+dz+z		,
				2	,1	,0+dz+z		)
		end
	end
	if self.bgexit==3 or self.bgexit==6 or self.bgexit==12 then
		for dz=10,16,2 do--µÿ∞Â
		Render4V('labyrinth_bg',
				0	,-1	,2+dz+z		,
				2	,-1	,2+dz+z		,
				2	,-1	,0+dz+z		,
				0	,-1	,0+dz+z		)
		Render4V('labyrinth_bg',
				0	,-1	,2+dz+z		,
				-2	,-1	,2+dz+z		,
				-2	,-1	,0+dz+z		,
				0	,-1	,0+dz+z		)
		end
		for dz=10,16,2 do--«Ω
		Render4V('labyrinth_bg',
				2	,1	,2+dz+z		,
				2	,-1	,2+dz+z		,
				2	,-1	,0+dz+z		,
				2	,1	,0+dz+z		)
		Render4V('labyrinth_bg',
				-2	,1	,2+dz+z		,
				-2	,-1	,2+dz+z		,
				-2	,-1	,0+dz+z		,
				-2	,1	,0+dz+z		)
		end
	else
		for dx=-2,0,2 do--‘∂¥¶◊Û‘∂«Ω
		Render4V('labyrinth_bg',
				0+dx	,1	,10+z	,
				0+dx	,-1	,10+z	,
				2+dx	,-1	,10+z	,
				2+dx	,1	,10+z	)
		end
		for dx=0,2,2 do--‘∂¥¶”“‘∂«Ω
		Render4V('labyrinth_bg',
				2+dx	,1	,10+z	,
				2+dx	,-1	,10+z	,
				0+dx	,-1	,10+z	,
				0+dx	,1	,10+z	)
		end
	end
	for dz=-4,4,2 do--µÿ∞Â
		Render4V('labyrinth_bg',
				0	,-1	,2+dz+z		,
				2	,-1	,2+dz+z		,
				2	,-1	,0+dz+z		,
				0	,-1	,0+dz+z		)
		Render4V('labyrinth_bg',
				0	,-1	,2+dz+z		,
				-2	,-1	,2+dz+z		,
				-2	,-1	,0+dz+z		,
				0	,-1	,0+dz+z		)
	end
	if self.bgexit==2 then
		Render4V('labyrinth_bg2',
				0	,-1	,2+6+z		,
				-2	,-1	,2+6+z		,
				-2	,-1	,0+6+z		,
				0	,-1	,0+6+z		)
		Render4V('labyrinth_bg',
				0	,-1	,2+6+z		,
				2	,-1	,2+6+z		,
				2	,-1	,0+6+z		,
				0	,-1	,0+6+z		)
		Render4V('labyrinth_bg3',
				0	,-1	,2+8+z		,
				2	,-1	,2+8+z		,
				2	,-1	,0+8+z		,
				0	,-1	,0+8+z		)
		Render4V('labyrinth_bg',
				-2	,-1	,8+z	,
				-2	,-1	,10+z	,
				-0	,-1	,10+z	,
				-0	,-1	,8+z	)
	elseif self.bgexit==4 then
		Render4V('labyrinth_bg2',
				0	,-1	,2+6+z		,
				2	,-1	,2+6+z		,
				2	,-1	,0+6+z		,
				0	,-1	,0+6+z		)
		Render4V('labyrinth_bg',
				0	,-1	,2+6+z		,
				-2	,-1	,2+6+z		,
				-2	,-1	,0+6+z		,
				0	,-1	,0+6+z		)
		Render4V('labyrinth_bg3',
				0	,-1	,2+8+z		,
				-2	,-1	,2+8+z		,
				-2	,-1	,0+8+z		,
				0	,-1	,0+8+z		)
		Render4V('labyrinth_bg',
				2	,-1	,8+z	,
				2	,-1	,10+z	,
				0	,-1	,10+z	,
				0	,-1	,8+z	)
	elseif self.bgexit==3 then
		for dz=6,8,2 do--µÿ∞Â
		Render4V('labyrinth_bg',
				0	,-1	,2+dz+z		,
				2	,-1	,2+dz+z		,
				2	,-1	,0+dz+z		,
				0	,-1	,0+dz+z		)
		Render4V('labyrinth_bg',
				0	,-1	,2+dz+z		,
				-2	,-1	,2+dz+z		,
				-2	,-1	,0+dz+z		,
				0	,-1	,0+dz+z		)
		end
	elseif self.bgexit==8 then
		Render4V('labyrinth_bg',
				2	,-1	,8+z	,
				2	,-1	,10+z	,
				0	,-1	,10+z	,
				0	,-1	,8+z	)
		Render4V('labyrinth_bg',
				-2	,-1	,8+z	,
				-2	,-1	,10+z	,
				-0	,-1	,10+z	,
				-0	,-1	,8+z	)
		Render4V('labyrinth_bg2',
				2	,-1	,6+z	,
				2	,-1	,8+z	,
				0	,-1	,8+z	,
				0	,-1	,6+z	)
		Render4V('labyrinth_bg2',
				-2	,-1	,6+z	,
				-2	,-1	,8+z	,
				-0	,-1	,8+z	,
				-0	,-1	,6+z	)
	elseif self.bgexit==6 then
		for dz=6,8,2 do
		Render4V('labyrinth_bg',
				0	,-1	,2+dz+z		,
				2	,-1	,2+dz+z		,
				2	,-1	,0+dz+z		,
				0	,-1	,0+dz+z		)
		Render4V('labyrinth_bg2',
				0	,-1	,2+dz+z		,
				-2	,-1	,2+dz+z		,
				-2	,-1	,0+dz+z		,
				0	,-1	,0+dz+z		)
		end
	elseif self.bgexit==12 then
		for dz=6,8,2 do
		Render4V('labyrinth_bg',
				0	,-1	,2+dz+z		,
				-2	,-1	,2+dz+z		,
				-2	,-1	,0+dz+z		,
				0	,-1	,0+dz+z		)
		Render4V('labyrinth_bg2',
				0	,-1	,2+dz+z		,
				2	,-1	,2+dz+z		,
				2	,-1	,0+dz+z		,
				0	,-1	,0+dz+z		)
		end
	end

	for dz=-4,4,2 do--«Ω
		Render4V('labyrinth_bg',
				2	,1	,2+dz+z		,
				2	,-1	,2+dz+z		,
				2	,-1	,0+dz+z		,
				2	,1	,0+dz+z		)
		Render4V('labyrinth_bg',
				-2	,1	,2+dz+z		,
				-2	,-1	,2+dz+z		,
				-2	,-1	,0+dz+z		,
				-2	,1	,0+dz+z		)
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
