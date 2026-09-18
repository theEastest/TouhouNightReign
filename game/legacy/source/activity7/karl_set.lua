--¸Ä×ÔQueue.lua

karl_set = {}

function karl_set:insert(item)
	self[self.start+self.n]=item
	self.n = self.n + 1
end

function karl_set:get(index)
	return self[self.start+index-1]
end

function karl_set.new()
	local self = {}
	self.n = 0
	self.start = 0
	setmetatable(self,{__index = karl_set})
	return self
end

function karl_set:delete(index)
	local s=self.start
	local i=s+index-1
	local temp=self[i]
	self[i]=self[s]
	self[s]=nil
	self.start = self.start + 1
	self.n = self.n - 1
	return temp
end