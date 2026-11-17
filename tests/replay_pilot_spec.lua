return function(eq,ok)
    local Pilot=require("tnr.debug.replay_pilot")
    local Transform=require("tnr.legacy_replay.bullet_transforms")
    local player={x=0,y=100,alive=true,hitbox=2,invulnerable=0,
        power=100,collect_line=128,definition={}}
    local shot={x=0,y=80,vx=1,vy=2,speed=2.236,angle=1.1,
        sprite=0,anim_frame=0,keep_offscreen=0,
        transforms={{flags=2,int1=1},{flags=256,int1=180}}}
    ok(Transform.prepare_spawn(shot,nil,function() return 14,0 end),"birth begins")
    local birth=shot.transform_birth
    local stage={players={[1]=player},items={list={}},
        adapter={shots={shot},enemies={},player=player}}
    Pilot.sample(stage,1)
    ok(shot.transform_birth==birth,"prediction keeps the live birth state")
    eq(birth.n,1,"pilot prediction does not advance the live birth clock")
    ok(shot.birth_spawn_pending,"prediction does not consume the live birth frame")
end
