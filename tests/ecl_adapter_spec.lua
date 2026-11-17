-- Tests for the ECL engine adapter used by the legacy replay mode.
--
-- The adapter binds interpreter instructions to the object model. These tests
-- run the whole th15 stage 1 timeline against a recording host and assert the
-- enemies and bullets it produces, so a regression in the instruction mapping
-- fails here instead of only in a live game.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local Adapter = require("tnr.legacy_replay.adapter")
    local chunks = require("tnr.legacy_replay.data.th15_all")
    local anm = require("tnr.legacy_replay.data.th15_anm")

    -- Stage 1's first boss spell configures emitter groups via $A. The same
    -- resolved group must be used by etNew, the configuration and etOn.
    local groups=Adapter.new({lstg={},chunks={},difficulty=1})
    local group_thread=groups.runtime:spawn("unused")
    group_thread.object={x=0,y=128}
    group_thread.ints.A=0
    groups.instructions.etNew(group_thread,nil,{"$A"})
    groups.instructions.etSprite(group_thread,nil,{"$A","4","2"})
    group_thread.ints.A=2
    groups.instructions.etNew(group_thread,nil,{"$A"})
    groups.instructions.etSprite(group_thread,nil,{"$A","18","3"})
    groups.instructions.etSpeed(group_thread,nil,{"$A","1.5f","1.0f"})
    groups.instructions.etEx(group_thread,nil,{"$A","0","2","1","-999999","-999999.0f","-999999.0f"})
    assert_equal(group_thread.bullets[0].sprite,4,"dynamic group leaves group zero unchanged")
    assert_equal(group_thread.bullets[2].sprite,18,"dynamic group selects the requested sprite")
    assert_equal(group_thread.bullets[2].color_index,3,"dynamic group selects the requested color")
    assert_equal(group_thread.bullets[2].speed,1.5,"dynamic group selects the requested speed")
    assert_equal(group_thread.bullets[2].transforms[1].flags,2,"dynamic group retains its birth transform")
    assert_true(group_thread.bullets[0].transforms==nil,"dynamic group does not alter other transforms")

    -- 41c1f2 uses >= +999990 to aim a transformed laser at the player at
    -- creation, and <= -999990 to retain the incoming bullet's angle.
    local aim_adapter=Adapter.new({lstg={},chunks={}})
    aim_adapter.player={x=0.2265625,y=174.59375}
    local source={x=99,y=99,angle=.75,speed=3,transforms={}}
    local event={x=-136.83203125,y=206.99996948242188,angle=.75,speed=3,
        prep={int1=1,int2=38,int3=2,int4=67072,float1=1000000.56,float2=16,float3=16,float4=640},
        finish={int1=30,int2=30,int3=30,int4=30,float1=16,float2=0,float3=0}}
    local aimed=aim_adapter:laser_from_transform(source,event)
    assert_true(math.abs(aimed.angle-(-.2321767508983612))<1e-6,"positive sentinel matches original player-directed laser angle")
    aim_adapter.player.y=233.09375
    require("tnr.legacy_replay.laser").update(aimed,aim_adapter.player)
    assert_true(math.abs(aimed.angle-(-.2321767508983612))<1e-6,"aimed laser keeps its birth angle as the player moves")
    event.prep.float1=-999990
    local inherited=aim_adapter:laser_from_transform(source,event)
    assert_equal(inherited.angle,.75,"negative sentinel retains the incoming bullet angle")
    event.prep.float1=999990
    aim_adapter.player={x=event.x,y=event.y}
    local coincident=aim_adapter:laser_from_transform(source,event)
    assert_true(math.abs(coincident.angle-math.pi/2)<1e-6,"coincident positive-sentinel aim uses the native downward angle")
    event.prep.float1=7
    local absolute=aim_adapter:laser_from_transform(source,event)
    assert_true(math.abs(absolute.angle-(7-2*math.pi))<1e-6,"ordinary transform angle is normalized")

    -- Native stage-four bullet 1750 remains on screen during its 30x30 birth
    -- sprite, then changes to its 14x16 live sprite on frame 11630.
    local clipping=Adapter.new({lstg={},chunks={},anm=anm})
    local angle=math.atan2 and math.atan2(-1.9994792938232422,-0.045634686946868896)
        or math.atan(-1.9994792938232422,-0.045634686946868896)
    clipping:spawn_bullet(nil,-192,455.82998657227,2,angle,11,11,false,2,nil,{
        {flags=2,int1=1}, {flags=16,int1=60,int2=1,int3=1,int4=0,float1=0,float2=4}})
    local tracked=clipping.shots[1]
    for frame=1,54 do
        clipping:advance_shots()
        assert_equal(#clipping.shots,1,"native birth sprite keeps the edge bullet alive")
        if frame==6 or frame==13 or frame==14 then
            local animation=clipping:bullet_animation(tracked,require("tnr.legacy_replay.data.th15_bullet_types")[11])
            assert_equal(animation:global_sprite(),frame<14 and 324 or 210,
                "edge bullet uses the native sprite on birth and release frames")
        end
    end
    assert_true(math.abs(tracked.x-(-193.39178466797))<.002
        and math.abs(tracked.y-394.84619140625)<.002,
        "the edge bullet reaches its sampled original position")
    local no_animation=Adapter.new({lstg={},chunks={},anm=anm})
    no_animation.bullet_anim_info=function() return nil end
    assert_true(not no_animation:shot_in_field({x=-191.9543,y=457.8295,sprite=11,color_index=2}),
        "missing animation data falls back to the live sprite rectangle")

    local draws=0
    groups.runtime.host.globals=setmetatable({}, {__index=function(_,key)
        if key=="RAND" then draws=draws+1;return 2 end
    end})
    groups.instructions.etSprite(group_thread,nil,{"$RAND","18","3"})
    assert_equal(draws,1,"a random group operand is evaluated once")
    assert_equal(group_thread.bullets[2].sprite,18,"the resolved random group is used")

    local boss_spell=Adapter.new({lstg={},chunks=chunks,stage_key="st01",difficulty=1,
        random=function(a,b) return a and (a+b)/2 or .5 end})
    boss_spell.player={x=0,y=400}
    local boss={x=0,y=128}
    local left=boss_spell.runtime:spawn("st01bs.BossCard1_at2")
    local right=boss_spell.runtime:spawn("st01bs.BossCard1_at2")
    left.object=boss;right.object=boss
    left.arguments={1,1.5707964};right.arguments={2,-1.5707964}
    boss_spell.runtime.threads={left,right}
    boss_spell.runtime:update()
    assert_equal(#boss_spell.shots,2,"the real first-spell routines each fire one projectile")
    for _,shot in ipairs(boss_spell.shots) do
        assert_equal(shot.sprite,18,"the first-spell projectile uses its original type")
        assert_equal(shot.color_index,3,"the first-spell projectile uses its original color")
        assert_equal(shot.speed,1.5,"the first-spell projectile uses its original speed")
        assert_equal(#shot.transforms,6,"the first-spell projectile keeps all scripted transforms")
        assert_equal(shot.transforms[1].flags,2,"the first-spell projectile starts with its birth animation")
    end

    -- Original stage 4 MBoss invokes the default EffChargePoint3 helper with
    -- `var A, B, C, D, E, F;` body registers. Its three charge sprites belong
    -- in slots 8-10; treating the missing function-header parameters as zero
    -- overwrote slot 0 with an effect animation at x=-1056.
    local stage4_anm=Adapter.new({lstg={},chunks=chunks,anm=anm,stage_key="st04",difficulty=1})
    local stage4_boss={x=0,y=128,legacy_globals={}}
    stage4_anm.enemies={stage4_boss}
    local stage4_thread=stage4_anm.runtime:spawn("st04mbs.MBoss")
    stage4_thread.object=stage4_boss
    stage4_anm.instructions.anmSelect(stage4_thread,nil,{"3"})
    stage4_anm.instructions.anmSetMain(stage4_thread,nil,{"0","0"})
    local stage4_body=stage4_boss.legacy_anm
    stage4_anm.runtime:call(stage4_thread,"default.EffChargePoint3",false,
        {"1.5707964f","0.5235988f","8","11","11","11"})
    assert_true(stage4_boss.legacy_anm==stage4_body,
        "stage-four charge helper leaves the boss body animation in slot zero")
    assert_equal(stage4_boss.legacy_anm_slots[8].archive_name,"effect",
        "stage-four charge helper binds the first requested overlay slot")
    assert_equal(stage4_boss.legacy_anm_slots[8].script,165,
        "stage-four charge helper binds its requested ANM script")
    assert_equal(stage4_boss.legacy_anm_slots[9].script,165,
        "stage-four charge helper binds the second requested ANM script")
    assert_equal(stage4_boss.legacy_anm_slots[10].script,165,
        "stage-four charge helper binds the third requested ANM script")
    local charge=stage4_boss.legacy_anm_slots[8]
    charge:update()
    assert_equal(#(stage4_anm.animations or {}),0,"ANM 508 type one never spawns the gray transition")
    assert_equal(#charge.children,4,"the native emitter creates four charge particles per tick")
    assert_equal(charge.children[1].script,152,"the first three particles use the charge sprite")
    assert_equal(charge.children[4].script,153,"the fourth particle uses the alternate charge blend")
    assert_equal(stage4_anm.rng.draws,48,"native charge motion uses six replay-safe draws per particle")
    for _=2,60 do charge:update() end
    assert_equal(stage4_anm.rng.draws,2400,"fifty emission ticks precede the second trajectory")
    charge:update()
    assert_equal(stage4_anm.rng.draws,2432,"the first four particles change trajectory on tick 61")
    for _=1,220 do charge:update() end
    assert_equal(#charge.children,0,"charge particles expire instead of covering the battle")
    assert_equal(charge.charge,nil,"the finished charge no longer emits particles")
    stage4_anm.instructions.anmSelect(stage4_thread,nil,{3})
    stage4_boss.legacy_final_vx,stage4_boss.legacy_final_vy=-2,2
    stage4_anm:advance_enemy_pose(stage4_boss)
    assert_equal(stage4_boss.legacy_anm.script,1,"diagonal motion plays the left movement bank")
    stage4_boss.legacy_final_vx=0
    stage4_anm:advance_enemy_pose(stage4_boss)
    assert_equal(stage4_boss.legacy_anm.script,3,"stopping left uses the original transition script")
    stage4_anm.instructions.anm316(stage4_thread,nil,{0,0})
    assert_equal(stage4_boss.legacy_anm.script,5,"spell activation starts the attack animation")
    stage4_anm.instructions.anm316(stage4_thread,nil,{0,-1})
    assert_equal(stage4_boss.legacy_anm.script,0,"negative attack offset restores the idle script")
    local movement = Adapter.new({lstg={}, chunks={}})
    local native = Adapter.new({lstg={}, chunks={}, seed=0})
    assert_equal(native.runtime.host.globals.RAND,0x30ddeff1,"TH15 RAND uses two unrotated words")
    assert_equal(native.rng.state,49095,"TH15 RAND preserves the rotated internal state")
    assert_equal(native.rng:next_u16(),4755,"TH15 16-bit draw returns the rotated word")
    assert_equal(native.rng:next_u32(),0x1f50861d,"mixed-width calls advance the same seed")
    assert_equal(native.rng.draws,5,"RNG count tracks original 16-bit steps")
    native = Adapter.new({lstg={}, chunks={}, seed=151})
    assert_equal(native.runtime.host.globals.RANDRAD,-1.9308092594146729,"TH15 RANDRAD is rounded as a signed float")
    local demo = Adapter.new({lstg={},chunks=chunks,stage_key="st02",seed=16841,difficulty=1})
    demo.player={x=0,y=400}
    demo.runtime.threads={demo.runtime:spawn("st02.main")}
    for _=1,62 do demo:update() end
    assert_equal(demo.rng.draws,0,"native stage-two demo creates its first fairy before running her attack")
    local fairy=demo.enemies[2]
    assert_equal(fairy.x,192,"the first fairy stays at the native spawn point for one frame")
    assert_equal(fairy.y,-16,"the first fairy starts above the right edge")
    demo:update()
    assert_equal(demo.rng.draws,2,"the fairy attack first draws RAND on frame 63")
    assert_equal(demo.rng.state,56667,"frame 63 uses the same seed as the native demo")
    local float32=require("tnr.legacy_replay.reference_rules").float32
    assert_equal(fairy.x,float32(191.23),"frame 63 X matches the native fairy trace")
    assert_equal(fairy.y,float32(-14.16),"frame 63 Y matches the native fairy trace")
    for _=64,113 do demo:update() end
    assert_equal(fairy.x,float32(145.28),"movement interpolation matches the traced fairy at frame 113")
    assert_equal(fairy.y,float32(78.30),"frame 113 fairy Y matches the native trace")
    local opening_bullet=demo.shots[1]
    assert_true(math.abs(opening_bullet.y-float32(42.45))<1e-5,"first blue rice bullet spawns at the native position")
    for _=114,120 do demo:update() end
    assert_true(opening_bullet.no_collision,"the first eight spawn ticks do not collide")
    demo:update()
    assert_true(not opening_bullet.no_collision,"the visible spawn can graze after eight ticks")
    for _=122,127 do demo:update() end
    assert_true(math.abs(opening_bullet.y-float32(54.45))<1e-5,
        "the live transition performs both movements on the traced frame")

    local first_stage=Adapter.new({lstg={},chunks=chunks,stage_key="st01",difficulty=1})
    first_stage.runtime.threads={first_stage.runtime:spawn("st01.main")}
    for _=1,62 do first_stage:update() end
    local first=first_stage.enemies[1]
    assert_equal(first.x,-224,"the first stage-one fairy spawns on frame 62")
    first_stage:update()
    assert_equal(first.x,-224,"the original list tail is skipped once after its initial update")
    first_stage:update()
    assert_equal(first.x,float32(-222.86),"the first fairy starts moving on the traced frame 64")
    for _=65,93 do first_stage:update() end
    assert_equal(first_stage.enemies[4].x,float32(-222.86),
        "the second batch already moves on the tick after it spawns")

    local lifecycle=Adapter.new({lstg={},chunks={
        Root={{"ins","enmCreateA",{"Helper",0,64,10,0}},{"ins","wait",{1}},
            {"ins","enmCreateA",{"Follower",-224,64,80,0}},{"ret"}},
        Helper={{"ins","delete",{}}},
        Follower={{"ins","moveVel",{0,5}},{"ins","wait",{60}}},
    }})
    lifecycle.runtime.threads={lifecycle.runtime:spawn("Root")}
    lifecycle:update()
    local helper=lifecycle.enemies[1]
    assert_true(helper.legacy_deleted and helper.legacy_delete_after_init,
        "a helper that returns deletion on creation remains linked until the manager revisits it")
    lifecycle:update()
    local follower=lifecycle.enemies[2]
    assert_equal(follower.x,-224,"the next enemy starts at its spawn position")
    lifecycle:update()
    assert_equal(lifecycle.enemies[1],follower,"the finished helper unlinks on its second manager visit")
    assert_equal(follower.x,-219,"the next enemy moves on time when a linked helper precedes it")

    local phases=Adapter.new({lstg={},chunks={
        Opening={{"ins","setInterrupt",{1,0,1800,"Exit"}},{"ins","wait",{1800}}},
        Exit={{"ins","lifeSet",{100000}},{"ins","wait",{2}},{"ins","delete",{}}},
    }})
    local midboss=phases:spawn_enemy("Opening",0,128,13000,{})
    phases:update()
    midboss.hp=0
    phases:update()
    assert_equal(midboss.hp,100000,"the defeat routine starts on the same tick as the last hit")
    phases:update()
    assert_equal(#phases.enemies,1,"the retreat waits its scripted duration")
    phases:update()
    assert_equal(#phases.enemies,0,"the defeat timer starts on the hit frame")

    local timeout_phase=Adapter.new({lstg={},chunks={
        Opening={{"ins","setInterrupt",{1,0,2,"Exit"}},{"ins","wait",{20}}},
        Exit={{"ins","lifeSet",{8000}},{"ins","wait",{2}}},
    }})
    local timeout_boss=timeout_phase:spawn_enemy("Opening",0,128,13000,{})
    timeout_phase:update()
    timeout_phase:update()
    assert_equal(timeout_boss.hp,0,"timeout switches context without executing its new script")
    assert_true(timeout_boss.legacy_pending_interrupt,"the timed-out boss remains linked for the next tick")
    timeout_phase:update()
    assert_equal(timeout_boss.hp,8000,"the timeout script starts on the following tick")

    local waves=Adapter.new({lstg={},chunks={}})
    local caller=waves.runtime:spawn("MainLatter")
    waves:set_boss_object({x=0,y=128})
    waves.instructions.enmCreateF(caller,waves.runtime,{"GirlD01",224,32,1000})
    waves.instructions.enmCreateMF(caller,waves.runtime,{"GirlD01",-224,32,1000})
    assert_equal(#waves.enemies,0,"F waves cannot spawn while the original midboss is active")
    waves:set_boss_object(nil)
    waves.instructions.enmCreateMF(caller,waves.runtime,{"GirlD01",-224,32,1000})
    assert_equal(#waves.enemies,1,"F waves resume when the midboss exits")
    assert_true(waves.enemies[1].legacy_mirror,"the MF variant preserves the mirrored pattern")

    local aim=waves.runtime:spawn("Aim")
    aim.object={x=184,y=140,legacy_globals={F2=0}}
    waves.instructions.getAngle(aim,waves.runtime,{"%F2","%FINAL_X","%FINAL_Y",144,200})
    waves.instructions.moveVel(aim,waves.runtime,{"%F2",3})
    assert_true(aim.object.legacy_vx<0 and aim.object.legacy_vy>0,
        "getAngle writes the per-enemy F2 used by stage-three spirits")

    -- Stage one, the right-hand GirlBlueA03 observed on frames 2152..2156.
    local turning=Adapter.new({lstg={},chunks=chunks,stage_key="st01",difficulty=1})
    local spawn_context=turning.runtime:spawn("st01.MainSub02")
    spawn_context.object={legacy_globals={F0=float32(.073302)}}
    local right=turning:spawn_enemy("st01.GirlBlueA03",120,-24,50,{},spawn_context)
    local left=turning:spawn_enemy("st01.GirlBlueA03",-120,-24,50,{mirrored=true},spawn_context)
    for _=1,61 do turning:update() end
    assert_equal(right.y,126,"the fairy travels straight for sixty ticks")
    for _,position in ipairs({{119.81,128.49},{119.44,130.96},{118.89,133.39},{118.16,135.78}}) do
        turning:update()
        assert_equal(right.x,float32(position[1]),"the original angle increments bend the right wave inward")
        assert_equal(right.y,float32(position[2]),"the original angle increments match the observed height")
    end
    assert_true(left.x>-120,"the mirror reverses the direction of the angular increment")

    local second_wave=Adapter.new({lstg={},chunks=chunks,stage_key="st02",difficulty=1})
    second_wave.player={x=0,y=400}
    local girl=second_wave.runtime:spawn("st02.GirlC01_at")
    girl.object={x=55.11,y=114.90}
    second_wave.runtime.threads={girl}
    local speeds={}
    second_wave.spawn_bullet=function(_,_,_,_,speed)
        speeds[#speeds+1]=speed
    end
    for _=1,110 do second_wave.runtime:update() end
    assert_equal(#speeds,30,"normal stage two fires six groups of five blue bullets")
    for group, speed in ipairs({1,1.3,1.6,1.9,2.2,2.5}) do
        assert_true(math.abs(speeds[(group-1)*5+1]-speed)<1e-5,
            "normal stage-two volley speeds follow the native 0.3 increment")
    end

    -- Normal demo frame 1563: the fast rice bullet at 2 units/tick
    -- shares its origin with a slow one, not seven other fast bullets.
    for difficulty=0,3 do
        local phantom=Adapter.new({lstg={},chunks=chunks,stage_key="st02",difficulty=difficulty})
        phantom.player={x=0,y=400}
        phantom:spawn_enemy("st02.Phantom01_at2",-84.7,5.7,100)
        phantom:update()
        assert_equal(#phantom.shots,2^difficulty,"phantom speed layers match its difficulty")
        assert_equal(phantom.shots[1].speed,({1,2,3,3})[difficulty+1],"first layer starts at the script speed")
        if difficulty>0 then
            assert_true(math.abs(phantom.shots[#phantom.shots].speed-(difficulty==1 and .8 or 1))<1e-6,
                "last layer uses its own difficulty bank")
        end
    end

    local draws=0
    local seeded=Adapter.new({lstg={},chunks={},random=function(a,b)
        draws=draws+1;return a+(b-a)*.25
    end})
    local fired={}
    seeded.spawn_bullet=function(self,class,x,y,speed,angle)
        fired[#fired+1]={speed=speed,angle=angle}
    end
    local shooter={object={x=0,y=0},ints={},floats={}}
    seeded.instructions.etCount(shooter,nil,{0,2,1})
    seeded.instructions.etAim(shooter,nil,{0,8})
    seeded.instructions.etSpeed(shooter,nil,{0,2,4})
    seeded.instructions.etAngle(shooter,nil,{0,0,1})
    seeded:fire_bullet_group(shooter,0)
    assert_equal(draws,4,"random volleys use the injected shared random source")
    assert_equal(fired[1].angle,-.5,"random angle is centered on its configured direction")
    assert_equal(fired[1].speed,3,"random speed uses the original additive range")
    seeded.instructions.etCount(shooter,nil,{0,0,1})
    seeded:fire_bullet_group(shooter,0)
    assert_equal(#fired,2,"zero-count ECL volley emits nothing")
    assert_equal(seeded.runtime.host.globals.RANDRAD,-math.pi/2,"RANDRAD is a signed angle")
    local sounds={}
    seeded.on_sound=function(path) sounds[#sounds+1]=path end
    seeded.instructions.etSprite(shooter,nil,{0,18,6})
    seeded.instructions.etOffsetAbs(shooter,nil,{0,120,80})
    seeded.instructions.etNew(shooter,nil,{0})
    assert_equal(shooter.bullets[0].sprite,0,"etNew resets the previous bullet type")
    assert_equal(shooter.bullets[0].color_index,0,"etNew resets the previous colour")
    assert_equal(shooter.bullets[0].speed,2,"native new-group primary speed")
    assert_equal(shooter.bullets[0].speed_spec,0,"native new-group secondary speed")
    assert_equal(shooter.bullets[0].aim,0,"new groups default to aimed fans")
    assert_equal(shooter.bullets[0].offset_abs,nil,"etNew restores enemy-relative emission")
    seeded.instructions.etSound(shooter,nil,{0,38,-1})
    assert_equal(#sounds,0,"configuring volley sound does not play it")
    seeded:fire_bullet_group(shooter,0)
    seeded:fire_bullet_group(shooter,0)
    assert_equal(#sounds,2,"each volley plays its configured sound once")
    seeded.instructions.etSound(shooter,nil,{0,-1,-1})
    seeded:fire_bullet_group(shooter,0)
    assert_equal(#sounds,2,"negative sound ID disables volley audio")
    seeded.instructions.etEx(shooter,nil,{0,0,16777216,1,2,3,4})
    seeded.instructions.etExSub(shooter,seeded.runtime,{0,0,"FirstController"})
    seeded.instructions.etCopy(shooter,nil,{1,0})
    seeded.instructions.etExSub(shooter,seeded.runtime,{1,0,"SecondController"})
    assert_true(shooter.bullets[0].transforms[1].routine~=shooter.bullets[1].transforms[1].routine,
        "copied bullet groups own independent controller transforms")
    local moving = {x=0,y=0}
    local wobble={object={x=0,y=0},ints={},floats={}}
    movement.instructions.moveVel(wobble,nil,{math.pi/2,2})
    movement.instructions.moveEllipseRel(wobble,nil,{0,math.pi/2,10,0,math.pi/2,0})
    assert_true(math.abs(wobble.object.x-10)<1e-6,"zero-aspect ellipse oscillates perpendicular to its rotation axis")
    movement:advance_enemy_movement(wobble.object)
    -- A float32 quarter turn can leave a tiny negative x before the two
    -- movement channels and their sum are quantized to hundredths.
    assert_true(math.abs(wobble.object.x)<=.031 and math.abs(wobble.object.y-2)<=.021
        and math.abs(wobble.object.legacy_vy-2)<1e-5,
        "relative ellipse does not replace the enemy's forward velocity")
    local context = {object=moving, ints={}, floats={}}
    movement.instructions.moveVel(context, movement.runtime, {"0.0f", "3.0f"})
    movement.instructions.moveVelTime(context, movement.runtime, {"60", "0", "-999999.0f", "1.0f"})
    for _=1,60 do movement:advance_enemy_movement(moving) end
    assert_true(math.abs(moving.legacy_speed-1)<1e-6, "velocity interpolation reaches the requested speed")
    local end_x = moving.x
    movement:advance_enemy_movement(moving)
    assert_true(math.abs(moving.x-end_x-1)<.021, "enemy keeps moving after the velocity transition")
    assert_true(end_x>110 and end_x<130, "deceleration integrates velocity rather than half a target displacement")

    -- Real st06 MainSub06: ten creation-register snapshots choose distinct
    -- relative destinations over 160 frames (source st06.decl 798..808).
    local sixth=Adapter.new({lstg={},chunks=chunks,stage_key="st06",difficulty=1,
        random=function(a,b) return a and (a+b)/2 or .5 end})
    local wave=sixth.runtime:spawn("st06.MainSub06")
    sixth.runtime.threads={wave}
    for _=1,280 do sixth:update() end
    assert_equal(#sixth.enemies,10,"stage six circular wave contains ten emitters")
    for index,enemy in ipairs(sixth.enemies) do
        assert_true(math.abs(enemy.x-(-160+32*index))<1e-5,"each emitter reaches its own horizontal destination")
        assert_true(math.abs(enemy.y-160)<1e-5,"relative destination is added to base height 256")
        assert_equal(enemy.legacy_globals.F0,-160+32*index,"creation registers are copied, not shared")
    end
    local original_sixth=Adapter.new({lstg={},chunks=chunks,stage_key="st06",difficulty=1,seed=37744})
    original_sixth.runtime.threads={original_sixth.runtime:spawn("st06.main")}
    for _=1,185 do original_sixth:update() end
    assert_equal(original_sixth.enemies[2].x,float32(-144.30),"second spirit uses the native X random draw")
    assert_true(math.abs(original_sixth.enemies[2].y-133.03)<.011,"second spirit uses the earlier native Y draw")
    assert_equal(original_sixth.rng.draws,12,"two spawns consume the native coordinate and orbit draws")

    -- Opening st06.MainSub00 consists of three sweeps of 32 spirits.
    -- Their death volleys originate at each spirit's current orbital position,
    -- not the timeline controller or the initial creation coordinate.
    local opening=Adapter.new({lstg={},chunks=chunks,stage_key="st06",difficulty=1,
        random=function(a,b) return a and (a+b)/2 or .5 end})
    local opening_thread=opening.runtime:spawn("st06.MainSub00")
    opening.runtime.threads={opening_thread}
    for _=1,220 do opening:update() end
    assert_equal(#opening.enemies,32,"opening sweep creates thirty-two independent spirits")
    local death_origins={}
    opening.spawn_bullet=function(self,class,x,y)
        death_origins[#death_origins+1]={x=x,y=y}
    end
    for index,enemy in ipairs(opening.enemies) do
        local base_x=-160+(index-1)*10
        assert_true(math.abs(enemy.x-base_x)<=16.001,"opening emitter keeps its own horizontal base")
        local before=#death_origins
        opening:damage_enemy(enemy,10000)
        opening:run_death_routine(enemy)
        assert_equal(#death_origins-before,3,"Normal opening death volley has three speed layers")
        for j=before+1,#death_origins do
            assert_equal(death_origins[j].x,enemy.x,"death volley uses the individual spirit's current x")
            assert_equal(death_origins[j].y,enemy.y,"death volley uses the individual spirit's current y")
        end
        opening:run_death_routine(enemy)
        assert_equal(#death_origins,before+3,"death volley runs only once")
    end
    assert_true(death_origins[#death_origins].x-death_origins[1].x>270,
        "opening death bullets remain distributed across the playfield")
    local moving_rain=Adapter.new({lstg={},chunks=chunks,stage_key="st06",difficulty=1,
        random=function(a,b) return a and (a+b)/2 or .5 end})
    moving_rain.player={x=0,y=400}
    local moving_origins={}
    local moving_emitter=moving_rain:spawn_enemy("st06.Phantom03",-100,64,120,{})
    moving_rain.spawn_bullet=function(self,class,x,y)
        assert_equal(x,moving_emitter.x,"moving spirit fires from its current horizontal position")
        assert_equal(y,moving_emitter.y,"moving spirit fires from its current vertical position")
        moving_origins[#moving_origins+1]={x=x,y=y}
    end
    for _=1,340 do moving_rain:update() end
    assert_equal(#moving_origins,10,"Normal moving spirit emits ten volleys")
    assert_true(math.abs(moving_origins[1].y-moving_origins[10].y)>30,
        "successive volleys follow movement instead of reusing the first emission point")
    local object={x=20,y=100}
    local relative={object=object,ints={},floats={}}
    movement.instructions.movePosRel(relative,nil,{40,-20})
    movement.instructions.movePosRelTime(relative,nil,{10,0,-40,20})
    movement.instructions.moveVel(relative,nil,{0,2})
    for _=1,5 do movement:advance_enemy_movement(object) end
    assert_true(math.abs(object.x-30)<1e-5 and math.abs(object.y-100)<1e-5,
        "relative tween and absolute velocity progress concurrently")

    -- Actual st06 Phantom04_at emits from seven horizontal bands. The
    -- invisible controller's coordinates must not replace etOffsetAbs.
    local rain=Adapter.new({lstg={},chunks=chunks,stage_key="st06",difficulty=1,
        random=function(a,b) return a and (a+b)/2 or .5 end})
    local origins={}
    rain.spawn_bullet=function(self,class,x,y) origins[math.floor(x+.5)]=true end
    rain:spawn_enemy("st06.Phantom04",0,200,100,{})
    for _=1,200 do rain:update() end
    for _,x in ipairs({0,128,-128,192,-192,64,-64}) do
        assert_true(origins[x]==true,"original stage six rain emission band "..x)
    end
    local wall=Adapter.new({lstg={},chunks=chunks,stage_key="st06",difficulty=1})
    -- st05 final survival: all three moons share the outer orbit centre,
    -- but each snapshots its own inner-orbit phase from the boss's F0.
    local moons=Adapter.new({lstg={},chunks=chunks,stage_key="st05",difficulty=1})
    local parent={object={x=0,y=192,legacy_globals={}},routine="st05bs.BossCard5",ints={},floats={}}
    for _,phase in ipairs({-math.pi/2,math.pi/6,5*math.pi/6}) do
        parent.object.legacy_globals.F0=phase
        moons:spawn_enemy("st05bs.BossCard5_Moon",0,192,100,{},parent)
    end
    local fired = {}
    local fire_bullet_group = moons.fire_bullet_group
    function moons:fire_bullet_group(thread,index)
        fired[#fired+1]=self.frame
        return fire_bullet_group(self,thread,index)
    end
    for _=1,300 do moons:update() end
    assert_equal(#fired,6,"Fake Apollo fires two three-moon volleys in the first 300 frames")
    assert_equal(fired[4]-fired[1],120,"the first two volleys use the original Normal spacing")
    assert_equal(#moons.enemies,3,"Fake Apollo keeps all three moon controllers alive")
    for i=1,3 do
        local a,b=moons.enemies[i],moons.enemies[i%3+1]
        local distance=((a.x-b.x)^2+(a.y-b.y)^2)^.5
        assert_true(math.abs(distance-140*math.sqrt(3))<.04,
            "Fake Apollo moons retain their original 120-degree separation")
        assert_equal(a.legacy_circle.origin_y,192,"outer orbit remains centred at the boss's creation position")
        assert_true(a.legacy_no_damage,"moon bodies cannot be destroyed by player fire")
    end
    wall.shots={{x=193,y=200,vx=2,vy=0,angle=0,speed=2,transforms={
        {flags=64,int1=1,int2=15,float1=-999999},
        {flags=16777216,routine="st06bs.BossCard2_at2",int1=17,float1=.25},
        {flags=1024}}}}
    wall:advance_shots()
    assert_equal(#wall.enemies,1,"sixth boss ricochet creates its wall attack controller")
    assert_equal(wall.enemies[1].x,191,"wall attack starts at the bounced bullet, not the boss")
    assert_equal(wall.enemies[1].legacy_globals.I0,17,"transform passes integer creation registers")
    assert_equal(wall.enemies[1].legacy_globals.F0,.25,"transform passes float creation registers")
    local transform_order=Adapter.new({lstg={},chunks={}})
    local positions={}
    function transform_order:spawn_enemy(_,x,y)
        positions[#positions+1]=x
        return {x=x,y=y}
    end
    for _,x in ipairs({-20,20}) do
        transform_order:spawn_bullet(nil,x,100,0,0,4,4,false,2,nil,
            {{flags=16777216,routine="Controller"}})
    end
    transform_order:advance_shots()
    assert_equal(positions[1],20,"newest native bullet creates its controller first")
    assert_equal(positions[2],-20,"older native bullet creates its controller second")
    assert_equal(transform_order.shots[1].x,-20,"bullet storage retains creation order")
    assert_equal(transform_order.shots[2].x,20,"newer bullet remains at the end of storage")
    local mixed=Adapter.new({lstg={},chunks={}})
    local updates={}
    function mixed:spawn_enemy(_,x,y)
        updates[#updates+1]="bullet:"..x
        return {x=x,y=y}
    end
    local Laser=require("tnr.legacy_replay.laser")
    local laser_update,laser_in_field=Laser.update,Laser.in_field
    Laser.update=function(shot) updates[#updates+1]="laser:"..shot.x end
    Laser.in_field=function() return true end
    mixed:spawn_bullet(nil,-20,100,0,0,4,4,false,2,nil,{{flags=16777216,routine="Controller"}})
    mixed.shots[#mixed.shots+1]={laser=true,x=-10,y=100}
    mixed:spawn_bullet(nil,20,100,0,0,4,4,false,2,nil,{{flags=16777216,routine="Controller"}})
    mixed.shots[#mixed.shots+1]={laser=true,x=10,y=100}
    mixed:advance_shots()
    Laser.update,Laser.in_field=laser_update,laser_in_field
    assert_equal(table.concat(updates,","),"laser:-10,laser:10,bullet:20,bullet:-20",
        "laser manager runs oldest first before newest-first ordinary bullets")
    assert_equal(mixed.shots[1].x,-20,"mixed storage still starts with the oldest shot")
    assert_equal(mixed.shots[4].x,10,"mixed storage still ends with the newest shot")
    local cancellation_order=Adapter.new({lstg={},chunks={}})
    local cancel_order={}
    local original_cancel=Laser.cancel_in_circle
    Laser.cancel_in_circle=function(shot)
        cancel_order[#cancel_order+1]=shot.laser_handle
        shot.deleted=true
        return {}
    end
    cancellation_order.shots={{laser=true,laser_handle=1},{laser=true,laser_handle=2}}
    cancellation_order.instructions.etCancel({object={x=0,y=0}},nil,{"100"})
    Laser.cancel_in_circle=original_cancel
    assert_equal(table.concat(cancel_order,","),"1,2","laser cancellation follows native oldest-first order")
    local controller=Adapter.new({lstg={},chunks={
        Controller={{"ins","flagSet",{"288"}},{"ins","record_args",{}},
            {"call","Child",true,{}},{"ins","wait",{"10"}}},
        Child={{"ins","record_child",{}},{"ret"}},
    }})
    local initial_args,child_calls
    child_calls=0
    controller.instructions.record_args=function(t) initial_args=t.object.legacy_globals.I0 end
    controller.instructions.record_child=function() child_calls=child_calls+1 end
    controller:spawn_bullet(nil,10,100,0,0,4,4,false,2,nil,
        {{flags=16777216,routine="Controller",int1=17}})
    controller:advance_shots()
    assert_equal(controller.enemies[1].legacy_flags,288,
        "bullet controller sets homing-exclusion flags on its creation tick")
    assert_equal(initial_args,17,"bullet controller receives transform arguments before initialization")
    controller:update()
    assert_equal(child_calls,0,"first manager visit skips the initialized controller")
    controller:update()
    assert_equal(child_calls,1,"asynchronous child begins after the skipped visit")
    wall:update()
    local fixed,curved=0,0
    for _,shot in ipairs(wall.shots) do
        if shot.laser_kind=="stationary" then fixed=fixed+1 end
        if shot.laser_kind=="curve" then curved=curved+1 end
    end
    assert_true(fixed>0 and curved>0,"original wall callback emits both straight and curved lasers")
    local cleared={object={},ints={},floats={}}
    wall.instructions.setDeath(cleared,wall.runtime,{"0"})
    wall:run_death_routine(cleared.object)
    assert_equal(cleared.object.legacy_death_routine,nil,"reference string zero disables the death callback")
    local orbit={x=20,y=100}
    local orbit_context={object=orbit,ints={},floats={}}
    movement.instructions.moveCircleRel(orbit_context,nil,{0,math.pi/20,0,0})
    movement.instructions.moveCircleRelTime(orbit_context,nil,{10,0,-999999,10,0})
    movement.instructions.moveVel(orbit_context,nil,{0,2})
    for _=1,10 do movement:advance_enemy_movement(orbit) end
    assert_true(math.abs(orbit.x-40)<.021 and math.abs(orbit.y-110)<.021,
        "circle radius grows while center translates independently")
    movement.instructions.movePosRel(orbit_context,nil,{0,0})
    movement:advance_enemy_movement(orbit)
    assert_true(math.abs(orbit.x-42)<1e-5 and math.abs(orbit.y-100)<1e-5,
        "relative position replaces orbit without cancelling absolute velocity")

    -- Stage 4 original enemy 343, sampled on frames 4661–4667. A one-cent
    -- position error changes the angle of its next bullet and a later graze.
    local sampled_orbit={x=-25.790000915527,y=38.319999694824,
        legacy_circle={origin_x=28.680000305176,origin_y=122.19000244141,
            angle=-2.1467802524567,angular=-0.05236,radius=100,radial=0}}
    for _=1,6 do movement:advance_enemy_movement(sampled_orbit) end
    assert_true(math.abs(sampled_orbit.x-(-49.040000915527))<1e-5
        and math.abs(sampled_orbit.y-59.259998321533)<1e-5,
        "circle accumulation matches the original stage four position")
    assert_true(math.abs(sampled_orbit.legacy_final_vy-3.9899978637695)<1e-5,
        "circle motion preserves the original emitter direction")
    -- At frame 4556, the original source's unrounded vertical delta is .92
    -- even though its visible position advances by only .91 after flooring.
    local sampled_delta={x=26.520000457764,y=130.22999572754,
        legacy_base_x=26.770000457764,legacy_base_y=131.15636557741}
    movement:advance_enemy_movement(sampled_delta)
    assert_true(math.abs(sampled_delta.y-131.13999938965)<1e-5,
        "the original visible position is quantized")
    assert_true(math.abs(sampled_delta.legacy_final_vy-0.91999816894531)<1e-5
        and math.abs(sampled_delta.legacy_final_angle-1.30546378106)<1e-5,
        "FINAL_ANGLE uses the velocity before visible-position quantization")
    -- Original stage 4 actor 504 at frame 12245: native 4076a0 rounds the
    -- polar product to float before adding the center. The boundary below
    -- distinguishes it from adding an unrounded double-precision product.
    local rounded_orbit={x=-70.779998779297,y=122.76000213623,
        legacy_base_x=-70.779998779297,legacy_base_y=122.76000213623,
        legacy_circle={origin_x=29.090000152588,origin_y=128,angle=3.14155,
            radius=100,angular=0,radial=0}}
    movement:advance_enemy_movement(rounded_orbit)
    assert_true(math.abs(rounded_orbit.legacy_base_x-(-70.919998168945))<1e-5,
        "circle product rounds before adding its center")
    assert_true(math.abs(rounded_orbit.legacy_final_vx-(-0.13999938964844))<1e-5,
        "circle direction retains the native float-rounded product")
    for _,direction in ipairs({-1,1}) do
        local wrapped={x=0,y=0,legacy_circle={origin_x=0,origin_y=0,
            angle=direction*3.13,angular=direction*0.1,radius=10,radial=0}}
        for _=1,200 do
            movement:advance_enemy_movement(wrapped)
            assert_true(math.abs(wrapped.legacy_circle.angle)<=math.pi+1e-6,
                "circle angle wraps in both directions across multiple turns")
        end
    end

    local tween_adapter=Adapter.new({lstg={},chunks={Test={
        {"ins","floatTime",{0,"%C",10,0,3,1}}, {"ins","wait",{20}}
    }}})
    local tween_thread=tween_adapter.runtime:spawn("Test")
    tween_adapter.runtime.threads={tween_thread}
    tween_adapter.runtime:update()
    assert_equal(tween_thread.floats.C,3,"floatTime writes its initial value immediately")
    for _=1,5 do tween_adapter.runtime:update() end
    assert_true(math.abs(tween_thread.floats.C-2)<1e-6,"floatTime advances during wait")
    for _=1,5 do tween_adapter.runtime:update() end
    assert_equal(tween_thread.floats.C,1,"floatTime reaches its final value")

    local draws=0
    local random_adapter=Adapter.new({lstg={},chunks={},random=function(a,b) draws=draws+1;return (a+b)/2 end})
    local globals=random_adapter.runtime.host.globals
    local difficulty=globals.DIFF
    assert_equal(draws,0,"reading difficulty does not consume random numbers")
    local fraction=globals.RANDF
    assert_equal(draws,1,"one random global read draws exactly once")

    local fourth=Adapter.new({lstg={},chunks=chunks,stage_key="st04",difficulty=1})
    local boss=fourth:spawn_enemy("st04bs.BossCard3_at",20,144,100,{})
    for _=1,200 do fourth:update() end
    assert_true(#fourth.enemies<100,"fourth boss variable waits cannot flood thousands of enemies")
    local spawned=fourth.enemies[2]
    assert_true(spawned~=nil,"fourth boss creates circular minions")
    local before=#fourth.enemies
    fourth.instructions.enmCreate(boss.legacy_thread,fourth.runtime,{"st04bs.BCirC03",0,0,100})
    local eq_created=fourth.enemies[before+1]
    assert_equal(eq_created.x,boss.x,"relative creation uses boss horizontal position")
    assert_equal(eq_created.y,boss.y,"relative creation uses boss vertical position")

    local mirrored,mirrored_thread=movement:spawn_enemy("Test",100,100,100,{mirrored=true})
    movement.instructions.moveVel(mirrored_thread,nil,{0,2})
    movement:advance_enemy_movement(mirrored)
    assert_true(math.abs(mirrored.x-98)<1e-5,"mirrored enemy reflects ordinary movement angle")
    movement.instructions.moveVelNM(mirrored_thread,nil,{0,2})
    movement:advance_enemy_movement(mirrored)
    assert_true(math.abs(mirrored.x-100)<1e-5,"NM movement bypasses mirror flag")
    movement.instructions.moveSpeedTime(mirrored_thread,nil,{10,0,4})
    for _=1,10 do movement:advance_enemy_movement(mirrored) end
    assert_true(math.abs(mirrored.legacy_speed-4)<1e-5,"speed-only interpolation uses third argument as speed")
    local old_x,old_y=mirrored.x,mirrored.y
    movement.instructions.circlePos(mirrored_thread,nil,{"%A","%B",math.pi/2,20})
    assert_true(math.abs(mirrored_thread.floats.B-20)<1e-5,"circlePos writes the computed vector")
    assert_equal(mirrored.x,old_x,"circlePos cannot move the boss horizontally")
    assert_equal(mirrored.y,old_y,"circlePos cannot move the boss vertically")

    local animated=Adapter.new({lstg={},chunks=chunks,anm=anm,stage_key="st06"})
    local orb=animated:spawn_enemy("st06.ECir00",0,200,160,{})
    for _=1,60 do animated:update() end
    local vm=orb.legacy_anm
    assert_true(math.abs(vm.alpha-255)<1e-5,"original circle enemy finishes its 60-frame fade")
    assert_true(vm.scale_x>.5 and vm.scale_x<1,"circle enemy scale progresses during its 120-frame entrance")
    assert_equal(#vm.children,2,"original circle enemy has both rotating satellite graphics")
    assert_true(vm.children[1].rotation>1,"negative-duration velocity interpolation continues spinning")
    assert_equal(vm.color[1],32,"ECL entrance tint survives ANM updates")
    for _=1,100 do animated:update() end
    assert_true(math.abs(vm.scale_x-1)<1e-5,"circle enemy reaches full scale")

    -- A recording host: enemy and bullet creation are both counted.
    local enemies_created, bullets_created = 0, 0
    local fake = {
        New = function(class, ...)
            local args = { ... }
            if class == "enemy" then
                enemies_created = enemies_created + 1
                return { x = 0, y = 0, hp = 100 }
            end
            bullets_created = bullets_created + 1
            return { x = args[3], y = args[4] }
        end,
        Del = function() end,
        player = { x = 0, y = 0 },
    }
    local adapter = Adapter.new({
        lstg = fake,
        enemy_class = "enemy",
        bullet_styles = { "fake_bullet" },
        anm = anm,
        chunks = chunks,
    })

    -- The stage 1 timeline must be startable.
    local thread = adapter.runtime:spawn("st01.MainFront")
    assert_true(thread ~= nil, "the stage 1 timeline starts")
    assert_equal(thread.routine, "st01.MainFront", "the timeline resolves to the stage 1 entry")
    adapter.runtime.threads[#adapter.runtime.threads + 1] = thread

    -- Run the opening waves.
    for _ = 1, 900 do adapter:update() end
    assert_true(#adapter.enemies > 0, "the timeline spawns enemies")
    assert_true(enemies_created > 0, "enemies go through the object factory")

    -- Enemy positions must spread across the playfield instead of collapsing to
    -- the origin, which is what happens when expression arguments are not
    -- evaluated.
    local min_x, max_x = math.huge, -math.huge
    for _, enemy in ipairs(adapter.enemies) do
        min_x = math.min(min_x, enemy.x or 0)
        max_x = math.max(max_x, enemy.x or 0)
    end
    assert_true(max_x > min_x, "enemies spawn across the playfield width")

    -- Bullets must be produced by the attack routines.
    assert_true(#(adapter.shots or {}) > 0, "attack routines fire bullets")

    -- Every instruction the stage uses must be implemented. A non-zero count
    -- here means the adapter is missing a mapping the stage depends on.
    local report = adapter:missing_report()
    assert_equal(#report, 0, "stage 1 uses no unimplemented instruction")

    -- The difficulty branch list must resolve per mode: a harder difficulty
    -- waits fewer frames before the same attack.
    local function first_wait_frames(difficulty)
        local diff_adapter = Adapter.new({
            lstg = fake,
            enemy_class = "enemy",
            anm = anm,
            chunks = chunks,
            difficulty = difficulty,
        })
        local attack = diff_adapter.runtime:spawn("st01.GirlA01_at")
        attack.runtime = diff_adapter.runtime
        diff_adapter.runtime.threads[#diff_adapter.runtime.threads + 1] = attack
        for _ = 1, 5 do diff_adapter.runtime:update() end
        return attack.wait
    end
    local normal_wait = first_wait_frames(1)
    local lunatic_wait = first_wait_frames(3)
    assert_true(normal_wait > lunatic_wait,
        "lunatic waits fewer frames than normal for the same opening")
end
