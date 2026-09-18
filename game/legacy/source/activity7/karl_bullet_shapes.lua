--requires karl_misc.lua
--requires karl_2d_vector.lua
--requires karl_set.lua

karl_bullet_shape=karl_set.new()

function karl_bullet_shape.new()
	local self=karl_set.new()
	setmetatable(self, {__index = karl_bullet_shape})
	return self
end

function karl_bullet_shape:size()
	return self.n
end

function karl_bullet_shape:skip(number)
	if number>self.n then
		number=self.n
	end
	while number>0 do
		self:delete(1)
		number=number-1
	end
end

function karl_bullet_shape:x_flip_over(sym_x)
	sym_x=sym_x or 0
	local i=1
	while i<=self.n do
		local pos=self:get(i)
		pos.x=sym_x*2-pos.x
		pos.angle=180-pos.angle
		i=i+1
	end
	return self
end

function karl_bullet_shape:rotate(angle)
	angle=angle or 0
	local i=1
	while i<=self.n do
		local pos=self:get(i)
		karl_rotate_point(pos,cos(angle),sin(angle))
		pos.angle=pos.angle+angle
		i=i+1
	end
	return self
end

function karl_bullet_shape:translate(x,y)
	x=x or 0
	y=y or 0
	local i=1
	while i<=self.n do
		local pos=self:get(i)
		pos.x=pos.x+x
		pos.y=pos.y+y
		i=i+1
	end
	return self
end

function karl_bullet_shape:rotate_then_translate(angle,x,y)
	x=x or 0
	y=y or 0
	angle=angle or 0
	local i=1
	while i<=self.n do
		local pos=self:get(i)
		karl_rotate_point(pos,cos(angle),sin(angle))
		pos.angle=pos.angle+angle
		pos.x=pos.x+x
		pos.y=pos.y+y
		i=i+1
	end
	return self
end

function karl_bullet_shape:add_bullet(pos)
	local pos_b={x=pos.x,y=pos.y,angle=pos.angle,v=pos.v}
	self:insert(pos_b)
end

function karl_bullet_shape:add_shape(shape)
	local i=1
	local n=shape.n
	while i<=n do
		self:add_bullet(shape:get(i))
		i=i+1
	end
end

function karl_bullet_shape:copy(start,tail)
	local shape=karl_bullet_shape.new()
	tail=tail or self.n
	if tail>self.n then
		tail=self.n
	end
	local i=start or 1
	if i<1 then
		i=1
	end
	while i<=tail do
		shape:add_bullet(self:get(i))
		i=i+1
	end
	return shape
end

function karl_bullet_shape:shoot(shoot_bullet)
	local i=1
	while i<=self.n do
		local pos=self:get(i)
		shoot_bullet(pos.x,pos.y,pos.angle,pos.v)
		i=i+1
	end
end
--x,y为发弹点坐标偏移，angle为发射方向，shoot_bullet是一个接受x,y,angle作为参数并发射一个弹幕的函数

function karl_bullet_shape:line_box_cut(minx,miny,maxx,maxy)
	local i=1
	while i<=self.n do
		local pos=self:get(i)
		local x1=pos.x
		local y1=pos.y
		local x2=x1+pos.v*cos(pos.angle)
		local y2=y1+pos.v*sin(pos.angle)
		if x1<minx or x1>maxx or x2<minx or x2>maxx or y1<miny or y1>maxy or y2<miny or y2>maxy then
			self:delete(i)
		else
			i=i+1
		end
	end
end

function karl_bullet_shape:tessellation_rotate(v1,v2,unit_shape,center,minx,miny,maxx,maxy,angle)
	unit_shape=unit_shape:copy()
	local temp=90-v1:angle()
	angle=angle-temp
	v1=v1:rotate(temp)
	v2=v2:rotate(temp)
	unit_shape:rotate(temp)
	local x1=minx-center.x
	local x2=maxx-center.x
	local y1=miny-center.y
	local y2=maxy-center.y
	local p1=karl_2d_vector.new(x1,y1):rotate(-angle)
	local p2=karl_2d_vector.new(x1,y2):rotate(-angle)
	local p3=karl_2d_vector.new(x2,y1):rotate(-angle)
	local p4=karl_2d_vector.new(x2,y2):rotate(-angle)
	local min=math.min
	local max=math.max
	x1=min(p1.x,p2.x,p3.x,p4.x)
	x2=max(p1.x,p2.x,p3.x,p4.x)
	y1=min(p1.y,p2.y,p3.y,p4.y)
	y2=max(p1.y,p2.y,p3.y,p4.y)
	if v2.x<0 then
		v2.x=-v2.x
		v2.y=-v2.y
	end
	local floor=math.floor
	local ceil=math.ceil
	local i=floor(x1/v2.x)
	local maxi=ceil(x2/v2.x)
	while i<=maxi do
		local base_y=v2.y*i
		local j=floor((y1-base_y)/v1.y)
		local maxj=ceil((y2-base_y)/v1.y)
		while j<=maxj do
			self:add_shape(unit_shape:copy():translate(v2.x*i,base_y+v1.y*j))
			j=j+1
		end
		i=i+1
	end
	self:rotate_then_translate(angle,center.x,center.y)
	self:line_box_cut(minx,miny,maxx,maxy)
