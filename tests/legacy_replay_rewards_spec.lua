return function(eq,ok)
    local Replay=require("tnr.legacy_replay.replay")
    local I=require("tnr.legacy_replay.interfaces")
    local replay=Replay.new({lstg={}})
    ok(replay:start_stage(),"modern stage starts")
    local equipment=replay:get_equipment_session()
    local player=equipment:get_player(1)
    replay:finish_stage("cleared")
    local choices=replay:next_reward_round()
    eq(#choices,3,"mixed rewards remain three choices")
    ok(not choices[1].kind,"first card preserves training")
    local selected
    for index,choice in ipairs(choices) do
        if choice.kind=="EQUIPMENT" then
            selected=selected or index
            local d=equipment.equipment_registry:get(choice.definition_id)
            ok(not d.internal_only and not d.starter_only and not d.test_only,"public reward pool only")
        end
    end
    ok(selected~=nil,"first round contains equipment")
    replay.reward_cursor=selected
    local choice=choices[selected]
    local capacity=player.loadout.inventory.capacity
    player.loadout.inventory.capacity=0
    eq(replay:claim_reward(),false,"full inventory does not consume reward")
    ok(replay.reward_choices~=nil,"full inventory retains the same choice")
    player.loadout.inventory.capacity=capacity
    ok(replay:claim_reward(),"grant through normal acquisition service")
    local instance=player.loadout.inventory.items[1]
    eq(instance.definition_id,choice.definition_id,"selected equipment is actually owned")
    eq(#instance.random_affixes,#choice.random_affixes,"previewed affixes survive acquisition")
    local definition=equipment.equipment_registry:get(instance.definition_id)
    local group=({SUPPORT="supports",SELF_MODIFIER="self_modifiers",SUPPORT_MODIFIER="support_modifiers"})[definition.equipment_type]
        or (definition.allowed_slots and not definition.allowed_slots.HIGH_WEAPON and "low_weapons" or "high_weapons")
    local equipped,err=equipment.loadout_service:equip_from_inventory(1,1,group,1)
    ok(equipped~=nil,"reward equipment can be equipped through normal loadout service: "..tostring(err))
    eq(replay:claim_reward(),false,"cannot claim twice")
    replay:next_reward_round()
    replay.reward_choices={Replay.REWARDS[1]};replay.reward_cursor=1
    ok(replay:claim_reward(),"training is claimable")
    eq(replay:next_reward_round(),nil,"only two rounds")
    replay:stop()
    eq(replay:get_equipment_session(),equipment,"return to select retains inventory")
    ok(replay:start_stage(),"restart builds combat from retained equipment run")
    eq(replay.runtime.players[1].training_damage_bonus,.1,"training persists into next combat")
    eq(replay.runtime.modern.session,equipment,"combat reads the reward equipment session")
    eq(equipment:get_player(1).loadout[group][1].instance_id,instance.instance_id,"equipped reward survives stage replacement")
    if definition.equipment_type=="WEAPON" then
        ok(replay.runtime.players[1].combat_runtime.weapon_manager:find(instance.instance_id)~=nil,"reward weapon is in real firing manager")
    end
    replay:stop()
    replay.mode_cursor=2
    ok(replay:start_stage(),"classic starts independently")
    eq(replay.runtime.modern,nil,"classic has no equipment combat")
    eq(replay.runtime.players[1].training_damage_bonus,nil,"modern training never leaks into classic")
    replay:finish_stage("cleared")
    eq(#replay.last_result.rewards,0,"classic has no rewards")
    eq(replay:next_reward_round(),nil,"classic cannot open reward selection")
    local session=I.ReplaySession.new({mode=I.classic_mode()})
    local mode=session.mode
    for _=1,100 do mode:on_item_collected(session,1,{kind="power"}) end
    eq(session:get_power(1),2,"100 small P items raise power by exactly one")
    mode:on_item_collected(session,1,{kind="power_large"})
    eq(session:get_power(1),3,"large P raises power by one")
    mode:on_item_collected(session,1,{kind="full_power"})
    eq(session:get_power(1),4,"full power caps at four")
    mode:on_player_hit(session,1);eq(session:get_power(1),3.5,"miss loses half a power level")
    for _=1,5 do mode:on_player_hit(session,1) end
    eq(session:get_power(1),1,"classic power never drops below one on miss")
    local runtime=replay.runtime
    local classic_ship=runtime.players[1]
    local lives=runtime.session:life_count(1)
    local adapter=runtime.adapter
    local function chapter(graze, defeated, targets)
        for index=1,targets do
            local target={legacy_chapter=runtime.chapter}
            adapter.instructions.setHurtbox({object=target},adapter.runtime,{24,24})
            if index<=defeated then adapter:credit_chapter_target(target) end
        end
        runtime:add_graze(1,graze)
        adapter.instructions.setChapter({},adapter.runtime,{runtime.chapter+1})
        runtime:finish_chapter()
    end
    chapter(170,61,64)
    eq(runtime.stats.score,810150,"the first native stage-two chapter awards 810150 points")
    eq(classic_ship.life_piece,nil,"less than a million does not award a fragment")
    chapter(200,1,1)
    eq(classic_ship.life_piece,1,"a million exactly awards a life fragment")
    runtime:finish_chapter()
    eq(classic_ship.life_piece,1,"the same chapter cannot pay twice")
    chapter(200,1,1);chapter(200,1,1)
    eq(classic_ship.life_piece,0,"three earned fragments are consumed")
    eq(runtime.session:life_count(1),lives+1,"three qualifying chapters grant an extra life")
    replay:reset_progress()
    eq(replay.equipment_session,nil,"returning to main menu ends the equipment run")
end
