-- Real-engine, real TCP acceptance. Only ordinary pilot inputs affect play.
local root=assert(os.getenv("TNR_TEST_PROJECT_ROOT")):gsub("\\","/")
package.path=root.."/game/scripts/?.lua;"..root.."/game/scripts/?/init.lua;"..package.path
local api=require("lstg")
local Bootstrap=require("tnr.bootstrap")
local Pilot=require("tnr.debug.replay_pilot")
local role=assert(os.getenv("TNR_TEST_ROLE"))
local id=role=="host" and 1 or 2
local rules=os.getenv("TNR_TEST_MODE")=="modern" and 1 or 2
local stage_index=tonumber(os.getenv("TNR_TEST_STAGE")) or 1
local last_stage=os.getenv("TNR_TEST_CAMPAIGN")=="1" and 6 or stage_index
local app,finished,peer_done,report
local pilot_frame,pilot_input
local stage_verified,observed_stage
local select_sent=false
local sent_inputs,stage_reports={},{}
local volleys,bombs_spent
local polls=0
local visual=os.getenv("TNR_TEST_VISUAL")=="1"
local function write(text)
    local f=assert(io.open("replay-lan.result","w"));f:write(text,"\n");f:close()
end
local function verified_done()
    if stage_verified then return false end
    peer_done=app.transport:consume_peer_snapshot() or peer_done
    if finished and peer_done and peer_done.stage==finished.stage then
        assert(peer_done.hash==finished.hash and peer_done.frames==finished.frames
            and peer_done.outcome==finished.outcome,"final state mismatch")
        stage_reports[#stage_reports+1]=report
        stage_verified=true
        local failed=finished.outcome~="cleared"
        local status=failed and "FAIL_SURVIVAL" or stage_index==last_stage and "FINAL_RESULT" or "NEXT_STAGE"
        write(table.concat(stage_reports,"\n\n").."\nVERDICT="..status)
        return failed
    end
    return false
end

local function equip_rewards(replay)
    local equipment=replay:get_equipment_session()
    local loadout=equipment:get_player(id).loadout
    local service=equipment.loadout_service
    for index=#loadout.inventory.items,1,-1 do
        local instance=loadout.inventory.items[index]
        local groups=({WEAPON={"low_weapons","high_weapons"},SUPPORT={"supports"},
            SELF_MODIFIER={"self_modifiers"},SUPPORT_MODIFIER={"support_modifiers"}})[instance.equipment_type] or {}
        local equipped=false
        for _,group in ipairs(groups) do
            for slot=1,#loadout[group] do
                if not loadout:get_slot(group,slot) and service:can_equip(instance,group,slot,id) then
                    assert(service:equip_from_inventory(id,index,group,slot))
                    equipped=true
                    break
                end
            end
            if equipped then break end
        end
    end
end

local function choose_reward(replay)
    local best,priority=1,0
    local session=replay.runtime.session
    local life_rank=session:life_count(id)<=4 and 7 or 4
    local bomb_rank=session:bomb_count(id)<2 and 6 or 3
    for index,choice in ipairs(replay.reward_choices) do
        local rank=0
        if choice.kind=="RESOURCE" then rank=choice.resource=="life" and life_rank or bomb_rank
        elseif choice.kind=="EQUIPMENT" then
            local definition=replay:get_equipment_session().equipment_registry:get(choice.definition_id)
            rank=definition.equipment_type=="WEAPON" and 5 or 1
        elseif choice.key=="life" then rank=life_rank
        elseif choice.key=="bomb" then rank=bomb_rank
        elseif choice.key=="power" then rank=2 end
        if rank>priority then best,priority=index,rank end
    end
    return best
end

local function observe(stage)
    observed_stage=stage
    pilot_frame=nil
    sent_inputs,volleys,bombs_spent={},{0,0},{0,0}
    local use_bomb=stage.use_bomb
    stage.use_bomb=function(self,player_id)
        if not use_bomb(self,player_id) then return false end
        bombs_spent[player_id]=bombs_spent[player_id]+1
        return true
    end
    if stage.modern then
        local input=stage.modern.input
        stage.modern.input=function(self,player_id,value)
            local before=#self.shots
            input(self,player_id,value)
            if #self.shots>before then volleys[player_id]=volleys[player_id]+1 end
        end
    end
end
function GameInit()
    app=Bootstrap.create({run_seed=151})
    app.replay.lstg=visual and api or {}
    if visual then
        api.LoadTexture("tnr-white-texture","assets/texture/white.png",false)
        api.LoadImage("tnr-white","tnr-white-texture",0,0,16,16)
        api.LoadTTF("Sans","assets/font/SourceHanSansCN-Bold.otf",48,48)
        app.renderer=require("tnr.ui.map_renderer").new(api,1280,720)
        app:open_network_menu(role);app.network_menu.play_mode="replay";app.network_menu.cursor=3
        app:init()
    end
end
local function step()
    polls=polls+1
    if visual and polls<600 then return false end
    if not app.replay_network then
        local ok=app:start_network_game({mode=role,host="127.0.0.1",port=tonumber(os.getenv("TNR_TEST_PORT")),seed=151,play_mode="replay"})
        if not ok then return false end
    end
    local n=app.replay_network
    local r=app.replay
    local input={}
    if n.phase=="select" then
        if stage_verified then
            if stage_index==last_stage then
                if not select_sent then
                    app.transport:publish_peer_snapshot({select_complete=true,stage=stage_index,
                        hash=finished.hash,frames=finished.frames,outcome=finished.outcome})
                    select_sent=true
                end
                app.transport:update()
                local snapshot=app.transport:consume_peer_snapshot() or peer_done
                if snapshot and snapshot.select_complete and snapshot.stage==stage_index then
                    write(table.concat(stage_reports,"\n\n").."\nVERDICT=PASS")
                    return true
                end
                return false
            end
            stage_index=stage_index+1
            finished,peer_done,stage_verified=nil,nil,nil
        end
        r.character_cursor=id==1 and 1 or 3
        if n.host and r.mode_cursor~=rules then
            app.replay_field="mode"
            input.move_y=r.mode_cursor>rules and 1 or -1
        elseif n.host and r.stage_cursor~=stage_index then
            app.replay_field="stage"
            input.move_y=r.stage_cursor>stage_index and 1 or -1
        elseif r.stage_cursor==stage_index and r.mode_cursor==rules and (not visual or polls>1200) and not n.ready[id] then
            if rules==1 then equip_rewards(r) end
            input.confirm=true
        end
    elseif n.phase=="playing" then
        local stage=r.runtime
        if observed_stage~=stage then observe(stage) end
        if pilot_frame~=stage.frames then
            local queued={}
            for tick=stage.frames+1,stage.frames+n.DELAY do queued[#queued+1]=sent_inputs[tick] or {} end
            sent_inputs[stage.frames]=nil
            pilot_frame,pilot_input=stage.frames,Pilot.sample(stage,id,queued)
        end
        input=pilot_input
    elseif n.phase=="result" and n.host and stage_verified then
        input.confirm=true
    elseif n.phase=="reward" and r.reward_player_id==id then
        r.reward_cursor=choose_reward(r)
        if not r:can_claim_reward() then
            local equipment=r:get_equipment_session()
            assert(equipment.loadout_service:discard_inventory(id,1))
        end
        input.confirm=true
    end
    local previous_sent=n.sent_tick
    app.input:set_pending(input,id)
    app:update()
    if n.sent_tick and previous_sent and n.sent_tick>previous_sent then sent_inputs[n.sent_tick]=input end
    if finished and verified_done() then return true end
    assert(app.replay_network,"unexpected disconnect")
    assert(n.phase~="error",app.replay.message)
    if polls%1800==0 then
        local f=assert(io.open("replay-lan.progress","w"))
        f:write(n.phase," stage=",stage_index," polls=",polls," frame=",r.runtime and r.runtime.frames or 0,
            " mode=",r.mode_cursor," cursor=",r.stage_cursor," revision=",n.revision or 0,
            " ready=",tostring(n.ready[1]),",",tostring(n.ready[2])," connected=",tostring(app.transport.connected));f:close()
    end
    if n.phase=="result" then
        if not finished then
            local s=r.runtime
            assert(#s.adapter:missing_report()==0,"unhandled ECL instruction")
            assert(not s.dialogue or next(s.dialogue.unknown)==nil,"unhandled dialogue instruction")
            if not s.modern then volleys={s.players[1].shots_fired,s.players[2].shots_fired} end
            assert(volleys[1]>0 and volleys[2]>0,"one player never fired")
            finished={done=true,stage=stage_index,hash=n:signature(),frames=s.frames,outcome=r.last_result.outcome}
            app.transport:publish_peer_snapshot(finished)
            report=table.concat({"role="..role,"stage="..stage_index,"frames="..s.frames,
                "outcome="..finished.outcome,
                "team_life="..s.session.party.team_life,"team_bombs="..s.session.team_bombs,
                "P1_volleys="..volleys[1],"P2_volleys="..volleys[2],
                "P1_bombs_spent="..bombs_spent[1],"P2_bombs_spent="..bombs_spent[2],
                "final_hash="..finished.hash},"\n")
            write(table.concat(stage_reports,"\n\n").."\n"..report.."\nVERDICT=AWAITING_PEER")
        end
        app.transport:update()
        if verified_done() then return true end
    end
    return false
end
function FrameFunc()
    for _=1,visual and 5 or 30 do
        local ok,result=xpcall(step,debug.traceback)
        if not ok then write("ERROR\n"..result);return true end
        if result then return true end
    end
    return false
end
function RenderFunc()
    if visual then app:render()
    else api.BeginScene();api.RenderClear(api.Color(255,10,15,25));api.EndScene() end
end
function GameExit() if app and app.transport then app.transport:disconnect() end end
function FocusGainFunc() end
function FocusLoseFunc() end