end
--将unit_shape中心在对于所有整数n,m，n*v1+m*v2的位置上密铺并逆时针旋转angle°并平移(center.x,center.y)后将所有不在区域内的线段筛掉

------------------------以下为生成特定形状的代码------------------------

function karl_bullet_shape:sector_shape(a1,a2,a3,l,v,n)
	local i=0
	local temp=a1
	while i<n do
		local pos={}
		pos.x=cos(temp)*l
		pos.y=sin(temp)*l
		pos.angle=temp+a3
		pos.v=v
		self:add_bullet(pos)
		i=i+1
		temp=temp+a2
	end
end
--把子弹按扇形排好

function karl_bullet_shape:sector_shape_v2(a1,a2,a3,l,unit_shape,n)
	local i=0
	local temp=a1
	while i<n do
		self:add_shape(unit_shape:copy():rotate_then_translate(temp+a3,cos(temp)*l,sin(temp)*l))
		i=i+1
		temp=temp+a2
	end
end
--把一个karl_bullet_shape对象的复制按扇形排好

function karl_bullet_shape:random_group_shape(n,l1,l2,v)
	local angle=0
	local da=360/n
	local points={}
	local count=1
	while count<=n do
		local l=sqrt(ran:Float(l1*l1,l2*l2))
		points[count]={x=cos(angle)*l,y=sin(angle)*l}
		angle=angle+da
		count=count+1
	end
	local i=1
	while i<n do
		local x1=points[i].x
		local y1=points[i].y
		local j=i+1
		while j<=n do
			local x2=points[j].x
			local y2=points[j].y
			local pos={}
			pos.x=(x1+x2)*0.5
			pos.y=(y1+y2)*0.5
			pos.angle=Angle(x1,y1,x2,y2)
			pos.v=v
			self:add_bullet(pos)
			pos.angle=pos.angle+180
			self:add_bullet(pos)
			pos=nil
			j=j+1
		end
		i=i+1
	end
end

function karl_bullet_shape:hexagon_diamond_tessellation(radius,flip,center,minx,miny,maxx,maxy,angle)
	local unit_shape=karl_bullet_shape.new()
	unit_shape:sector_shape(90,60,120,radius,radius,6)
	unit_shape:sector_shape(90,120,0,radius,radius,3)
	unit_shape:add_shape(unit_shape:copy():rotate_then_translate(180,-sqrt(3)*0.5*radius,2.5*radius))
	local v1=karl_2d_vector.new(sqrt(3)*0.5*radius,4.5*radius)
	local v2=karl_2d_vector.new(sqrt(3)*2.5*radius,1.5*radius)
	self:tessellation_rotate(v1,v2,unit_shape,center,minx,miny,maxx,maxy,angle)
	if flip then
		self:x_flip_over()
	end
end

function karl_bullet_shape:triangle_square_octagon_tessellation(radius,center,minx,miny,maxx,maxy,angle)
	local big_unit_shape=karl_bullet_shape.new()
	local unit_shape=karl_bullet_shape.new()
	unit_shape:sector_shape(120,60,120,radius,radius,5)
	--unit_shape:sector_shape(0,120,0,0,radius,3)
	big_unit_shape:sector_shape_v2(90,60,-90,(sqrt(3)*0.5+tan(75)*0.5)*radius,unit_shape,6)
	unit_shape=karl_bullet_shape.new()
	unit_shape:sector_shape(45,180,135,sqrt(2)*0.5*radius,radius,2)
	big_unit_shape:sector_shape_v2(60,60,90,(0.5+tan(75)*0.5)*radius,unit_shape,6)
	unit_shape:sector_shape(135,180,135,sqrt(2)*0.5*radius,radius,2)
	local l=(0.5+sqrt(3)+tan(75)*0.5)*radius
	big_unit_shape:sector_shape_v2(30,60,0,l,unit_shape,3)
	l=l*2
	local v1=karl_2d_vector.new(0,l)
	local v2=karl_2d_vector.new(l*cos(30),l*sin(30))
	self:tessellation_rotate(v1,v2,big_unit_shape,center,minx,miny,maxx,maxy,angle)
end

function karl_bullet_shape:cirno_tessellation(radius,center,minx,miny,maxx,maxy,angle,length)
	local unit_shape=karl_bullet_shape.new()
	unit_shape:sector_shape(90,60,120,radius*2,radius,6)
	unit_shape:sector_shape(90,60,-120,radius*2,radius,6)
	unit_shape:sector_shape(150,-60,-120,radius,radius,5)
	unit_shape:sector_shape(30,120,0,0,radius,2)
	local l=2*sqrt(3)*radius+length
	local v1=karl_2d_vector.new(l*cos(60),l*sin(60))
	local v2=karl_2d_vector.new(l,0)
	self:tessellation_rotate(v1,v2,unit_shape,center,minx,miny,maxx,maxy,angle)
end