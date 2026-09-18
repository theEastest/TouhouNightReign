AE_moonworld_background=Class(object)

function AE_moonworld_background:init()
	--
	background.init(self,false)
	--resource
	LoadImageFromFile('AE_moonworld_a','AE_moonworld_a.png')
	LoadImageFromFile('AE_moonworld_c','AE_moonworld_c.png')
	LoadImageFromFile('AE_moonworld_d','AE_moonworld_d.png')
	LoadImageFromFile('AE_moonworld_e','AE_moonworld_e.png')
	--set 3d camera and fog
	Set3D('eye',0,-1.0,-7.0)
	Set3D('at',0,-0.52,-0.9)
	Set3D('up',0,1,0)
	Set3D('z',1,15)
	Set3D('fovy',0.93)
	Set3D('fog',0,11,Color(100,0,0,0))
	-----
	self.speed=0
	self.z=0
	self.z0=0
	self.eyxx=0
	self.eyxy=0
end

function AE_moonworld_background:frame()
	self.z=self.z+self.speed
	self.z0=self.z0+self.speed/10
	if IsValid(player) then
		local x=player.x/80
		local y=(player.y+176)/180
		self.eyxy=0.03*y+0.95*self.eyxy
		self.eyxx=0.02*x+0.95*self.eyxx
		Set3D('eye',self.eyxx/2,-1-self.eyxy/2,-6.0)
		Set3D('at',self.eyxx/3,-0.40,1.0)
	end
end

function AE_moonworld_background:render()
	SetViewMode'3d'
	local showboss = IsValid(_boss)
	if showboss then
        PostEffectCapture()
    end
	for j=-2,3 do
		local dz=10*j-math.mod(self.z,10)
		AE_moonworld_background.rendersea(dz,self)
		AE_moonworld_background.renderground(dz,self)
	end
	Render4V('AE_moonworld_e',-4,4,1,4,4,1,4,0,1,-4,0,1)
--  AE_moonworld_background.rendercosmos(self)
--	AE_moonworld_background.rendercosmos(self)
    if showboss then
		local x,y = WorldToScreen(_boss.x,_boss.y)
		local x1 = x * screen.scale
		local y1 = (screen.height - y) * screen.scale
		local fxr = _boss.fxr or 163
		local fxg = _boss.fxg or 73
		local fxb = _boss.fxb or 164
		PostEffectApply("boss_distortion", "", {
			centerX = x1,
			centerY = y1,
			size = _boss.aura_alpha*200*lstg.scale_3d,
			color = Color(125,fxr,fxg,fxb),
			colorsize = _boss.aura_alpha*200*lstg.scale_3d,
			arg=1500*_boss.aura_alpha/128*lstg.scale_3d,
			timer = self.timer
        })
	end
	SetViewMode'world'
end

local hin=-0.2
function AE_moonworld_background.renderground(z,self)
	SetImageState('AE_moonworld_a','mul+add',Color(255,255,255,255))
	Render4V('AE_moonworld_a',-5,-0.2+0.26*z,z+3,
					   5,-0.2+0.26*z,z+3,
					   5,-2.8+0.26*z,z-7,
					  -5,-2.8+0.26*z,z-7)
end

function AE_moonworld_background.rendersea(z,self)
    SetImageState('AE_moonworld_d','mul+add',Color(255,255,255,255))
	Render4V('AE_moonworld_d',-5,-0.2+0.26*z,z+7,
					   5,-0.2+0.26*z,z+7,
					   5,-2.8+0.26*z,z-3,
					  -5,-2.8+0.26*z,z-3)
end
----
--local h=4
--local R=10
--function AE_moonworld_background.rendercosmos(self)
--	local alpha=140+20*sin(self.timer)
--	SetImageState('AE_moonworld_b','',Color(alpha,130+125*sin(self.timer),130-125*sin(self.timer),130+125*cos(self.timer)))
--	local timer=self.timer/100
--	Render4V('AE_moonworld_b',
--	R*cos(timer),h,R*sin(timer),
--	-R*sin(timer),h,R*cos(timer),
--	-R*cos(timer),h,-R*sin(timer),
--	R*sin(timer),h,-R*cos(timer))
--end
-----------------------------------------------------------------------------
------±≥æ∞÷ÿ÷√
function AE_moonworld_background_change(self)
			Set3D('eye',0,-1.0,-7.0)
	        Set3D('at',0,-0.52,-0.9)
	        Set3D('up',0,1,0)
			Set3D('fog',0,14,Color(100,0,0,0))
			coroutine.yield()
end

