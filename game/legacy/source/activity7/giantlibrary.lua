giantlibrary_background=Class(object)

function giantlibrary_background:init()
	--
	background.init(self,false)
	--
	LoadFX('distortion_colorburn','void_distortion_with_colorburn.fx')
	LoadImageFromFile('void_floor','void_floor.png')
	LoadImageFromFile('void_mask','void_mask.png')
	LoadImageFromFile('void_mask2','void_mask2.png')
	for i=1,8 do
		LoadImageFromFile('void_book'..i,'void_book'..i..'.png')
	end
	LoadTexture('void_wood_vertical','void_wood_vertical.png')
	LoadTexture('void_wood_horizonal','void_wood_horizonal.png')
	LoadImageFromFile('void_shadow','void_shadow.png')
	LoadImageFromFile('void_shadowc','void_shadowc.png')
	for i=0,4 do
		LoadImageFromFile('void_lamp'..i,'void_lamp'..i..'.png')
	end
	LoadImageFromFile('void_bigmisc','void_bigmisc.png')
	LoadImageFromFile('void_woodlongmisc','void_woodlongmisc.png')
	LoadImageFromFile('void_woodwidthmisc','void_woodwidthmisc.png')
	LoadImageFromFile('void_eyemisc','void_eyemisc.png')
	LoadImage('void_wood_long','void_wood_vertical',0,0,128,512)
	LoadImage('void_wood_width','void_wood_vertical',64,0,32,512) --l:w=4:1
	SetImageState('void_wood_width','mul+alpha',Color(255,200,200,200))
	LoadImage('void_wood_verylong','void_wood_horizonal',0,0,512,64)
	SetImageState('void_wood_verylong','mul+alpha',Color(255,200,200,200))
	--
	Set3D('eye',0,0.9,1) -- -0.09 to 0.09
	Set3D('at',0,0.5,3.5)
	Set3D('up',0,1,0)
	Set3D('fovy',0.35)
	Set3D('z',1,100)
	Set3D('fog',0.3,24.2,Color(255,0,0,0))
	--
	self.z=0
	self.mask_z=0
	self.mask2_z=0
	self.speed=0.01
	self.fogspeed1=self.speed*0.2
	self.fogspeed2=self.speed*0.6
	--
	self.list={}
	self.liststart=1
	self.listend=0
	self.interval=3
	self.md=self.interval
	--
	self.lamp_list={}
	self.lamp_liststart=1
	self.lamp_listend=0
	self.lamp_color=0
	self.lamp_mainbreath=0.5
	self.lamp_breath=0.5
	self.lamp_coloraphb=0.663	
	self.lamp_woodlongcoloraphb=0.789	
	self.lamp_woodwidthcoloraphb=0.15
	self.lamp_eyecoloraphb=0.3
	self.lamp_coloraph=self.lamp_coloraphb*self.lamp_breath
	self.lamp_woodlongcoloraph=self.lamp_woodlongcoloraphb*self.lamp_breath
	self.lamp_woodwidthcoloraph=self.lamp_woodwidthcoloraphb*self.lamp_breath
	self.lamp_eyecoloraphb=self.lamp_eyecoloraphb*self.lamp_breath
	self.lightcolorcbase={	{255,255,0,0}, --red --woodwidthcolor
							{255,255,127,0}, --orange
							{255,255,255,0}, --yellow
							{255,0,128,255}, --blue
							{255,0,255,0}} --green
	self.lamp_c={			Color(255,255*self.lamp_mainbreath,0,0), --red
							Color(255,255*self.lamp_mainbreath,127*self.lamp_mainbreath,0), --orange
							Color(255,255*self.lamp_mainbreath,255*self.lamp_mainbreath,0), --yellow
							Color(255,0,128*self.lamp_mainbreath,255*self.lamp_mainbreath), --blue
							Color(255,0,255*self.lamp_mainbreath,0)} --green
					
	self.lamp_colorlist={	Color(255,255*self.lamp_coloraph,0,0), --red
							Color(255,255*self.lamp_coloraph,127*self.lamp_coloraph,0), --orange
							Color(255,255*self.lamp_coloraph,255*self.lamp_coloraph,0), --yellow
							Color(255,0,128*self.lamp_coloraph,255*self.lamp_coloraph), --blue
							Color(255,0,255*self.lamp_coloraph,0)} --green
	self.lamp_woodlongcolorlist={	Color(255,255*self.lamp_woodlongcoloraph,0,0), --red
							Color(255,255*self.lamp_woodlongcoloraph,127*self.lamp_woodlongcoloraph,0), --orange
							Color(255,255*self.lamp_woodlongcoloraph,255*self.lamp_woodlongcoloraph,0), --yellow
							Color(255,0,128*self.lamp_woodlongcoloraph,255*self.lamp_woodlongcoloraph), --blue
							Color(255,0,255*self.lamp_woodlongcoloraph,0)} --green
	self.lamp_ww={	{255,255*self.lamp_woodwidthcoloraph,0,0}, --red --woodwidthcolor
					{255,255*self.lamp_woodwidthcoloraph,127*self.lamp_woodwidthcoloraph,0}, --orange
					{255,255*self.lamp_woodwidthcoloraph,255*self.lamp_woodwidthcoloraph,0}, --yellow
					{255,0,128*self.lamp_woodwidthcoloraph,255*self.lamp_woodwidthcoloraph}, --blue
					{255,0,255*self.lamp_woodwidthcoloraph,0}} --green
	self.lamp_interval=12
	self.lamp_md=self.lamp_interval
	--
	self.misccount=0
	--chase
	self.splayerx=player.x
	self.splayery=player.y
	--
	for i=1,2400 do giantlibrary_background.frame(self) end
	--
	giantlibrary=self
	--
	--New(camera_setter)
	--
