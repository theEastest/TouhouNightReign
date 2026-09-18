--require karl_rb_tree.lua
--require karl_interval_line.lua

karl_nointersection_generation={}

function karl_nointersection_generation.new(line_start,line_end,loop)
	local obj={}
	setmetatable(obj, {__index = karl_nointersection_generation})
	obj.line_start=line_start or 0
	if line_end==nil then
		line_end=line_start+1
	end
	obj.line_end=line_end
	obj.line_length=obj.line_end-obj.line_start
	if loop==nil then
		loop=false
	end
	obj.loop=loop
	obj.tree=karl_rb_tree:new()
	obj.line=karl_interval_line:new(line_start,line_end)
	return obj
end

function karl_nointersection_generation:set_line(line_start,line_end)
	if self.loop then
		return nil
	else
		self.line_start=line_start
		self.line_end=line_end
		self.line_length=self.line_end-self.line_start
	end
end

function karl_nointersection_generation:wait(t)
--Print("delete")
	local tree=self.tree
	local guard=tree.guard
	local list={}
	local n=0
	local x=tree:tree_minimum(tree.root)
	while x~=guard do
		x.t=x.t-t
		if x.t<=0 then
			n=n+1
			list[n]=x
--Print(x.key)
--Print(x.keyb)
		end
		x=tree:tree_successor(x)
	end
	while n>0 do
		tree:rb_delete(list[n])
		n=n-1
	end
--Print("end")
end

function karl_nointersection_generation:insert(head,tail,t)
--Print("insert")
--Print(head)
--Print(tail)
	local length=tail-head
	if length<=0 then
		return false
	end
	if self.loop then
		local ls=self.line_start
		local le=self.line_end
		local ll=self.line_length
		if head<ls or head>le then
			local floor=math.floor
			head=(((head-ls)/ll)%1)*ll+ls
			tail=head+length
		end
	end
	self.tree:rb_insert({key=head,keyb=tail,t=t})
	return true
end

function karl_nointersection_generation:renew_line(width)
--Print("renew")
	width=width or 0
	local tree=self.tree
	local guard=tree.guard
	local ll=self.line_length
	local ls=self.line_start
	local le=self.line_end
	local x=tree:tree_minimum(tree.root)
	if self.loop then
		local y=x
		if x~=guard then
			local temp=x.key-width+ll
			if temp<le then
				le=temp
			end
		end
		local temp=ls-width
		while x~=guard do
			if x.keyb>temp then
				temp=x.keyb
			end
			x=tree:tree_successor(x)
		end
		temp=temp+width-ll
		if temp>ls then
			ls=temp
		end
		if ls>le then
			return nil
		end
		x=y
	end
	self.line=karl_interval_line:new(ls,le)
	local head=-1.7e308
	local tail=head
	guard.key=1.7e308
	guard.keyb=guard.key
	while true do
		local key=x.key-width
		local keyb=x.keyb+width
		if tail<key then
			if tail>ls and head<le then
				if head<ls then
					head=ls
				end
				if tail>le then
					tail=le
					self.line:insert(head,tail)
					break
				end
--Print(head)
--Print(tail)
				self.line:insert(head,tail)
			end
			head=key
			tail=keyb
		elseif tail<keyb then
			tail=keyb
		end
		if x==guard then
			break
		end
		x=tree:tree_successor(x)
	end
--Print("end")
end

function karl_nointersection_generation:born_position()
--Print("born")
	if self.line then
		local temp=self.line:get_random_position()
--Print(temp)
		return temp
	else
		return nil
	end
end