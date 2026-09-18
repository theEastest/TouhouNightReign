--requires karl_misc.lua

karl_2d_vector={}

function karl_2d_vector.new(x,y)
	local v = {}
	v.x = x or 0
	v.y = y or 0
	setmetatable(v, {__index = karl_2d_vector} )
	return v
end

function karl_2d_vector:set_xy(x,y)
	self.x=x
	self.y=y
end

function karl_2d_vector:set_da(d,angle)
	self.x=cos(angle)*d
	self.y=sin(angle)*d
end

function karl_2d_vector:copy()
	return karl_2d_vector.new(self.x,self.y)
end

function karl_2d_vector:add(vector)
	return karl_2d_vector.new(self.x+vector.x,self.y+vector.y)
end

function karl_2d_vector:multiply(n)
	return karl_2d_vector.new(self.x*n,self.y*n)
end

function karl_2d_vector:dot_product(vector)
	return self.x*vector.x+self.y*vector.y
end

function karl_2d_vector:cross_product(vector)
	return self.x*vector.y-vector.x*self.y
end

function karl_2d_vector:angle()
	return Angle(0,0,self.x,self.y)
end

function karl_2d_vector:length()
	return sqrt(self.x*self.x+self.y*self.y)
end

function karl_2d_vector:unitize()
	local temp=1/self:length()
	return karl_2d_vector.new(self.x*temp,self.y*temp)
end

function karl_2d_vector:transformation(vector)
	return karl_2d_vector.new(self.x*vector.x - self.y*vector.y, self.x*vector.y + self.y*vector.x)
end

function karl_2d_vector:rotate(angle)
	local vector=karl_2d_vector.new(cos(angle),sin(angle))
	return self:transformation(vector)
end