end

function giantlibrary_background:frame()
	--
	self.splayerx=self.splayerx+(player.x-self.splayerx)*1/2
	self.splayery=self.splayery+(player.y-self.splayery)*1/2
	Set3D('eye',self.splayerx/((lstg.world.r-lstg.world.l)/2)*0.09,	(1-1/8.9/2)+1/8.9/2*self.splayery/((lstg.world.t-lstg.world.b)/2),	1)
	Set3D('at',self.splayerx/((lstg.world.r-lstg.world.l)/2)*0.09,(1-1/8.9/2-0.4)+1/8.9/2*self.splayery/((lstg.world.t-lstg.world.b)/2),3.5)
	--
	self.z=self.z-self.speed
	self.mask_z=self.mask_z-self.speed-self.fogspeed1
	self.mask2_z=self.mask2_z-self.speed-self.fogspeed2
	--
	self.lamp_mainbreath=0.7+0.3*sin(1.25*self.timer)
	self.lamp_breath=0.35+0.25*sin(1.25*self.timer)
	self.lamp_coloraph=self.lamp_coloraphb*self.lamp_breath
	self.lamp_woodlongcoloraph=self.lamp_woodlongcoloraphb*self.lamp_breath
	self.lamp_woodwidthcoloraph=self.lamp_woodwidthcoloraphb*self.lamp_breath
	self.lamp_c={			Color(255,255*self.lamp_mainbreath,0,0), --red
							Color(255,255*self.lamp_mainbreath,127*self.lamp_mainbreath,0), --orange
							Color(255,255*self.lamp_mainbreath,255*self.lamp_mainbreath,0), --yellow
							Color(255,0,128*self.lamp_mainbreath,255*self.lamp_mainbreath), --blue
							Color(255,0,255*self.lamp_mainbreath,0)} --green
	for i=0,4 do
		SetImageState('void_lamp'..i,'mul+alpha',self.lamp_c[i+1])
	end
	self.lamp_colorlist={	Color(255,255*self.lamp_coloraph,0,0), --red
							Color(255,255*self.lamp_coloraph,127*self.lamp_coloraph,0), --orange
							Color(255,255*self.lamp_coloraph,255*self.lamp_coloraph,0), --yellow
							Color(255,0,128*self.lamp_coloraph,255*self.lamp_coloraph), --blue
							Color(255,0,255*self.lamp_coloraph,0)} --green
	self.lamp_woodlongcolorlist={	Color(255,255*self.lamp_woodlongcoloraph,0,0), --red
							Color(255,255*self.lamp_woodlongcoloraph,127*self.lamp_woodlongcoloraph,0), --orange
							Color(255,255*self.lamp_woodlongcoloraph,255*self.lamp_woodlongcoloraph,0), --yellow
							Color(255,0,128*self.lamp_woodlongcoloraph,255*self.lamp_woodlongcoloraph), --blue
							Color(255,0,255*self.lamp_woodlongcoloraph,0)} --green
	self.lamp_ww={	{255,255*self.lamp_woodwidthcoloraph,0,0}, --red --woodwidthcolor
					{255,255*self.lamp_woodwidthcoloraph,127*self.lamp_woodwidthcoloraph,0}, --orange
					{255,255*self.lamp_woodwidthcoloraph,255*self.lamp_woodwidthcoloraph,0}, --yellow
					{255,0,128*self.lamp_woodwidthcoloraph,255*self.lamp_woodwidthcoloraph}, --blue
					{255,0,255*self.lamp_woodwidthcoloraph,0}} --green
	--
	self.md=self.md+self.speed
	if self.md>=self.interval then
		self.md=self.md-self.interval
		for i=1,16 do
			self.listend=self.listend+1
			self.list[self.listend]={'void_book'..ran:Int(1,8),21}
		end
	end
	for i=self.liststart,self.listend do
		self.list[i][2]=self.list[i][2]-self.speed
	end
	while true do
		if self.list[self.liststart][2]<-3 then
			self.list[self.liststart]=nil
			self.liststart=self.liststart+1
		else break
		end
	end
	--
	--
	self.lamp_md=self.lamp_md+self.speed
	if self.lamp_md>=self.lamp_interval then
		self.lamp_md=self.lamp_md-self.lamp_interval
		self.lamp_listend=self.lamp_listend+1
		self.lamp_color=(self.lamp_color+1)%5
		self.lamp_list[self.lamp_listend]={'void_lamp'..self.lamp_color,24,self.lamp_color+1}
	end
	for i=self.lamp_liststart,self.lamp_listend do
		self.lamp_list[i][2]=self.lamp_list[i][2]-self.speed
	end
	while true do
		if self.lamp_list[self.lamp_liststart][2]<-3 then
			self.lamp_list[self.lamp_liststart]=nil
			self.lamp_liststart=self.lamp_liststart+1
		else break
		end
	end
	--
