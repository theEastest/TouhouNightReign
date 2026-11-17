-- TH15 curves schedule motion at absolute laser ages (4498f9..449981).
-- They do not run the bullet interpreter's sequential acceleration timers.
local Rules=require("tnr.legacy_replay.reference_rules")
local f32=Rules.float32
local Curve={}

local function velocity(angle,speed)
    return f32(math.cos(angle)*speed),f32(math.sin(angle)*speed)
end

function Curve.new(shot)
    local paths,other={},{}
    local last=0
    for _,entry in ipairs(shot.transforms or {}) do
        if entry.flags==8 then
            local start=math.max(0,entry.int2 or 0)
            local finish=start+math.max(0,entry.int1 or 0)
            paths[#paths+1]={start=start,finish=finish,accel=entry.float1 or 0,turn=entry.float2 or 0}
            last=math.max(last,finish)
        else other[#other+1]=entry end
    end
    local x,y=f32(shot.x),f32(shot.y)
    local angle,speed=Rules.normalize_angle(shot.angle),f32(shot.speed)
    local points={}
    for age=0,last do
        points[age+1]={x=x,y=y,angle=angle,speed=speed}
        if age<last then
            local vx,vy=velocity(angle,speed)
            x,y=f32(x+vx),f32(y+vy)
            for _,path in ipairs(paths) do
                if age>=path.start and age<path.finish then
                    angle=Rules.normalize_angle(f32(angle+path.turn))
                    speed=f32(speed+path.accel)
                    break
                end
            end
        end
    end
    shot.transforms=other
    return {points=points,last=last}
end

function Curve.point(motion,age)
    if age<=0 then return motion.points[1] end
    local point=motion.points[age+1]
    if point then return point end
    local tail=motion.points[#motion.points]
    local vx,vy=velocity(tail.angle,tail.speed)
    local elapsed=age-motion.last
    return {x=f32(tail.x+f32(vx*elapsed)),y=f32(tail.y+f32(vy*elapsed)),
        angle=tail.angle,speed=tail.speed}
end

function Curve.update(shot,age)
    age=age-(shot.curve_offset or 0)
    local motion=shot.curve_motion
    local point=Curve.point(motion,age)
    local previous=Curve.point(motion,math.max(0,age-1))
    local vertical=shot.reflected and -1 or 1
    if shot.reflected then
        shot.x=f32(shot.x+f32(point.x-previous.x))
        shot.y=f32(shot.y-f32(point.y-previous.y))
    else shot.x,shot.y=point.x,point.y end
    shot.angle,shot.speed=point.angle,point.speed
    shot.vx,shot.vy=velocity(point.angle,point.speed)
    local node={x=shot.x,y=shot.y,angle=vertical*point.angle,speed=point.speed}
    table.insert(shot.nodes,1,node)
    local count=math.max(1,shot.timing[1] or 64)
    while #shot.nodes>count do table.remove(shot.nodes) end
end

function Curve.draw(g,shot,entry,rect,left,top,scale,tint,blend)
    if not g.RenderTexture or not entry.loaded_texture then return false end
    local nodes=shot.nodes
    local count=#nodes
    if count<2 then return true end
    local half=(shot.draw_width or shot.width)*.5
    local vertices={}
    for index,node in ipairs(nodes) do
        local angle=node.angle or 0
        if index>1 then
            local previous=nodes[index-1]
            angle=angle+Rules.normalize_angle((previous.angle or angle)-angle)*.5
        end
        local nx,ny=-math.sin(angle)*half,math.cos(angle)*half
        local u=rect.x+rect.w*(index-1)/(count-1)
        vertices[index]={
            {left+(node.x+nx+192)*scale,top-(node.y+ny)*scale,.5,u,rect.y,tint},
            {left+(node.x-nx+192)*scale,top-(node.y-ny)*scale,.5,u,rect.y+rect.h,tint},
        }
    end
    -- 4491b0 constructs one strip, with U running over the full curve.
    -- Repeating the full texture per segment turns its glow into beads.
    for index=1,count-1 do
        local a,b=vertices[index],vertices[index+1]
        g.RenderTexture(entry.loaded_texture,blend or "",a[1],b[1],b[2],a[2])
    end
    return true
end

return Curve
