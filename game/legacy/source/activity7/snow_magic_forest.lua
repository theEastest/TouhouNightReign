snow_magic_forest_background=Class(object)

function snow_magic_forest_background:init()
	--
	background.init(self,false)
	--resource
	LoadImageFromFile('snow_magic_forest_ground','ed-snow_ground.png')
	SetImageState('snow_magic_forest_ground','',Color(255/10,255,255,255))
	LoadImageFromFile('snow','ed-snow.png')
	SetImageState('snow','',Color(255/2,255,255,255))
	LoadImageFromFile('snow_magic_forest_clouds','ed-stage04a.png')
	LoadImageFromFile('snow_magic_forest_cloud','ed-stage04b.png')
	SetImageState('snow_magic_forest_clouds','',Color(0,255,255,255))
	LoadImageFromFile('snow_magic_forest_mountain','ed-stg4bg2.png')
	SetImageState('snow_magic_forest_mountain','',Color(0,255,255,255))
	LoadImageFromFile('tree1','ed-tree1.png')
	LoadImageFromFile('tree2','ed-tree2.png')
	SetImageState('tree1','',Color(255,255,255,255))
	SetImageState('tree2','',Color(255,255,255,255))
	LoadTexture('woods','ed-forest1.png')
	LoadImage('grass1','woods',0,0,512,256,0,0)
	LoadImage('grass2','woods',0,256,512,256,0,0)
	SetImageState('grass1','',Color(255*8/9,235,235,255))
	SetImageState('grass2','',Color(255*8/9,235,235,255))
	self.T=ran:Int(1,10)
	self.rot=ran:Float(0,360)
	self.time2=0
	self.time3=0
	self.layer=LAYER_TOP+100
	lstg.var.bgfly=false
	lstg.var.bgfly2=false
	--set 3d camera and fog
	Set3D('z',0.1,4.3)
	Set3D('eye',0,-1.6,0.4)
	Set3D('at',0,1.1,0)
	Set3D('up',0,0,1)
	Set3D('fovy',0.85)
	Set3D('fog',-2.0,-1.2,Color(255,0,0,0))
	--
	self.slist={}
	self.sliststart=1
	self.slistend=0
	self.rotlist={}
	self.list={}
	self.liststart=1
	self.listend=0
	self.imgs={'tree1','tree2','grass1','grass2'}
	self.clist={}
	self.cliststart=1
	self.clistend=0
	self.speed=0.007
	self.interval=0.1
	self.sinterval=0.02
	self.cinterval=0.15
	self.cloudalpha=0
	self.time=self.sinterval
	self.yos=self.interval
	self.acc=self.interval
	self.cacc=self.cinterval
	self.speedlist={}
	--New(camera_setter)
	for i=1,600 do snow_magic_forest_background.frame(self) end
end
	--需要用到的全局变量：lstg.var.bgfly lstg.var.bgfly2 在关卡开始前重置为false，需要用到时将lstg.var.bgfly 开启为true即可（lstg.var.bgfly2 会自动开启)）

rnd=math.random

