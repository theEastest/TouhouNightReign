XY_Midsummer_background=Class(object)

function XY_Midsummer_background:init()
	background.init(self,false)
	LoadImageFromFile('XY_Midsummer-cloud','XY_Midsummer-cloud.png')
	LoadImageFromFile('XY_Midsummer-cloud0','XY_Midsummer-cloud0.png')
	LoadImageFromFile('XY_Midsummer-vh','XY_Midsummer-vh.png')
	LoadImageFromFile('XY_Midsummer-vh0','XY_Midsummer-vh0.png')
	LoadImageFromFile('XY_Midsummer-sea','XY_Midsummer-sea.png')
	--set camera
	Set3D('eye',0.00,10.0,-2.00)
	Set3D('at',0.00,4.0,0.00)
	Set3D('up',0.00,0.00,0.50)
	Set3D('fovy',1.4)
	Set3D('z',0.1,50.00)
	Set3D('fog',6,18,Color(255,0,35,65))
	--
	self.zos=0
	self.speed=0.05
	self._x=0
	self.sp=0.015

	--New(camera_setter)
end

function XY_Midsummer_background:frame()
	self.zos=self.zos+self.speed
	self._x=self._x+self.sp
	if self.timer>0 then
		Set3D('eye',0+0.25*sin(self.timer/6),10.5+1.5*sin(self.timer/2.5),-3.5)
		Set3D('up',0+0.2*sin(self.timer/6),0.00,0.50)
		SetImageState('XY_Midsummer-vh0','mul+add',Color(155+100*sin(self.timer/0.3),255,255,150))
	end

	if self.timer<400 then
		Set3D('fog',-20+26*self.timer/399,0+18*self.timer/399,Color(255,0,35,65))
		Set3D('fovy',2-0.6*self.timer/399)
	end
	if self.timer>4800 and self.timer<5000 then
		Set3D('fog',6+3*(self.timer-4800)/199,18,Color(255,0+255*(self.timer-4800)/199,35+220*(self.timer-4800)/199,65))
		Set3D('at',0.00,4-2*(self.timer-4800)/199,0.00)
	end
end

function XY_Midsummer_background:render()
	RenderClear(lstg.view3d.fog[3])
	--Render('XY_Midsummer-sea',0,0)

	SetViewMode'3d'


	local z=self.zos%10
	local x=self._x%10
	for i=-10,20 do
		for o=-2,2 do
			Render4V('XY_Midsummer-vh',-5+o*10,3,-5-z+i*10,  5+o*10,3,-5-z+i*10,  5+o*10,3,5-z+i*10,  -5+o*10,3,5-z+i*10)
		end
	end
	for i=-10,20 do
		for o=-2,2 do
			Render4V('XY_Midsummer-vh0',-5+o*10,3.2,-5-z+i*10,  5+o*10,3.2,-5-z+i*10,  5+o*10,3.2,5-z+i*10,  -5+o*10,3.2,5-z+i*10)
		end
	end

	local z=self.zos%16
	local x=self._x%16
	for i=-10,15 do
	    for o=-1,1 do
			Render4V('XY_Midsummer-cloud0',8+o*16,3.1,-8-z+i*16,  -8+o*16,3.1,-8-z+i*16,  -8+o*16,3.1,8-z+i*16,  8+o*16,3.1,8-z+i*16)
	    end
	end
	for i=-10,15 do
	    for o=-1,1 do
			Render4V('XY_Midsummer-cloud',-8+o*16,6,-8-z+i*16,  8+o*16,6,-8-z+i*16,  8+o*16,6,8-z+i*16,  -8+o*16,6,8-z+i*16)
	    end
	end
	for i=-10,15 do
	    for o=-1,1 do
			Render4V('XY_Midsummer-cloud',8+o*16,7,-8-z+i*16,  -8+o*16,7,-8-z+i*16,  -8+o*16,7,8-z+i*16,  8+o*16,7,8-z+i*16)
	    end
	end
	SetViewMode'world'
end
