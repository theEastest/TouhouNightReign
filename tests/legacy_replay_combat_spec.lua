return function(eq,ok)
    local Stage=require("tnr.legacy_replay.stage_runtime")
    local Interfaces=require("tnr.legacy_replay.interfaces")
    local Items=require("tnr.legacy_replay.items")
    local Rules=require("tnr.legacy_replay.reference_rules")
    eq(Rules.point_score(10003,300,128,true),10000,"auto collection awards rounded maximum point value")
    eq(Rules.point_score(10000,300,128,false),4630,"low pickup uses native height reduction")
    eq(Rules.point_score(10000,148,148,false),10000,"Marisa's higher collection line is respected")
    local Transform=require("tnr.legacy_replay.bullet_transforms")
    local random_calls=0
    local stepped={x=0,y=0,angle=0,speed=3,vx=3,vy=0,
        random=function(a,b) random_calls=random_calls+1;return a+(b-a)*.75 end,
        transforms={{flags=16,int1=2,int2=2,int3=5,float1=1,float2=4}}}
    Transform.update(stepped)
    eq(stepped.speed,3,"a flag 16 turn keeps its initial speed on clock zero")
    Transform.update(stepped)
    eq(stepped.speed,1.5,"the first deceleration occurs at clock one")
    Transform.update(stepped)
    eq(stepped.speed,4,"the turn restores its target speed at clock two")
    Transform.update(stepped)
    eq(stepped.speed,2,"the next turn starts its deceleration at clock one")
    Transform.update(stepped)
    eq(stepped.angle,1,"random step adds the sampled turn on each repetition")
    eq(random_calls,1,"random turn is sampled once per transform")
    local async_birth={x=0,y=0,angle=0,speed=3,vx=3,vy=0,transforms={
        {flags=1,async=true},{flags=16,int1=4,int2=1,int3=4,float1=0,float2=4}}}
    for _=1,17 do Transform.update(async_birth) end
    eq(async_birth.speed,3,"the terminal birth-speed step remains active")
    eq(async_birth.transform_pc,2,"the following synchronous turn waits through the terminal step")
    Transform.update(async_birth)
    eq(async_birth.speed,3,"the following turn starts at phase zero after release")
    Transform.update(async_birth)
    eq(async_birth.speed,2.25,"the turn decelerates on its next tick")
    local instant={x=0,y=0,angle=1,saved_angle=math.pi/2,speed=.075,vx=0,vy=.075,
        random=function() return 0 end,transforms={
            {flags=16,int1=0,int2=1,int3=3,float1=0,float2=.8},
            {flags=16,int1=0,int2=1,int3=5,float1=.017453292,float2=-999999},
            {flags=16,int1=0,int2=1,int3=7,float1=-999999,float2=.2},
            {flags=1048576,int1=1}}}
    Transform.update(instant)
    ok(math.abs(instant.angle-math.pi)<1e-12,"mode three adds the stored heading at setup and completion")
    eq(instant.speed,.8,"two zero-duration random turns retain the target speed in the same tick")
    eq(instant.transform_blend,"mul+add","the instruction after zero-duration turns starts immediately")
    local repeated={x=0,y=0,angle=0,speed=1,vx=1,vy=0,
        transforms={{flags=16,int1=0,int2=2,int3=0,float1=.5,float2=1}}}
    Transform.update(repeated)
    eq(repeated.angle,.5,"the first zero-duration repetition runs immediately")
    ok(repeated.transform_block~=nil,"additional zero-duration repetitions wait for another tick")
    Transform.update(repeated)
    eq(repeated.angle,1,"the next tick completes the second repetition")
    stepped={x=0,y=0,angle=1,speed=3,vx=3,vy=0,
        random=function() return -.5 end,
        transforms={{flags=16,int1=2,int2=1,int3=7,float1=0,float2=2}}}
    Transform.update(stepped);Transform.update(stepped);Transform.update(stepped)
    eq(stepped.speed,2,"mode seven offsets initial speed by signed random amplitude")
    eq(stepped.angle,1,"mode seven keeps the original heading")
    local accelerated={x=0,y=0,angle=0,speed=0,vx=0,vy=0,sprite=5,
        transforms={{flags=4,int1=2,float1=1,float2=0},{flags=512,int1=8,int2=6}}}
    Transform.update(accelerated);Transform.update(accelerated)
    eq(accelerated.speed,2,"acceleration applies exactly its two configured changes")
    eq(accelerated.sprite,5,"the following transform waits through the final acceleration displacement")
    Transform.update(accelerated)
    eq(accelerated.speed,2,"releasing acceleration does not apply an extra speed change")
    eq(accelerated.sprite,8,"the following transform starts when the completed clock is checked")
    -- Original stage five actor 1467, 22924 -> 22925. funcSet(4)
    -- slows the vector while retaining the scalar used by acceleration.
    local slow_adapter=require("tnr.legacy_replay.adapter").new({lstg={},chunks={}})
    slow_adapter.player={x=0,y=0,alive=true,hitbox=2}
    local slowed={x=10,y=0,vx=1.5,vy=0,speed=1.5,angle=0,sprite=25,custom_mode=1}
    slow_adapter.shots={slowed}
    slow_adapter:apply_enemy_function({legacy_func=4,legacy_globals={F0=.98}})
    ok(math.abs(slowed.vx-1.4700000286102295)<1e-8 and slowed.speed==1.5,
        "graze slowdown changes the velocity vector but not nominal speed")
    local native_accel={x=-118.22378540039,y=383.18511962891,
        vx=-0.0779593288898468,vy=0.1389079988002777,
        speed=1.5,angle=2.0822205543518066,
        transforms={{flags=2097152,int1=120,float1=2,float2=-999999}}}
    Transform.update(native_accel)
    ok(math.abs(native_accel.speed-1.5041667222976685)<1e-7
        and math.abs(native_accel.vx-(-0.07999857515096664))<1e-7
        and math.abs(native_accel.vy-0.1425415277481079)<1e-7,
        "native acceleration updates nominal speed and vector independently")
    local ax,ay=native_accel.transform_block.accel_x,native_accel.transform_block.accel_y
    native_accel.vx,native_accel.vy,native_accel.angle=0,1,math.pi/2
    Transform.update(native_accel)
    ok(math.abs(native_accel.vx-ax)<1e-7 and math.abs(native_accel.vy-(1+ay))<1e-7,
        "an active acceleration retains its initial vector direction")
    local after_accel={vx=.1,vy=0,speed=1.5,angle=0,transforms={
        {flags=2097152,int1=1,float1=2,float2=-999999},
        {flags=8,int1=1,float1=0,float2=0}}}
    Transform.update(after_accel);Transform.update(after_accel)
    ok(math.abs(after_accel.speed-2)<1e-7 and math.abs(after_accel.vx-2)<1e-7,
        "the next transform reads nominal speed rather than vector length")
    -- Native 41b00e..41b0e8 initializes a leading birth at creation,
    -- then 41b180 installs later operations before subsequent enemies run.
    local birth_random_calls=0
    local birth_adapter=require("tnr.legacy_replay.adapter").new({lstg={},chunks={},
        random=function() birth_random_calls=birth_random_calls+1;return .5 end})
    local function make_birth(program)
        local before=#birth_adapter.shots
        birth_adapter:spawn_bullet(nil,-35.940109691986,281.01858522426,4,
            2.4048654526452,25,nil,false,0,nil,program)
        return birth_adapter.shots[before+1]
    end
    local born=make_birth({{flags=2,int1=1},{flags=1048576,int1=1},
        {flags=2097152,int1=30,float1=7,float2=-999999},{flags=32768,int1=0}})
    local bx,by=born.x,born.y
    ok(math.abs(bx-(-35.940109691986-math.cos(2.4048654526452)*16))<1e-8
        and born.no_collision and born.transform_birth ~= nil,
        "creation applies birth setback before enemy callbacks")
    ok(born.transform_pc==4 and #born.transform_active==1
        and born.transform_active[1].e.flags==2097152
        and born.transform_active[1].n==0 and math.abs(born.transform_active[1].rate-.1)<1e-7,
        "post-birth acceleration is installed but initially frozen")
    birth_adapter:apply_enemy_function({legacy_func=2,legacy_globals={F0=64},x=-92.96,y=296.68})
    ok(not born.deleted,"original stage-five bullet survives the moon's same-frame callback")
    Transform.update(born)
    ok(born.transform_birth.n==1 and born.x==bx and born.y==by,
        "first bullet update does not repeat the birth setback")
    for age=1,13 do
        born.anim_frame=age;Transform.update(born)
        ok(born.transform_birth and born.speed==4 and born.transform_active[1].n==0,
            "acceleration stays frozen during birth")
    end
    born.anim_frame=14;Transform.update(born)
    ok(not born.transform_birth and born.transform_active[1].n==1 and born.speed>4,
        "acceleration starts when the birth animation releases")
    local instant=make_birth({{flags=2,int1=0},{flags=32768,int1=1},
        {flags=256,int1=50},{flags=1048576,int1=1}})
    ok(instant.custom_mode==1 and instant.keep_offscreen==50 and instant.birth_offscreen_pending
        and instant.transform_blend=="mul+add" and instant.transform_pc==5,
        "independent post-birth immediate operations install in program order")
    local turning=make_birth({{flags=2,int1=1},
        {flags=16,int1=2,int2=1,int3=5,float1=1,float2=3},{flags=32768,int1=1}})
    ok(birth_random_calls==1 and turning.transform_pc==3
        and turning.transform_active[1].e.flags==16 and turning.transform_active[1].turn==.5,
        "birth-time turn samples its random parameter once and gates a synchronous successor")
    Transform.update(turning)
    for age=1,14 do turning.anim_frame=age;Transform.update(turning) end
    eq(birth_random_calls,1,"birth release does not resample the turn")
    local parallel_birth=make_birth({{flags=2,int1=1},
        {flags=4,int1=4,float1=.1,float2=0,async=true},
        {flags=8,int1=2,float1=.2,float2=0,async=true},{flags=32768,int1=1}})
    ok(#parallel_birth.transform_active==2 and parallel_birth.transform_pc==4
        and parallel_birth.custom_mode==nil,
        "different asynchronous transforms install together while the synchronous successor waits")
    local deferred_birth=make_birth({{flags=2,int1=1},{flags=128,int1=20}})
    ok(deferred_birth.transform_pc==2 and deferred_birth.bomb_invulnerable==nil,
        "unsupported birth initializer remains at the program counter")
    local plain_birth=make_birth({{flags=4,int1=1,float1=1}})
    ok(not plain_birth.transform_birth and math.abs(plain_birth.x-(-35.940109691986))<1e-9,
        "a program without a leading birth is unchanged")
    local Laser=require("tnr.legacy_replay.laser")
    -- 4423bf/44975f gate on the next instruction's async bit. A laser's
    -- countdown stays active while an async acceleration starts beside it.
    for _,kind in ipairs({"moving","curve"}) do
        local function timed(parallel)
            return {laser=true,laser_kind=kind,angle=0,speed=.3,vx=.3,vy=0,anim_frame=1,transforms={
                {flags=-2147483648,int1=3,async=false},
                {flags=4,int1=2,float1=.1,float2=-999999,async=parallel}}}
        end
        local parallel=timed(true)
        Transform.update(parallel)
        ok(math.abs(parallel.speed-.4)<1e-9,kind.." async acceleration starts during countdown")
        eq(#parallel.transform_active,2,kind.." countdown and acceleration both remain active")
        local serial=timed(false)
        for _=1,3 do Transform.update(serial);ok(math.abs(serial.speed-.3)<1e-9,kind.." sync acceleration waits") end
        Transform.update(serial)
        ok(math.abs(serial.speed-.4)<1e-9,kind.." sync acceleration starts after countdown")
    end
    -- Original stage three 15760/15761: the tip crosses the left wall;
    -- the parent continues and the new reflected segment begins at the
    -- intersection, at its initial speed with a fresh acceleration clock.
    local bounce_program={{flags=-2147483648,int1=180,async=false},
        {flags=4,int1=60,float1=.033333,float2=-999999,async=true},
        {flags=64,int1=2,int2=15,float1=-999999,async=true}}
    local bounced=Laser.new({angle=-2.687598466873169,speed=.3,transforms=bounce_program},
        {initial=18,length=128,width=16,timing={0,0,0,0,0}},-175.31289672851562,448,"moving",1)
    bounced.anim_frame=26;bounced.speed=1.166658;bounced.keep_offscreen=180
    bounced.vx=math.cos(bounced.angle)*bounced.speed;bounced.vy=math.sin(bounced.angle)*bounced.speed
    bounced.transform_pc=4
    bounced.transform_active={{e=bounced.transforms[1],n=26},{e=bounced.transforms[2],n=26,rate=.033333},
        {e=bounced.transforms[3],n=26,bounce_speed=.3}}
    local bounce_adapter=require("tnr.legacy_replay.adapter").new({lstg={},chunks={}})
    bounce_adapter.shots={bounced};bounce_adapter:advance_shots()
    eq(#bounce_adapter.shots,1,"laser tip inside wall emits no bounce child")
    bounced.length=19.499887466430664
    local parent_angle=bounced.angle
    bounce_adapter:advance_shots()
    eq(#bounce_adapter.shots,2,"wall crossing keeps the parent and appends a child")
    ok(bounce_adapter.shots[1]==bounced and bounced.angle==parent_angle and bounced.length>19.499887,
        "parent continues in its original direction")
    local child=bounce_adapter.shots[2]
    ok(math.abs(child.x+192)<1e-6 and math.abs(child.y-439.856842)<.001,
        "child is born at the original wall intersection")
    ok(math.abs(child.angle-(-.453994274))<1e-5,"child uses the reflected direction")
    eq(child.anim_frame,1,"child updates in its native birth frame")
    ok(math.abs(child.length-.333333)<1e-6,"child starts at original speed and reapplies acceleration")
    eq(child.transforms[3].int1,1,"child inherits one fewer remaining bounce")
    eq(bounced.transforms[3].int1,2,"parent transform program is retained")
    bounce_adapter:advance_shots()
    eq(child.anim_frame,2,"child advances normally after its birth")
    ok(math.abs(child.length-.699999)<2e-6,"second growth matches the original sample")
    local beam=Laser.new({angle=math.pi/2,speed=4,sprite=8,color_index=4},
        {initial=0,length=128,travel=0,width=16},20,40,"moving",1)
    for _=1,32 do Laser.update(beam) end
    eq(beam.length,128,"moving laser grows to ECL maximum length")
    eq(beam.y,40,"laser tail stays at emitter while growing")
    Laser.update(beam)
    eq(beam.y,44,"full-length laser tail travels at ECL speed")
    local reflected_beam=Laser.new({angle=math.pi/2,speed=4},
        {initial=128,length=128,width=16},20,140,"moving",2)
    reflected_beam.reflected=true
    for _=1,4 do Laser.update(reflected_beam) end
    eq(reflected_beam.y,124,"copied moving laser reverses vertical travel")
    ok(Laser.contact(reflected_beam,{x=20,y=60,hitbox=2}),"copied laser hitbox follows the reflected beam")
    local contact={x=20,y=100,hitbox=2}
    ok(Laser.contact(beam,contact),"laser damages along its body, away from emitter")
    contact.x=35
    local hit,graze,graze_x,graze_y=Laser.contact(beam,contact)
    ok(not hit and graze,"laser grazing uses an oriented strip")
    ok(math.abs(graze_x-20)<1e-8 and math.abs(graze_y-100)<1e-8,
        "laser graze effect projects onto the beam beside the ship")
    contact.x=42
    hit,graze=Laser.contact(beam,contact)
    ok(not hit and not graze,"Reimu does not graze the stage-four laser at an offset above twenty")
    -- Native stage 5 frame 17866: state 2, age 2, length 24, width 16
    -- already grazes. Moving collision has strict length/width limits rather
    -- than an unconditional three-frame startup delay (44365b..443675).
    local young=Laser.new({angle=0,speed=12},
        {initial=0,length=128,width=16,timing={0,0,0,0,0}},0,0,"moving",5)
    local young_hit={x=12,y=0,hitbox=2}
    local young_graze={x=12,y=18,hitbox=2}
    ok(not Laser.contact(young,young_hit),"new laser waits for its first update")
    Laser.update(young)
    ok(not Laser.contact(young,young_hit),"moving laser length below sixteen cannot hit")
    Laser.update(young)
    hit,graze=Laser.contact(young,young_graze)
    ok(not hit and graze,"moving laser can graze at age two")
    ok(Laser.contact(young,young_hit),"moving laser can hit at age two")
    young.length=16
    ok(not Laser.contact(young,young_hit),"moving laser length sixteen is excluded")
    young.length=16.0001
    ok(Laser.contact(young,young_hit),"moving laser length above sixteen is active")
    young.width=3;young.draw_width=3
    ok(not Laser.contact(young,young_hit),"moving laser width three is excluded")
    young.width=3.0001;young.draw_width=3.0001
    ok(Laser.contact(young,young_hit),"moving laser width above three is active")
    young.deleted=true
    ok(not Laser.contact(young,young_hit),"deleted moving laser cannot hit")
    young.deleted=false;young.native_full_cancel_pending=true
    ok(not Laser.contact(young,young_hit),"cancelled moving laser cannot hit")
    local fast_young=Laser.new({angle=0,speed=24},
        {initial=0,length=128,width=16,timing={0,0,0,0,0}},0,0,"moving",6)
    Laser.update(fast_young)
    ok(Laser.contact(fast_young,young_hit),"a long moving laser can hit on its first update")
    -- Native stage 5 frame 3855: stationary contact checks state and length
    -- at 445b63..445b84, without the moving laser's minimum-width condition.
    local thin_stationary={laser=true,laser_kind="stationary",x=-64.239158630371,
        y=47.020965576172,angle=1.5707963705063,length=512,width=16,
        draw_width=.53333336,no_collision=false}
    local thin_player={x=-52.09375,y=432,hitbox=2,hitbox_half=1}
    hit,graze=Laser.contact(thin_stationary,thin_player)
    ok(not hit and graze,"stationary laser grazes during thin growth")
    thin_stationary.length=16
    hit,graze=Laser.contact(thin_stationary,thin_player)
    ok(not hit and not graze,"stationary laser requires length greater than sixteen")
    thin_stationary.length=512;thin_stationary.no_collision=true
    hit,graze=Laser.contact(thin_stationary,thin_player)
    ok(not hit and not graze,"inactive stationary laser does not graze")
    thin_stationary.no_collision=false;thin_stationary.laser_kind="moving"
    hit,graze=Laser.contact(thin_stationary,thin_player)
    ok(not hit and not graze,"moving laser still requires width greater than three")
    local curve={laser=true,laser_kind="curve",width=28,draw_width=28,nodes={
        {x=0,y=100,angle=math.pi/2,speed=12},{x=0,y=88,angle=math.pi/2,speed=12},
        {x=0,y=76,angle=math.pi/2,speed=12},{x=0,y=64,angle=math.pi/2,speed=12}}}
    ok(not Laser.contact(curve,{x=0,y=112,hitbox=2}),"the first forward tangent is skipped before sixteen accumulated units")
    ok(Laser.contact(curve,{x=0,y=100,hitbox=2}),"the next node's forward tangent reaches the visible curve head")
    ok(Laser.contact(curve,{x=0,y=106,hitbox=2}),"the native collision origin includes its half-tangent offset")
    curve.width,curve.draw_width=40,40
    ok(Laser.contact(curve,{x=10,y=88,hitbox=2}),"wide curves retain a quarter-width hit strip")
    local scheduled=Laser.new({angle=0,speed=12,transforms={
        {flags=8,async=true,int1=30,int2=0,float1=0,float2=-.034906585},
        {flags=8,async=true,int1=30,int2=30,float1=0,float2=.034906585},
        {flags=8,async=true,int1=30,int2=60,float1=-.12,float2=0}}},
        {width=28,timing={64,0,0,0,0}},0,100,"curve",3)
    Laser.update(scheduled)
    eq(#scheduled.nodes,64,"unborn curve nodes remain at their emitter")
    eq(scheduled.x,0,"the first curve tick samples age zero without moving")
    ok(not scheduled.no_collision,"curves participate in collision on their first native update")
    Laser.update(scheduled)
    eq(scheduled.x,12,"curve movement uses the initial direction before the first turn")
    eq(scheduled.y,100,"curve motion does not rotate one tick before moving")
    for _=3,31 do Laser.update(scheduled) end
    ok(math.abs(scheduled.nodes[1].angle+math.pi/3)<1e-6,"the second curve program starts at absolute age thirty")
    for _=32,61 do Laser.update(scheduled) end
    ok(math.abs(scheduled.nodes[1].angle)<1e-6,"opposite thirty-frame turns cancel without a delayed transition")
    eq(scheduled.speed,12,"acceleration scheduled at age sixty has not changed its starting speed")
    Laser.update(scheduled)
    ok(math.abs(scheduled.speed-11.88)<1e-5,"the next interval accelerates once after its first displacement")
    local departed={laser_kind="moving",x=0,y=-15,angle=-math.pi/2,length=128,width=14,anim_frame=40}
    ok(not Laser.in_field(departed),"departed lasers are culled once both endpoints leave the native width margin")
    departed.y=-13
    ok(Laser.in_field(departed),"the full visual width remains part of the endpoint culling margin")
    local reflected_curve=require("tnr.core.immutable").copy(scheduled)
    reflected_curve.reflected=true
    local original_y,reflected_y=scheduled.y,reflected_curve.y
    Laser.update(scheduled);Laser.update(reflected_curve)
    ok(math.abs((scheduled.y-original_y)+(reflected_curve.y-reflected_y))<1e-5,
        "a copied curve reverses future vertical displacement without moving its old nodes")
    -- Captured from TH15 1.00b, Normal stage six, first BossCard2 curve.
    -- Ages are the native post-update clock; point zero samples age - 1.
    local native_curve=Laser.new({angle=-1.0471972227096558,speed=12,transforms={
        {flags=8,async=true,int1=30,int2=0,float1=0,float2=-.034906585},
        {flags=8,async=true,int1=30,int2=30,float1=0,float2=.034906585}}},
        {width=28,timing={64,0,0,0,0}},-111.68000030517578,447.9200134277344,"curve",4)
    local native_nodes={
        {2,-105.68000030517578,437.5277099609375},
        {15,-63.04639434814453,288.8466796875},
        {30,-100.04642486572266,114.77566528320312},
        {31,-105.68009185791016,104.1802978515625},
        {32,-111.68009948730469,93.78799438476562},
        {60,-117.31380462646484,-228.9640655517578},
        {61,-111.68014526367188,-239.55943298339844},
        {90,62.32000732421875,-540.9362182617188},
    }
    for _,sample in ipairs(native_nodes) do
        local point=require("tnr.legacy_replay.curve_laser").point(native_curve.curve_motion,sample[1]-1)
        ok(math.abs(point.x-sample[2])<.002 and math.abs(point.y-sample[3])<.002,
            "curved-laser position matches the executable's sampled node at age "..sample[1])
    end
    local growing=Laser.new({speed=.4,transforms={{flags=-2147483648,int1=60},
        {flags=4,int1=120,float1=.1}}},{length=128,width=16},0,128,"moving",1)
    for _=1,101 do Laser.update(growing) end
    ok(math.abs(growing.length-126.49998474121)<1e-6,
        "stage-four laser accelerates with native single-precision growth after the wait")
    local stationary=Laser.new({angle=0,speed=16},
        {initial=0,length=512,width=48,timing={20,30,60,30,0}},-180,300,"stationary",0)
    local newborn=Laser.new({angle=0,speed=16},
        {initial=256,length=512,width=48,timing={20,30,60,30,0}},-180,300,"stationary",0)
    ok(not Laser.contact(newborn,{x=0,y=300,hitbox=2}),"a newborn laser cannot hit before its warning")
    for _=1,20 do Laser.update(stationary) end
    eq(stationary.draw_width,2,"fixed laser starts as a narrow warning")
    ok(stationary.no_collision,"warning cannot hit")
    for _=1,30 do Laser.update(stationary) end
    ok(math.abs(stationary.draw_width-46.4)<1e-5,"fixed laser retains its penultimate growth width")
    Laser.update(stationary)
    eq(stationary.draw_width,48,"fixed laser completes its width transition")
    for _=1,90 do Laser.update(stationary) end
    ok(stationary.deleted,"fixed laser disappears after its original four timed phases")
    -- Original stationary laser 250688496, frames 19644–19734. The
    -- warning->growth and full->shrink transitions retain the prior width on
    -- their first tick, before the interpolator advances.
    local native_phase=Laser.new({speed=16},
        {initial=16,length=640,width=16,timing={30,30,30,30,0}},0,0,"stationary",0)
    local phase_samples={
        [30]={2,true,false},[31]={2,false,false},[32]={.5333333611488342,false,false},
        [60]={15.466666221618652,false,false},[61]={16,false,false},[90]={16,false,false},
        [91]={16,true,false},[92]={15.466666221618652,true,false},
        [120]={.5333337783813477,true,false},[121]={0,true,true},
    }
    for age=1,121 do
        Laser.update(native_phase)
        local sample=phase_samples[age]
        if sample then
            ok(math.abs(native_phase.draw_width-sample[1])<1e-6
                and not not native_phase.no_collision==sample[2]
                and not not native_phase.deleted==sample[3],
                "fixed laser native phase width and activity at age "..age)
        end
    end
    local function stage(mode,random,character)
        return Stage.new({lstg={},anm=require("tnr.legacy_replay.data.th15_anm"),
            chunks={},sht=require("tnr.legacy_replay.data.th15_sht"),random=random,character=character,
            session=Interfaces.ReplaySession.new({mode=mode=="modern" and Interfaces.modern_mode() or Interfaces.classic_mode()})})
    end
    -- Native ordinary bullets store position and velocity in float32. These
    -- two-step samples are from the stage-one boundary projectiles.
    local float_stage=stage("classic")
    local first={x=115.40245819091797,y=216.73428344726562,
        vx=1.4851876497268677,vy=0.5951619744300842,sprite=7,color_index=2,anim_frame=100,keep_offscreen=50}
    float_stage.adapter.shots={first}
    float_stage.adapter:advance_shots()
    eq(first.x,116.88764953613281,"native projectile x after first single-precision addition")
    eq(first.y,217.32945251464844,"native projectile y after first single-precision addition")
    float_stage.adapter:advance_shots()
    eq(first.x,118.37284088134766,"native projectile x after second single-precision addition")
    eq(first.y,217.92462158203125,"native projectile y after second single-precision addition")
    local second={x=81.12061309814453,y=133.41273498535156,
        vx=-1.5869165658950806,vy=0.20419561862945557,sprite=7,color_index=2,anim_frame=100,keep_offscreen=50}
    float_stage.adapter.shots={second};float_stage.adapter:advance_shots()
    eq(second.x,79.53369903564453,"native negative-x projectile step")
    eq(second.y,133.61692810058594,"native small-y projectile step")
    local born={x=10,y=20,vx=1.25,vy=2.5,sprite=7,color_index=2,anim_frame=0,keep_offscreen=50,
        transforms={{flags=2,int1=0}}}
    float_stage.adapter.shots={born};float_stage.adapter:advance_shots()
    eq(born.x,5.625,"birth transform followed by a half-speed position step")
    eq(born.y,11.25,"birth transform followed by a half-speed vertical step")
    local turning={x=10,y=20,vx=1,vy=0,sprite=7,color_index=2,anim_frame=100,keep_offscreen=50,
        angle=0,speed=1,transforms={{flags=16,int1=2,int2=1,int3=1,float1=1,float2=1}}}
    float_stage.adapter.shots={turning}
    for _=1,3 do
        local x,y=turning.x,turning.y
        float_stage.adapter:advance_shots()
        eq(turning.x,Rules.float32(Rules.float32(x)+Rules.float32(turning.vx)),"turn updates velocity before position x")
        eq(turning.y,Rules.float32(Rules.float32(y)+Rules.float32(turning.vy)),"turn updates velocity before position y")
    end
    ok(turning.vy~=0,"turn changes projectile direction")
    local accelerating={x=10,y=20,vx=0,vy=1,sprite=7,color_index=2,anim_frame=100,keep_offscreen=50,
        angle=math.pi/2,speed=1,transforms={{flags=4,int1=3,float1=0.1,float2=0}}}
    float_stage.adapter.shots={accelerating};float_stage.adapter:advance_shots()
    eq(accelerating.x,Rules.float32(10+Rules.float32(accelerating.vx)),"acceleration precedes float position update")
    local dead={x=0,y=20,vx=1,vy=2,sprite=7,color_index=2,anim_frame=100,deleted=true}
    float_stage.adapter.shots={dead};float_stage.adapter:advance_shots()
    eq(#float_stage.adapter.shots,0,"deleted ordinary projectile is removed")
    eq(dead.x,0,"deleted ordinary projectile is not moved")
    local clipping=stage("classic")
    clipping.adapter:spawn_bullet(nil,201,200,0,0,4,0,false,6)
    for _=1,5 do clipping.adapter:advance_shots() end
    eq(#clipping.adapter.shots,1,"new offscreen shot gets five ticks to enter the field")
    clipping.adapter:advance_shots()
    eq(#clipping.adapter.shots,0,"offscreen shot is removed when its sprite has no overlap")
    local edge_graze=stage("classic")
    local edge_player=edge_graze.players[1]
    edge_player.x,edge_player.y=-8.7734375,432
    edge_graze.adapter.shots={{x=-19.710859881671,y=455.85802491738,
        vx=-0.042008226266311,vy=0.69873836943877,sprite=5,color_index=6,anim_frame=247,
        grazed_by={[1]={age=90,timer=30,interval=30}}}}
    edge_graze.adapter:advance_shots()
    eq(#edge_graze.adapter.shots,0,"an offscreen bullet is absent from persistent storage")
    edge_graze:resolve_player_hits()
    eq(edge_player.graze,1,"the offscreen bullet still grazes before its final cull")
    edge_graze:resolve_player_hits()
    eq(edge_player.graze,1,"a culled bullet is not checked again")
    eq(#edge_graze.adapter.shots,0,"the final contact does not restore the culled bullet")
    clipping.adapter:spawn_bullet(nil,225,200,0,0,26,0,false,0)
    for _=1,6 do clipping.adapter:advance_shots() end
    eq(#clipping.adapter.shots,0,"a moon bullet uses the sprite chosen by its own ANM script for clipping")
    local ship=clipping.players[1]
    clipping.adapter.shots={{x=ship.x+30,y=ship.y,sprite=17}}
    clipping:resolve_player_hits()
    eq(ship.graze,0,"rectangular type seventeen has a smaller graze box than round shots")
    clipping.adapter.shots[1].x=ship.x+24
    clipping:resolve_player_hits()
    eq(ship.graze,1,"type seventeen grazes inside its axis-aligned box")
    local protected=stage("classic")
    local safe=protected.players[1]
    safe.invulnerable=20
    protected.adapter.shots={{x=safe.x+30,y=safe.y,sprite=8},{x=safe.x,y=safe.y,sprite=8}}
    protected:resolve_player_hits()
    eq(safe.deathbomb_frames,nil,"a protected contact cannot start a miss")
    eq(#protected.adapter.shots,1,"a protected hit still cancels the contacting bullet")
    eq(safe.graze,1,"invulnerability does not disable grazing nearby bullets")
    eq(protected.items.slowdown,Rules.float32(0.3),"protected graze still slows falling items")
    local modern_protected=stage("modern")
    local modern_ship=modern_protected.players[1]
    modern_ship.invulnerable=20
    modern_protected.adapter.shots={{x=modern_ship.x+24,y=modern_ship.y,sprite=17}}
    modern_protected:resolve_player_hits()
    eq(modern_ship.graze,1,"modern Bomb protection keeps original grazing")
    eq(modern_protected.items.slowdown,Rules.float32(0.3),"modern graze still slows falling items")

    local release=stage("classic")
    local near_ship=release.players[1]
    local rice={x=near_ship.x+20,y=near_ship.y,sprite=5,vx=0,vy=2,anim_frame=15,
        transform_pc=2,transforms={},transform_block={e={flags=2},n=15,ticks=15},
        grazed_by={[1]={age=44,timer=44,interval=60}}}
    release.adapter.shots={rice}
    release.adapter:advance_shots()
    release:resolve_player_hits()
    eq(rice.grazed_by[1].age,46,"the birth half-step and live step both accumulate contact")
    eq(#release.items.list,1,"crossing the native threshold yields only one graze drop")
    eq(release.items.list[1].y,near_ship.y+1,"the graze reward originates at the half-step")

    local clearing=stage("classic")
    clearing.adapter:spawn_bullet(nil,22,100,4,0,18,0,false,2)
    clearing.adapter.instructions.etClear({object={x=0,y=100}},nil,{20})
    eq(#clearing.adapter.shots,0,"scripted clear includes the edge of the bullet's hit box")
    eq(#clearing.adapter.cancelled_shots,1,"scripted clear keeps the native cancel animation")
    eq(clearing.adapter.cancelled_shots[1].x,24,"the fading projectile advances its final half-step")
    eq(clearing.items:count(),0,"scripted clear grants no cancel items")
    clearing.adapter:spawn_bullet(nil,22,100,4,0,18,0,false,2)
    local draws=clearing.adapter.rng.draws
    clearing.adapter.instructions.etCancel({object={x=0,y=100}},nil,{20})
    eq(clearing.items:count(),1,"scripted cancellation creates a point-value item")
    eq(clearing.items.list[1].kind,"cancel","scripted cancellation uses the original item type")
    eq(clearing.items.list[1].x,22,"the item launches before the visual half-step")
    eq(clearing.adapter.rng.draws,draws+2,"the item's launch consumes one original signed draw")
    clearing.items.list={}
    clearing.adapter.shots={Laser.new({angle=0,speed=0,sprite=8,color_index=6},
        {initial=64,length=64,width=14},0,100,"moving",10)}
    draws=clearing.adapter.rng.draws
    clearing.adapter.instructions.etCancel({object={x=0,y=100}},nil,{640})
    eq(#clearing.adapter.shots,1,"a fully cancelled moving laser remains linked for the current tick")
    ok(clearing.adapter.shots[1].native_full_cancel_pending,"full cancellation marks the original laser")
    ok(not Laser.contact(clearing.adapter.shots[1],clearing.players[1]),
        "a fully cancelled laser cannot hit while awaiting cleanup")
    eq(clearing.items:count(),4,"a sixty-four-unit laser drops four original cancel items")
    eq(clearing.items.list[1].x,8,"laser cancel items start eight units along the body")
    eq(clearing.items.list[4].x,56,"laser cancel items advance by sixteen units")
    eq(clearing.adapter.rng.draws,draws+8,"laser fragment launches consume their original item random draws")
    clearing.adapter:advance_shots()
    eq(#clearing.adapter.shots,0,"the next laser-manager update removes the cancelled laser")
    clearing.items.list={}
    clearing.adapter.shots={Laser.new({angle=0,speed=0,sprite=38},
        {initial=60,length=60,width=16},-192,68,"moving",10)}
    clearing.adapter.instructions.etCancel({object={x=0,y=128}},nil,{640})
    eq(clearing.items:count(),3,"the circle clear samples the three complete laser segments")
    clearing.adapter.instructions.laserCancel({object={}},nil,{})
    eq(clearing.items:count(),6,"same-tick laserCancel revisits the original three segments")
    eq(clearing.items.list[4].x,-184,"the second clear starts at the original first segment")
    eq(clearing.items.list[6].x,-152,"the second clear retains the original final segment")
    clearing.adapter:advance_shots()
    eq(#clearing.adapter.shots,0,"laserCancel finishes removing the revisited laser")
    local cancel_types=stage("classic")
    local effects=0
    function cancel_types.adapter:spawn_animation() effects=effects+1 end
    cancel_types.adapter.shots={
        {laser=true,laser_kind="curve",sprite=0,nodes={{x=0,y=100},{x=1,y=100},{x=2,y=100},{x=3,y=100}}},
        {laser=true,laser_kind="beam",sprite=0,x=0,y=100,angle=0,length=64},
    }
    cancel_types.adapter.instructions.laserCancel({object={}},nil,{})
    eq(cancel_types.items:count(),0,"curve and beam laserCancel do not create items")
    eq(effects,2,"curve laserCancel keeps its every-third-node visual effects")
    local short_tail=Laser.new({angle=0,speed=0},
        {initial=191.1,length=191.1,width=16},0,100,"moving",11)
    local tail_drops=0
    local untouched=Laser.cancel_in_circle(short_tail,184,100,1,function() tail_drops=tail_drops+1 end)
    eq(tail_drops,0,"an incomplete moving-laser tail cannot produce a cancel item")
    eq(#untouched,1,"a clear touching only an incomplete tail keeps the laser")
    local full_tail=Laser.new({angle=0,speed=0},
        {initial=192,length=192,width=16},0,100,"moving",11)
    Laser.cancel_in_circle(full_tail,184,100,1,function() tail_drops=tail_drops+1 end)
    eq(tail_drops,1,"a full moving-laser tail is included at the exact boundary")
    local stationary=Laser.new({angle=0,speed=16,sprite=38,color_index=2},
        {initial=64,length=512,width=48,timing={20,30,60,30,0}},0,100,"stationary",11)
    stationary.anim_frame=111
    local stationary_drops=0
    local stationary_pieces=Laser.cancel_in_circle(stationary,0,100,640,function() stationary_drops=stationary_drops+1 end)
    eq(stationary_drops,3,"stationary cancellation excludes the last half segment")
    eq(#stationary_pieces,0,"fully cancelled stationary laser creates no detached pieces")
    eq(stationary.length,0,"fully cancelled stationary laser truncates its current length")
    ok(not stationary.deleted,"fully cancelled stationary laser remains for its exit animation")
    for _=1,4 do Laser.update(stationary) end
    eq(stationary.length,64,"the exit animation can regrow the stationary laser")
    Laser.cancel_in_circle(stationary,0,100,640,function() stationary_drops=stationary_drops+1 end)
    eq(stationary_drops,6,"a second cancellation samples the regrown segment")
    local split=Laser.new({angle=0,speed=0},{initial=64,length=64,width=14},0,100,"moving",11)
    local pieces=Laser.cancel_in_circle(split,24,100,4)
    eq(#pieces,1,"a sixteen-unit prefix is discarded after a local clear")
    eq(pieces[1].x,32,"the surviving laser begins after the cancelled fragment")
    eq(pieces[1].length,32,"the thirty-two-unit remainder survives")
    local short_remainder=Laser.new({angle=0,speed=0},
        {initial=40,length=40,width=16},0,100,"moving",11)
    pieces=Laser.cancel_in_circle(short_remainder,8,100,1)
    eq(#pieces,0,"a twenty-four-unit moving-laser remainder is discarded")
    local long_remainder=Laser.new({angle=0,speed=0},
        {initial=47.6,length=47.6,width=16},0,100,"moving",11)
    pieces=Laser.cancel_in_circle(long_remainder,8,100,1)
    eq(#pieces,1,"a moving-laser remainder longer than twenty-four units survives")
    ok(math.abs(pieces[1].length-31.6)<1e-5,
        "the final moving-laser fragment retains its unsampled remainder")
    local growing=Laser.new({angle=0,speed=2},
        {initial=196,length=300,width=16},0,100,"moving",11)
    pieces=Laser.cancel_in_circle(growing,184,100,1)
    eq(#pieces,1,"clearing the tail leaves the long prefix")
    eq(pieces[1].length,176,"the surviving prefix ends before the removed segment")
    eq(pieces[1].max_length,280,"the prefix retains its original growth gap")
    Laser.update(pieces[1])
    eq(pieces[1].x,0,"a still-growing prefix does not move its tail early")
    eq(pieces[1].length,178,"the truncated prefix continues to grow")
    local precise=Laser.new({angle=0,speed=1.4},
        {initial=0,length=640,width=16},0,100,"moving",11)
    for _=1,40 do Laser.update(precise) end
    ok(math.abs(precise.length-56.000019073486)<1e-7,
        "moving-laser growth accumulates in native single precision")
    pieces=Laser.cancel_in_circle(precise,8,100,1)
    eq(#pieces,1,"the first cut leaves the long moving-laser tail")
    pieces=Laser.cancel_in_circle(pieces[1],24,100,1)
    eq(#pieces,1,"a float32 tail slightly longer than 24 remains active")
    ok(pieces[1].length>24 and pieces[1].length<24.001,
        "the original floating-point remainder is preserved")
    local native_split=Laser.new({angle=0,speed=1.4},
        {initial=308.1,length=640,width=16},0,100,"moving",11)
    native_split.speed,native_split.vx,native_split.anim_frame=6.9,6.9,114
    pieces=Laser.cancel_in_circle(native_split,208,100,25)
    eq(#pieces,2,"a central clear creates a prefix and a new tail")
    eq(pieces[2].length,64,"the new tail contains its four complete native segments")
    eq(pieces[2].anim_frame,0,"a split tail begins a fresh update clock")
    eq(pieces[2].speed,1.4,"a split tail starts at its original launch speed")
    eq(pieces[2].keep_offscreen,30,"a new moving-laser tail starts the native 30-frame offscreen grace")
    Laser.update(pieces[2])
    ok(math.abs(pieces[2].x-241.4)<1e-6 and pieces[2].anim_frame==1,
        "the new tail moves once using its launch speed")
    -- 442148 initializes +0x5a4 to 30; 443320 tests it before the
    -- decrement, so an offscreen child survives tick 30 and exits on 31.
    local grace_parent=Laser.new({angle=0,speed=1.4},
        {initial=128,length=128,width=16},0,-20,"moving",12)
    grace_parent.anim_frame=115;grace_parent.keep_offscreen=0
    local grace_pieces=Laser.cancel_in_shape(grace_parent,function(x) return x>=48 and x<64 end)
    eq(#grace_pieces,2,"a central clear emits a new tail for grace testing")
    local grace_child=grace_pieces[2]
    eq(grace_child.keep_offscreen,30,"the split tail resets grace instead of inheriting the parent countdown")
    local grace_adapter=require("tnr.legacy_replay.adapter").new({lstg={},chunks={}})
    grace_adapter.shots={grace_child}
    for age=1,30 do
        grace_adapter:advance_shots()
        eq(#grace_adapter.shots,1,"offscreen split tail survives native grace tick "..age)
        eq(grace_child.keep_offscreen,30-age,"split grace decrements once per update")
    end
    grace_adapter:advance_shots()
    eq(#grace_adapter.shots,0,"offscreen split tail is removed after grace expires")
    local curved=Laser.new({angle=0,speed=1},{width=16,timing={10,0,0,0,0}},0,100,"curve",12)
    local curve_drops=0
    pieces=Laser.cancel_in_circle(curved,0,100,640,function() curve_drops=curve_drops+1 end)
    eq(#pieces,0,"a fully cancelled curve removes every node")
    eq(curve_drops,4,"curve cancellation emits at every third native node")
    local curve_clock=stage("classic")
    local grazing_ship=curve_clock.players[1]
    grazing_ship.x,grazing_ship.y=0,118
    local clocked_curve={laser=true,laser_kind="curve",width=28,draw_width=28,anim_frame=5,nodes={
        {x=0,y=100,angle=0,speed=12},{x=-12,y=100,angle=0,speed=12},
        {x=-24,y=100,angle=0,speed=12},{x=-36,y=100,angle=0,speed=12}}}
    curve_clock.adapter.shots={clocked_curve}
    curve_clock:resolve_player_hits()
    eq(grazing_ship.graze,0,"entering a curve does not restart its global graze clock")
    clocked_curve.anim_frame=7
    curve_clock:resolve_player_hits()
    eq(grazing_ship.graze,1,"a curve awards graze on its existing three-frame clock")

    local bodies=stage("classic")
    local ship=bodies.players[1]
    ship.invulnerable=0
    local moon={x=ship.x+60,y=ship.y,hp=500,legacy_hitbox={96,96},legacy_body_graze=true}
    bodies.adapter.enemies={moon}
    bodies:resolve_player_hits()
    eq(ship.graze,1,"grazing the moon body contributes to the chapter")
    eq(bodies.items.slowdown,Rules.float32(Rules.graze_slowdown),"body graze slows falling items")
    bodies.adapter.frame=1
    bodies:resolve_player_hits()
    eq(ship.graze,1,"moon body graze is limited to every sixth enemy tick")
    moon.x,moon.legacy_hitbox=ship.x+8.1,{16,16}
    bodies:resolve_player_hits()
    eq(ship.deathbomb_frames,8,"body contact includes the player's collision radius")

    local pickup=stage("classic")
    local point=pickup.items:spawn("point",-150,100)
    local graze=pickup.items:spawn_graze(-150,100,1,-math.pi/2)
    pickup:_update_simulation()
    ok(not point.attracted,"a distant point stays out of proximity range below the collect line")
    ok(pickup:use_bomb(1),"classic Bomb starts an automatic collection window")
    for _=1,3 do pickup:_update_simulation() end
    ok(point.auto_collect and point.x>-150,"early Bomb attracts distant points towards the ship")
    ok(graze.rising_graze and not graze.attracted and graze.y<100,
        "a launched graze reward finishes its upward flight during Bomb collection")
    local reflection=stage("modern")
    local driver=reflection.modern.drivers[1]
    driver.bridge.update=function() driver.p_gauge.event=2;return {} end
    reflection.adapter:spawn_bullet(nil,0,80,2,math.pi/2,8,0,false,6)
    local source=reflection.adapter.shots[1]
    eq(reflection:bullet_image(source),"tnr-th15-bullet-1-135","source bullet is already drawn before the copy")
    reflection.modern:input(1,{})
    local duplicate=reflection.adapter.shots[2]
    eq(reflection:bullet_image(duplicate),"tnr-th15-bullet-1-135","reflected bullet creates a working animation VM")
    ok(duplicate.legacy_bullet_animation~=source.legacy_bullet_animation,"the copy owns its animation state")
    reflection.adapter:advance_shots()
    eq(source.y,82,"the original bullet continues downwards")
    eq(duplicate.y,78,"its copy moves upwards")
    local scatter=stage("classic")
    scatter.adapter.instructions.enmCreateA(scatter.adapter.runtime:spawn("main"),scatter.adapter.runtime,
        {"Fairy",0,100,100,1000,1})
    local dropper=scatter.adapter.enemies[1]
    dropper.legacy_drop_extra={[2]=1}
    scatter:drop_enemy_items(dropper,true)
    eq(scatter.items.list[1].kind,"power","enmCreate supplies the main power drop")
    eq(scatter.items.list[1].y,100,"main drop comes from the enemy's position")
    eq(scatter.items.list[2].kind,"point","extra drop uses its own item type")
    eq(scatter.adapter.rng.draws,6,"drop scatter uses the same RNG as ECL")
    scatter.items:spawn_graze(0,100,1)
    eq(scatter.adapter.rng.draws,8,"graze reward launch advances the shared game RNG")
    scatter:drop_enemy_items(dropper,true)
    eq(#scatter.items.list,3,"dropItems consumes the main and extra entries")
    dropper.hp,dropper.legacy_drop=0,7
    scatter.adapter.run_death_routine=function(_,enemy)
        eq(enemy.legacy_drop,0,"death routine runs after consuming the configured drop")
        eq(scatter.items.list[4].kind,"bomb","death routine runs after creating the drop")
    end
    scatter:drop_enemy_items(dropper,false)
    local items=Items.new({})
    local launch=items:spawn("power",250,100)
    eq(launch.x,192,"original item spawn clamps to playfield side")
    eq(launch.vy,Rules.float32(-2.2),"ordinary drops use original upward launch speed")
    items.list={}
    items:spawn("power",0,440)
    for _=1,180 do items:update() end
    eq(items:count(),0,"missed drops leave the bottom of the y-down field")
    eq(#items:drain_collected(),0,"leaving the screen is not collection")
    local orphan=items:spawn("power",0,440);orphan.attracted=true
    for _=1,180 do items:update() end
    eq(items:count(),0,"attraction ends when its player is absent")
    local Input=require("tnr.input.luastg_input")
    local input=Input.new({Input={Keyboard={GetKeyState=function() return 0 end}}})
    eq(input:key_down(13),false,"numeric zero is a released key")
    local s=stage("classic",function() return .25 end);local p=s.players[1]
    s.adapter:spawn_bullet(nil,0,50,2,math.pi/2,8,0,false,6,nil,{
        {flags=134217728,int1=0,int2=8,int3=6,int4=1,float1=-999999,float2=6,float3=32,float4=128},
        {flags=16384,int1=18,int2=38,int3=0,int4=0,float1=0,float2=16,float3=0,float4=0}})
    s.adapter:advance_shots()
    eq(#s.adapter.shots,1,"bullet-to-laser conversion removes its source")
    ok(s.adapter.shots[1].laser,"conversion creates a real laser")
    eq(s.adapter.shots[1].length,32,"converted laser keeps its initial length")
    for _=1,4 do s.adapter:advance_shots() end
    eq(#s.adapter.shots,1,"inherited conversion instructions do not recursively multiply lasers")
    s.adapter.shots={}
    local moon={x=0,y=0,legacy_func=2,legacy_globals={F0=64}}
    s.adapter.enemies={moon}
    s.adapter.shots={{x=30,y=0,vx=4,vy=2,sprite=26},{x=80,y=0},{x=20,y=0,player_bullet=true},
        {x=10,y=0,custom_mode=1}}
    s.adapter:apply_enemy_function(moon)
    ok(s.adapter.shots[1].deleted and not s.adapter.shots[2].deleted
        and not s.adapter.shots[3].deleted and not s.adapter.shots[4].deleted,
        "Clownpiece moon cancels only ordinary enemy bullets within original radius")
    eq(#s.adapter.cancelled_shots,1,"moon cancellation preserves a visual with no damage or pickup")
    local cancelled=s.adapter.cancelled_shots[1]
    eq(cancelled.x,32,"cancelled bullet takes a native half step")
    eq(cancelled.y,1,"cancelled bullet freezes after its half step")
    eq(s:bullet_image(cancelled),"tnr-th15-bullet-1-343","moon bullet uses the original cancel sprite")
    eq(cancelled.legacy_bullet_animation:global_sprite(),342,"moon bullet runs interrupt 1 of script 109")
    for _=1,13 do s.adapter:advance_shots() end
    eq(#s.adapter.cancelled_shots,1,"moon bullet dissolves over the script's fourteen frames")
    ok(cancelled.legacy_bullet_animation.alpha<255,"moon bullet fades during the cancellation")
    eq(cancelled.y,1,"the visual does not move during cancellation")
    s.adapter:advance_shots()
    eq(#s.adapter.cancelled_shots,0,"cancel sprite is removed when its original script ends")
    moon.legacy_func=3;moon.legacy_globals.F0=1.3;moon.legacy_globals.F1=-.5
    s.adapter.shots={{x=0,y=100,laser=true,laser_handle=0},{x=0,y=100,laser=true,laser_handle=1}}
    s.adapter:apply_enemy_function(moon)
    eq(s.adapter.shots[1].y,101.3,"laser callback scrolls first row using F0")
    eq(s.adapter.shots[2].y,99.5,"laser callback scrolls other rows using F1")
    s.adapter.enemies={};s.adapter.shots={}
    s:add_graze(1,3)
    eq(p.graze,3,"ordinary graze is counted")
    eq(s.point_rate,10003,"native internal +100 maps to one displayed maximum point")
    s.point_rate=499999;s:add_graze(1,3)
    eq(s.point_rate,500000,"Normal maximum point value uses the original cap")
    s.point_rate=10000;p.point_rate=10000
    local reward_items=Items.new({random=function(a,b) return b end})
    local reward=reward_items:spawn_graze(0,0)
    ok(math.abs(reward.vx-math.sin(math.pi/18)*2.2)<1e-6,
        "graze rewards use the original ten-degree launch spread")
    local body={x=144,y=-16};local t={object=body,runtime=s.adapter.runtime}
    local ins=s.adapter.instructions
    ins.movePos(t,nil,{"0.0f","128.0f"})
    eq(body.x,0,"Boss movePos applies X immediately")
    eq(body.y,128,"Boss movePos applies Y immediately")
    ins.moveLimit(t,nil,{"0.0f","128.0f","280.0f","64.0f"})
    eq(body.legacy_move_limit.top,96,"Boss limit is centered on its supplied position")
    local movement=require("tnr.legacy_replay.adapter").new({lstg={},seed=20616})
    local midboss={x=0,y=128,legacy_move_limit=body.legacy_move_limit}
    movement.player={x=1.0859375,y=322.7109375}
    movement.instructions.moveRand({object=midboss},nil,{60,4,1})
    for _=1,60 do movement:advance_enemy_movement(midboss) end
    ok(math.abs(midboss.x-28.68)<.011 and math.abs(midboss.y-122.19)<.011,
        "stage-four midboss random movement uses the native speed interpolator")
    eq(midboss.legacy_speed,0,"random movement stops at the end of the speed interpolation")
    midboss.hp,midboss.legacy_globals,midboss.legacy_ext_damage=1000,{I3=0},1
    movement:damage_enemy(midboss,15)
    eq(midboss.hp,970,"the original external damage callback doubles direct damage")
    midboss.legacy_globals.I3=220
    movement:apply_pending_damage(midboss)
    eq(midboss.hp,750,"an orb adds damage even on a tick without player shots")
    eq(midboss.legacy_globals.I3,0,"orb damage is consumed once")
    midboss.legacy_globals.I3=400
    midboss.legacy_invulnerable_until=(movement.frame or 0)+1
    movement:apply_pending_damage(midboss)
    eq(midboss.hp,750,"invulnerability blocks queued orb damage")
    eq(midboss.legacy_globals.I3,0,"invulnerability consumes the callback before damage protection")
    midboss.legacy_invulnerable_until=0
    midboss.legacy_no_damage=true
    midboss.legacy_globals.I3=400
    movement:apply_pending_damage(midboss)
    eq(midboss.hp,750,"the no-damage flag blocks queued orb damage")
    eq(midboss.legacy_globals.I3,0,"the no-damage flag does not retain the callback")
    midboss.legacy_no_damage=false
    movement:begin_spell({object=midboss},{0,2400,500000,"Test"})
    movement:damage_enemy(midboss,5)
    eq(midboss.hp,748,"spell HP uses the original scaled accumulator after direct damage")
    movement:damage_enemy(midboss,2)
    eq(midboss.hp,748,"successive hits preserve the fractional spell HP")
    movement.instructions.spellEnd({object=midboss})
    movement:damage_enemy(midboss,2)
    eq(midboss.hp,744,"damage returns to its ordinary scale after the card")
    ins.movePos(t,nil,{-130,128})
    ins.moveRand(t,nil,{60,4,1})
    ok(body.legacy_vx>0,"random movement near the left boundary steers toward the centre")
    ins.anmSelect(t,nil,{"3"});ins.anmSetMain(t,nil,{"0","0"})
    for _=1,8 do ins.anmSelectedPlay(t,nil,{"0"}) end
    eq(#(s.adapter.animations or {}),0,"Boss attack pose never spawns permanent detached bodies")
    eq(body.legacy_anm.script,5,"attack pose uses existing body slot")
    s.adapter.boss_object={x=0,y=0}
    s.adapter.player={x=-10,y=10}
    ok(math.abs(s.adapter.runtime.host.globals.ANGLE_PLAYER-math.pi*.75)<1e-9,
        "aim angle keeps the left-hand quadrant in LuaJIT and Lua 5.4")
    s.adapter.boss_object=nil;s.adapter.player=p
    s.items:spawn("power",p.x,p.y);s.items:update()
    eq(#s.items:drain_collected(),1,"touching a fresh item collects immediately")
    local e={x=0,y=100,hp=200,legacy_hurtbox={40,40}}
    local near,far,protected={x=0,y=350,vx=0,vy=1},{x=180,y=48},{x=0,y=355,bomb_invulnerable=1}
    s.adapter.enemies={e};s.adapter.shots={near,far,protected}
    s:apply_input(1,{bomb=true});eq(s.session.bombs_left[1],2,"Bomb spends one stock")
    s:update_bombs();eq(#p.classic_bomb.orbs,8,"Reimu launches eight independently moving orbs")
    eq(s.adapter.shots[1],far,"Reimu cancels within range of the active orb")
    eq(s.adapter.shots[2],protected,"Bomb invulnerability preserves protected bullets")
    eq(s.items.list[1].kind,"cancel","ordinary Bomb cancels drop original PIV items")
    s.session.roster:set_input(1,{sample=function() return {bomb=true} end})
    for _=1,280 do s:_update_simulation() end
    eq(s.session.bombs_left[1],2,"held Bomb never retriggers")
    ok(e.hp<200,"Bomb damages actual enemies")
    eq(p.classic_bomb,nil,"Reimu can spend another Bomb after the last orb fades")
    local reisen=stage("classic",nil,"reisen")
    local shielded=reisen.players[1]
    local untouched={x=0,y=400,hp=100,legacy_hurtbox={40,40},legacy_no_contact=true}
    reisen.adapter.enemies={untouched}
    reisen.adapter.shots={{x=0,y=390},{x=0,y=200}}
    ok(reisen:use_bomb(1),"Reisen spends a stock for her shield")
    for _=1,32 do reisen:_update_simulation() end
    eq(shielded.hitbox,7.5,"three barriers enlarge Reisen's hitbox")
    eq(#reisen.adapter.shots,1,"shield startup wave clears locally")
    eq(untouched.hp,100,"Reisen Bomb does not deal area damage")
    for layer=2,0,-1 do
        reisen.adapter.shots={{x=shielded.x,y=shielded.y,sprite=0},{x=60,y=400},{x=180,y=200}}
        reisen:resolve_player_hits()
        eq(shielded.classic_bomb and shielded.classic_bomb.layers or 0,layer,"collision removes one shield layer")
        eq(shielded.invulnerable,30,"shield break grants thirty frames of protection")
        eq(#reisen.adapter.shots,1,"shield break cancels nearby bullets")
        eq(shielded.deathbomb_frames,nil,"shield absorbs a miss before the deathbomb window")
        for _=1,32 do reisen:_update_simulation() end
        eq(shielded.hitbox,3+1.5*layer,"hitbox follows remaining barriers")
    end
    eq(reisen.session:bomb_count(1),2,"breaking shields does not spend extra Bombs")
    eq(reisen.session:life_count(1),2,"three shield hits cost no life")
    local laser_wave=stage("classic",nil,"reisen")
    laser_wave.players[1].x,laser_wave.players[1].y=0,100
    laser_wave.adapter.shots={Laser.new({angle=0,speed=0,sprite=8,color_index=6},
        {initial=128,length=128,width=14},-64,100,"moving",20)}
    ok(laser_wave:use_bomb(1),"a barrier wave can clear laser fragments")
    laser_wave.players[1].classic_bomb.age=4
    laser_wave:update_bombs()
    eq(#laser_wave.adapter.shots,2,"the local Bomb wave preserves laser sections outside its radius")
    eq(laser_wave.items:count(),2,"Bomb laser fragments release the same cancel items as scripted clears")
    local marisa=stage("classic",nil,"marisa")
    local spark=marisa.players[1]
    local in_beam={x=0,y=180,hp=300,legacy_hurtbox={16,16}}
    local beside={x=170,y=180,hp=300,legacy_hurtbox={16,16}}
    marisa.adapter.enemies={in_beam,beside}
    marisa:apply_input(1,{shoot=true,bomb=true})
    marisa:update_bombs()
    eq(spark.shots_fired,0,"Master Spark suspends the ordinary shot")
    eq(in_beam.hp,240,"overlapping Bomb sources share the original damage cap")
    eq(beside.hp,300,"Master Spark damage stays inside the beam")
    marisa:apply_input(1,{move_x=1})
    marisa:update_bombs()
    eq(spark.x,math.floor(math.floor(spark.definition.move_unfocused*128)*.2)/128,
        "Master Spark movement uses the native fixed point multiplier")
    ok(spark.classic_bomb.angle>-math.pi/2,"moving right steers Master Spark to the right")
    local sanae=stage("classic",nil,"sanae")
    local shrine=sanae.players[1]
    local fixed={x=0,y=380}
    local later={x=180,y=170}
    sanae.adapter.shots={fixed,later}
    sanae.adapter.spell_active=true
    ok(sanae:use_bomb(1),"Sanae starts an expanding field")
    shrine.x=-130
    for _=1,60 do sanae:_update_simulation() end
    eq(sanae.adapter.shots[1],later,"Sanae's first wave stays centered at the cast position")
    eq(#sanae.items.list,0,"a spell's regular Bomb cancel yields no PIV drop")
    for _=1,145 do sanae:_update_simulation() end
    eq(#sanae.adapter.shots,0,"Sanae's delayed burst reaches the far bullet")
    local deathbomb=stage("classic")
    local survivor=deathbomb.players[1]
    deathbomb.adapter.shots={{x=survivor.x,y=survivor.y,sprite=0}}
    deathbomb:resolve_player_hits()
    eq(survivor.deathbomb_frames,8,"classic contact opens the original Bomb window")
    for _=1,6 do deathbomb:apply_input(1,{}) end
    deathbomb:apply_input(1,{bomb=true})
    ok(survivor.alive and not survivor.deathbomb_frames,"Bomb cancels the impending miss on the last eligible frame")
    eq(deathbomb.session:life_count(1),2,"deathbomb saves the life")
    eq(deathbomb.session:bomb_count(1),2,"deathbomb uses a real Bomb")
    eq(#deathbomb.items.list,0,"deathbomb does not drop power")
    local missed=stage("classic")
    local ship=missed.players[1]
    missed.session.power[1],ship.power=4,400
    missed:on_player_contact(1,ship)
    for _=1,7 do missed:apply_input(1,{}) end
    ok(ship.alive,"classic contact preserves the opportunity to Bomb")
    local frozen_x,frozen_y=ship.x,ship.y
    missed:apply_input(1,{bomb=true,move_x=1,move_y=1})
    ok(ship.alive and ship.deathbomb_frames==0,"the expired window retains one final frozen frame")
    eq(ship.x,frozen_x,"the expired window cannot move horizontally")
    eq(ship.y,frozen_y,"the expired window cannot move vertically")
    eq(missed.session:life_count(1),2,"the final frozen frame does not spend a life")
    eq(missed.session:bomb_count(1),3,"a Bomb on the final frozen frame is rejected")
    missed:apply_input(1,{bomb=true})
    ok(not ship.alive,"the following frame resolves the miss without a late Bomb")
    eq(ship.power,400,"life loss does not immediately reduce classic power")
    eq(#missed.items.list,0,"life loss does not immediately spawn miss drops")
    missed:_update_simulation();missed:_update_simulation()
    eq(ship.power,400,"classic miss power stays unchanged for two further frames")
    missed:_update_simulation()
    eq(ship.power,350,"confirmed classic miss loses half a power level")
    eq(#missed.items.list,7,"confirmed miss scatters seven small P points")
    ok(missed.items.list[1].vx<0 and missed.items.list[7].vx>0,"miss drops spread up and toward the field")
    eq(missed.session:bomb_count(1),3,"an expired deathbomb does not consume a Bomb")
    local coop_session=Interfaces.ReplaySession.new({mode=Interfaces.classic_mode(),
        roster=Interfaces.PlayerRoster.new({player_ids={1,2}})})
    local coop=Stage.new({lstg={},anm=require("tnr.legacy_replay.data.th15_anm"),
        chunks={},sht=require("tnr.legacy_replay.data.th15_sht"),session=coop_session})
    local team_life=coop_session.party.team_life
    for id=1,2 do coop:on_player_contact(id,coop.players[id]) end
    for _=1,7 do for id=1,2 do coop:apply_input(id,{}) end end
    for id=1,2 do coop:apply_input(id,{bomb=true}) end
    ok(coop.players[1].alive and coop.players[2].alive,"both players remain alive through the final frozen frame")
    eq(coop_session.party.team_life,team_life,"a frozen team does not spend a shared life early")
    for id=1,2 do coop:apply_input(id,{}) end
    eq(coop_session.party.team_life,team_life-1,"simultaneous expired windows spend one shared team life")
    local damage_state=stage("classic")
    local damage_player=damage_state.players[1]
    local function volley()
        local target={x=0,y=100,hp=100,legacy_hurtbox={48,48}}
        damage_state.adapter.enemies={target}
        damage_state.adapter.shots={{x=0,y=100,damage=11,player_bullet=true},
            {x=0,y=100,damage=11,player_bullet=true}}
        damage_state:resolve_player_damage()
        return target.hp
    end
    damage_player.deathbomb_frames=1
    eq(volley(),78,"the deathbomb window retains full player-shot damage")
    damage_player.deathbomb_frames=nil
    damage_player.alive=false;damage_player.classic_miss_protection=true
    eq(volley(),96,"death reduces the combined volley to one fifth, rounded down")
    damage_player.alive=true;damage_player.invulnerable=2
    eq(volley(),96,"post-miss protection retains the same reduction")
    ok(damage_state:use_bomb(1),"a protected player can start a Bomb")
    eq(volley(),78,"Bomb switches out of the reduced-damage state")
    damage_player.classic_bomb=nil
    damage_player.classic_miss_protection=true
    damage_state:apply_input(1,{})
    damage_state:apply_input(1,{})
    eq(volley(),78,"normal damage returns when post-miss protection ends")
    for _=1,31 do missed:advance_respawns() end
    eq(ship.y,480,"classic respawn enters below the field")
    for _=1,59 do missed:apply_input(1,{move_x=1}) end
    eq(ship.x,0,"classic player cannot steer during the respawn ascent")
    missed:apply_input(1,{move_x=1})
    eq(ship.y,400,"classic respawn reaches the original play position")
    ok(ship.x>0,"movement resumes on the last ascent frame")
    s.session.lives_left[1]=1;s:on_player_hit(1,p)
    eq(s.session:life_count(1),0,"zero means the final playable life")
    for _=1,40 do s:advance_respawns() end
    ok(p.alive,"last stock respawns")
    s:on_player_hit(1,p)
    eq(s.session:life_count(1),-1,"miss on last life ends run")
    for _=1,60 do s:advance_respawns() end
    eq(p.alive,false,"game over never respawns")
    local pellets=stage("classic")
    local fairy={x=-10,y=341,hp=100,legacy_hurtbox={24,24}}
    pellets.adapter.enemies={fairy}
    pellets.frames=19
    pellets:apply_input(1,{shoot=true})
    eq(#pellets.adapter.shots,0,"classic fire is locked through frame nineteen")
    pellets.frames=20
    pellets:apply_input(1,{shoot=true})
    pellets.adapter:advance_shots()
    eq(pellets.adapter.shots[1].y,392,"the first shot tick stays at the SHT muzzle")
    pellets:resolve_player_damage()
    eq(fairy.hp,100,"the shot does not hit before its first movement")
    pellets.adapter:advance_shots()
    pellets:resolve_player_damage()
    eq(fairy.hp,86,"the rotated shot box overlaps the fairy before its centre reaches it")
    local impact=pellets.adapter.shots[1]
    ok(impact.spent and not impact.deleted,"the Reimu hit retains a visible but spent projectile")
    eq(impact.speed,3,"Reimu's 24-speed projectile slows to 3 on contact")
    eq(impact.player_animation.sprite,27,"the original hit sprite replaces the travel sprite")
    pellets:resolve_player_damage()
    eq(fairy.hp,86,"the impact animation cannot hit the fairy again")

    -- Stage 1 native demo frame 3695: float32 subtraction rounds this
    -- side contact to 27 exactly even though double precision exceeds it.
    local boundary=stage("classic")
    local boss={x=27.270000457763672,y=138.02999877929688,hp=100,legacy_hurtbox={48,48}}
    boundary.adapter.enemies={boss}
    boundary.adapter.shots={{x=0.27000001072883606,y=150.5,angle=Rules.float32(-math.pi/2),
        hitbox_x=48,hitbox_y=6,damage=8,player_bullet=true}}
    boundary:resolve_player_damage()
    eq(boss.hp,92,"float32 side-boundary contact deals the native eight damage")
    local corner=stage("classic")
    local target={x=6,y=8,hp=100,legacy_hurtbox={10,10}}
    corner.adapter.enemies={target}
    corner.adapter.shots={{x=0,y=0,angle=0,hitbox_x=6,hitbox_y=8,damage=8,player_bullet=true}}
    corner:resolve_player_damage()
    eq(target.hp,100,"a circle exactly tangent to the rectangle corner is excluded")

    local ClassicShots=require("tnr.legacy_replay.classic_shots")
    local edge={x=-16.42,y=-29.64,speed=24,vy=-24,angle=Rules.float32(-math.pi/2),anim_frame=14,
        player_bullet=true,player_animation=ClassicShots.animation(pellets.anm.pl00,"pl00",0,42)}
    for _=1,edge.anim_frame do edge.player_animation:update() end
    pellets.adapter:advance_player_shot(edge)
    ok(not edge.deleted,"a shot leaving the top survives while its previous sprite touches the field")
    pellets.adapter:advance_player_shot(edge)
    ok(edge.deleted,"the shot is removed once all four previous vertices have left")

    -- The second-stage Normal demo's first high-speed volley (frame 368).
    local tracking=stage("classic")
    local target={x=-23.65999984741211,y=157.57000732421875,hp=100}
    local homing={x=96.0625,y=291.703125,angle=Rules.float32(-math.pi*11/18),speed=4,
        just_fired=true,callback_tick=1,player_bullet=true}
    tracking.adapter.enemies={target}
    tracking.adapter.shots={homing}
    tracking.adapter.advance_enemy_movement=function(_, enemy) enemy.x,enemy.y=-21.26,158.87 end
    tracking.adapter:update()
    ok(math.abs(homing.angle+1.949586)<0.00002,"launch callback aims at the enemy before it moves")
    eq(homing.homing_target,target,"homing takes the closest eligible target")
    local nearer={x=homing.x+2,y=homing.y+2,hp=100}
    tracking.adapter.enemies[2]=nearer
    tracking.adapter:advance_shots()
    eq(homing.homing_target,target,"nearer enemies cannot steal an active lock")
    target.legacy_removed=true
    tracking.adapter:advance_shots()
    eq(homing.homing_target,nil,"lost target releases its lock this tick")
    tracking.adapter:advance_shots()
    eq(homing.homing_target,nearer,"the next tick can acquire another target")
    local moon_thread={object=nearer,runtime=tracking.adapter.runtime}
    tracking.adapter.instructions.ins_544(moon_thread,nil,{1})
    eq(nearer.legacy_flags,0x8000000,"moon instruction sets the native homing-exclusion flag")
    local angle_before=homing.angle
    tracking.adapter:advance_shots()
    eq(homing.angle,angle_before,"a previously locked moon stops steering the homing shot")
    local fresh={x=nearer.x,y=nearer.y+30,angle=-math.pi/2,speed=4}
    ClassicShots.advance_homing(fresh,tracking.adapter.enemies)
    eq(fresh.homing_target,nil,"new homing shots cannot acquire an excluded moon")
    tracking.adapter.instructions.flagSet(moon_thread,nil,{0x80000000})
    tracking.adapter.instructions.ins_549(moon_thread,nil,{0})
    eq(nearer.legacy_flags,0x8000000,"clearing the high visual flag preserves homing exclusion")
    tracking.adapter.instructions.ins_544(moon_thread,nil,{0})
    tracking.adapter:advance_shots()
    eq(homing.homing_target,nearer,"clearing exclusion permits homing acquisition again")
    moon_thread.floats={A=Rules.float32(-3.665191)}
    tracking.adapter.instructions.validRad(moon_thread,nil,{"%A"})
    eq(moon_thread.floats.A,Rules.float32(Rules.float32(-3.665191)+Rules.float32(math.pi*2)),
        "five-stage angle wrapping preserves the reference float32 calculation")

    local ordered=stage("classic")
    local recorded
    local runtime=ordered.adapter.runtime
    runtime.chunks.Older={{"ins","setHurtbox",{"24","24"}},{"ins","wait",{"30"}}}
    runtime.chunks.Newer={{"call","Observe",true,{}},{"ins","wait",{"30"}}}
    runtime.chunks.Observe={{"ins","wait",{"1"}},{"ins","observe",{}}}
    ordered.adapter.instructions.observe=function()
        recorded=#ordered.items.list
    end
    local older=ordered.adapter:spawn_enemy("Older",0,100,5,{main_drop=2})
    local newer=ordered.adapter:spawn_enemy("Newer",0,100,100)
    for frame=1,2 do
        ordered.adapter.shots={{player_bullet=true,x=0,y=100,damage=14}}
        ordered:update()
        eq(older.hp,5,"spawn protection prevents damage on tick "..frame)
        eq(#ordered.adapter.shots,0,"the protected enemy still consumes the pellet")
        eq(ordered.stats.score,10*frame,"a protected hit still scores")
    end
    ordered.adapter.shots={{player_bullet=true,x=0,y=100,damage=14},
        {player_bullet=true,x=0,y=100,damage=14}}
    ordered:update()
    eq(older.hp,0,"older enemy receives the whole volley before it dies")
    eq(newer.hp,100,"overkill pellets do not pass to the next enemy")
    eq(recorded,1,"older enemy drops before the next enemy's async context")
    eq(ordered.stats.score,30,"one capped damage query grants ten more score")

    local laser=stage("classic")
    laser.players[1].definition=require("tnr.core.immutable").copy(require("tnr.legacy_replay.data.th15_sht").marisa)
    laser.players[1].power=100
    laser.adapter.enemies={{x=0,y=100,hp=1000,legacy_hurtbox={80,40}}}
    laser.frames=20
    laser:apply_input(1,{shoot=true})
    laser:resolve_player_damage()
    ok(laser.adapter.enemies[1].hp<1000,"zero-speed Marisa source damages along a beam")
    for _=1,600 do laser.adapter:advance_shots() end
    eq(#laser.adapter.shots,0,"stationary beams expire rather than accumulating")
    local b={x=0,y=0,vx=2,vy=0,speed=2,angle=0,transforms={
        {flags=-2147483648,int1=3},{flags=2097152,int1=4,float1=6,float2=-999999}}}
    for _=1,3 do Transform.update(b) end
    eq(b.speed,2,"wait blocks acceleration through the tick reaching zero")
    for _=1,4 do Transform.update(b) end
    eq(b.speed,6,"target acceleration reaches target exactly")
    local simultaneous={x=0,y=0,vx=0,vy=0,speed=0,angle=0,transforms={
        {flags=8,async=true,int1=3,float1=1,float2=0},
        {flags=8,async=true,int1=2,float1=10,float2=0},
        {flags=32768,int1=1}}}
    Transform.update(simultaneous);eq(simultaneous.speed,1,"same async effect does not overlap itself")
    Transform.update(simultaneous);eq(simultaneous.speed,2,"first angular effect continues alone")
    Transform.update(simultaneous);eq(simultaneous.speed,13,"next effect begins when previous effect finishes")
    eq(simultaneous.custom_mode,nil,"synchronous callback waits for active async effects")
    Transform.update(simultaneous);eq(simultaneous.custom_mode,1,"callback starts after the async chain")
    local m=stage("modern");local mp=m.players[1];local d=mp.combat_runtime
    ok(d~=nil,"modern stage has real equipment runtime")
    local enemy={x=0,y=150,hp=10000,legacy_hurtbox={40,40}}
    m.adapter.enemies={enemy}
    for _=1,90 do m:apply_input(1,{shoot=true});m.modern:update() end
    ok(enemy.hp<10000,"modern weapon projectiles reach ECL enemies")
    local hp=enemy.hp
    m.dialogue.active=true
    for _=1,60 do m.modern:update() end
    eq(enemy.hp,hp,"dialogue suspends modern projectile damage")
    m.dialogue.active=false
    ok(d.p_gauge.value<d.p_gauge.maximum,"modern firing consumes P")
    d.p_gauge.value=40;m.modern:pickup(1,{kind="power"});eq(d.p_gauge.value,50,"small P restores ten percent")
    m.modern:pickup(1,{kind="power_large"});eq(d.p_gauge.value,70,"large P restores twenty percent")
    local before=#m.modern.shots
    d.p_gauge.hot_frames=30
    m:apply_input(1,{shoot=true})
    eq(#m.modern.shots,before,"overheat blocks real modern shots")
end
