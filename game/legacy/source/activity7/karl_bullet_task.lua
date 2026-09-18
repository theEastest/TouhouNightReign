--require karl_set.lua

karl_bullet_task=karl_set.new()

function karl_bullet_task.new()
	local self=karl_set.new()
	setmetatable(self, {__index = karl_bullet_task})
	return self
end

function karl_bullet_task.exist_time_task(bullet,t,trigger_event)
	if trigger_event==nil then
		trigger_event=true
	end
	task.New(bullet,function()
		task._Wait(t)
		_del(bullet,trigger_event)
	end)
end

function karl_bullet_task.screen_bound_and_rebound_task(bullet,screen,trigger_event,...)
	bullet.bound=false
	if trigger_event==nil then
		trigger_event=true
	end
	local arg={...}
	task.New(bullet,function()
		while true do
			task.Wait(1)
			screen:set_bullet_rebound_in_box(bullet,unpack(arg))
			if screen:is_in_box(bullet)==false then
				_del(bullet,trigger_event)
			end
		end
	end)
end

function karl_bullet_task.delay_appear_bullet_task(bullet,t,add_mode,change_colli)
	bullet.hide=true
	if change_colli==nil then
		change_colli=true
	end
	if change_colli then
		bullet.colli=false
	end
	task.New(bullet,function()
		bullet.hide=false
		local i=1
		local b=255/t
		while i<=t do
			_object.set_color(bullet,add_mode,i*b,255,255,255)
			i=i+1
          			task._Wait(1)
		end
		_object.set_color(bullet,add_mode,255,255,255,255)
		if change_colli then
			bullet.colli=true
		end
	end)
end

function karl_bullet_task.acc_bullet_task(bullet,acc_controller,angle,start_time,set_rot)
	angle=angle or bullet.rot
	if set_rot or set_rot==nil then
		bullet.rot=angle
	end
	local x=bullet.x
	local y=bullet.y
	local t=start_time or 0
	local l=acc_controller:get_length(t)
	bullet.x=x+l*cos(angle)
	bullet.y=y+l*sin(angle)
	task.New(bullet,function()
		while true do
			t=t+1
			l=acc_controller:get_length(t)
			bullet.x=x+l*cos(angle)
			bullet.y=y+l*sin(angle)
			task.Wait(1)
		end
	end)
end

function karl_bullet_task:find_str(str)
	local i=1
	local n=self.n
	while i<=n do
		local t=self:get(i)
		if t[1]==str then
			return t
		end
		i=i+1
	end
	return nil
end

function karl_bullet_task:bullet_control_parameter(str,n,p)
	local t=self:find_str(str)
	if t then
		t[2][n]=p
		return true
	else
		return false
	end
end

function karl_bullet_task:bullet_control(str,...)
	local t=self:find_str(str)
	if t then
		t[2]={...}
		return true
	else
		self:insert({str,{...}})
		return false
	end
end
--返回true表明是复写设置，返回false表明是初次设置

function karl_bullet_task:bullet_task_copy()
	local bullet_task=karl_bullet_task.new()
	local i=1
	local n=self.n
	while i<=n do
		local t=self:get(i)
		bullet_task:bullet_control(t[1],unpack(t[2]))
		i=i+1
	end
	return bullet_task
end

function karl_bullet_task:set_bullet(bullet)
	local i=1
	local n=self.n
	while i<=n do
		local t=self:get(i)
		self[t[1]](bullet,unpack(t[2]))
		i=i+1
	end
end

function karl_bullet_task:connect_bullet_to_bullet(bullet_m,bullet_s,connect_death,connect_position,trigger_event)
	if trigger_event==nil then
		trigger_event=true
	end
	if connect_death and connect_position then
		task.New(bullet_s,function()
			while true do
				if IsValid(bullet_m) then
					bullet_s.x=bullet_m.x
					bullet_s.y=bullet_m.y
				else
					_del(bullet_s,trigger_event)
				end
				task._Wait(1)
			end
		end)
	elseif connect_death then
		task.New(bullet_s,function()
			while true do
				if IsValid(bullet_m)==false then
					_del(bullet_s,trigger_event)
				end
				task._Wait(1)
			end
		end)
	elseif connect_position then
		task.New(bullet_s,function()
			while true do
				if IsValid(bullet_m) then
					bullet_s.x=bullet_m.x
					bullet_s.y=bullet_m.y
				else
					break
				end
				task._Wait(1)
			end
		end)
	end
end