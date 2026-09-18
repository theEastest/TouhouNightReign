--require karl_misc.lua
--require karl_acc_controller.lua

karl_delay_appear_bullet=Class(bullet)
karl_delay_appear_bullet.init=function(self,_x,_y,style,color,a,v,t,highlight,stay,des)
    stay=stay or true
    des=des or true
    bullet.init(self,style,color,stay,des)
    self.x,self.y=_x,_y
    SetV2(self,v,a,true,false)
    highlight=highlight or false
    if highlight then
        highlight="mul+add"
    else
        highlight=""
    end
    _object.set_color(self,highlight,0,255,255,255)
    self.colli=false
    task.New(self,function()
        do local b,_d_b=(0),(255/t) for _=1,t do
            _object.set_color(self,highlight,b,255,255,255)
            task._Wait(1)
        b=b+_d_b end end
        self.colli=true
        _object.set_color(self,highlight,255,255,255,255)
    end)
end

karl_gravity_bullet=Class(bullet)
karl_gravity_bullet.init=function(self,_x,_y,style,color,highlight,stay,des,navi,angle,omiga,t,vx,vy,avx,avy,bound_pos)
    bullet.init(self,style,color,stay,des)
    self.x,self.y=_x,_y
    self.rot=angle
    self.omiga=omiga
    self.navi=navi
    t2=t2 or 0
    v2=v2 or v1
    if highlight then
        _object.set_color(self,"mul+add",255,255,255,255)
    end
    self.bound=false
    vx=vx or 0
    vy=vy or 0
    avx=avx or 0
    avy=avy or 0
    task.New(self,function()
        bound_pos=bound_pos or {}
        bound_pos.l=bound_pos.l or -232
        bound_pos.r=bound_pos.r or 232
        bound_pos.b=bound_pos.b or -264
        bound_pos.t=bound_pos.t or 264
        do for _=1,_infinite do
            if self.x<bound_pos.l or self.x>bound_pos.r or self.y<bound_pos.b or self.y>bound_pos.t then
                _del(self,true)
            end
            task._Wait(1)
        end end
    end)
    task.New(self,function()
        local x=self.x
        local y=self.y
        do for _=1,_infinite do
            self.x=x+(2*vx+t*avx)*t*0.5
            self.y=y+(2*vy+t*avy)*t*0.5
            t=t+1
            task._Wait(1)
        end end
    end)
end

karl_acc_bullet=Class(bullet)
karl_acc_bullet.init=function(self,_x,_y,style,color,highlight,stay,des,angle,omiga,t1,v1,t2,v2)
    bullet.init(self,style,color,stay,des)
    self.x,self.y=_x,_y
    self.rot=angle
    self.omiga=omiga
    t2=t2 or 0
    v2=v2 or v1
    if highlight then
        _object.set_color(self,"mul+add",255,255,255,255)
    end
        local x = self.x
        local y = self.y
        local controller=karl_acc_controller.new(v1)
        controller:add_speed(t2,v2)
        local l = controller:get_length(t1)
        self.x=x+l*cos(angle)
        self.y=y+l*sin(angle)
    task.New(self,function()
        do for _=1,_infinite do
                l = controller:get_length(t1)
                self.x=x+l*cos(angle)
                self.y=y+l*sin(angle)
	t1=t1+1
            	task._Wait(1)
        end end
    end)
end
--t1是已发射的时间，发射时速度v1，t2时间后速度为v2

karl_initializer_bullet=Class(bullet)
karl_initializer_bullet.init=function(self,_x,_y,bullet_initializer,bullet_init)
	self.x,self.y=_x,_y
	if bullet_init==nil then
		bullet_init=false
	end
	bullet_initializer:initialize_bullet(self,bullet_init)
end

karl_acc_bullet_v2=Class(bullet)
karl_acc_bullet_v2.init=function(self,_x,_y,bullet_initializer,t1,controller,angle)
	self.x,self.y=_x,_y
	bullet_initializer:bullet_control("acc_bullet_task",controller,angle,t1)
	bullet_initializer:initialize_bullet(self)
	self.rot=angle
end

karl_acc_bullet_v3_shooter=Class(_object)
karl_acc_bullet_v3_shooter.init=function(self,_x,_y,bullet_initializer,t1,controller,angle)
    self.x,self.y=_x,_y
	self.img="leaf"
	self.layer=LAYER_ENEMY_BULLET
	self.group=GROUP_ENEMY_BULLET
	self.hide=true
	self.bound=false
	self.navi=false
	self.hp=10
	self.maxhp=10
	self.colli=false
	self._servants={}
	self._blend,self._a,self._r,self._g,self._b='',255,255,255,255
    task.New(self,function()
        t1=-t1
        local temp = math.ceil(t1)
        task._Wait(temp)
        last=New(karl_acc_bullet_v2,self.x,self.y,bullet_initializer,temp-t1,controller,angle)
        _del(self,true)
    end)
end