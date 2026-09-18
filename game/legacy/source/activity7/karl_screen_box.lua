--require karl_misc.lua

karl_screen_box={}

function karl_screen_box.new(xmin,ymin,xmax,ymax)
	local box={}
	box.xmin=xmin or -192
	box.ymin=ymin or -224
	box.xmax=xmax or 192
	box.ymax=ymax or 224
	setmetatable(box, {__index = karl_screen_box} )
	return box
end

function karl_screen_box:copy()
	return karl_screen_box.new(self.xmin,self.ymin,self.xmax,self.ymax)
end

function karl_screen_box:set_box_x(xmin,xmax)
	self.xmin=xmin
	self.xmax=xmax
end

function karl_screen_box:set_box_y(ymin,ymax)
	self.ymin=ymin
	self.ymax=ymax
end

function karl_screen_box:is_in_box(point)
	if point.x<=self.xmax and point.x>=self.xmin and point.y<=self.ymax and point.y>=self.ymin then
		return true
	else
		return false
	end
end

function karl_screen_box:in_box_area(point)
	local temp=1
	if point.x<self.xmin then
		temp=7
	elseif point.x<=self.xmax then
		temp=4
	end
	if point.y<self.ymin then
		temp=temp+2
	elseif point.y<=self.ymax then
		temp=temp+1
	end
	return temp
end

function karl_screen_box:set_obj_rebound_in_box_x(obj1,obj2)
	local xmin=self.xmin
	local x_border=(self.xmax-xmin)*2
	local x=obj1.x-xmin
	x=x-math.floor(x/x_border)*x_border
	if x>x_border*0.5 then
		x=x_border-x
		obj2.angle=180-obj1.angle
		obj2.vx=-obj1.vx
	else
		obj2.angle=obj1.angle
		obj2.vx=obj1.vx
	end
	obj2.x=x+xmin
end

function karl_screen_box:set_obj_rebound_in_box_y(obj1,obj2)
	local ymin=self.ymin
	local y_border=(self.ymax-ymin)*2
	local y=obj1.y-ymin
	y=y-math.floor(y/y_border)*y_border
	if y>y_border*0.5 then
		y=y_border-y
		obj2.angle=-obj1.angle
		obj2.vy=-obj1.vy
	else
		obj2.angle=obj1.angle
		obj2.vy=obj1.vy
	end
	obj2.y=y+ymin
end

function karl_screen_box:set_obj_rebound_in_box(obj1,obj2)
	self:set_obj_rebound_in_box_x(obj1,obj2)
	self:set_obj_rebound_in_box_y(obj1,obj2)
end

function karl_screen_box:rebound_in_box_x(obj)
	local temp={}
	self:set_obj_rebound_in_box_x(obj,temp)
	return temp
end

function karl_screen_box:rebound_in_box_y(obj)
	local temp={}
	self:set_obj_rebound_in_box_y(obj,temp)
	return temp
end

function karl_screen_box:rebound_in_box(obj)
	local temp={}
	self:set_obj_rebound_in_box(obj,temp)
	return temp
end

function karl_screen_box:set_bullet_rebound_in_box(bullet,set_x,set_y,set_rot,set_v)
	if set_x or set_y then
		local temp={angle=bullet.rot,vx=bullet.vx,vy=bullet.vy}
		if set_x then
			temp.x=bullet.x
			if set_y then
				temp.y=bullet.y
				self:set_obj_rebound_in_box(temp,temp)
			else
				self:set_obj_rebound_in_box_x(temp,temp)
			end
		else
			temp.y=bullet.y
			self:set_obj_rebound_in_box_y(temp,temp)
		end
		if set_x then
			bullet.x=temp.x
			if set_v then
				bullet.vx=temp.vx
			end
		end
		if set_y then
			bullet.y=temp.y
			if set_v then
				bullet.vy=temp.vy
			end
		end
		if set_rot then
			bullet.rot=temp.angle
		end
	end
end

function karl_screen_box:laser_intersection(point,angle)
end