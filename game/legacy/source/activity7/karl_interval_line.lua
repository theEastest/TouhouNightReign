karl_interval_line={}

function karl_interval_line:new(line_start,line_end)
	local obj={}
	setmetatable(obj, {__index = karl_interval_line})
	obj.line_start=line_start
	obj.line_end=line_end
	obj.line_length=line_end-line_start
	obj.error_length=obj.line_length*0.0000000001
	obj.head={}
	obj.tail={}
	obj.size=0
	return obj
end

function karl_interval_line:insert(head,tail)
	local size=self.size+1
	self.size=size
	self.head[size]=head
	self.tail[size]=tail
	self.line_length=self.line_length-tail+head
end

function karl_interval_line:get_position(length)
	length=length+self.line_start
	local size=self.size
	local head=self.head
	local tail=self.tail
	if head[1] and (head[1]==self.line_start or length>head[1]) then
		length=length-head[1]+tail[1]
	end
	local i=2
	while i<=size and length>head[i] do
		length=length-head[i]+tail[i]
		i=i+1
	end
	if length>=self.line_end-self.error_length then
		return nil
	else
		return length
	end
end

function karl_interval_line:get_random_position()
	return self:get_position(ran:Float(0,self.line_length))
end