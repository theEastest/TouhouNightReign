-- Reference destruction particles; use the bundled THlib atlas.
LoadTexture('etbreak', 'THlib/bullet/etbreak.png')
LoadImageGroup('etbreak', 'etbreak', 0, 0, 64, 64, 4, 2, 0, 0)
BulletBreakIndex={
	Color(0xC0FF3030),--red
	Color(0xC0FF30FF),--purple
	Color(0xC03030FF),--blue
	Color(0xC030FFFF),--cyan
	Color(0xC030FF30),--green
	Color(0xC0FFFF30),--yellow
	Color(0xC0FF8030),--orange
	Color(0xC0D0D0D0),--gray
}

BulletBreak=Class(object)
function BulletBreak:init(x,y,index)
	self.x=x
	self.y=y
	self.group=GROUP_GHOST
	self.layer=LAYER_ENEMY_BULLET-50
	self.index=index
	local s = ran:Float(0.5,0.75)
	self.hscale=s self.vscale=s
	self.rot=ran:Float(0,360)
	if index%2==0 then
		self.color=BulletBreakIndex[index/2]
	else
		self.color=0.5*BulletBreakIndex[(index+1)/2]+Color(0x60000000)
	end
	if index==15 then self.color=BulletBreakIndex[8] end
end

function BulletBreak:frame()
	if self.timer==23 then Del(self) end
end

function BulletBreak:render()
	local t=int((self.timer+3)/3)
	if self.index==15 then
	SetImageState('etbreak'..t,'',self.color)
	else
	SetImageState('etbreak'..t,'mul+add',self.color)
	end
	Render('etbreak'..t,self.x,self.y,self.rot,self.hscale)
	--SetImageState('etbreak'..t,'mul+add',Color(0xFFFFFFFF))
end
----
