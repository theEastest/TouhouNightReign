-- Input-only pilot for the playability audit.
local Pilot = {}
local Types = require("tnr.legacy_replay.data.th15_bullet_types")
local Laser = require("tnr.legacy_replay.laser")
local Player = require("tnr.legacy_replay.player")
local ClassicBombs = require("tnr.legacy_replay.classic_bombs")
local Transform = require("tnr.legacy_replay.bullet_transforms")
local moves = {{0,0},{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}
local focus_modes = {true,false}
local look = {1,2,4,7,11,16,22,28}
local beam_history=setmetatable({},{__mode="k"})
local reloading=setmetatable({},{__mode="k"})
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function snapshot(source)
    local result={}
    for key,value in pairs(source) do result[key]=value end
    return result
end

local function predict_bullet(shot,lead)
    local future=snapshot(shot)
    future.random=nil
    future.transform_block=shot.transform_block and snapshot(shot.transform_block)
    future.transform_birth=shot.transform_birth and snapshot(shot.transform_birth)
    future.transform_active={}
    for _,state in ipairs(shot.transform_active or {}) do
        future.transform_active[#future.transform_active+1]=snapshot(state)
    end
    future.transform_sounds,future.transform_enemies,future.transform_emissions=nil,nil,nil
    future.unsupported_transforms=nil
    local positions={}
    for tick=1,28+lead do
        Transform.update(future)
        future.x=future.x+(future.vx or 0)*(future.motion_scale or 1)
        future.y=future.y+(future.vy or 0)*(future.motion_scale or 1)*(future.reflected and -1 or 1)
        future.anim_frame=(future.anim_frame or 0)+1
        positions[tick]={x=future.x,y=future.y,deleted=future.deleted,no_collision=future.no_collision}
    end
    return positions
end

local function threats_for(stage,p,lead)
    local bullets,lasers={},{}
    for _,s in ipairs(stage.adapter.shots) do
        if s.laser and not s.deleted then lasers[#lasers+1]=s
        elseif not s.player_bullet and not s.deleted and (s.x-p.x)^2+(s.y-p.y)^2<200^2 then
            local kind=Types[s.sprite or s.anim or 0]
            local r=(kind and kind.radius or 3)*(s.scale or 1)
            local margin=kind and kind.rectangular and r/2+(p.hitbox_half or p.hitbox/2)
                or math.sqrt(r*r+p.hitbox*p.hitbox)
            local prediction=s.transforms and #s.transforms>0 and (s.x-p.x)^2+(s.y-p.y)^2<140^2
                and predict_bullet(s,lead)
            bullets[#bullets+1]={x=s.x,y=s.y,vx=(s.vx or 0)*(s.motion_scale or 1),
                vy=(s.vy or 0)*(s.motion_scale or 1)*(s.reflected and -1 or 1),
                hit=margin,box=kind and kind.rectangular,prediction=prediction,
                delay=s.no_collision and 8-(s.anim_frame or 0) or 0}
        end
    end
    for _,e in ipairs(stage.adapter.enemies) do
        if (e.hp or 0)>0 and not e.legacy_no_contact and not e.legacy_deleted
            and e.legacy_hitbox and (e.x-p.x)^2+(e.y-p.y)^2<200^2 then
            local radius=e.legacy_hitbox[1]/2
            bullets[#bullets+1]={x=e.x,y=e.y,vx=e.legacy_final_vx or 0,vy=e.legacy_final_vy or 0,
                hit=math.sqrt(radius*radius+p.hitbox*p.hitbox),delay=0}
        end
    end
    return bullets,lasers
end

local function beam_drift(beam)
    local previous=beam_history[beam]
    if previous and previous.age==beam.anim_frame then return previous.dx,previous.dy end
    local dx,dy=0,0
    if previous and previous.age+1==beam.anim_frame then
        -- Laser.update records the origin after ECL moves the whole row.
        dx=(beam.previous_x or previous.x)-previous.x
        dy=(beam.previous_y or previous.y)-previous.y
    end
    beam_history[beam]={age=beam.anim_frame,x=beam.x,y=beam.y,dx=dx,dy=dy}
    return dx,dy
end

local function laser_positions(lasers,lead,aim,player)
    local positions={}
    local speed=math.max(player.definition.move_unfocused or 4.5,player.definition.move_focused or 2)
    for _,t in ipairs(look) do if t<=16 then positions[t]={} end end
    for _,laser in ipairs(lasers) do
        local dx,dy=beam_drift(laser)
        local future=snapshot(laser)
        -- Transform instructions are immutable, but their counters and random
        -- source belong to the estimate. Leave the simulation untouched.
        future.random=nil
        future.transform_block=laser.transform_block and snapshot(laser.transform_block)
        future.transform_active={}
        future.nodes=laser.nodes and snapshot(laser.nodes)
        for _,state in ipairs(laser.transform_active or {}) do
            future.transform_active[#future.transform_active+1]=snapshot(state)
        end
        future.transform_sounds,future.transform_enemies,future.unsupported_transforms=nil,nil,nil
        local elapsed=0
        for _,t in ipairs(look) do
            if t>16 then break end
            for _=elapsed+1,t+lead do
                future.x,future.y=future.x+dx,future.y+dy
                Laser.update(future,aim)
            end
            elapsed=t+lead
            if not future.no_collision and not future.deleted then
                local reach=math.min(t,14)*speed+(future.draw_width or future.width)/2+4
                local tip_x=future.x+math.cos(future.angle)*future.length
                local tip_y=future.y+math.sin(future.angle)*future.length*(future.reflected and -1 or 1)
                local left,right=math.min(future.x,tip_x),math.max(future.x,tip_x)
                local top,bottom=math.min(future.y,tip_y),math.max(future.y,tip_y)
                for _,node in ipairs(future.nodes or {}) do
                    left,right=math.min(left,node.x),math.max(right,node.x)
                    top,bottom=math.min(top,node.y),math.max(bottom,node.y)
                end
                if player.x>=left-reach and player.x<=right+reach
                    and player.y>=top-reach and player.y<=bottom+reach then
                    local sample=positions[t]
                    local beam=snapshot(future)
                    beam.nodes=future.nodes and snapshot(future.nodes)
                    sample[#sample+1]=beam
                end
            end
        end
    end
    return positions
end

local function goal_for(stage,p,threats,id)
    local boss=stage.adapter.boss_object
    local target=boss and not boss.legacy_no_damage and boss.y<p.y-20 and boss
    local best=math.huge
    if not target then
        for _,e in ipairs(stage.adapter.enemies) do
            if (e.hp or 0)>0 and e.legacy_hurtbox and not e.legacy_no_damage and e.y>0 and e.y<p.y-24 then
                local distance=math.abs(e.x-p.x)+math.abs(e.y-p.y)*.18
                if distance<best then target,best=e,distance end
            end
        end
    end
    local x=target and clamp(target.x+8*(target.legacy_final_vx or 0),-172,172) or 0
    local late=p.combat_runtime and (stage.stage_key=="st05" or stage.stage_key=="st06")
    local y=target and clamp(target.y+(late and 196 or 210),270,late and 376 or 395) or 362
    if stage.coop then
        local offset=p.combat_runtime and 8 or 23
        x=clamp(x+(id==1 and -offset or offset),-175,175)
    end
    local gauge=p.combat_runtime and p.combat_runtime.p_gauge
    local want_power=gauge and gauge.value<90 or not gauge and p.power<390
    if not target and #threats<12 or want_power and #threats<18 then
        local nearest,item_count=math.huge,0
        for _,item in ipairs(stage.items.list) do
            if not item.attracted and (item.owner_player_id==nil or item.owner_player_id==id)
                and (item.kind=="power" or item.kind=="power_large" or item.kind=="life_piece" or item.kind=="bomb") then
                local dx,dy=item.x-p.x,item.y-p.y
                local distance=dx*dx+dy*dy
                if distance<nearest and item.y>p.collect_line then
                    x,y,nearest=clamp(item.x,-174,174),clamp(item.y+12,70,428),distance
                end
                if item.y>60 then item_count=item_count+1 end
            end
        end
        if item_count>=6 and #threats<=3 then y=p.collect_line-2 end
    end
    return x,y
end

local function rate(p,threats,lasers,dx,dy,focus,goal_x,goal_y,lead)
    local d=p.definition
    local speed=focus and (d.move_focused or 2) or (d.move_unfocused or 4.5)
    if dx~=0 and dy~=0 then
        speed=(focus and d.move_focused_diagonal or d.move_unfocused_diagonal) or speed*.7071
    end
    local vx,vy=dx*speed,-dy*speed
    local x=clamp(p.x+vx*11,-184,184)
    local y=clamp(p.y+vy*11,32,432)
    local score=math.abs(x-goal_x)*.09+math.abs(y-goal_y)*.055
    local edge=math.max(0,math.abs(x)-156)
    score=score+edge*.14+(focus and 0 or .5)
    local hit_soon=false
    for _,t in ipairs(look) do
        local px=clamp(p.x+vx*math.min(t,14),-184,184)
        local py=clamp(p.y+vy*math.min(t,14),32,432)
        local weight=1/(1+t/8)
        for _,s in ipairs(threats) do
            local predicted=s.prediction and s.prediction[t+lead]
            if t+lead>=s.delay and not (predicted and (predicted.deleted or predicted.no_collision)) then
                local sx,sy
                if predicted then sx,sy=math.abs(predicted.x-px),math.abs(predicted.y-py)
                else sx,sy=math.abs(s.x+s.vx*(t+lead)-px),math.abs(s.y+s.vy*(t+lead)-py) end
                local gap=s.box and math.max(sx,sy)-s.hit or math.sqrt(sx*sx+sy*sy)-s.hit
                if gap<1.2 and p.invulnerable<=t then
                    score=score+(t<=4 and 16000 or 950)*weight
                    if t<=4 then hit_soon=true end
                elseif gap<27 then
                    score=score+10*weight/math.max(1,gap+1.5)
                end
            end
        end
        local beams=lasers[t]
        if beams and #beams>0 then
            local candidate={x=px,y=py,hitbox=p.hitbox+1,hitbox_half=(p.hitbox_half or p.hitbox/2)+.5}
            for _,s in ipairs(beams) do
                local hit=Laser.contact(s,candidate)
                if hit and p.invulnerable<=t then
                    score=score+(t<=4 and 16000 or 1200)*weight
                    if t<=4 then hit_soon=true end
                end
            end
        end
    end
    return score,hit_soon
end

function Pilot.sample(stage,id,queued)
    local p=stage.players[id]
    if not p or not p.alive then return {} end
    if stage.dialogue and stage.dialogue.active then return {skip_dialogue=true} end
    if p.deathbomb_frames then
        local partner=stage.coop and stage.players[3-id]
        local designated=not partner or not partner.deathbomb_frames or stage.coop.focus==id
        return {bomb=designated and not p.classic_bomb and p.deathbomb_frames>1 and not p.bomb_down}
    end
    local lead=queued and #queued or 0
    if lead>0 and not p.respawn_frames then
        -- Existing inputs will move the player before the new LAN input runs.
        -- Predict on a copy so the audit never changes the battle state.
        local predicted=setmetatable(snapshot(p),Player)
        local speed_scale=ClassicBombs.master_spark(p) and .2 or 1
        for _,input in ipairs(queued) do
            Player.move(predicted,input.move_x,input.move_y,input.focus,speed_scale)
        end
        predicted.invulnerable=math.max(0,p.invulnerable-lead)
        p=predicted
    end
    local threats,lasers=threats_for(stage,p,lead)
    local beam_positions=laser_positions(lasers,lead,stage.adapter.player,p)
    local goal_x,goal_y=goal_for(stage,p,threats,id)
    local chosen,chosen_focus,imminent,best=moves[1],true,false,math.huge
    for _,m in ipairs(moves) do
        for _,focus in ipairs(focus_modes) do
            local score,risk=rate(p,threats,beam_positions,m[1],m[2],focus,goal_x,goal_y,lead)
            if score<best then chosen,chosen_focus,imminent,best=m,focus,risk,score end
        end
    end
    local gauge=p.combat_runtime and p.combat_runtime.p_gauge
    if gauge then
        local owner=stage.players[id]
        if gauge.value<=40 then reloading[owner]=true
        elseif gauge.value>=85 then reloading[owner]=nil end
    end
    local bomb_owner=not stage.coop or id==(stage.coop.focus or 1)
    local danger=imminent or best>320
    return {shoot=not reloading[stage.players[id]],focus=chosen_focus,move_x=chosen[1],move_y=chosen[2],
        bomb=gauge~=nil and bomb_owner and danger and p.invulnerable<=1 and (p.bomb_frames or 0)<=lead}
end
return Pilot