function snow_magic_forest_background:frame()
    if KeyIsDown('shoot') then
	    self.timer=self.timer+2
		self.yos=self.yos+self.speed*2
		self.acc=self.acc+self.speed*2
		self.cacc=self.cacc+self.speed*2
		self.time=self.time+self.speed*2
	end
	self.yos=self.yos+self.speed
	self.acc=self.acc+self.speed
	self.cacc=self.cacc+self.speed
	self.time=self.time+self.speed
	if self.timer<=30 then
		Set3D('fog',-3.0,-2.2,Color(255,(255)*(sin(-90+180*self.timer/30)/2+1/2)+0*(1-(sin(-90+180*self.timer/30)/2+1/2)),(255)*(sin(-90+180*self.timer/30)/2+1/2)+0*(1-(sin(-90+180*self.timer/30)/2+1/2)),255*(sin(-90+180*self.timer/30)/2+1/2)+0*(1-(sin(-90+180*self.timer/30)/2+1/2))))
    end
	if self.timer<=240+30 and self.timer>=30 then
		Set3D('fog',1.1*((self.timer-30)/240)+-3.0*(1-(self.timer-30)/240),2.9*((self.timer-30)/240)-2.2*(1-(self.timer-30)/240),Color(255,255,255,255))
    end
    if lstg.var.bgfly then
	    Set3D('eye',0,-3.4*(sin(-90+180*self.time2/120)/2+1/2)-1.6*(1-(sin(-90+180*self.time2/120)/2+1/2)),2.2*(sin(-90+180*self.time2/120)/2+1/2)+0.4*(1-(sin(-90+180*self.time2/120)/2+1/2)))
		Set3D('at',0,1.5*(sin(-90+180*self.time2/120)/2+1/2)+1.1*(1-(sin(-90+180*self.time2/120)/2+1/2)),2.6*(sin(-90+180*self.time2/120)/2+1/2)-0*(1-(sin(-90+180*self.time2/120)/2+1/2)))
		self.speed=0.007*2*(sin(-90+180*self.time2/120)/2+1/2)+0.007*(1-(sin(-90+180*self.time2/120)/2+1/2))
		SetImageState('tree1','',Color(255*(1-self.time2/120),255,255,255))
		SetImageState('tree2','',Color(255*(1-self.time2/120),255,255,255))
		SetImageState('grass1','',Color(255*8/9*(1-self.time2/120),235,235,255))
		SetImageState('grass2','',Color(255*8/9*(1-self.time2/120),235,235,255))
		if self.time2<119 then
		    if KeyIsDown('shoot') then self.time2=self.time2+1/8*2 end
		    self.time2=self.time2+1/8
		else
		    self.time2=0
			lstg.var.bgfly=false
			lstg.var.bgfly2=0
		end
	end
	if lstg.var.bgfly2==0 then
	    Set3D('eye',0,-1.4*(sin(-90+180*self.time2/120)/2+1/2)-3.4*(1-(sin(-90+180*self.time2/120)/2+1/2)),1.4*(sin(-90+180*self.time2/120)/2+1/2)+2.2*(1-(sin(-90+180*self.time2/120)/2+1/2)))
		Set3D('at',0,1.5,0.4*(sin(-90+180*self.time2/120)/2+1/2)+2.6*(1-(sin(-90+180*self.time2/120)/2+1/2)))
		Set3D('fovy',0.6*(sin(-90+180*self.time2/120)/2+1/2)+0.85*(1-(sin(-90+180*self.time2/120)/2+1/2)))
		self.cloudalpha=(self.time2/120)
		Set3D('fog',1.1,2.9,Color(255,(195-75)*(sin(-90+180*self.time2/120)/2+1/2)+255*(1-(sin(-90+180*self.time2/120)/2+1/2)),(215-75)*(sin(-90+180*self.time2/120)/2+1/2)+255*(1-(sin(-90+180*self.time2/120)/2+1/2)),(235)*(sin(-90+180*self.time2/120)/2+1/2)+255*(1-(sin(-90+180*self.time2/120)/2+1/2))))
		if self.time2<119 then
		    if KeyIsDown('shoot') then self.time2=self.time2+1/3*2 end
		    self.time2=self.time2+1/3
		else
		    self.time2=0
			lstg.var.bgfly2=1
		end
	end
	if lstg.var.bgfly2==1 then
		Set3D('fog',1.1,3.4*(self.time2/120)+2.9*(1-self.time2/120),Color(255,195-75,215-75,235))
		SetImageState('snow_magic_forest_mountain','',Color(255/4*self.time2/120,255,255,255))
		SetImageState('snow_magic_forest_clouds','',Color(255/2*self.time2/120,255,255,255))
		if self.time2<119 then
		    if KeyIsDown('shoot') then self.time2=self.time2+1/3 end
		    self.time2=self.time2+1/3
		else
		    self.time2=0
			lstg.var.bgfly2=2
		end
	end
    if self.time>self.sinterval then
	    self.time=self.time-self.sinterval
		local x=ran:Float(-1,1)
	    local y=ran:Float(2.9,3.5)
	    local z=ran:Float(0.1,2.5)
		local rot=ran:Float(0,360)
		local zv=ran:Float(0.0001,0.005)
		local size=ran:Float(0.02,0.025)
		local omiga=ran:Sign()*ran:Float(1,3)
		self.slistend=self.slistend+1
		self.rotlist[self.slistend]={rot,omiga,x,y,z,size}
		self.slist[self.slistend]={zv,x-size*cos(self.rotlist[self.slistend][1]),y-size*sin(self.rotlist[self.slistend][1]),z+size,x+size*cos(self.rotlist[self.slistend][1]),y+size*sin(self.rotlist[self.slistend][1]),z+size,x+size*cos(self.rotlist[self.slistend][1]),y+size*sin(self.rotlist[self.slistend][1]),z-size,x-size*cos(self.rotlist[self.slistend][1]),y-size*sin(self.rotlist[self.slistend][1]),z-size}
	end
	if self.acc>=self.interval then
		self.acc=self.acc-self.interval
		self.listend=self.listend+1
		local x=ran:Float(0,1)
		self.list[self.listend]={rnd(3,4),0.5+x,3,0.2,0+x,3,0.2,0+x,3,-0.1,0.5+x,3,-0.1}
		local x2=ran:Float(0,1)
		self.listend=self.listend+1
		self.list[self.listend]={rnd(3,4),-(0.5+x2),3,0.2,-(0+x2),3,0.2,-(0+x2),3,-0.1,-(0.5+x2),3,-0.1}
		local x12=ran:Float(-0.1,0.1)
		local y=ran:Float(-0.1+0.2,0.1+0.2)
		local rot=ran:Float(-30,30)
		self.listend=self.listend+1
		self.list[self.listend]={rnd(3,4),0.25+x+x12+0.25*cos(rot),3,0.5+0.05+y+0.15*sin(rot),0.25+x+x12+0.25*cos(rot+90),3,0.5+0.05+y+0.15*sin(rot+90),0.25+x+x12+0.25*cos(rot+180),3,0.5+0.05+y+0.15*sin(rot+180),0.25+x+x12+0.25*cos(rot+270),3,0.5+0.05+y+0.15*sin(rot+270)}
		local x22=ran:Float(-0.1,0.1)
		local y=ran:Float(-0.1+0.2,0.1+0.2)
		self.listend=self.listend+1
		self.list[self.listend]={rnd(3,4),-(0.5+x2+x22),3,0.5+0.2+y,-(0+x2+x22),3,0.5+0.2+y,-(0+x2+x22),3,0.5-0.1+y,-(0.5+x2+x22),3,0.5-0.1+y}
		local x12=ran:Float(-0.1,0.1)
		local y=ran:Float(-0.1,0.1)
		self.listend=self.listend+1
		self.list[self.listend]={rnd(3,4),0.5+x+x12,3,1+0.2+y,0+x+x12,3,1+0.2+y,0+x+x12,3,1-0.1+y,0.5+x+x12,3,1-0.1+y}
		local x22=ran:Float(-0.1,0.1)
		local y=ran:Float(-0.1,0.1)
		self.listend=self.listend+1
		self.list[self.listend]={rnd(3,4),-(0.5+x2+x22),3,1+0.2+y,-(0+x2+x22),3,1+0.2+y,-(0+x2+x22),3,1-0.1+y,-(0.5+x2+x22),3,1-0.1+y}
		self.acc=self.acc-self.interval
		self.listend=self.listend+1
		self.list[self.listend]={rnd(1,2),0.7+x,3.1,1.5,0+x,3.1,1.5,0+x,3.1,0,0.7+x,3.1,0}
		self.listend=self.listend+1
		self.list[self.listend]={rnd(1,2),-(0.7+x2),3.1,1.5,-(0+x2),3.1,1.5,-(0+x2),3.1,0,-(0.7+x2),3.1,0}
	end
    if self.cacc>self.cinterval then
	    self.cacc=self.cacc-self.cinterval
		local x=ran:Float(-1,1)
	    local y=ran:Float(3,3.5)
	    local z=ran:Float(0.1,2)
		local rot=ran:Float(0,360)
		local alpha=0
		self.clistend=self.clistend+1
		self.clist[self.clistend]={alpha,x-cos(rot),y,z-sin(rot),x-cos(rot),y,z+sin(rot),x+cos(rot),y,z+sin(rot),x+cos(rot),y,z-sin(rot)}
	end
	for i=self.liststart,self.listend do
	    if KeyIsDown('shoot') then
		    self.list[i][3]=self.list[i][3]-self.speed*2
		    self.list[i][6]=self.list[i][6]-self.speed*2
		    self.list[i][9]=self.list[i][9]-self.speed*2
		    self.list[i][12]=self.list[i][12]-self.speed*2
		end
		self.list[i][3]=self.list[i][3]-self.speed
		self.list[i][6]=self.list[i][6]-self.speed
		self.list[i][9]=self.list[i][9]-self.speed
		self.list[i][12]=self.list[i][12]-self.speed
	end
	while true do
		if self.list[self.liststart][3]<-3 then
			self.list[self.liststart]=nil
			self.liststart=self.liststart+1
		else break
		end
	end
	for i=self.sliststart,self.slistend do
	    if KeyIsDown('shoot') then
			self.rotlist[i][4]=self.rotlist[i][4]-self.speed*2
			self.rotlist[i][5]=self.rotlist[i][5]-self.slist[i][1]*2
			self.rotlist[i][1]=self.rotlist[i][1]-self.rotlist[i][2]*2
			self.slist[i][2]=self.rotlist[i][3]-self.rotlist[i][6]*cos(self.rotlist[i][1])*2
			self.slist[i][3]=self.rotlist[i][4]-self.rotlist[i][6]*sin(self.rotlist[i][1])*2
			self.slist[i][4]=self.rotlist[i][5]+self.rotlist[i][6]*2
			self.slist[i][5]=self.rotlist[i][3]+self.rotlist[i][6]*cos(self.rotlist[i][1])*2
			self.slist[i][6]=self.rotlist[i][4]+self.rotlist[i][6]*sin(self.rotlist[i][1])*2
			self.slist[i][7]=self.rotlist[i][5]+self.rotlist[i][6]*2
			self.slist[i][8]=self.rotlist[i][3]+self.rotlist[i][6]*cos(self.rotlist[i][1])*2
			self.slist[i][9]=self.rotlist[i][4]+self.rotlist[i][6]*sin(self.rotlist[i][1])*2
			self.slist[i][10]=self.rotlist[i][5]-self.rotlist[i][6]*2
			self.slist[i][11]=self.rotlist[i][3]-self.rotlist[i][6]*cos(self.rotlist[i][1])*2
			self.slist[i][12]=self.rotlist[i][4]-self.rotlist[i][6]*sin(self.rotlist[i][1])*2
			self.slist[i][13]=self.rotlist[i][5]-self.rotlist[i][6]*2
		end
		self.rotlist[i][4]=self.rotlist[i][4]-self.speed
		self.rotlist[i][5]=self.rotlist[i][5]-self.slist[i][1]
		self.rotlist[i][1]=self.rotlist[i][1]-self.rotlist[i][2]
		self.slist[i][2]=self.rotlist[i][3]-self.rotlist[i][6]*cos(self.rotlist[i][1])
		self.slist[i][3]=self.rotlist[i][4]-self.rotlist[i][6]*sin(self.rotlist[i][1])
		self.slist[i][4]=self.rotlist[i][5]+self.rotlist[i][6]
		self.slist[i][5]=self.rotlist[i][3]+self.rotlist[i][6]*cos(self.rotlist[i][1])
		self.slist[i][6]=self.rotlist[i][4]+self.rotlist[i][6]*sin(self.rotlist[i][1])
		self.slist[i][7]=self.rotlist[i][5]+self.rotlist[i][6]
		self.slist[i][8]=self.rotlist[i][3]+self.rotlist[i][6]*cos(self.rotlist[i][1])
		self.slist[i][9]=self.rotlist[i][4]+self.rotlist[i][6]*sin(self.rotlist[i][1])
		self.slist[i][10]=self.rotlist[i][5]-self.rotlist[i][6]
		self.slist[i][11]=self.rotlist[i][3]-self.rotlist[i][6]*cos(self.rotlist[i][1])
		self.slist[i][12]=self.rotlist[i][4]-self.rotlist[i][6]*sin(self.rotlist[i][1])
		self.slist[i][13]=self.rotlist[i][5]-self.rotlist[i][6]
	end
	while true do
		if self.slist[self.sliststart][3]<-3 then
			self.slist[self.sliststart]=nil
			self.sliststart=self.sliststart+1
		else break
		end
	end
	for i=self.cliststart,self.clistend do
	    if KeyIsDown('shoot') then
			self.clist[i][3]=self.clist[i][3]-self.speed*2
		    self.clist[i][6]=self.clist[i][6]-self.speed*2
		    self.clist[i][9]=self.clist[i][9]-self.speed*2
		    self.clist[i][12]=self.clist[i][12]-self.speed*2
		    if self.clist[i][1]<1 then
		    	self.clist[i][1]=self.clist[i][1]+1/14*2
		    else
		    	self.clist[i][1]=1
		    end
		end

		self.clist[i][3]=self.clist[i][3]-self.speed*2
		self.clist[i][6]=self.clist[i][6]-self.speed*2
		self.clist[i][9]=self.clist[i][9]-self.speed*2
		self.clist[i][12]=self.clist[i][12]-self.speed*2
		if self.clist[i][1]<1 then
			self.clist[i][1]=self.clist[i][1]+1/14
		else
			self.clist[i][1]=1
		end
	end
	while true do
		if self.clist[self.cliststart][3]<-3 then
			self.clist[self.cliststart]=nil
			self.cliststart=self.cliststart+1
		else break
		end
	end
