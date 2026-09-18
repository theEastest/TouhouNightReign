karl_float_timer={integer=0,small=0}

function karl_float_timer:new(start_time)
	start_time=start_time or 0
	local list={integer=0,small=start_time}
	setmetatable(list,self)
	self.__index=self
	return list
end

function karl_float_timer:wait(wait_time)
	self.small=self.small+wait_time
	local t=math.floor(self.small)
	self.integer=self.integer+t
	self.small=self.small-t
	task._Wait(t)
end

function karl_float_timer:get_small()
	return self.small
end

function karl_float_timer:get_integer()
	return self.integer
end

function karl_float_timer:get_time()
	return self.integer+self.small
end