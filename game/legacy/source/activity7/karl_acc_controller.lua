karl_acc_controller={}

function karl_acc_controller.new(start_v)
	local list={}
	setmetatable(list, {__index = karl_acc_controller} )
	list.n=0
	list[1]=start_v or 0
	return list
end

function karl_acc_controller:add_speed(time,speed)
	self.n=self.n+1
	self[self.n*2]=time
	self[self.n*2+1]=speed
end

function karl_acc_controller:get_max()
	local i=1;
	local max_time=0
	while i<=self.n do
		max_time=max_time+self[i*2]
		i=i+1
	end
	return max_time
end

function karl_acc_controller:get_length(time)
	if time<0 then
		return time*self[1]
	end
	local i=1
	local length=0
	while i<=self.n do
		local t=self[2*i]
		local v1=self[2*i-1]
		local v2=self[2*i+1]
		if time>t then
			length=length+(v1+v2)*t*0.5
			time=time-t
		else
			if t==0 then
				return length
			else
				local v3=v1+(v2-v1)/t*time
				return length+(v1+v3)*time*0.5
			end
		end
		i=i+1
	end
	return length+time*self[2*i-1]
end