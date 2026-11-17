-- TH15 ANM v8. Jumps address bytes within a script and set its local time.
-- A VM advances once per simulation tick; selecting another ECL resource does
-- not restart an already running VM.
local ease=require("tnr.legacy_replay.interpolation")
local A={};A.__index=A
A.OP={SET_ACTIVE_SPRITE=300,JUMP=200,STOP=3,EXIT=1,SET_SCALE=402,SET_ALPHA=403,
    SET_COLOR=404,FLIP_X=308,FLIP_Y=309,SET_ROTATION=401,SET_POS=400}
function A.new(archive,name,index)
    A.visual_seed=((A.visual_seed or 151)*48271)%2147483647
    local self=setmetatable({unhandled={},random_state=A.visual_seed},A)
    self:set_archive(archive or {},name,index)
    self:reset()
    return self
end
function A:reset()
    -- Controllers such as the stage title root spawn children without a sprite.
    self.pc,self.frame,self.sprite=1,-1,0
    self.scale_x,self.scale_y,self.alpha=1,1,255
    self.rotation,self.rotation_x,self.rotation_y,self.x,self.y,self.z=0,0,0,0,0,0
    self.rotate_auto=false;self.angle_vel=0;self.angle_vel_x=0;self.angle_vel_y=0
    self.growth_x=0;self.growth_y=0
    self.u,self.v,self.u_vel,self.v_vel=0,0,0,0
    self.uv_scale_x,self.uv_scale_y=1,1
    -- Direct3D's default texture addressing for TH15 ANM sprites is WRAP.
    self.scroll_mode_x,self.scroll_mode_y=0,0
    self.resample_mode,self.rotation_system=0,0
    self.red,self.green,self.blue=255,255,255
    self.red2,self.green2,self.blue2,self.alpha2=255,255,255,255
    self.color_mode=0;self.anchor_x=0;self.anchor_y=0;self.anchor_dx=0;self.anchor_dy=0
    self.scale2_x,self.scale2_y=1,1
    self.polygon_radius=nil
    self.geometry_width,self.geometry_height=nil,nil
    self.texture_circle_max=nil
    self.texture_cylinder_segments=nil
    self.render_mode=0
    self.flip_x,self.flip_y,self.blend_mode=false,false,0
    self.visible,self.finished,self.stopped=true,false,false
    self.color={255,255,255};self.tweens={};self.vars={};self.offsets={};self.interrupts={}
    self.children={};self.colorize_children=false;self.attached=false
    self.pending_roots={};self.interrupt_return=nil
    self.charge=nil
end
function A:set_archive(archive,name,index)
    if not archive then return false end
    self.archive,self.archive_name,self.entry_index=archive,name or self.archive_name,index or 1
    self.sprites,self.scripts=archive.sprites or {},archive.scripts or {}
    self.script=nil
    return true
end
function A:play(id)
    if not self.scripts[id] then self.unhandled["script:"..tostring(id)]=1;return false end
    self:reset();self.script=id
    local offset=0
    for i,ins in ipairs(self.scripts[id]) do
        self.offsets[offset]=i
        if ins.id==5 then self.interrupts[ins[1]]=i+1 end
        offset=offset+8+4*#ins
    end
    self:run()
    return true
end
function A:ramp(key,value,duration,mode)
    if duration<0 and (mode==7 or mode==17) then
        self.tweens[key]={from=self[key],target=value,duration=duration,age=0,mode=mode,velocity=0}
    elseif duration<=0 then self[key]=value;self.tweens[key]=nil
    else self.tweens[key]={from=self[key],target=value,duration=duration,age=0,mode=mode} end
end
function A:jump(offset,time)
    self.pc=assert(self.offsets[offset],"invalid ANM byte address "..tostring(offset))
    self.frame=time
end
function A:interrupt(id)
    local pc=self.interrupts[id];if not pc then return false end
    self.interrupt_return={pc=self.pc,frame=self.frame,stopped=self.stopped}
    self.pc,self.frame,self.stopped=pc,self.scripts[self.script][pc].time,false
    self:run();return true
