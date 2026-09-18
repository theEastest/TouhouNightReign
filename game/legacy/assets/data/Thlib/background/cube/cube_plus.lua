cube_plus_background=Class(object)

function cube_plus_background:init()
	--
	background.init(self,false)
	--
	LoadImageFromFile('cube_plus','THlib\\background\\cube_plus\\cube_plus.png')
	--
	Set3D('eye',0,2.5,-3.8)
	Set3D('at',0,0,0)
	Set3D('up',-1,1,0)
	Set3D('z',1,100)
	Set3D('fovy',0.6)
	Set3D('fog',3,10,Color(0xff3d72be))
	--
	self.z=0
	self.timer=0
	self.timeradd=0.25
	self.eyey=0
	self.speed=0.01
	self.rotangle=45
	self.col={	37,69,115,	--cube 123
				0,0,0,	--fogcol intime 456
				0,0,0,	--fogcol min 789
				61,114,190}	--fogcol max 10,11,12
	self.colcodep={}
	self.colorcode={}
	cube_plus=self
	--
end

function cube_plus_background:frame()
	self.z=self.z+self.speed
	self.timer=self.timer+self.timeradd
	for i=4,6 do
		self.col[i]=(self.col[i+6]-self.col[i+3])/2*cos(self.timer+180)+(self.col[i+6]-self.col[i+3])/2
	end
	self.rotangle=self.rotangle+0.05
	self.eyey=self.rotangle
	Set3D('up',cos(0.5*self.rotangle),sin(0.5*self.rotangle),0)
	Set3D('eye',0.1*sin(12.5*self.rotangle-45),1.5*sin(self.eyey-45),-3.8)
	for i=1,6 do
		local hexacode=string.format('%#x',self.col[i])
		self.colcodep[i]=string.sub(hexacode,3,string.len(hexacode))
		if string.len(self.colcodep[i]) < 2 and string.len(self.colcodep[i]) > 0 then self.colcodep[i]='0'..self.colcodep[i] end
		if string.len(self.colcodep[i]) > 2 then
			if string.len(self.colcodep[i]) <= 3
				then self.colcodep[i]='FF'
			end
		end
		if string.len(self.colcodep[i]) > 3 or string.len(self.colcodep[i]) == 0 then self.colcodep[i]='00' end
	end
	self.colorcode[1]='0xff'..self.colcodep[1]..self.colcodep[2]..self.colcodep[3]
	self.colorcode[2]='0xff'..self.colcodep[4]..self.colcodep[5]..self.colcodep[6]
	SetImageState('cube_plus','mul+alpha',Color(self.colorcode[1]))
	Set3D('fog',3,10,Color(self.colorcode[2]))
end

