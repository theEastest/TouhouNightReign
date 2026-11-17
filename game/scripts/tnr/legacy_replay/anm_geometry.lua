-- TH15 ANM textured annulus (600), native vertex builder 47b640..47b8f9.
local Geometry={}

-- TH15 47d840 selects the framebuffer equation independently from sprite
-- tint. LuaSTG's alpha+bal uses the same exclusion factors as ANM mode 4.
-- Modes 6/7 have no corresponding legacy LuaSTG blend mode.
local BLENDS={[0]="","mul+add","mul+rev","one","alpha+bal","mul+mul",
    [8]="mul+min",[9]="mul+max"}

function Geometry.blend(mode)
    return BLENDS[mode] or ""
end

local function axis_breaks(a,b,size,mode)
    local result={0,1}
    if mode==0 or mode==2 then
        local delta=b-a
        if math.abs(delta)>1e-8 then
            local lo,hi=math.min(a,b),math.max(a,b)
            local first=math.floor(lo/size)+1
            local last=math.floor((hi-1e-8)/size)
            for tile=first,math.min(last,first+127) do
                local t=(tile*size-a)/delta
                if t>1e-8 and t<1-1e-8 then result[#result+1]=t end
            end
        end
    end
    table.sort(result)
    return result
end

local function address_axis(value,mode,size,tile,linear,point,mixed_wrap)
    if mode==0 then return value-(tile or math.floor(value/size))*size end
    if mode==2 then
        local k=tile or math.floor(value/size)
        local mapped=(k%2==0) and (value-k*size) or ((k+1)*size-value)
        return math.max(0.5,math.min(size-0.5,mapped))
    end
    local mapped=math.max(0,math.min(size,value))
    if mixed_wrap and (mapped==0 or mapped==size) then
        if linear then return math.max(0.5,math.min(size-0.5,mapped)) end
        if point and mapped==size then return size-1e-5 end
    end
    return mapped
end

-- Split a sprite quad at texture-addressing boundaries. This preserves the
-- original wrap/clamp/mirror behavior even though LuaSTG exposes one sampler
-- address mode for both texture axes.
function Geometry.uv_patches(u0,u1,v0,v1,width,height,mode_u,mode_v,point)
    width,height=math.max(1,width or 1),math.max(1,height or 1)
    mode_u,mode_v=mode_u or 0,mode_v or 0
    local xs=axis_breaks(u0,u1,width,mode_u)
    local ys=axis_breaks(v0,v1,height,mode_v)
    local has_wrap=mode_u==0 or mode_v==0
    local linear=not point
    local patches={}
    for xi=1,#xs-1 do
        local s0,s1=xs[xi],xs[xi+1]
        local um=u0+(u1-u0)*(s0+s1)/2
        local utile=(mode_u==0 or mode_u==2) and math.floor(um/width) or nil
        for yi=1,#ys-1 do
            local t0,t1=ys[yi],ys[yi+1]
            local vm=v0+(v1-v0)*(t0+t1)/2
            local vtile=(mode_v==0 or mode_v==2) and math.floor(vm/height) or nil
            local mixed_wrap=has_wrap
            local function map(u,v)
                return address_axis(u,mode_u,width,utile,linear,point,mixed_wrap),
                    address_axis(v,mode_v,height,vtile,linear,point,mixed_wrap)
            end
            local ua,va=map(u0+(u1-u0)*s0,v0+(v1-v0)*t0)
            local ub,vb=map(u0+(u1-u0)*s1,v0+(v1-v0)*t0)
            local uc,vc=map(u0+(u1-u0)*s1,v0+(v1-v0)*t1)
            local ud,vd=map(u0+(u1-u0)*s0,v0+(v1-v0)*t1)
            patches[#patches+1]={s0=s0,s1=s1,t0=t0,t1=t1,
                uv={{ua,va},{ub,vb},{uc,vc},{ud,vd}},
                sampler=(point and "point" or "linear")..(has_wrap and "+wrap" or "+clamp")}
        end
    end
    return patches
end

local ROTATION_ORDERS={
    {"x","y","z"},{"x","z","y"},{"y","x","z"},
    {"y","z","x"},{"z","x","y"},{"z","y","x"},
}

function Geometry.rotate3(x,y,z,rx,ry,rz,system)
    local angles={x=rx or 0,y=ry or 0,z=rz or 0}
    local order=ROTATION_ORDERS[(math.floor(system or 0)%6)+1]
    for _,axis in ipairs(order) do
        local a,c,s=angles[axis]
        c,s=math.cos(a),math.sin(a)
        if axis=="x" then y,z=y*c-z*s,y*s+z*c
        elseif axis=="y" then x,z=x*c+z*s,-x*s+z*c
        else x,y=x*c-y*s,x*s+y*c end
    end
    return x,y,z
end

-- Draw TH15 ANM 603's untextured custom quad. The opcode's two floats replace
-- the normal sprite dimensions; TH15 uses it for small square projectiles and
-- full-screen transition panels. Coordinates are already in screen space.
function Geometry.draw_rect(g,vm,x,y,width,height,scale_x,scale_y,alpha,color)
    if not g or not vm or not width or not height then return false end
    scale_x,scale_y=scale_x or 1,scale_y or scale_x or 1
    local half_w,half_h=width*scale_x/2,height*scale_y/2
    local points={{-half_w,-half_h},{half_w,-half_h},{half_w,half_h},{-half_w,half_h}}
    color=color or {vm.red or 255,vm.green or 255,vm.blue or 255}
    local tint=g.Color(alpha or vm.alpha or 255,color[1],color[2],color[3])
    local vertices={}
    for _,p in ipairs(points) do
        local dx,dy=p[1],p[2]
        if vm.render_mode==8 then
            dx,dy=Geometry.rotate3(dx,dy,0,vm.rotation_x,vm.rotation_y,
                vm.rotation,vm.rotation_system)
        elseif vm.render_mode and vm.render_mode~=0 then
            local c,s=math.cos(vm.rotation or 0),math.sin(vm.rotation or 0)
            dx,dy=dx*c-dy*s,dx*s+dy*c
        end
        vertices[#vertices+1]={x+dx,y+dy,0.5,0,0,tint}
    end
    if g.RenderTexture then
        g.RenderTexture("tnr-white-texture",Geometry.blend(vm.blend_mode),
            vertices[1],vertices[2],vertices[3],vertices[4])
        return true
    end
    if g.RenderRect and g.SetImageState then
        g.SetImageState("tnr-white",Geometry.blend(vm.blend_mode),tint)
        g.RenderRect("tnr-white",x-half_w,x+half_w,y-half_h,y+half_h)
        return true
    end
    return false
end

function Geometry.draw_circle(g,vm,entry,rect,size,x,y,scale,parent_x,parent_y)
    if not vm.texture_circle_max or not g.RenderTexture or not entry.loaded_texture then return false end
    local points=math.min(vm.texture_circle_max,math.floor(vm.vars[10000] or 0))
    if points<2 then return true end
    local scale_x=vm.scale_x*(vm.scale2_x or 1)
    local scale_y=vm.scale_y*(vm.scale2_y or 1)
    local outer=scale_y+math.abs(scale_x)/2
    local inner=scale_y-math.abs(scale_x)/2
    local repeats=vm.vars[10001] or 0
    local width,height=size[1] or rect.w,size[2] or rect.h
    local u=(rect.x+(entry.offset_x or 0))+(vm.u or 0)*width
    local v=rect.y+(entry.offset_y or 0)+(vm.v or 0)*height
    local primary=g.Color(vm.alpha,vm.red,vm.green,vm.blue)
    local secondary=vm.color_mode~=0 and g.Color(vm.alpha2,vm.red2,vm.green2,vm.blue2) or primary
    local radial_outer_u,radial_inner_u
    if scale_x<0 then radial_outer_u,radial_inner_u=u,u+rect.w
    else radial_outer_u,radial_inner_u=u+rect.w,u end
    local function vertex(t,radius,uv_x,color)
        local angle=(vm.rotation or 0)+t*(vm.arc_angle or math.pi*2)
        return {x+math.cos(angle)*radius*scale*(parent_x or 1),
            y-math.sin(angle)*radius*scale*(parent_y or 1),.5,
            uv_x,v+t*repeats*height,color}
    end
    if g.SetTextureSamplerState then g.SetTextureSamplerState(entry.loaded_texture,"linear+wrap") end
    for i=0,points-2 do
        local a,b=i/(points-1),(i+1)/(points-1)
        g.RenderTexture(entry.loaded_texture,Geometry.blend(vm.blend_mode),
            vertex(a,outer,radial_outer_u,primary),vertex(b,outer,radial_outer_u,primary),
            vertex(b,inner,radial_inner_u,secondary),vertex(a,inner,radial_inner_u,secondary))
    end
    return true
end

local function world_rotation(vm)
    return vm.rotation_x or 0,vm.rotation_y or 0,vm.rotation or 0,vm.rotation_system or 0
end

local function world_color(g,alpha,r,gc,b)
    return g.Color(alpha or 255,r or 255,gc or 255,b or 255)
end

local function rotated_world_point(x,y,z,center,vm)
    local rx,ry,rz,system=world_rotation(vm)
    x,y,z=Geometry.rotate3(x,y,z,rx,ry,rz,system)
    return center[1]+x,center[2]+y,center[3]+z
end

-- Draw ANM opcode 600 in the STD world's perspective space. Unlike the
-- screen-space version above, coordinates remain in stage units so the ring
-- receives the same camera projection and fog as its parent background face.
function Geometry.draw_world_circle(g,vm,entry,rect,size,center,blend)
    if not vm.texture_circle_max or not g.RenderTexture or not entry.loaded_texture then return false end
    local points=math.min(vm.texture_circle_max,math.floor(vm.vars[10000] or 0))
    if points<2 then return true end
    local scale_x=(vm.scale_x or 1)*(vm.scale2_x or 1)
    local scale_y=(vm.scale_y or 1)*(vm.scale2_y or 1)
    local outer=scale_y+math.abs(scale_x)/2
    local inner=scale_y-math.abs(scale_x)/2
    local repeats=vm.vars[10001] or 0
    local width=size[1] or entry.width or rect.w
    local height=size[2] or entry.height or rect.h
    local u=rect.x+(entry.offset_x or 0)+(vm.u or 0)*width
    local v=rect.y+(entry.offset_y or 0)+(vm.v or 0)*height
    local c1=world_color(g,vm.alpha,vm.red,vm.green,vm.blue)
    local c2=vm.color_mode~=0 and world_color(g,vm.alpha2,vm.red2,vm.green2,vm.blue2) or c1
    -- The native circle reverses the source image along the radial axis.
    -- A negative scale.x flips it back, matching the original opcode behavior.
    local radial_outer_u,radial_inner_u
    if scale_x<0 then radial_outer_u,radial_inner_u=u,u+rect.w*(vm.uv_scale_x or 1)
    else radial_outer_u,radial_inner_u=u+rect.w*(vm.uv_scale_x or 1),u end
    local function vertex(t,radius,tex_u,color)
        local angle=t*math.pi*2
        local x,y,z=rotated_world_point(math.cos(angle)*radius,math.sin(angle)*radius,0,center,vm)
        return {x,y,z,tex_u,v+t*repeats*height,color}
    end
    if g.SetTextureSamplerState then g.SetTextureSamplerState(entry.loaded_texture,"linear+wrap") end
    for i=0,points-2 do
        local a,b=i/(points-1),(i+1)/(points-1)
        g.RenderTexture(entry.loaded_texture,blend or Geometry.blend(vm.blend_mode),
            vertex(a,outer,radial_outer_u,c1),vertex(b,outer,radial_outer_u,c1),
            vertex(b,inner,radial_inner_u,c2),vertex(a,inner,radial_inner_u,c2))
    end
    return true
end

-- Draw ANM opcode 609 (`texCylinder3D`). Its angular span is centred on F3,
-- has width F0, radius F2, and height F1. The source texture's vertical axis
-- wraps around the cylinder as described by the reference ANM documentation.
function Geometry.draw_world_cylinder(g,vm,entry,rect,size,center,blend)
    if not vm.texture_cylinder_segments or not g.RenderTexture or not entry.loaded_texture then return false end
    local points=math.min(vm.texture_cylinder_segments,math.floor(vm.vars[10000] or 0))
    if points<2 then return true end
    local slices=math.min(512,points-1)
    local span=vm.vars[10004] or 0
    local height3d=vm.vars[10005] or 0
    local radius=vm.vars[10006] or 0
    local middle=vm.vars[10007] or 0
    local repeats=vm.vars[10001] or 1
    local width=size[1] or entry.width or rect.w
    local height=size[2] or entry.height or rect.h
    local u0=rect.x+(entry.offset_x or 0)+(vm.u or 0)*width
    local u1=u0+rect.w*(vm.uv_scale_x or 1)
    local v0=rect.y+(entry.offset_y or 0)+(vm.v or 0)*height
    local v_span=height*(vm.uv_scale_y or 1)*repeats
    local top_color=world_color(g,vm.alpha,vm.red,vm.green,vm.blue)
    local bottom_color=vm.color_mode~=0 and world_color(g,vm.alpha2,vm.red2,vm.green2,vm.blue2) or top_color
    local function vertex(theta,y,u,v,color)
        local x,z=radius*math.cos(theta),radius*math.sin(theta)
        local wx,wy,wz=rotated_world_point(x,y,z,center,vm)
        return {wx,wy,wz,u,v,color}
    end
    if g.SetTextureSamplerState then g.SetTextureSamplerState(entry.loaded_texture,"linear+wrap") end
    for i=0,slices-1 do
        local t0,t1=i/(points-1),(i+1)/(points-1)
        local theta0=middle-span/2+span*t0
        local theta1=middle-span/2+span*t1
        g.RenderTexture(entry.loaded_texture,blend or Geometry.blend(vm.blend_mode),
            vertex(theta0,height3d/2,u0,v0+v_span*t0,top_color),
            vertex(theta1,height3d/2,u0,v0+v_span*t1,top_color),
            vertex(theta1,-height3d/2,u1,v0+v_span*t1,bottom_color),
            vertex(theta0,-height3d/2,u1,v0+v_span*t0,bottom_color))
    end
    return true
end
return Geometry
