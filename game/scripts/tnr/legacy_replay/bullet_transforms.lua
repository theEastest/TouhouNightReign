-- Sequential TH13+ etEx programs. Parameters follow MERLIN's documented
-- transforms; etEx appends, etExSet replaces a zero-based slot. Async entries
-- run alongside subsequent entries, rather than replacing the whole program.
local T={}
local float32=require("tnr.legacy_replay.reference_rules").float32
local function real(n,fallback) return n and n>-99999 and n or fallback end
local function velocity(s,angle,speed)
    s.angle,s.speed=angle,speed
    s.vx,s.vy=math.cos(angle)*speed,math.sin(angle)*speed
end
local function tick(s,state,player,spawn_ticks)
    local e=state.e;local f=e.flags
    -- TH15's line-laser interpreter (442370) has no bullet-to-laser opcode;
    -- inherited copies must not recursively spawn another laser every frame.
    if s.laser and (f==134217728 or f==16384) then return true end
    local n=state.n or 0;state.n=n+1
    local duration=math.max(1,e.int1 or 1)
    if f==2 then
        if n==0 then
            local mode = e.int1 or 0
            local age = s.anim_frame or 0
            state.started_in_flight = age > 0 or s.transform_pc > 2
            local interrupt = (state.started_in_flight or mode ~= 1) and 7 + mode or nil
            local ticks, offset
            if spawn_ticks then ticks, offset = spawn_ticks(s, interrupt) end
            state.ticks = ticks or ({[0]=8,[1]=14,[2]=25})[mode] or 8
            if state.started_in_flight then state.ticks = state.ticks + 1; offset = -1 end
            s.spawn_effect = true
            s.spawn_effect_id, s.spawn_effect_age, s.spawn_animation_offset = interrupt, age, offset
            s.legacy_bullet_animation=nil
            s.x=s.x-s.vx*4;s.y=s.y-s.vy*4*(s.reflected and -1 or 1)
        end
        local live = n >= state.ticks
        s.no_collision = not live and (s.anim_frame or 0) < 8
        s.motion_scale = state.started_in_flight and n == 0 and 1 or 0.5
        if live then
            -- 419494 applies its half-step before the VM releases the bullet
            -- into normal motion and the next transforms on the same tick.
            s.x = s.x + s.vx * 0.5
            s.y = s.y + s.vy * 0.5 * (s.reflected and -1 or 1)
            if (s.anim_frame or 0)>=8 then
                s.birth_contact_x,s.birth_contact_y=s.x,s.y
            end
            s.motion_scale = 1
        end
        return live
    elseif f==1 then
        -- 41c8a0 keeps the terminal n=16 step active; n=17 releases it.
        if n>16 then return true end
        if n==0 then state.speed=s.speed end
        velocity(s,s.angle,state.speed+5*math.max(0,1-n/16))
        return false
    elseif f==4 or f==2097152 then
        -- 41c99c / 442f6c test the acceleration clock before applying it.
        -- The following instruction starts one tick after the last speed
        -- change, using the position reached by that final displacement.
        if n>=duration then return true end
        -- Laser growth has its own audited rounding and timing. This change
        -- targets ordinary projectile scalar/vector state only.
        if s.laser then
            if n==0 then state.rate=f==4 and real(e.float1,0) or (real(e.float1,s.speed)-s.speed)/duration end
            local angle=real(e.float2,s.angle)
            s.vx=s.vx+math.cos(angle)*state.rate;s.vy=s.vy+math.sin(angle)*state.rate
            s.speed=(s.vx*s.vx+s.vy*s.vy)^.5
            s.angle=math.atan2 and math.atan2(s.vy,s.vx) or math.atan(s.vy,s.vx)
            return false
        end
        if n==0 and state.rate==nil then
            local rate=f==4 and real(e.float1,0)
                or float32(float32(real(e.float1,s.speed))-float32(s.speed))/duration
            state.rate=float32(rate)
            local angle=real(e.float2,s.angle)
            -- 41bd7e..41be71 and 41cbc0 store scalar and vector increments
            -- separately. The acceleration direction is fixed on entry.
            state.accel_x=float32(math.cos(angle)*state.rate)
            state.accel_y=float32(math.sin(angle)*state.rate)
        end
        -- Some saved/debug fixtures predate cached acceleration components.
        if state.accel_x==nil then
            local angle=real(e.float2,s.angle)
            state.accel_x=float32(math.cos(angle)*state.rate)
            state.accel_y=float32(math.sin(angle)*state.rate)
        end
        s.speed=float32(float32(s.speed)+state.rate)
        s.vx=float32(float32(s.vx)+state.accel_x)
        s.vy=float32(float32(s.vy)+state.accel_y)
        if math.abs(s.vx)>0.0001 or math.abs(s.vy)>0.0001 then
            s.angle=float32(math.atan2 and math.atan2(s.vy,s.vx) or math.atan(s.vy,s.vx))
        end
        return false
    elseif f==8 then
        velocity(s,s.angle+real(e.float2,0),s.speed+real(e.float1,0))
        return state.n>=duration
    elseif f==16 then
        -- Native 41b4cc..41b584 samples once when the transform starts,
        -- and reuses that sample for every step (not once per turn).
        duration=math.max(0,e.int1 or 1)
        if n==0 and not state.initialized then
            state.turn=real(e.float1,0);state.target_speed=real(e.float2,s.speed)
            if e.int3==3 then
                -- 41b4b5 saves the stored heading plus float1; 41cfc4
                -- adds that stored heading again when the turn completes.
                state.turn=(s.saved_angle or s.angle)+state.turn
            elseif e.int3==5 or e.int3==6 then
                state.turn=(s.random or function(a,b) return (a+b)/2 end)(-1,1)*state.turn
            elseif e.int3==7 then
                state.target_speed=s.speed+(s.random or function(a,b) return (a+b)/2 end)(-1,1)*real(e.float2,0)
            end
        end
        -- 41cf50/41d08f evaluate the current clock before 41d0f3 advances
        -- it: the initial tick has phase zero, subsequent cycles start at 1.
        local phase=duration==0 and 0 or n==0 and 0 or (n-1)%duration+1
        if n==0 or (phase==1 and n>1) then state.speed=s.speed end
        if phase==duration then
            local angle=s.angle+state.turn
            if (e.int3==1 or e.int3==6) and player then
                local dx,dy=player.x-s.x,player.y-s.y
                angle=(math.atan2 and math.atan2(dy,dx) or math.atan(dy,dx))+state.turn
            elseif e.int3==2 and player then
                local dx,dy=player.x-(s.saved_x or s.x),player.y-(s.saved_y or s.y)
                angle=(math.atan2 and math.atan2(dy,dx) or math.atan(dy,dx))+real(e.float1,0)
            elseif e.int3==3 then angle=(s.saved_angle or s.angle)+state.turn
            elseif e.int3==4 then angle=real(e.float1,s.angle)
            elseif e.int3==7 then angle=s.angle end
            velocity(s,angle,state.target_speed)
        else velocity(s,s.angle,state.speed*(1-phase/duration)) end
        if duration==0 then return state.n>=math.max(1,e.int2 or 1) end
        return n>=duration*math.max(1,e.int2 or 1)
    elseif f==-2147483648 then
        -- 41960a checks the countdown before decrementing it. The next
        -- transform starts on the tick after the countdown reaches zero.
        return (e.int1 or 0)<=0 or state.n>duration
    elseif f==1048576 then s.transform_blend=e.int1==1 and "mul+add" or "";return true
    elseif f==2048 then
        s.transform_sounds=s.transform_sounds or {};s.transform_sounds[#s.transform_sounds+1]=e.int1
        return true
    elseif f==262144 then velocity(s,real(e.float1,s.angle),real(e.float2,s.speed));return true
    elseif f==1024 then s.deleted=true;return true
    elseif f==64 then
        if s.laser_kind=="moving" then
            -- 4429e0: bounce at the leading tip; leave the parent travelling
            -- in the old direction and emit a fresh child at the wall.
            if (e.int1 or 0)<=0 then return true end
            if n==0 then state.bounce_speed=real(e.float1,s.native_transform_start_speed or s.speed) end
            local walls=e.int2 or 15
            local function has(bit) return math.floor(walls/bit)%2==1 end
            local tipx=s.x+math.cos(s.angle)*(s.length or 0)
            local tipy=s.y+math.sin(s.angle)*(s.length or 0)
            local crossed={}
            if has(1) and tipy<0 then crossed[#crossed+1]={'y',0} end
            if has(2) and tipy>448 then crossed[#crossed+1]={'y',448} end
            if has(4) and tipx< -192 then crossed[#crossed+1]={'x',-192} end
            if has(8) and tipx>192 then crossed[#crossed+1]={'x',192} end
            if #crossed==0 then return false end
            if not has(16) then
                for _,wall in ipairs(crossed) do
                    local t=wall[1]=='x' and (wall[2]-s.x)/(tipx-s.x) or (wall[2]-s.y)/(tipy-s.y)
                    local x,y=s.x+t*(tipx-s.x),s.y+t*(tipy-s.y)
                    local vx,vy=math.cos(s.angle),math.sin(s.angle)
                    if wall[1]=='x' then vx=-vx else vy=-vy end
                    local a=math.atan2 and math.atan2(vy,vx) or math.atan(vy,vx)
                    s.bounce_emissions=s.bounce_emissions or {}
                    s.bounce_emissions[#s.bounce_emissions+1]={x=x,y=y,angle=a,speed=state.bounce_speed,entry=e}
                end
            end
            return true
        end
        local walls=e.int2 or 15
        local function has(bit) return math.floor(walls/bit)%2==1 end
        local w=has(32) and real(e.float2,384) or 384
        local h=has(32) and real(e.float3,448) or 448
        local bounced=false
        if has(1) and s.y<0 and s.vy<0 then s.y=-s.y;s.vy=-s.vy;bounced=true end
        if has(2) and s.y>h and s.vy>0 then s.y=2*h-s.y;s.vy=-s.vy;bounced=true end
        if has(4) and s.x< -w/2 and s.vx<0 then s.x=-w-s.x;s.vx=-s.vx;bounced=true end
        if has(8) and s.x>w/2 and s.vx>0 then s.x=w-s.x;s.vx=-s.vx;bounced=true end
        if bounced then
            local angle=math.atan2 and math.atan2(s.vy,s.vx) or math.atan(s.vy,s.vx)
            velocity(s,angle,real(e.float1,s.speed));state.bounces=(state.bounces or 0)+1
        end
        return (state.bounces or 0)>=math.max(0,e.int1 or 1)
    elseif f==32768 then
        s.custom_mode=e.int1 or 0
        if s.laser then s.laser_handle=s.custom_mode end
        return true
    elseif f==256 then s.keep_offscreen=math.max(s.keep_offscreen or 0,duration);return true
    elseif f==128 then s.bomb_invulnerable=math.max(s.bomb_invulnerable or 0,duration);return true
    elseif f==8388608 then
        s.saved_x,s.saved_y=s.x,s.y
        -- 41c032..41c060 stores the bullet's own angle and speed, not its aim.
        s.saved_angle,s.saved_speed=s.angle,s.speed
        return true
    elseif f==512 then
        s.sprite=real(e.int1,s.sprite);s.color_index=(e.int2 or 0)%32768
        s.legacy_bullet_animation=nil
        return true
    elseif f==33554432 then s.draw_layer=e.int1 or 0;return true
    elseif f==16777216 and e.routine then
        -- 41bf97..41c027: create an ECL controller at the bullet's current
        -- position; copy the transform's four integer/float creation slots.
        s.transform_enemies=s.transform_enemies or {}
        s.transform_enemies[#s.transform_enemies+1]={entry=e,x=s.x,y=s.y}
        return true
    elseif f==134217728 then s.laser_prep=e;return true
    elseif f==16384 and s.laser_prep then
        s.transform_emissions=s.transform_emissions or {}
        s.transform_emissions[#s.transform_emissions+1]={prep=s.laser_prep,finish=e,
            x=s.x,y=s.y,angle=s.angle,speed=s.speed}
        local flags=s.laser_prep.int4 or 0
        if s.laser_prep.int1==1 then
            if math.floor(flags/65536)%2==1 then s.deleted=true end
        elseif flags~=0 then s.deleted=true end
        s.laser_prep=nil
        return true
    elseif f==0 then return true
    end
    s.unsupported_transform=f
    s.unsupported_transforms=s.unsupported_transforms or {};s.unsupported_transforms[f]=true
    return true
end
-- 41b00e..41b0e8 starts a leading birth animation before the newly
-- spawned projectile can be observed by later enemy callbacks. Native birth
-- has no active transform bit, so the interpreter can install immediate and
-- asynchronous operations behind it while their clocks remain frozen.
function T.prepare_spawn(s,player,spawn_ticks)
    local program=s.transforms
    if not program or not program[1] or program[1].flags~=2 then return false end
    s.transform_pc=2
    local birth={e=program[1],n=0}
    if tick(s,birth,player,spawn_ticks) then return false end
    s.transform_birth=birth
    s.birth_spawn_pending=true
    s.transform_active={}
    local immediate={ [1048576]=true,[32768]=true,[512]=true,[33554432]=true,
        [8388608]=true,[262144]=true,[2048]=true }
    local active={ [1]=true,[4]=true,[8]=true,[16]=true,[64]=true,
        [2097152]=true,[-2147483648]=true }
    for _=1,64 do
        local e=program[s.transform_pc]
        if not e then return true end
        for _,v in ipairs(s.transform_active) do
            if not e.async or v.e.flags==e.flags then return true end
        end
        local flag=e.flags
        if flag==256 and (e.int2 or 0)==0 then
            tick(s,{e=e,n=0},player,spawn_ticks)
            s.birth_offscreen_pending=true
        elseif immediate[flag] then
            tick(s,{e=e,n=0},player,spawn_ticks)
        elseif active[flag] then
            local state={e=e,n=0}
            if flag==4 or flag==2097152 then
                local duration=math.max(1,e.int1 or 1)
                local rate=flag==4 and real(e.float1,0)
                    or float32(float32(real(e.float1,s.speed))-float32(s.speed))/duration
                state.rate=float32(rate)
                local angle=real(e.float2,s.angle)
                state.accel_x=float32(math.cos(angle)*state.rate)
                state.accel_y=float32(math.sin(angle)*state.rate)
            elseif flag==16 then
                state.turn=real(e.float1,0);state.target_speed=real(e.float2,s.speed)
                if e.int3==3 then state.turn=(s.saved_angle or s.angle)+state.turn
                elseif e.int3==5 or e.int3==6 then
                    state.turn=(s.random or function(a,b) return (a+b)/2 end)(-1,1)*state.turn
                elseif e.int3==7 then
                    state.target_speed=s.speed+(s.random or function(a,b) return (a+b)/2 end)(-1,1)*real(e.float2,0)
                end
                state.initialized=true
            end
            s.transform_active[#s.transform_active+1]=state
        else
            -- Unsupported initializers remain at the program counter rather
            -- than being executed speculatively; later ordinary updates use
            -- the established interpreter path.
            return true
        end
        s.transform_pc=s.transform_pc+1
    end
    error("bullet transform creation instruction budget exceeded")
end
function T.update(s,player,spawn_ticks)
    s.birth_contact_x,s.birth_contact_y=nil,nil
    if not s.transforms then return end
    if s.transform_birth then
        if s.birth_spawn_pending then s.birth_spawn_pending=nil;return end
        if not tick(s,s.transform_birth,player,spawn_ticks) then return end
        s.transform_birth=nil
        s.birth_offscreen_pending=nil
    end
    s.transform_pc=s.transform_pc or 1;s.transform_active=s.transform_active or {}
    local kept={}
    for _,state in ipairs(s.transform_active) do if not tick(s,state,player,spawn_ticks) then kept[#kept+1]=state end end
    s.transform_active=kept
    if s.transform_block then
        if not tick(s,s.transform_block,player,spawn_ticks) then return end
        if s.transform_block.e.flags==2 then s.birth_offscreen_pending=nil end
        s.transform_block=nil
    end
    for _=1,64 do
        local e=s.transforms[s.transform_pc]
        if not e then return end
        -- Native 41b1e2..41b200: a synchronous instruction waits for every
        -- active transform, and even async instructions cannot overlap the
        -- same transform type. The async bit does not mean fire-and-forget.
        for _,active in ipairs(s.transform_active) do
            if not e.async or active.e.flags==e.flags then return end
        end
        s.transform_pc=s.transform_pc+1
        local state={e=e,n=0}
        if not tick(s,state,player,spawn_ticks) then
            if (e.async and e.flags~=2) or ((s.laser_kind=="moving" or s.laser_kind=="curve") and e.flags==-2147483648) then s.transform_active[#s.transform_active+1]=state
            else
                s.transform_block=state
                -- 41b242 sets birth state without an active transform bit;
                -- 41b888 can therefore install an immediately following
                -- offscreen guard before the birth animation releases. Its
                -- clock is paused while the bullet remains in birth state.
                -- Limit this path to the timer-only form observed in stage 3.
                local next_entry=s.transforms[s.transform_pc]
                if not s.laser and e.flags==2 and #s.transform_active==0 and (s.keep_offscreen or 0)==0
                    and next_entry and next_entry.flags==256 and (next_entry.int2 or 0)==0 then
                    tick(s,{e=next_entry,n=0},player,spawn_ticks)
                    s.transform_pc=s.transform_pc+1
                    s.birth_offscreen_pending=true
                end
                return
            end
        end
    end
    error("bullet transform instruction budget exceeded")
end
return T
