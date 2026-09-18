--require karl_set.lua
--require karl_nointersection_generation.lua

karl_nointersection_generation_v2={}

function karl_nointersection_generation_v2.new(line_start,line_end,loop)
	local self={}
	setmetatable(self, {__index = karl_nointersection_generation_v2})
	self.line_start=line_start
	self.line_end=line_end
	if loop==nil then
		loop=false
	end
	self.loop=loop
	self.n=0
	self.r1={}
	self.r2={}
	self.tl={}
	self.rh=0
	self.length={}
	self.bullet_number={}
	self.next_bullet={}
	self.bullet={}
	return self
end

function karl_nointersection_generation_v2:go_through(length)
	local i=1
	local process_bullet=karl_set.new()
	while i<=self.n do
		local l=length
		local b=self.bullet[i]
		local nb=self.next_bullet[i]
		local gl=self.length[i]
		local tl=self.tl[i]
		local tl2=self.tl[i+1]
		if tl2==nil then
			tl2=0
		end
		local r1=self.r1[i]
		while process_bullet.n>0 do
			b:insert(process_bullet:delete(1))
		end
		while true do
			local ps=nil
			local generator=karl_nointersection_generation.new(self.line_start,self.line_end,self.loop)
			if l>=nb then
				ps=nb
			else
				ps=l
			end
			l=l-ps
			nb=nb-ps
			local j=1
			while j<=b.n do
				local sb=b:get(j)
				sb.y=sb.y+ps
				if sb.y>=tl then
					sb.y=sb.y-tl-tl2+l-length
					process_bullet:insert(b:delete(j))
				else
					local temp=r1+sb.r
					temp=temp*temp-sb.y*sb.y
					if nb==0 and temp>0 then
						temp=sqrt(temp)
						generator:insert(sb.x-temp,sb.x+temp,1)
					end
					j=j+1
				end
			end
			j=1
			while nb==0 and j<=self.bullet_number[i] do
				generator:renew_line(0)
				local x=generator:born_position()
				if x~=nil then
					local r2=self.r2[i]
					local sb={x=x,y=0,r=r2,n=i}
					b:insert(sb)
					generator:insert(x-r2-r1,x+r2+r1)
				else
					break
				end
				j=j+1
			end
			if nb==0 then
				nb=gl
			end
			if l==0 then
				self.next_bullet[i]=nb
				break
			end
		end
		i=i+1
	end
	i=1
	while i<process_bullet.n do
		local b=process_bullet:get(i)
		b.y=b.y+length
		i=i+1
	end
	return process_bullet
end

function karl_nointersection_generation_v2:add_new_style(r1,r2,length,bullet_number)
	self.n=self.n+1
	self.r1[self.n]=r1
	self.r2[self.n]=r2
	if r2>self.rh then
		self.rh=r2
	end
	self.length[self.n]=length
	self.bullet_number[self.n]=bullet_number
	self.next_bullet[self.n]=length
	self.bullet[self.n]=karl_set.new()
	self.tl[self.n]=r1+self.rh
	if self.n==1 then
		self:go_through(self.tl[self.n])
	else
		self:go_through(self.tl[self.n]*2)
	end
end