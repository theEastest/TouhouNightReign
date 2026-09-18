function karl_dot_product(x1,y1,x2,y2)
	return x1*x2+y1*y2
end

function karl_cross_product(x1,y1,x2,y2)
	return x1*y2-x2*y1
end

function karl_rotate_point(point,p1,p2)
	if not(p2) then
		p2=sin(p1)
		p1=cos(p1)
	end
	local temp=point.x*p2
	point.x=point.x*p1 - point.y*p2
	point.y=temp + point.y*p1
end
--直接更改点坐标，可以只填旋转角p1，或p1,p2分别填旋转角a的余弦正弦值

function karl_is_intersect(x1,y1,x2,y2,x3,y3,x4,y4)
	if karl_cross_product(x2-x1,y2-y1,x3-x1,y3-y1)*karl_cross_product(x2-x1,y2-y1,x4-x1,y4-y1)<0 then
		if karl_cross_product(x4-x3,y4-y3,x1-x3,y1-y3)*karl_cross_product(x4-x3,y4-y3,x2-x3,y2-y3)<0 then
			return true
		end
	end
	return false
end
--参数先后是一条直线的两个端点和另一条直线的两个端点

function karl_mix_loc(a1,a2,a3,p)
	local p2=1-p
	a1=a1*p2+a2*p
	a2=a2*p2+a3*p
	return a1*p2+a2*p
end

function karl_limit_in_box(obj,angle,x,y,a,b)
	local vx=cos(angle)
	local vy=sin(angle)
	x=obj.x-x
	y=obj.y-y
	local temp=karl_dot_product(x,y,vx,vy)
	local l=temp-a
	if l>0 then
		obj.x=obj.x-l*vx
		obj.y=obj.y-l*vy
	else
		l=temp+a
		if l<0 then
			obj.x=obj.x-l*vx
			obj.y=obj.y-l*vy
		end
	end
	temp=karl_dot_product(x,y,-vy,vx)
	l=temp-b
	if l>0 then
		obj.x=obj.x+l*vy
		obj.y=obj.y-l*vx
	else
		l=temp+b
		if l<0 then
			obj.x=obj.x+l*vy
			obj.y=obj.y-l*vx
		end
	end
end

function karl_is_in_box(obj,angle,x,y,a,b)
	local vx=cos(angle)
	local vy=sin(angle)
	x=obj.x-x
	y=obj.y-y
	local temp=karl_dot_product(x,y,vx,vy)
	if temp-a>=0 or temp+a<=0 then
		return false
	end
	temp=karl_dot_product(x,y,-vy,vx)
	if temp-b>=0 or temp+b<=0 then
		return false
	end
	return true
end

function karl_in_box_side(obj,angle,x,y,a,b)
	local vx=cos(angle)
	local vy=sin(angle)
	x=obj.x-x
	y=obj.y-y
	local temp=karl_dot_product(x,y,vx,vy)
	local side=nil
	local l=nil
	local l1=temp-a
	local l3=temp+a
	if l1>=0 then
		side=1
		l=l1
	elseif l3<=0 then
		side=3
		l=-l3
	end
	temp=karl_dot_product(x,y,-vy,vx)
	local l2=temp-b
	local l4=temp+b
	if l2>=0 and(l==nil or l2>l) then
		side=2
	elseif l4<=0 and(l==nil or -l4>l) then
		side=4
	end
	return side
end

function karl_is_in_circle(x,y,l)
	return x*x+y*y<l*l
end

function karl_fast_colli(obj,obj2)
	local x=obj.x-obj2.x
	local y=obj.y-obj2.y
	local dx=obj.dx-obj2.dx
	local dy=obj.dy-obj2.dy
	local r=obj.a
	if dx<=0 then
		if x>=r or x+r<=dx then
			return false
		end
	else
		if x>=r+dx or x<=-r then
			return false
		end
	end
	if dy<=0 then
		if y>=r or y+r<=dy then
			return false
		end
	else
		if y>=r+dy or y<=-r then
			return false
		end
	end	
	local a=x*x+y*y
	if a==0 then
		if r==0 then
			return false
		else
			return true
		end
	end
	local b=2*(x*dx+y*dy)
	local c=dx*dx+dy*dy
	local t=c-(b*b)/(4*a)
	if t>=1 then
		t=1
	elseif t<=0 then
		t=0
	end
	return karl_is_in_circle(x-dx*t,y-dy*t,obj.a)
end

function karl_AI_fly_rot(x,y,vx,vy,av,p)
	local l=hypot(x,y)
	local v=hypot(vx,vy)
	local vmax=sqrt(2*l*av)
	local s=math.abs(karl_dot_product(vx,vy,x,y)/l-vmax)+v*p
	local n=-1
	local a=0
	while(a<8)
	do
		local rot=a*45
		local vx2=vx+cos(rot)*av
		local vy2=vy+sin(rot)*av
		v=hypot(vx2,vy2)
		local temp=math.abs(karl_dot_product(vx2,vy2,x,y)/l-vmax)+v*p
		if temp<s then
			s=temp
			n=a
		end
		a=a+1
	end
	return n
end