end

function giantlibrary_background:render()
	SetViewMode'3d'
	local showboss = IsValid(_boss)
	if showboss then
        PostEffectCapture()
    end
	RenderClear(lstg.view3d.fog[3])
	local z=self.z%1
	local mz=self.mask_z%1
	local m2z=self.mask2_z%1
	
	for i=28,-1,-1 do --z way floor
		for j=-3,3,1 do --x way floor
			Render4V('void_floor',	j-0.5,0,z+1+i,
								j+0.5,0,z+1+i,
								j+0.5,0,z-0+i,
								j-0.5,0,z-0+i)
		end
	end
	for i=6,-1,-1 do --shadow
		local dz=self.z%3		
		local ss=0.06
		Render4V('void_shadow',		-0.25-2,0,dz+i*3+1, --b
								-0.25-2,0,dz+i*3+1+3*ss, 
								-0.25,0,dz+i*3+1+3*ss,	
								-0.25,0,dz+i*3+1) 
		Render4V('void_shadow',		-0.25,0,dz+i*3, --f
								-0.25,0,dz+i*3-3*ss, 
								-0.25-2,0,dz+i*3-3*ss,	
								-0.25-2,0,dz+i*3) 
		Render4V('void_shadow',		-0.25,0,dz+i*3+1, --r
								-0.25+ss,0,dz+i*3+1,
								-0.25+ss,0,dz+i*3,
								-0.25,0,dz+i*3)
		Render4V('void_shadowc',		-0.25,0,dz+i*3, --fr
								-0.25+ss,0,dz+i*3,
								-0.25+ss,0,dz+i*3-3*ss,
								-0.25,0,dz+i*3-3*ss)
		Render4V('void_shadowc',		-0.25,0,dz+i*3+1, --br
								-0.25,0,dz+i*3+1+3*ss,
								-0.25+ss,0,dz+i*3+1+3*ss,
								-0.25+ss,0,dz+i*3+1)
		
		--
		Render4V('void_shadow',		0.25+2,0,dz+i*3+1, --b
								0.25+2,0,dz+i*3+1+3*ss, 
								0.25,0,dz+i*3+1+3*ss,	
								0.25,0,dz+i*3+1) 
		Render4V('void_shadow',		0.25,0,dz+i*3, --f
								0.25,0,dz+i*3-3*ss, 
								0.25+2,0,dz+i*3-3*ss,	
								0.25+2,0,dz+i*3) 
		Render4V('void_shadow',		0.25,0,dz+i*3+1, --r
								0.25-ss,0,dz+i*3+1,
								0.25-ss,0,dz+i*3,
								0.25,0,dz+i*3)
		Render4V('void_shadowc',		0.25,0,dz+i*3, --fl
								0.25-ss,0,dz+i*3,
								0.25-ss,0,dz+i*3-3*ss,
								0.25,0,dz+i*3-3*ss)
		Render4V('void_shadowc',		0.25,0,dz+i*3+1, --bl
								0.25,0,dz+i*3+1+3*ss,
								0.25-ss,0,dz+i*3+1+3*ss,
								0.25-ss,0,dz+i*3+1)
		--
	end --shadow end
	for i=self.lamp_listend,self.lamp_liststart,-1 do --misc floor
		local lampit=12
		local dz=self.z%lampit
		SetImageState('void_bigmisc','mul+add',self.lamp_colorlist[self.lamp_list[i][3]])
		Render4V('void_bigmisc',		-2.5,0,self.lamp_list[i][2]+3, --5*5
								2.5,0,self.lamp_list[i][2]+3,
								2.5,0,self.lamp_list[i][2]-2,
								-2.5,0,self.lamp_list[i][2]-2)
	end
	for i=28,-1,-1 do --z way mask
		for j=-1,1,1 do --x way mask
			Render4V('void_mask',	j-0.5,0.05,mz+0.5+i,
								j+0.5,0.05,mz+0.5+i,
								j+0.5,0.05,mz-0.5+i,
								j-0.5,0.05,mz-0.5+i)
			Render4V('void_mask2',	j-0.5,0.1,m2z+0.5+i,
								j+0.5,0.1,m2z+0.5+i,
								j+0.5,0.1,m2z-0.5+i,
								j-0.5,0.1,m2z-0.5+i)					
		end
	end 
	--[[for i=6,-1,-1 do --wood start
		local dz=self.z%3	
		Render4V('wood_width',	-0.25,1.25,dz+i*3,
								-0.25-0.03125,1.25,dz+i*3,
								-0.25-0.03125,0,dz+i*3,
								-0.25,0,dz+i*3)
		
		--
		Render4V('wood_width',	0.25,1.25,dz+i*3,
								0.25+0.03125,1.25,dz+i*3,
								0.25+0.03125,0,dz+i*3,
								0.25,0,dz+i*3)
		--	
	end --wood end --]]
	for i=self.listend,self.liststart,-1 do --book
		local dz=self.z%3
		local a=i%4
		if a==0 then a=4 end
		local b=(((i-a+1)%16)-1)/4+1
		local c=math.ceil(i/16)
		if a<=2 then
			Render4V(self.list[i][1],	-0.28125-0.25-0.25*(a-1),	0.25+(b-1)*0.25,	self.list[i][2],
								-0.28125-0.25*(a-1),	0.25+(b-1)*0.25,	self.list[i][2],
								-0.28125-0.25*(a-1),	0.03125+(b-1)*0.25,	self.list[i][2],
								-0.28125-0.25-0.25*(a-1),	0.03125+(b-1)*0.25,	self.list[i][2])
			local maph=1-0.5*(a-1)
			local arraph=0
			if a==1 then
				Render4V('void_wood_width',		-0.25,			0.25+(b-1)*0.25,		self.list[i][2],
											-0.25-0.03125,	0.25+(b-1)*0.25,		self.list[i][2],
											-0.25-0.03125,	0+(b-1)*0.25,			self.list[i][2],
											-0.25,			0+(b-1)*0.25,			self.list[i][2])
				if b==4 then
				Render4V('void_book3',	-0.28125-0.25-0.25*(a-1),	0.25+(b)*0.25,	self.list[i][2],
								-0.28125-0.25*(a-1),	0.25+(b)*0.25,	self.list[i][2],
								-0.28125-0.25*(a-1),	0.03125+(b)*0.25,	self.list[i][2],
								-0.28125-0.25-0.25*(a-1),	0.03125+(b)*0.25,	self.list[i][2])
				Render4V('void_wood_verylong',	-0.28125,0.03125+b*0.25,self.list[i][2],
											-0.28125-1,0.03125+b*0.25,self.list[i][2],
											-0.28125-1,0+b*0.25,self.list[i][2],
											-0.28125,0+b*0.25,self.list[i][2])	
				Render4V('void_wood_width',		-0.25,			0.25+(b)*0.25,		self.list[i][2],
											-0.25-0.03125,	0.25+(b)*0.25,		self.list[i][2],
											-0.25-0.03125,	0+(b)*0.25,			self.list[i][2],
											-0.25,			0+(b)*0.25,			self.list[i][2])
				end
			end
			if a==2 then
				Render4V('void_wood_verylong',	-0.28125,	0.03125+(b-1)*0.25,self.list[i][2],
											-0.28125-1,	0.03125+(b-1)*0.25,self.list[i][2],
											-0.28125-1,	0+(b-1)*0.25,self.list[i][2],
											-0.28125,	0+(b-1)*0.25,self.list[i][2])	
			end
			if (math.floor((i-1)/16-1)-1)%4 ==0 or (math.floor((i-1)/16-1)+0)%4==0 then arraph=1 end
			local colv=((math.floor((i-1)/64)+1)%5)+1
			SetImageState('void_woodwidthmisc','mul+add',Color(	self.lamp_ww[colv][1], --a
															self.lamp_ww[colv][2]*maph*arraph,  --r
															self.lamp_ww[colv][3]*maph*arraph,  --g
															self.lamp_ww[colv][4]*maph*arraph))  --b
			Render4V('void_woodwidthmisc',		-0.25-0.28125-0.28125*(a-1),	0.25+(b-1)*0.25,	self.list[i][2],
								-0.25-0.28125*(a-1),	0.25+(b-1)*0.25,	self.list[i][2],
								-0.25-0.28125*(a-1),	0+(b-1)*0.25,	self.list[i][2],
								-0.25-0.28125-0.28125*(a-1),	0+(b-1)*0.25,	self.list[i][2])
			if a==1 then
				if b==4 then
				Render4V('void_woodwidthmisc',	-0.25-0.5,0.25+b*0.25,self.list[i][2],
											-0.25,0.25+b*0.25,self.list[i][2],
											-0.25,0+b*0.25,self.list[i][2],
											-0.25-0.5,0+b*0.25,self.list[i][2])	
				end
			end
		end
		if a>=3 then
			Render4V(self.list[i][1],	0.28125+0.25*(a-3),	0.25+(b-1)*0.25,	self.list[i][2],
								0.28125+0.25+0.25*(a-3),	0.25+(b-1)*0.25,	self.list[i][2],
								0.28125+0.25+0.25*(a-3),	0.03125+(b-1)*0.25,	self.list[i][2],
								0.28125+0.25*(a-3),	0.03125+(b-1)*0.25,	self.list[i][2])	
			local maph=1-0.5*(a-3)
			local arraph=0
			if a==3 then
				Render4V('void_wood_width',		0.25,			0.25+(b-1)*0.25,		self.list[i][2],
											0.25+0.03125,	0.25+(b-1)*0.25,		self.list[i][2],
											0.25+0.03125,	0+(b-1)*0.25,			self.list[i][2],
											0.25,			0+(b-1)*0.25,			self.list[i][2])
				if b==4 then
					Render4V('void_book3',	0.28125+0.25+0.25*(a-3),	0.25+(b)*0.25,	self.list[i][2],
								0.28125+0.25*(a-3),	0.25+(b)*0.25,	self.list[i][2],
								0.28125+0.25*(a-3),	0.03125+(b)*0.25,	self.list[i][2],
								0.28125+0.25+0.25*(a-3),	0.03125+(b)*0.25,	self.list[i][2])
					Render4V('void_wood_verylong',	0.28125,0.03125+b*0.25,self.list[i][2],
												0.28125+1,0.03125+b*0.25,self.list[i][2],
												0.28125+1,0+b*0.25,self.list[i][2],
												0.28125,0+b*0.25,self.list[i][2])	
					Render4V('void_wood_width',		0.25,			0.25+(b)*0.25,		self.list[i][2],
											0.25+0.03125,	0.25+(b)*0.25,		self.list[i][2],
											0.25+0.03125,	0+(b)*0.25,			self.list[i][2],
											0.25,			0+(b)*0.25,			self.list[i][2])
				end
			end
			if a==4 then
				Render4V('void_wood_verylong',	0.28125,0.03125+(b-1)*0.25,self.list[i][2],
											0.28125+1,0.03125+(b-1)*0.25,self.list[i][2],
											0.28125+1,0+(b-1)*0.25,self.list[i][2],
											0.28125,0+(b-1)*0.25,self.list[i][2])	
			end
			if (math.floor((i-1)/16-1)-1)%4 ==0 or (math.floor((i-1)/16-1)+0)%4==0 then arraph=1 end
			local colv=((math.floor((i-1)/64)+1)%5)+1
			SetImageState('void_woodwidthmisc','mul+add',Color(	self.lamp_ww[colv][1], --a
															self.lamp_ww[colv][2]*maph*arraph,  --r
															self.lamp_ww[colv][3]*maph*arraph,  --g
															self.lamp_ww[colv][4]*maph*arraph))  --b
			Render4V('void_woodwidthmisc',		0.25+0.28125+0.28125*(a-3),	0.25+(b-1)*0.25,	self.list[i][2],
								0.25+0.28125*(a-3),	0.25+(b-1)*0.25,	self.list[i][2],
								0.25+0.28125*(a-3),	0+(b-1)*0.25,	self.list[i][2],
								0.25+0.28125+0.28125*(a-3),	0+(b-1)*0.25,	self.list[i][2])
			if a==3 then
				if b==4 then
				Render4V('void_woodwidthmisc',	0.25+0.5,0.25+b*0.25,self.list[i][2],
											0.25,0.25+b*0.25,self.list[i][2],
											0.25,0+b*0.25,self.list[i][2],
											0.25+0.5,0+b*0.25,self.list[i][2])	
				end
			end
		end
	end
	for i=6,-1,-1 do --wood start
		local dz=self.z%3	
		Render4V('void_wood_long',	-0.25,1.25,dz+i*3, --l
								-0.25,1.25,dz+1+i*3,
								-0.25,0,dz+1+i*3,
								-0.25,0,dz+i*3)		
		--
		Render4V('void_wood_long',	0.25,1.25,dz+i*3, --r
								0.25,1.25,dz+1+i*3,
								0.25,0,dz+1+i*3,
								0.25,0,dz+i*3)
		--	
	end --wood end
	for i=self.lamp_listend,self.lamp_liststart,-1 do --misc woodlong
		local lampit=12
		local dz=self.z%lampit
		SetImageState('void_woodlongmisc','mul+add',self.lamp_woodlongcolorlist[self.lamp_list[i][3]])
		Render4V('void_woodlongmisc',		-0.25,1.25,self.lamp_list[i][2], 
										-0.25,1.25,self.lamp_list[i][2]+1,
										-0.25,0,self.lamp_list[i][2]+1,
										-0.25,0,self.lamp_list[i][2])
		Render4V('void_woodlongmisc',		0.25,1.25,self.lamp_list[i][2], 
										0.25,1.25,self.lamp_list[i][2]+1,
										0.25,0,self.lamp_list[i][2]+1,
										0.25,0,self.lamp_list[i][2])
	end
	for i=self.lamp_listend,self.lamp_liststart,-1 do
		local lampit=12
		local dz=self.z%lampit
		Render4V(self.lamp_list[i][1],	-0.25,0.8+0.0625*2,self.lamp_list[i][2]+0.5+0.0625*2, --l
										-0.25,0.8+0.0625*2,self.lamp_list[i][2]+0.5-0.0625*2,
										-0.25,0.8-0.0625*2,self.lamp_list[i][2]+0.5-0.0625*2,
										-0.25,0.8-0.0625*2,self.lamp_list[i][2]+0.5+0.0625*2)
		Render4V(self.lamp_list[i][1],	0.25,0.8+0.0625*2,self.lamp_list[i][2]+0.5+0.0625*2, --l
										0.25,0.8+0.0625*2,self.lamp_list[i][2]+0.5-0.0625*2,
										0.25,0.8-0.0625*2,self.lamp_list[i][2]+0.5-0.0625*2,
										0.25,0.8-0.0625*2,self.lamp_list[i][2]+0.5+0.0625*2)
		if abs(self.lamp_list[i][2]+0.5-1-12-1.5)<=2.5 then
			local d=abs(self.lamp_list[i][2]+0.5-1-12-1.5)
			local a=math.min(1,(2-d/2.5*2))*0.25
			SetImageState('void_eyemisc','mul+add',Color(self.lightcolorcbase[((i-1)%5)+1][1]*a*self.lamp_breath,
													self.lightcolorcbase[((i-1)%5)+1][2]*a*self.lamp_breath,
													self.lightcolorcbase[((i-1)%5)+1][3]*a*self.lamp_breath,
													self.lightcolorcbase[((i-1)%5)+1][4]*a*self.lamp_breath))
			SetViewMode'world'
			Render4V('void_eyemisc',	lstg.world.l-1,lstg.world.t+1,0.5,
								lstg.world.r+1,lstg.world.t+1,0.5,
								lstg.world.r+1,lstg.world.b-1,0.5,
								lstg.world.l-1,lstg.world.b-1,0.5)
			SetViewMode'3d'
		end
	end
	
	if showboss then
		local x,y = WorldToScreen(_boss.x,_boss.y)
		local x1 = x * screen.scale
		local y1 = (screen.height - y) * screen.scale
		local fxr = _boss.fxr or 163
		local fxg = _boss.fxg or 73
		local fxb = _boss.fxb or 164
		PostEffectApply("distortion_colorburn", "", {
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