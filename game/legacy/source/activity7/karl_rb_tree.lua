--Excerpts from CLRS
--Used in an implementation of self-sorting

karl_rb_tree={}

function karl_rb_tree:new()
	local tree={}
	setmetatable(tree,self)
	self.__index=self
	local guard={color=false}
	guard.left=guard
	guard.right=guard
	guard.p=guard
	tree.guard=guard
	tree.root=guard
	return tree
end

function karl_rb_tree:get_root()
	return self.root
end

function karl_rb_tree.tree_search(x,k)
	while x~=self.guard and k~=x.key do
		if k<x.key then
			x=x.left
		else
			x=x.right
		end
	end
	return x
end

function karl_rb_tree:tree_minimum(x)
	while x.left~=self.guard do
		x=x.left
	end
	return x
end

function karl_rb_tree:tree_maximum(x)
	while x.right~=self.guard do
		x=x.right
	end
	return x
end

function karl_rb_tree:left_rotate(x)
	local y=x.right
	x.right=y.left
	if y.left~=self.guard then
		y.left.p=x
	end
	y.p=x.p
	if x.p==self.guard then
		self.root=y
	elseif x==x.p.left then
		x.p.left=y
	else
		x.p.right=y
	end
	y.left=x
	x.p=y
end

function karl_rb_tree:right_rotate(x)
	local y=x.left
	x.left=y.right
	if y.right~=self.guard then
		y.right.p=x
	end
	y.p=x.p
	if x.p==self.guard then
		self.root=y
	elseif x==x.p.right then
		x.p.right=y
	else
		x.p.left=y
	end
	y.right=x
	x.p=y
end

function karl_rb_tree:rb_insert_fixup(z)
	while z.p.color==true do
		local x=z.p
		if x==x.p.left then
			local y=x.p.right
			if y.color==true then
				x.color=false
				y.color=false
				x.p.color=true
				z=x.p
			else
				if z==x.right then
					z=x
					self:left_rotate(z)
				end
				z.p.color=false
				z.p.p.color=true
				self:right_rotate(z.p.p)
			end
		else
			local y=x.p.left
			if y.color==true then
				x.color=false
				y.color=false
				x.p.color=true
				z=x.p
			else
				if z==x.left then
					z=x
					self:right_rotate(z)
				end
				z.p.color=false
				z.p.p.color=true
				self:left_rotate(z.p.p)
			end
		end
	end
	self.root.color=false
end

function karl_rb_tree:rb_insert(z)
	local x=self.root
	local y=self.guard
	while x~=self.guard do
		y=x
		if z.key<x.key then
			x=x.left
		else
			x=x.right
		end
	end
	z.p=y
	if y==self.guard then
		self.root=z
	elseif z.key<y.key then
		y.left=z
	else
		y.right=z
	end
	z.left=self.guard
	z.right=self.guard
	z.color=true
	self:rb_insert_fixup(z)
end

function karl_rb_tree:rb_transplant(u,v)
	if u.p==self.guard then
		self.root=v
	elseif u==u.p.left then
		u.p.left=v
	else
		u.p.right=v
	end
	v.p=u.p
end

function karl_rb_tree:rb_delete_fixup(x)
	while x~=self.root and x.color==false do
		if x==x.p.left then
			local w=x.p.right
			if w.color==true then
				w.color=false
				x.p.color=true
				self:left_rotate(x.p)
				w=x.p.right
			end
			if w.left.color==false and w.right.color==false then
				w.color=true
				x=x.p
			else
				if w.right.color==false then
					w.left.color=false
					w.color=true
					self:right_rotate(w)
					w=x.p.right
				end
				w.color=x.p.color
				x.p.color=false
				w.right.color=false
				self:left_rotate(x.p)
				x=self.root
			end
		else
			local w=x.p.left
			if w.color==true then
				w.color=false
				x.p.color=true
				self:right_rotate(x.p)
				w=x.p.left
			end
			if w.right.color==false and w.left.color==false then
				w.color=true
				x=x.p
			else
				if w.left.color==false then
					w.right.color=false
					w.color=true
					self:left_rotate(w)
					w=x.p.left
				end
				w.color=x.p.color
				x.p.color=false
				w.left.color=false
				self:right_rotate(x.p)
				x=self.root
			end
		end
	end
	x.color=false
end

function karl_rb_tree:rb_delete(z)
	local x=nil
	local y=z
	local y_original_color=y.color
	if z.left==self.guard then
		x=z.right
		self:rb_transplant(z,x)
	elseif z.right==self.guard then
		x=z.left
		self:rb_transplant(z,x)
	else
		y=self:tree_minimum(z.right)
		y_original_color=y.color
		x=y.right
		if y.p==z then
			x.p=y
		else
			self:rb_transplant(y,y.right)
			y.right=z.right
			y.right.p=y
		end
		self:rb_transplant(z,y)
		y.left=z.left
		y.left.p=y
		y.color=z.color
	end
	if y_original_color==false then
		self:rb_delete_fixup(x)
	end
end

function karl_rb_tree:inorder_tree_walk(x,f)
	if x~=self.guard then
		self:inorder_tree_walk(x.left,f)
		f(x)
		self:inorder_tree_walk(x.right,f)
	end
end

function karl_rb_tree:tree_successor(x)
	if x.right~=self.guard then
		return self:tree_minimum(x.right)
	end
	local y=x.p
	while y~=self.guard and x==y.right do
		x=y
		y=y.p
	end
	return y
end

function karl_rb_tree:tree_predecessor(x)
	if x.left~=self.guard then
		return self:tree_maximum(x.left)
	end
	local y=x.p
	while y~=self.guard and x==y.left do
		x=y
		y=y.p
	end
	return y
end