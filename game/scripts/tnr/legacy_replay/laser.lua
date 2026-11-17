-- TH15 laser geometry. Creation fields: 42c669; moving length/tail: 443259;
-- stationary warning/growth/active/shrink phases: 4459c0.
local L={}
local Transform=require("tnr.legacy_replay.bullet_transforms")
local float32=require("tnr.legacy_replay.reference_rules").float32
local copy=require("tnr.core.immutable").copy
local Curve=require("tnr.legacy_replay.curve_laser")
function L.new(group,config,x,y,kind,handle)
    local angle,speed=group.angle or 0,group.speed or 0
    local distance=group.distance or 0
    local shot={laser=true,laser_kind=kind,laser_handle=handle,
        x=x+math.cos(angle)*distance,y=y+math.sin(angle)*distance,
        angle=angle,speed=speed,initial_speed=speed,vx=math.cos(angle)*speed,vy=math.sin(angle)*speed,
        sprite=group.sprite or 0,color_index=group.color_index or 0,
        length=math.max(0,config.initial or 0),max_length=math.max(0,config.length or 0),
        travel_limit=config.travel or 0,travel=0,width=config.width or 16,
        timing=copy(config.timing or {0,0,0,0,0}),no_collision=true,
        transforms=copy(group.transforms),ex=copy(group.ex),anim_frame=0,
        nodes=kind=="curve" and {} or nil}
    if shot.nodes then
        shot.curve_motion=Curve.new(shot)
        angle=shot.curve_motion.points[1].angle
        -- 447d40 initializes the entire strip at the emitter. Unborn nodes
        -- retain its initial tangent, as does 44845b during later updates.
        for _=1,math.max(2,shot.timing[1] or 64) do
            shot.nodes[#shot.nodes+1]={x=shot.x,y=shot.y,angle=angle,speed=speed}
        end
    end
    return shot
end
function L.update(s,player)
    s.native_transform_start_speed=s.speed
    if s.transforms then Transform.update(s,player) end
    s.anim_frame=s.anim_frame+1
    local age=s.anim_frame
    local vertical=s.reflected and -1 or 1
    s.previous_x,s.previous_y=s.x,s.y
    if s.laser_kind=="curve" then
        Curve.update(s,age-1)
        s.draw_width=s.width;s.no_collision=false
    else
        s.angle=s.angle+(s.rotation_speed or 0)
        if s.length<s.max_length then
            -- 443271..443287 stores the growth step as single precision.
            s.length=math.min(s.max_length,float32(s.length+float32(math.max(0,s.speed))))
        elseif s.laser_kind=="moving" then
            s.x=s.x+s.vx;s.y=s.y+s.vy*vertical;s.travel=s.travel+s.speed
            if s.travel_limit>0 and s.travel+s.length>s.travel_limit then
                s.length=math.max(0,s.travel_limit-s.travel);s.max_length=s.length
                if s.length<=0 then s.deleted=true end
            end
        end
        s.draw_width=s.width
        if s.laser_kind=="stationary" then
            local a,b,c,d=math.max(0,s.timing[1]),math.max(0,s.timing[2]),math.max(0,s.timing[3]),math.max(0,s.timing[4])
            -- 4459d6 switches the warning to growth without evaluating the
            -- new phase on that tick; 445a10 similarly starts the shrink
            -- phase at full width before its first interpolation step.
            local first_growth=a+1
            local full_start=first_growth+math.max(1,b)
            local shrink_start=full_start+c
            if age<=first_growth then s.draw_width=2
            elseif age<full_start then
                s.draw_width=float32(float32(s.width*(age-first_growth))/b)
            elseif age<shrink_start then s.draw_width=s.width
            else
                s.draw_width=float32(s.width-float32(float32(s.width*(age-shrink_start))/math.max(1,d)))
                if age>=shrink_start+d then s.deleted=true end
            end
            s.no_collision=age<=a or age>=shrink_start
        else
            -- 44365b checks moving-laser length and width, not a fixed
            -- startup age. The manager admits live state 2 before age four.
            s.no_collision=false
        end
    end
end
function L.segments(s,visit)
    if s.nodes then
        for i=2,#s.nodes do local a,b=s.nodes[i-1],s.nodes[i];visit(a.x,a.y,b.x,b.y) end
    elseif (s.length or 0)>0 then
        local vertical=s.reflected and -1 or 1
        visit(s.x,s.y,s.x+math.cos(s.angle)*s.length,s.y+math.sin(s.angle)*s.length*vertical)
    end
end
local function collision_segments(s,visit)
    if not s.nodes then return L.segments(s,visit) end
    for index=1,#s.nodes-1 do
        local node=s.nodes[index]
        if node.angle and node.speed then
            -- 448700..448784 offsets the collision origin by half a tangent
            -- before passing its full length to 455e10's forward strip test.
            local dx,dy=math.cos(node.angle)*node.speed,math.sin(node.angle)*node.speed
            visit(node.x+dx*.5,node.y+dy*.5,node.x+dx*1.5,node.y+dy*1.5)
        else
            local next_node=s.nodes[index+1]
            visit(node.x,node.y,next_node.x,next_node.y)
        end
    end
end
function L.in_field(s)
    local visible=false
    local function point_in_field(x,y)
        local width=s.width or 16
        return x+width> -192 and x-width<192 and y+width>0 and y-width<448
    end
    if s.nodes then
        -- 4484f4 checks every node with the full visual width as its margin.
        for _,node in ipairs(s.nodes) do
            if point_in_field(node.x,node.y) then visible=true;break end
        end
    elseif s.laser_kind=="moving" then
        -- 443360 checks the two endpoints, not a larger generic bullet field.
        local vertical=s.reflected and -1 or 1
        visible=point_in_field(s.x,s.y) or point_in_field(s.x+math.cos(s.angle)*s.length,
            s.y+math.sin(s.angle)*s.length*vertical)
    else
        L.segments(s,function(x1,y1,x2,y2)
            if math.max(x1,x2)>-260 and math.min(x1,x2)<260 and math.max(y1,y2)>-80 and math.min(y1,y2)<540 then visible=true end
        end)
    end
    return visible or s.anim_frame<4
end
function L.cancel_effect_script(s)
    local kind=s.sprite or 0
    local script=(s.nodes or kind<=17 or kind==34 or kind==38) and 201
        or (kind<=31 or kind==27) and 249 or kind<=33 and 273
    return script and script+2*(s.color_index or 0)
end
function L.cancel_in_shape(s,contains,emit,visual)
    if (s.bomb_invulnerable or 0)>0 then return {s} end
    local samples={}
    if s.nodes then
        for index,node in ipairs(s.nodes) do
            samples[index]={x=node.x,y=node.y,emit=(index-1)%3==0}
        end
    elseif (s.length or 0)>=16 then
        local vertical=s.reflected and -1 or 1
        for distance=8,s.length,16 do
            -- 444e64 admits a moving segment only when its full 16 units
            -- fit; 446ea4/44710d use a strict boundary for stationary lasers.
            if (s.laser_kind=="moving" and distance+8<=s.length)
                or (s.laser_kind=="stationary" and distance+8<s.length)
                or (s.laser_kind~="moving" and s.laser_kind~="stationary") then
                samples[#samples+1]={x=s.x+math.cos(s.angle)*distance,
                    y=s.y+math.sin(s.angle)*distance*vertical,emit=true}
            end
        end
    end
    local removed=0
    for _,point in ipairs(samples) do
        point.cancelled=contains(point.x,point.y)
        if point.cancelled then
            removed=removed+1
            if point.emit then
                -- 444b8f samples straight lasers every sixteen units;
                -- 44af5c samples every third node on a curved laser.
                if emit then emit(point.x,point.y) end
                if visual then visual(point.x,point.y,s) end
            end
        end
    end
    if removed==0 then return {s} end
    if s.laser_kind=="stationary" and removed==#samples then
        -- 44724e..44727a truncates the original laser to zero; its own
        -- exit animation can grow that length again before a later clear.
        s.length=0
        return {}
    end
    if s.laser_kind=="moving" and removed==#samples then
        -- 444e9f marks the original object but keeps its geometry available
        -- to a second clear in the same enemy-manager tick.
        s.native_full_cancel_pending=true
        return {s}
    end
    s.deleted=true
    local pieces={}
    local index,run_index=1,0
    while index<=#samples do
        if samples[index].cancelled then index=index+1
        else
            run_index=run_index+1
            local first=index
            repeat index=index+1 until index>#samples or samples[index].cancelled
            local last=index-1
            local piece=copy(s);piece.deleted=false
            piece.legacy_bullet_animation=nil
            if s.nodes then
                piece.nodes={}
                for i=first,last do piece.nodes[#piece.nodes+1]=copy(s.nodes[i]) end
                piece.timing[1]=#piece.nodes
                piece.curve_offset=(s.curve_offset or 0)+first-1
                piece.x,piece.y=piece.nodes[1].x,piece.nodes[1].y
            else
                local offset=(first-1)*16
                piece.x=s.x+math.cos(s.angle)*offset
                piece.y=s.y+math.sin(s.angle)*offset*(s.reflected and -1 or 1)
                piece.length=math.min(s.length-offset,(last-first+1)*16)
                if s.laser_kind=="moving" and last==#samples and run_index==1 then
                    -- 444f2b preserves the actual remainder after the last
                    -- sampled fragment, including its unsampled short tail.
                    piece.length=s.length-offset
                end
                piece.max_length=piece.length
                if s.laser_kind=="moving" and first==1 then
                    -- 444fa9 keeps the original remaining growth on the
                    -- surviving prefix instead of making its tail move early.
                    piece.max_length=piece.length+math.max(0,(s.max_length or 0)-s.length)
                end
                piece.travel=s.travel+offset
                if s.laser_kind=="moving" and run_index>1 then
                    -- 444ff4 creates a new laser from the original launch
                    -- parameters, with a fresh update clock.
                    piece.anim_frame=0
                    piece.keep_offscreen=30
                    piece.native_split_grace=true
                    piece.speed=s.initial_speed or s.speed
                    piece.vx,piece.vy=math.cos(piece.angle)*piece.speed,math.sin(piece.angle)*piece.speed
                    piece.transform_pc,piece.transform_active,piece.transform_block=nil,nil,nil
                end
            end
            -- 444f34 / 445010 discard moving remnants of at most 24 units.
            if s.laser_kind~="moving" or piece.length>24 then
                pieces[#pieces+1]=piece
            end
        end
    end
    return pieces
end
function L.cancel_in_circle(s,x,y,radius,emit,visual)
    return L.cancel_in_shape(s,function(px,py) return (px-x)^2+(py-y)^2<=radius*radius end,emit,visual)
end
function L.contact(s,player)
    if s.no_collision or s.deleted or s.native_full_cancel_pending then return false,false end
    local hit,graze=false,false
    local graze_x,graze_y,closest
    local width=s.draw_width or s.width
    -- 445b63..445b84 checks active state and length for stationary lasers;
    -- unlike moving lasers, its 445b50 contact path does not reject thin beams.
    if s.laser_kind=="stationary" then
        if (s.length or 0)<=16 then return false,false end
    elseif width<=3 then return false,false end
    -- 443640 and 445b50 build different strips for moving and fixed lasers.
    local trim=s.laser_kind=="moving" and math.floor((s.timing[5] or 0)/2)%2==0
    local fixed=s.laser_kind=="stationary"
    local half=width/4
    if not s.nodes and width>=32 then
        half=fixed and (width-(width+16)/3)/2 or (width-16)/4
    end
    -- 4535b4 stores half the SHT hitbox. 455ed3 uses sixteen times that half
    -- extent for laser graze, including along the beam's ends.
    local r=player.hitbox_half or player.hitbox/2
    local g=r*16
    local travelled=0
    collision_segments(s,function(x1,y1,x2,y2)
        local dx,dy=x2-x1,y2-y1
        local length=math.sqrt(dx*dx+dy*dy)
        travelled=travelled+length
        -- 448755..448768 omits the curve's leading segments until their
        -- accumulated length reaches sixteen units.
        if s.nodes and travelled<16 then return end
        if length<=0 or (not s.nodes and length<=16) then return end
        local along=((player.x-x1)*dx+(player.y-y1)*dy)/length
        local across=math.abs((player.x-x1)*dy-(player.y-y1)*dx)/length
        local start,finish=trim and length*.1 or 0,(trim or fixed) and length*.9 or length
        if along+r>=start and along-r<=finish and across<=half+r then hit=true end
        if along+g>=start and along-g<=finish and across<=half+g and (not closest or across<closest) then
            graze,closest=true,across
            graze_x,graze_y=x1+along*dx/length,y1+along*dy/length
        end
    end)
    return hit,graze and not hit,graze_x,graze_y
end
return L
