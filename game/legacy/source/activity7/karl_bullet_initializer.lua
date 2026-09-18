--require karl_bullet_task.lua
--require karl_screen_box.lua

karl_bullet_initializer=karl_bullet_task.new()

function karl_bullet_initializer.new(style,color,bound,add_mode,stay,des,rot,omiga,navi)
	if style==nil then
		style=arrow_big
	end
	if color==nil then
		color=COLOR_RED
	end
	if bound==nil then
		bound=true
	end
	if stay==nil then
		stay=true
	end
	if des==nil then
		des=true
	end
	if navi==nil then
		navi=false
	end
	local obj=karl_bullet_task.new()
	obj.style=style
	obj.color=color
	obj.rot=rot or 0
	obj.omiga=omiga or 0
	obj.bound=bound
	obj.navi=navi
	if add_mode then
		obj.add_mode=add_mode
	else
		obj.add_mode=""
	end
	obj.stay=stay
	obj.des=des
	setmetatable(obj, {__index = karl_bullet_initializer})
	return obj
end

function karl_bullet_initializer:change_style_color(style,color)
	self.style=style
	self.color=color
end

function karl_bullet_initializer.set_bullet_v(bullet,v,angle,set_rot)
	if set_rot==nil then
		set_rot=true
	end
	if angle==nil then
		angle=bullet.rot
	end
	bullet.vx=v*cos(angle)
	bullet.vy=v*sin(angle)
	if set_rot then
		bullet.rot=angle
	end
end

function karl_bullet_initializer.set_bullet_a(bullet,a,angle)
	angle=angle or 270
	_set_a(bullet,a,angle,false)
end

function karl_bullet_initializer.set_bullet_timer(bullet,t)
	bullet.timer=t
end

function karl_bullet_task:set_bullet_bound(xmin,ymin,xmax,ymax)
	local screen=karl_screen_box.new(xmin,ymin,xmax,ymax)
	self:bullet_control("screen_bound_and_rebound_task",screen,true,false,false,false,false)
end

function karl_bullet_initializer:change_highlight(highlight)
	if highlight then
		self.add_mode="mul+add"
	else
		self.add_mode=""
	end
end

function karl_bullet_initializer:change_property(str,value)
	self[str]=value
end

function karl_bullet_initializer:copy()
	local bullet_initializer=self:bullet_task_copy()
	bullet_initializer.style=self.style
	bullet_initializer.color=self.color
	bullet_initializer.rot=self.rot
	bullet_initializer.omiga=self.omiga
	bullet_initializer.bound=self.bound
	bullet_initializer.add_mode=self.add_mode
	bullet_initializer.stay=self.stay
	bullet_initializer.des=self.des
	bullet_initializer.navi=self.navi
	setmetatable(bullet_initializer, {__index = karl_bullet_initializer})
	return bullet_initializer
end

function karl_bullet_initializer:set_bullet_style(bullet)
	ChangeBulletImage(bullet,self.style,self.color)
	_object.set_color(bullet,self.add_mode,255,255,255,255)
end

function karl_bullet_initializer:initialize_bullet(b,bullet_init)
	if bullet_init then
		bullet.init(b,self.style,self.color,self.stay,self.des)
	else
		ChangeBulletImage(b,self.style,self.color)
		b.stay=self.stay
		if self.des then b.group=GROUP_ENEMY_BULLET else b.group=GROUP_INDES end
	end
	b.bound=self.bound
	b.rot=self.rot
	b.omiga=self.omiga
	b.navi=self.navi
	_object.set_color(b,self.add_mode,255,255,255,255)
	self:set_bullet(b)
end