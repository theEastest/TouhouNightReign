TDstage5bg=Class(object)

function TDstage5bg:init()
	background.init(self,false)
	--resource
	LoadImageFromFile('TDstage5a','TDstage5a.png')
	LoadImageFromFile('TDstage5b','TDstage5b.png')
	LoadImageFromFile('TDstage5c','TDstage5c.png')
	LoadImageFromFile('TDstage5d','TDstage5d.png')
	LoadImageFromFile('TDstage5e','TDstage5e.png')
	--
	--set 3d camera and fog
	Set3D('eye',0,7,0)
	Set3D('at',0.0,-1,0.2)
	Set3D('up',0,0,1)
	Set3D('z',1,22)
	Set3D('fovy',0.6)
	Set3D('fog',1,20,Color(100,40,20,98))
	-----
	self.tspeed=0.005
	self.tz=0
	self.an=0
	self.turnspeed=0.3
	self.da=0
end

function TDstage5bg:frame()
	self.tz=self.tz+self.tspeed
	self.an=self.an+self.turnspeed
	Set3D('up',0.1*sin(0.368*self.timer),0,1)
	if self.timer>180 then
		Set3D('at',0.5*sin(self.timer),-1,0.2)
	else
		Set3D('at',5*(self.timer-180)/180*cos(self.timer),-1,0.2)
	end
	if self.timer%1200==1199 then self.da=self.da+1 end
end

function TDstage5bg:render()
	local y=(self.timer/10)%480
	Render('TDstage5e',0,y)
	Render('TDstage5e',0,y-480)
	SetViewMode'3d'
	for j=-3,3 do
		local dz=2*j-math.mod(self.tz,6)
		TDstage5bg.renderfloor(2,self.an+(self.da+j)*45,2,0,0,dz)
	end
	SetViewMode'world'
	Render('TDstage5d',0,0)
end

function TDstage5bg.renderfloor(r,a,h,x,y,z)
	for i=0,7 do
		local an=(a+i*45)%360
		if an>=15 and an<=165 then
			Render4V('TDstage5a',x+r*cos(an+22.5),y+r*sin(an+22.5),z+0.5*h,x+r*cos(an-22.5),y+r*sin(an-22.5),z+0.5*h,
								x+r*cos(an-22.5),y+r*sin(an-22.5),z,x+r*cos(an+22.5),y+r*sin(an+22.5),z)
			if i%2==0 then
				Render4V('TDstage5b',x+r*cos(an+22.5),y+r*sin(an+22.5),z+h,x+r*cos(an-22.5),y+r*sin(an-22.5),z+h,
								x+r*cos(an-22.5),y+r*sin(an-22.5),z+0.5*h,x+r*cos(an+22.5),y+r*sin(an+22.5),z+0.5*h)
				Render4V('TDstage5c',x+r*cos(an+22.5),y+r*sin(an+22.5),z+h,x+r*cos(an-22.5),y+r*sin(an-22.5),z+h,
								x+r*cos(an-22.5),y+r*sin(an-22.5),z+0.5*h,x+r*cos(an+22.5),y+r*sin(an+22.5),z+0.5*h)
			else
				Render4V('TDstage5a',x+r*cos(an+22.5),y+r*sin(an+22.5),z+h,x+r*cos(an-22.5),y+r*sin(an-22.5),z+h,
								x+r*cos(an-22.5),y+r*sin(an-22.5),z+0.5*h,x+r*cos(an+22.5),y+r*sin(an+22.5),z+0.5*h)
			end
		end
	end
end

