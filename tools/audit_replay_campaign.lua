-- Diagnostic only: survival bypass isolates interpreter and phase deadlocks.
-- This is NOT a playability or visual-fidelity acceptance test.
package.path="game/scripts/?.lua;"..package.path
io.stdout:setvbuf("no")
local Stage=require("tnr.legacy_replay.stage_runtime")
local data={chunks=require("tnr.legacy_replay.data.th15_all"),anm=require("tnr.legacy_replay.data.th15_anm"),
    std=require("tnr.legacy_replay.data.th15_std"),sht=require("tnr.legacy_replay.data.th15_sht")}
local failures=0
for n=tonumber(arg[1]) or 1,tonumber(arg[2]) or 6 do
    local key=string.format("st%02d",n)
    local stage
    local transforms={}
    local animations={}
    local incomplete={}
    local moon_trace_start
    local function audit_animation(vm)
        if not vm then return end
        for op in pairs(vm.unhandled or {}) do
            animations[(vm.archive_name or "?")..":"..tostring(vm.script)..":"..op]=true
        end
        for _,child in ipairs(vm.children or {}) do audit_animation(child) end
    end
    local ok,err=pcall(function()
        stage=Stage.new({lstg={},stage=key,difficulty=tonumber(arg[3]) or 1,chunks=data.chunks,anm=data.anm,std=data.std,sht=data.sht})
        if arg[5]=="trace" then
            for _,name in ipairs({"spell","spell3","spellEx"}) do
                local original=stage.adapter.instructions[name]
                stage.adapter.instructions[name]=function(thread,runtime,args)
                    print(key,"SPELL",stage.frames,args[4],thread.object.x,thread.object.y,thread.object.legacy_ecl)
                    if n==5 and tostring(args[4]):find("フェイクアポロ",1,true) then
                        moon_trace_start=stage.frames
                    end
                    return original(thread,runtime,args)
                end
            end
            local anm_events=0
            for _,name in ipairs({"anmSelect","anmSetMain","anmSetSprite","anmSelectedPlay"}) do
                local original=stage.adapter.instructions[name]
                stage.adapter.instructions[name]=function(thread,runtime,args)
                    local object=thread and thread.object
                    local tracked=object and (object.legacy_ecl=="MBoss" or object.legacy_ecl=="Boss")
                    local before=object and object.legacy_anm
                    local result=original(thread,runtime,args)
                    if tracked and anm_events<120 then
                        anm_events=anm_events+1
                        local current=object.legacy_anm
                        print("ANM_EVENT",stage.frames,name,thread.routine,table.concat(args or {},","),
                            object.legacy_anm_selection,object.legacy_main_selection,
                            before and before.archive_name,before and before.script,
                            current and current.archive_name,current and current.script,
                            object.legacy_main_script,object.legacy_pose)
                    end
                    return result
                end
            end
        end
        for _,name in ipairs({"gameSpeed","stageLogo","funcCall","spec1","spec2",
            "diffWait","etProtectRange","bombShield","laserOffset","laserTrajectory","laserStLength","laserStWidth",
            "spellMode","spellTimeout"}) do
            local original=stage.adapter.instructions[name]
            if original then stage.adapter.instructions[name]=function(...)
                incomplete[name]=(incomplete[name] or 0)+1;return original(...)
            end end
        end
        if arg[4]=="shoot" then
            local pilot=require("tnr.debug.replay_pilot")
            stage.session.roster:set_input(1,{sample=function() return pilot.sample(stage,1) end})
        end
        stage:start()
        local boss_outside=false
        local boss_draw_outside=false
        local last_boss
        for frame=1,100000 do
            for _,p in pairs(stage.players) do p.invulnerable=999 end
            stage:update()
            if arg[5]=="trace" then
                local boss=stage.adapter.boss_object
                if boss then
                    if boss~=last_boss then boss_outside=false;boss_draw_outside=false;last_boss=boss end
                    local outside=math.abs(boss.x or 0)>192 or (boss.y or 0)<-32 or (boss.y or 0)>480
                    if outside and not boss_outside then
                        local thread=boss.legacy_thread
                        print(key,"BOSS_OUT",stage.frames,boss.x,boss.y,boss.legacy_ecl,
                            thread and thread.routine or "",thread and thread.pc or "")
                    end
                    boss_outside=outside
                    local vm=boss.legacy_anm
                    if vm then
                        local draw_x=(boss.x or 0)+(vm.x or 0)+(vm.offset_x or 0)
                        local draw_y=(boss.y or 0)+(vm.y or 0)+(vm.offset_y or 0)
                        local draw_outside=math.abs(draw_x)>192 or draw_y< -32 or draw_y>480
                        if draw_outside and not boss_draw_outside then
                            local tween=vm.tweens and vm.tweens.x
                            local fields={key,"BOSS_DRAW_OUT",stage.frames,boss.x,boss.y,draw_x,draw_y,
                                vm.archive_name,vm.entry_index,vm.script,vm.sprite,vm.frame,vm.pc,vm.x,vm.y,
                                tween and tween.from,tween and tween.target,tween and tween.age,tween and tween.mode,
                                boss.legacy_pose,boss.legacy_main_script,boss.legacy_ecl}
                            local columns={}
                            for i=1,22 do columns[i]=tostring(fields[i]) end
                            print(table.concat(columns,"\t"))
                        end
                        boss_draw_outside=draw_outside
                    end
                end
                if n==5 and moon_trace_start and stage.frames-moon_trace_start<=420 and stage.frames%15==0 then
                    for _,moon in ipairs(stage.adapter.enemies) do
                        if tostring(moon.legacy_ecl):find("BossCard5_Moon",1,true) then
                            local c,r=moon.legacy_circle,moon.legacy_rel_circle
                            print(key,"MOON",stage.frames,moon.x,moon.y,
                                c and c.angle or -1,c and c.radius or -1,c and c.origin_x or -1,c and c.origin_y or -1,
                                r and r.angle or -1,r and r.radius or -1,moon.legacy_globals and moon.legacy_globals.F0)
                        end
                    end
                end
            end
            for _,shot in ipairs(stage.adapter.shots) do
                if shot.unsupported_transform then transforms[shot.unsupported_transform]=true end
            end
            for flag in pairs(stage.adapter.unsupported_transforms or {}) do transforms[flag]=true end
            for _,enemy in ipairs(stage.adapter.enemies) do
                for _,vm in pairs(enemy.legacy_anm_slots or {}) do audit_animation(vm) end
            end
            for _,vm in ipairs(stage.adapter.animations or {}) do audit_animation(vm) end
            if frame%10000==0 then print(key,"PROGRESS",frame,#stage.adapter.enemies,#stage.adapter.shots) end
            if stage:timeline_finished() then break end
        end
        assert(stage:timeline_finished(),"timeline stalled")
        assert(not stage.adapter.boss_object,"boss remains at clear")
        assert(#stage.adapter:missing_report()==0,"unsupported instructions")
        assert(not stage.dialogue or next(stage.dialogue.unknown)==nil,"unsupported dialogue")
    end)
    print(key,ok and "TIMELINE_PASS" or "FAIL",stage and stage.frames,err or "")
    if stage then
        local ids={};for id in pairs(transforms) do ids[#ids+1]=id end;table.sort(ids)
        for _,id in ipairs(ids) do print(key,"UNSUPPORTED_TRANSFORM",id) end
        local partial={};for name in pairs(incomplete) do partial[#partial+1]=name end;table.sort(partial)
        for _,name in ipairs(partial) do print(key,"INCOMPLETE_HANDLER",name,incomplete[name]) end
        local ops={};for op in pairs(animations) do ops[#ops+1]=op end;table.sort(ops)
        for _,op in ipairs(ops) do print(key,"UNSUPPORTED_ANM",op) end
        for _,e in ipairs(stage.adapter:missing_report()) do print("missing",e[1],e[2]) end
        if stage.dialogue then for id,count in pairs(stage.dialogue.unknown) do print("MSG",id,count) end end
    end
    if not ok then failures=failures+1 end
end
assert(failures==0,tostring(failures).." stage diagnostics failed")