end

function snow_magic_forest_background:render()
	SetViewMode'3d'
	RenderClear(lstg.view3d.fog[3])
	local showboss = IsValid(_boss)
	if showboss then
        PostEffectCapture()
		RenderClear(lstg.view3d.fog[3])
    end

	local y=self.yos%1
	local y2=self.yos%2
	self.wy=y
    for i=-1,2 do
		Render4V('snow_magic_forest_clouds',-1,0-y2+i,0.02,-1,2-y2+i,0.02,1,2-y2+i,0.02,1,0-y2+i,0.02)
    end
	for i=-1,4 do
	    if lstg.var.bgfly2 and lstg.var.bgfly2>0 then
		    Render4V('snow_magic_forest_mountain',0,0-y+i,0.52,0,1-y+i,0.52,1,1-y+i,0.52,1,-y+i,0.52)
			Render4V('snow_magic_forest_mountain',-1,0-y+i,0.52,-1,1-y+i,0.52,0,1-y+i,0.52,0,-y+i,0.52)
			Render4V('snow_magic_forest_mountain',0+1,0-y+i,0.52,0+1,1-y+i,0.52,1+1,1-y+i,0.52,1+1,-y+i,0.52)
			Render4V('snow_magic_forest_mountain',-1+1,0-y+i,0.52,-1+1,1-y+i,0.52,0+1,1-y+i,0.52,0+1,-y+i,0.52)
			Render4V('snow_magic_forest_mountain',0-1,0-y+i,0.52,0-1,1-y+i,0.52,1-1,1-y+i,0.52,1-1,-y+i,0.52)
			Render4V('snow_magic_forest_mountain',-1-1,0-y+i,0.52,-1-1,1-y+i,0.52,0-1,1-y+i,0.52,0-1,-y+i,0.52)
		else
	    	Render4V('snow_magic_forest_ground',0,0-y+i,0,0,1-y+i,0,1,1-y+i,0,1,-y+i,0)
	    	Render4V('snow_magic_forest_ground',-1,0-y+i,0,-1,1-y+i,0,0,1-y+i,0,0,-y+i,0)
	    	Render4V('snow_magic_forest_ground',0+1,0-y+i,0,0+1,1-y+i,0,1+1,1-y+i,0,1+1,-y+i,0)
	    	Render4V('snow_magic_forest_ground',-1+1,0-y+i,0,-1+1,1-y+i,0,0+1,1-y+i,0,0+1,-y+i,0)
	    	Render4V('snow_magic_forest_ground',0-1,0-y+i,0,0-1,1-y+i,0,1-1,1-y+i,0,1-1,-y+i,0)
	    	Render4V('snow_magic_forest_ground',-1-1,0-y+i,0,-1-1,1-y+i,0,0-1,1-y+i,0,0-1,-y+i,0)
		end
	end
	if lstg.var.bgfly2 then
		for i=self.clistend,self.cliststart,-1 do
			local p=self.clist[i]
		    SetImageState('snow_magic_forest_cloud','',Color(255/10*p[1]*self.cloudalpha,255,255,255))
			Render4V('snow_magic_forest_cloud',p[2],p[3],p[4],p[5],p[6],p[7],p[8],p[9],p[10],p[11],p[12],p[13])
			--Render(self.imgs[1],0,0,0,1,1,0)
		end
	else
		for i=self.listend,self.liststart,-1 do
			local p=self.list[i]
			Render4V(self.imgs[p[1]],p[2],p[3],p[4],p[5],p[6],p[7],p[8],p[9],p[10],p[11],p[12],p[13])
			--Render(self.imgs[1],0,0,0,1,1,0)
		end
	end
	for i=self.slistend,self.sliststart,-1 do
		local p=self.slist[i]
		Render4V('snow',p[2],p[3],p[4],p[5],p[6],p[7],p[8],p[9],p[10],p[11],p[12],p[13])
		--Render(self.imgs[1],0,0,0,1,1,0)
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