end
function A:run()
    if self.finished or self.stopped or not self.script then return end
    local script=self.scripts[self.script]
    for _=1,256 do
        local ins=script[self.pc]
        if not ins or ins.time>self.frame then return end
        self.pc=self.pc+1;self.yielded=false;self:execute(ins)
        if self.finished or self.stopped or self.yielded then return end
    end
    error("ANM zero-time loop in "..tostring(self.archive_name)..":"..tostring(self.script))
end
function A:update()
    if self.finished or not self.script then return end
    for key,t in pairs(self.tweens) do
        t.age=t.age+1
        if t.mode==7 then self[key]=self[key]+t.target
        elseif t.mode==17 then self[key]=self[key]+(t.velocity or 0);t.velocity=(t.velocity or 0)+t.target
        elseif t.mode==8 and t.in_tangent then
            local u=math.min(1,t.age/t.duration)
            local s=1-u
            self[key]=(1+2*u)*s*s*t.from+(3-2*u)*u*u*t.target
                +u*s*s*t.in_tangent-u*u*s*t.out_tangent
        else self[key]=t.from+(t.target-t.from)*ease(t.mode,t.age/t.duration) end
        if t.duration>=0 and t.age>=t.duration then self.tweens[key]=nil end
    end
    self.rotation_x=self.rotation_x+(self.angle_vel_x or 0)
    self.rotation_y=self.rotation_y+(self.angle_vel_y or 0)
    self.rotation=self.rotation+(self.angle_vel or 0)
    self.u=self.u+self.u_vel;self.v=self.v+self.v_vel
    self.color={self.red,self.green,self.blue}
    self.scale_x=self.scale_x+(self.growth_x or 0);self.scale_y=self.scale_y+(self.growth_y or 0)
    if not self.stopped then self.frame=self.frame+1;self:run() end
    -- 508 installs the effect before the callback for this animation tick.
    if self.charge then self.charge:update(self) end
    local kept={}
    for _,child in ipairs(self.children) do child:update();if not child.finished then kept[#kept+1]=child end end
    self.children=kept
end
function A:create_child(script,x,y,z,root)
    for index,entry in ipairs(self.archive_entries or {self.archive}) do
        if entry.scripts and entry.scripts[script] then
            local child=A.new(entry,self.archive_name,self.archive_entries and index or self.entry_index)
            child.archive_entries=self.archive_entries
            child.parent_vm=self
            child.source_object=self.source_object
            child.on_effect=self.on_effect
            child:play(script)
            child.inherit_color=not root and self.colorize_children
            child.offset_x,child.offset_y,child.offset_z=x or 0,y or 0,z or 0
            if root then
                child.rotation=child.rotation+self.rotation
                self.pending_roots[#self.pending_roots+1]=child
            else self.children[#self.children+1]=child end
            return child
        end
    end
    self.unhandled["child:"..tostring(script)]=1
end
-- Visual randomness must never consume the ECL/LAN simulation random stream.
function A:random()
    self.random_state=((self.random_state or 151)*48271)%2147483647
    return self.random_state/2147483647
end
function A:read_var(key)
    if key==10013 then return self.x elseif key==10014 then return self.y elseif key==10015 then return self.z end
    if key==10010 or key==10030 then return (self:random()*2-1)*(self.vars[10028] or math.pi) end
    if key==10011 or key==10031 then return self:random()*(self.vars[10027] or 1) end
    if key==10012 or key==10032 then return (self:random()*2-1)*(self.vars[10027] or 1) end
    if key==10022 then return math.floor(self:random()*(self.vars[10029] or 65536)) end
    return self.vars[key] or 0
end
function A:execute(raw)
    local i={id=raw.id};local mask=raw.mask or 0
    for n,value in ipairs(raw) do
        i[n]=math.floor(mask/2^(n-1))%2==1 and self:read_var(value) or value
    end
    local id=i.id
    if id>=100 and id<=129 then
        local key=raw[1];local value
        if id<=101 then value=i[2]
        elseif id<=121 then
            local op,left,right
            if id<=111 then op=math.floor((id-102)/2);left=self:read_var(key);right=i[2]
            else op=math.floor((id-112)/2);left=i[2];right=i[3] end
            if op==0 then value=left+right elseif op==1 then value=left-right
            elseif op==2 then value=left*right elseif op==3 then value=right~=0 and left/right or 0
            else value=right~=0 and math.fmod(left,right) or 0 end
            if id%2==0 then value=value<0 and math.ceil(value) or math.floor(value) end
        elseif id==122 then value=math.floor(self:random()*i[2])
        elseif id==123 then value=self:random()*i[2]
        elseif id==124 then value=math.sin(i[2]) elseif id==125 then value=math.cos(i[2])
        elseif id==126 then value=math.tan(i[2]) elseif id==127 then value=math.acos(i[2])
        elseif id==128 then value=math.atan(i[2])
        else value=(self:read_var(key)+math.pi)%(2*math.pi)-math.pi end
        self.vars[key]=value
    elseif id==130 or id==131 then
        local angle,radius=i[3],i[4]
        if id==131 then radius=i[3]+self:random()*(i[4]-i[3]);angle=(self:random()*2-1)*math.pi end
        self.vars[raw[1]],self.vars[raw[2]]=math.cos(angle)*radius,math.sin(angle)*radius
    elseif id==300 then self.sprite=i[1]+1
    elseif id==301 then self.sprite=i[1]+math.floor(self:random()*math.max(1,i[2]))+1
    elseif id==302 then self.render_mode=i[1]
    elseif id==500 or id==501 then self:create_child(i[1])
    elseif id==505 then self:create_child(i[1],i[2],i[3],i[4])
    elseif id==504 then self:create_child(i[1],0,0,0,true)
    elseif id==506 then self:create_child(i[1],i[2]-self.x,i[3]-self.y,0,true)
    elseif id==508 then
        if self.on_effect then self.on_effect(i[1],self)
        else self.unhandled["effect:"..tostring(i[1])]=1 end
    elseif id==315 then self.colorize_children=i[1]~=0
    elseif id==304 then self.layer=i[1]
    elseif id==200 then self:jump(i[1],i[2])
    elseif id>=202 and id<=213 then
        local op=math.floor((id-202)/2);local left,right=i[1],i[2]
        local take=(op==0 and left==right) or (op==1 and left~=right)
            or (op==2 and left<right) or (op==3 and left<=right)
            or (op==4 and left>right) or (op==5 and left>=right)
        if take then self:jump(i[3],i[4]) end
    elseif id==201 then
        local key=raw[1];self.vars[key]=(self.vars[key] or 0)-1
        if self.vars[key]>0 then self:jump(i[2],i[3]) end
    elseif id==1 then self.finished=true;self.visible=false
    elseif id==6 then self.frame=self.frame-i[1];self.yielded=i[1]>0
    elseif id==7 and self.interrupt_return then
        local saved=self.interrupt_return;self.interrupt_return=nil
        self.pc,self.frame,self.stopped=saved.pc,saved.frame,saved.stopped
    elseif id==2 or id==3 then self.stopped=true
    elseif id==4 then self.stopped=true;self.visible=false
    elseif id==402 then self.scale_x,self.scale_y=i[1],i[2]
    elseif id==403 then self.alpha=i[1]
    elseif id==405 then self.alpha2=i[1]
    elseif id==406 then self.red2,self.green2,self.blue2=i[1],i[2],i[3]
    elseif id==413 then
        self.color_mode=1
        self:ramp("red2",i[3],i[1],i[2]);self:ramp("green2",i[4],i[1],i[2]);self:ramp("blue2",i[5],i[1],i[2])
    elseif id==414 then self.color_mode=1;self:ramp("alpha2",i[3],i[1],i[2])
    elseif id==423 then self.color_mode=i[1]
    elseif id==421 then self.anchor_x=i[1]%65536;self.anchor_y=math.floor(i[1]/65536)
    elseif id==436 then self.anchor_dx,self.anchor_dy=i[1],i[2]
    elseif id==434 then self.scale2_x,self.scale2_y=i[1],i[2]
    elseif id==600 then self.texture_circle_max=math.max(0,math.floor(i[1]))
    elseif id==609 then self.texture_cylinder_segments=math.max(1,math.floor(i[1]))
    elseif id==603 then self.geometry_width,self.geometry_height=i[1],i[2]
    elseif id==604 then self.polygon_radius=i[1];self.vars[10000]=i[2]
    elseif id==435 then self:ramp("scale2_x",i[3],i[1],i[2]);self:ramp("scale2_y",i[4],i[1],i[2])
    elseif id==404 then self.red,self.green,self.blue=i[1],i[2],i[3];self.color={i[1],i[2],i[3]}
    elseif id==408 then
        self:ramp("red",i[3],i[1],i[2]);self:ramp("green",i[4],i[1],i[2]);self:ramp("blue",i[5],i[1],i[2])
    elseif id==410 then
        self:ramp("rotation_x",i[3],i[1],i[2]);self:ramp("rotation_y",i[4],i[1],i[2])
        self:ramp("rotation",i[5],i[1],i[2])
    elseif id==411 then self:ramp("rotation",i[3],i[1],i[2])
    elseif id==425 then self.u_vel=i[1]
    elseif id==426 then self.v_vel=i[1]
    elseif id==427 then self:ramp("u_vel",i[3],i[1],i[2])
    elseif id==428 then self:ramp("v_vel",i[3],i[1],i[2])
    elseif id==429 then self.uv_scale_x,self.uv_scale_y=i[1],i[2]
    elseif id==430 then
        self:ramp("uv_scale_x",i[3],i[1],i[2]);self:ramp("uv_scale_y",i[4],i[1],i[2])
    elseif id==308 then self.flip_x=not self.flip_x
    elseif id==309 then self.flip_y=not self.flip_y
    elseif id==310 then self.visible=i[1]~=0
    elseif id==303 then self.blend_mode=i[1]
    elseif id==400 then self.x,self.y,self.z=i[1],i[2],i[3]
    elseif id==401 then self.rotation_x,self.rotation_y,self.rotation=i[1] or 0,i[2] or 0,i[3] or 0
    elseif id==424 then self.rotate_auto=i[1]~=0
    elseif id==407 then
        self:ramp("x",i[3],i[1],i[2]);self:ramp("y",i[4],i[1],i[2]);self:ramp("z",i[5],i[1],i[2])
    elseif id==420 then
        -- 479e64 / 40a71c: current position, destination and two Hermite
        -- tangents in xyz order. Tangents are already scaled to the interval.
        for axis,key in ipairs({"x","y","z"}) do
            self:ramp(key,i[axis+1],i[1],8)
            local tween=self.tweens[key]
            if tween then
                tween.in_tangent,tween.out_tangent=i[axis+4],i[axis+7]
            end
        end
    elseif id==409 or id==417 then self:ramp("alpha",i[3] or i[2],i[1],id==417 and 0 or i[2])
    elseif id==412 then self:ramp("scale_x",i[3],i[1],i[2]);self:ramp("scale_y",i[4],i[1],i[2])
    elseif id==415 then self.angle_vel_x,self.angle_vel_y,self.angle_vel=i[1] or 0,i[2] or 0,i[3] or 0
    elseif id==416 then self.growth_x,self.growth_y=i[1],i[2]
    elseif id==311 then self.resample_mode=i[1]
    elseif id==312 then self.scroll_mode_x,self.scroll_mode_y=i[1],i[2]
    elseif id==437 then self.rotation_system=math.max(0,math.min(5,math.floor(i[1] or 0)))
    elseif id==0 or id==5 or id==305 or id==306 or id==307
        or id==313 or id==314 or id==438 then
        -- Engine placement/sampling metadata does not alter sprite timing.
    else self.unhandled["op:"..id]=(self.unhandled["op:"..id] or 0)+1 end
end
function A:rect()
    local index=self.sprite
    if index<1 then return end
    if not self.archive_entries then return self.sprites[index],self.entry_index,index end
    -- ANM 300 selects a sprite across the archive. The executing script may
    -- be stored on a different texture entry from the displayed frame.
    for entry_index,entry in ipairs(self.archive_entries) do
        if index<=#entry.sprites then return entry.sprites[index],entry_index,index end
        index=index-#entry.sprites
    end
end
return A
