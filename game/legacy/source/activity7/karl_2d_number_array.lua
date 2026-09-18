karl_2d_number_array={}

function karl_2d_number_array.new(n,m,k)
	local a={}
	setmetatable(a, {__index = karl_2d_number_array} )
	a.n=n
	a.m=m
	local i=1
	while i<=n do
		a[i]={}
		local j=1
		while j<=m do
			a[i][j]=k
			j=j+1
		end
		i=i+1
	end
	return a
end

function karl_2d_number_array:set_line_x(x,k)
	local i=1
	while i<=self.m do
		self[x][i]=k
		i=i+1
	end
end

function karl_2d_number_array:set_line_y(y,k)
	local i=1
	while i<=self.n do
		self[i][y]=k
		i=i+1
	end
end

function karl_2d_number_array:get(x,y)
	return self[x][y]
end

function karl_2d_number_array:spread(b,is_border,c,min,max)
	max=max or 1
	min=min or 0
	local s=1
	local n=self.n
	local m=self.m
	local start=0
	local tail=1
	if is_border then
		s=2
		n=n-1
		m=m-1
		start=-1
		tail=0
	end
	local i=s
	while i<=n do
		local j=s
		while j<=m do
			local p=start
			while p<=tail do
				local q=start
				while q<=tail do
					local temp=(b[i+p][j+q]-min)*c+self[i][j]
					if temp>max then
						temp=max
					end
					self[i][j]=temp
					q=q+1
				end
				p=p+1
			end
			j=j+1
		end
		i=i+1
	end
end