function cube_plus_background:render()
	SetViewMode'3d'
	RenderClear(lstg.view3d.fog[3])
	local long = 1
	local st = 0.5
	for j=15,-2,-1 do
		for i=-2,2,1 do
			for k=0,1 do
				local dz=j*2-math.mod(self.z,2)
				local dy=i*2
				local dx=k*2
				if 1.5*sin(self.eyey-45) >= long+dy then
					-- bottom side --
					Render4V('cube_plus',	-(st+dx),0+dy,dz+long,
										-(st+long+dx),0+dy,dz+long,
										-(st+long+dx),0+dy,dz,
										-(st+dx),0+dy,dz
							)
					-- bottom side --
					Render4V('cube_plus',	-(st+dx),0+long+dy,dz,
										-(st+long+dx),0+long+dy,dz,
										-(st+long+dx),0+dy,dz,
										-(st+dx),0+dy,dz
							)
					Render4V('cube_plus',	-(st+dx),0+long+dy,dz,
										-(st+dx),0+long+dy,dz+long,
										-(st+dx),0+dy,dz+long,
										-(st+dx),0+dy,dz
							)
					-- top side --
					Render4V('cube_plus',	-(st+dx),0+long+dy,dz+long,
										-(st+long+dx),0+long+dy,dz+long,
										-(st+long+dx),0+long+dy,dz,
										-(st+dx),0+long+dy,dz
							)
					-- top side --
				end
				if 1.5*sin(self.eyey-45) >= dy and 1.5*sin(self.eyey-45) < long+dy then
					-- top side --
					Render4V('cube_plus',	-(st+dx),0+long+dy,dz+long,
										-(st+long+dx),0+long+dy,dz+long,
										-(st+long+dx),0+long+dy,dz,
										-(st+dx),0+long+dy,dz
							)
					-- top side --
					-- bottom side --
					Render4V('cube_plus',	-(st+dx),0+dy,dz+long,
										-(st+long+dx),0+dy,dz+long,
										-(st+long+dx),0+dy,dz,
										-(st+dx),0+dy,dz
							)
					Render4V('cube_plus',	-(st+dx),0+long+dy,dz,
										-(st+dx),0+long+dy,dz+long,
										-(st+dx),0+dy,dz+long,
										-(st+dx),0+dy,dz
							)
					-- bottom side --
					Render4V('cube_plus',	-(st+dx),0+long+dy,dz,
										-(st+long+dx),0+long+dy,dz,
										-(st+long+dx),0+dy,dz,
										-(st+dx),0+dy,dz
							)
				end
				if 1.5*sin(self.eyey-45) < dy then
					-- top side --
					Render4V('cube_plus',	-(st+dx),0+long+dy,dz+long,
										-(st+long+dx),0+long+dy,dz+long,
										-(st+long+dx),0+long+dy,dz,
										-(st+dx),0+long+dy,dz
							)
					-- top side --
					Render4V('cube_plus',	-(st+dx),0+long+dy,dz,
										-(st+long+dx),0+long+dy,dz,
										-(st+long+dx),0+dy,dz,
										-(st+dx),0+dy,dz
							)
					Render4V('cube_plus',	-(st+dx),0+long+dy,dz,
										-(st+dx),0+long+dy,dz+long,
										-(st+dx),0+dy,dz+long,
										-(st+dx),0+dy,dz
							)
					-- bottom side --
					Render4V('cube_plus',	-(st+dx),0+dy,dz+long,
										-(st+long+dx),0+dy,dz+long,
										-(st+long+dx),0+dy,dz,
										-(st+dx),0+dy,dz
							)
					-- bottom side --
				end
			end
		end
	end
	for j=15,-2,-1 do
		for i=-2,2,1 do
			for k=0,1 do
				local dz=j*2-math.mod(self.z,2)
				local dy=i*2
				local dx=k*2
				if 1.5*sin(self.eyey-45) >= long+dy then
					-- bottom side --
					Render4V('cube_plus',	(st+dx),0+dy,dz+long,
										(st+long+dx),0+dy,dz+long,
										(st+long+dx),0+dy,dz,
										(st+dx),0+dy,dz
							)
					-- bottom side --
					Render4V('cube_plus',	(st+dx),0+long+dy,dz,
										(st+long+dx),0+long+dy,dz,
										(st+long+dx),0+dy,dz,
										(st+dx),0+dy,dz
							)
					Render4V('cube_plus',	(st+dx),0+long+dy,dz,
										(st+dx),0+long+dy,dz+long,
										(st+dx),0+dy,dz+long,
										(st+dx),0+dy,dz
							)
					-- top side --
					Render4V('cube_plus',	(st+dx),0+long+dy,dz+long,
										(st+long+dx),0+long+dy,dz+long,
										(st+long+dx),0+long+dy,dz,
										(st+dx),0+long+dy,dz
							)
					-- top side --
				end
				if 1.5*sin(self.eyey-45) >= dy and 1.5*sin(self.eyey-45) < long+dy then
					-- top side --
					Render4V('cube_plus',	(st+dx),0+long+dy,dz+long,
										(st+long+dx),0+long+dy,dz+long,
										(st+long+dx),0+long+dy,dz,
										(st+dx),0+long+dy,dz
							)
					-- top side --
					-- bottom side --
					Render4V('cube_plus',	(st+dx),0+dy,dz+long,
										(st+long+dx),0+dy,dz+long,
										(st+long+dx),0+dy,dz,
										(st+dx),0+dy,dz
							)
					Render4V('cube_plus',	(st+dx),0+long+dy,dz,
										(st+dx),0+long+dy,dz+long,
										(st+dx),0+dy,dz+long,
										(st+dx),0+dy,dz
							)
					-- bottom side --
					Render4V('cube_plus',	(st+dx),0+long+dy,dz,
										(st+long+dx),0+long+dy,dz,
										(st+long+dx),0+dy,dz,
										(st+dx),0+dy,dz
							)
				end
				if 1.5*sin(self.eyey-45) < dy then
					-- top side --
					Render4V('cube_plus',	(st+dx),0+long+dy,dz+long,
										(st+long+dx),0+long+dy,dz+long,
										(st+long+dx),0+long+dy,dz,
										(st+dx),0+long+dy,dz
							)
					-- top side --
					Render4V('cube_plus',	(st+dx),0+long+dy,dz,
										(st+long+dx),0+long+dy,dz,
										(st+long+dx),0+dy,dz,
										(st+dx),0+dy,dz
							)
					Render4V('cube_plus',	(st+dx),0+long+dy,dz,
										(st+dx),0+long+dy,dz+long,
										(st+dx),0+dy,dz+long,
										(st+dx),0+dy,dz
							)
					-- bottom side --
					Render4V('cube_plus',	(st+dx),0+dy,dz+long,
										(st+long+dx),0+dy,dz+long,
										(st+long+dx),0+dy,dz,
										(st+dx),0+dy,dz
							)
					-- bottom side --
				end
			end
		end
	end
	SetViewMode'world'
end
