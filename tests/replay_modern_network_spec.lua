return function(eq,ok)
    local Fake=require("tnr.multiplayer.fake_transport")
    local Bootstrap=require("tnr.bootstrap")
    local Network=require("tnr.multiplayer.replay_network")
    local links={Fake.create_pair()};local apps={}
    for id=1,2 do
        local a=Bootstrap.create({transport=links[id],network_role=id==1 and "host" or "client",local_player_id=id,player_count=2,run_seed=151})
        a.replay.lstg={};a.network_seed=151
        a.replay_network=Network.new(a,id==1 and "replay" or nil);apps[id]=a
    end
    for cycle=1,500 do for id,a in ipairs(apps) do
        local n=a.replay_network
        if n.phase=="select" then
            a.replay.mode_cursor=1
            a.replay.character_cursor=id==1 and 1 or 3
        end
        a.input:set_pending({confirm=n.phase=="select" and not n.ready[id],shoot=true},id);a:update()
        ok(n.phase~="error",tostring(a.replay.message))
    end end
    for _,a in ipairs(apps) do
        eq(a.replay.active_mode,"modern","modern survives LAN start")
        ok(a.replay.runtime.modern.drivers[2]~=nil,"second player's equipment runtime exists")
        eq(a.replay.runtime.modern.drivers[2].descriptor.character_id,"sanae","P2 starts with the selected character kit")
        local s=a.replay.runtime
        local aggro=s.coop.aggro
        ok(aggro.damage[2]+(aggro.last_report and aggro.last_report.damage[2] or 0)>0,
            "P2 modern weapon damage contributes to aggro")
        s.coop:revive(1);s.coop:revive(2)
        local counters={0,0}
        for id=1,2 do
            local affix=s.players[id].combat_runtime.affixes
            local original_miss=affix.miss
            affix.miss=function(self) counters[id]=counters[id]+1;original_miss(self) end
        end
        s.players[1].combat_runtime.affixes.shield=600
        s:on_player_hit(1,s.players[1])
        ok(s.players[1].alive,"modern LAN shield prevents entering respawn")
        eq(s.players[1].combat_runtime.affixes.shield,0,"modern LAN hit consumes shield")
        s:on_player_hit(1,s.players[1])
        eq(counters[1],0,"single-player miss does not grant team-wipe growth")
        s:on_player_hit(2,s.players[2])
        eq(counters[1],1,"team wipe grants first player's miss growth once")
        eq(counters[2],1,"team wipe grants second player's miss growth once")
        a.replay:finish_stage("cleared");a.replay_network.phase="result"
    end
    -- Client Enter must open rewards, not request an unconditional return.
    apps[2].input:set_pending({confirm=true},2);apps[2]:update()
    apps[1].input:set_pending({},1);apps[1]:update()
    eq(apps[1].replay_network.phase,"reward","client confirmation starts reward selection")
    -- Simulate reward_open arriving in the same receive batch as the result.
    apps[2].replay_network.phase="await_result"
    apps[2].replay_network.pending_result={tick=apps[2].replay.runtime.frames,outcome="cleared"}
    apps[2].input:set_pending({},2);apps[2]:update()
    eq(apps[2].replay_network.phase,"reward","early reward message waits for result synchronization")
    local host,client=apps[1],apps[2]
    host.input:set_pending({confirm=true},1);host:update()
    client.input:set_pending({},2);client:update()
    eq(client.replay.reward_player_id,2,"the second pick belongs to the client")
    local equipment=client.replay:get_equipment_session()
    local inventory=equipment:get_player(2).loadout.inventory
    for _=1,inventory.capacity do
        ok(equipment.equipment_reward_service:grant("sanae_initial_support",2).acquired,"fill the local warehouse")
    end
    local stale=host.replay:get_equipment_session():get_player(2).loadout.inventory
    stale.capacity=0
    client.replay.reward_cursor=2
    local choice=client.replay.reward_choices[2]
    eq(choice.kind,"EQUIPMENT","round two has a support reward")
    client.input:set_pending({confirm=true},2);client:update();host:update()
    eq(host.replay.reward_round,2,"full local warehouse does not send a pick")
    ok(not client.replay_network.reward_pending,"full warehouse leaves the choice editable")
    client.input:set_pending({tab=true},2);client:update()
    ok(client.preparation_overlay,"client can open inventory from reward selection")
    ok(equipment.loadout_service:discard_inventory(2,1)~=nil,"client frees a slot using the inventory service")
    client.input:set_pending({cancel=true},2);client:update()
    client.input:set_pending({confirm=true},2);client:update();host:update();client:update()
    eq(client.replay.reward_round,3,"stale host inventory cannot reject a valid client claim")
    eq(inventory.items[#inventory.items].definition_id,choice.definition_id,"equipment goes to the owning client")
    eq(#stale.items,0,"host does not mirror equipment acquisition for the client")
    local equipped=equipment.loadout_service:equip_from_inventory(2,#inventory.items,"supports",2)
    ok(equipped~=nil,"client equips their awarded support")
    for cycle=1,50 do for id,a in ipairs(apps) do
        local n=a.replay_network;local r=a.replay
        if n.phase=="reward" and r.reward_player_id==id then
            for i,choice in ipairs(r.reward_choices or {}) do
                if choice.kind=="EQUIPMENT" then r.reward_cursor=i;break end
            end
            if not r:can_claim_reward() then r.reward_cursor=1 end
        end
        a.input:set_pending({confirm=n.phase=="reward" and r.reward_player_id==id},id);a:update()
    end end
    for _,a in ipairs(apps) do eq(a.replay_network.phase,"select","both finish all reward rounds") end
    local Wire=require("tnr.multiplayer.lan_transport")
    eq(Wire.encode(apps[1].replay.training_bonuses),Wire.encode(apps[2].replay.training_bonuses),"training rewards agree")
    eq(#host.replay:get_equipment_session():get_player(2).loadout.inventory.items,0,
        "the host keeps the teammate's equipment external to its warehouse")
    for _=1,60 do for id,a in ipairs(apps) do
        local n=a.replay_network
        a.input:set_pending({confirm=n.phase=="select" and not n.ready[id]},id);a:update()
    end end
    for _,a in ipairs(apps) do
        eq(a.replay.runtime.modern.drivers[2].descriptor.supports[2].definition_id,choice.definition_id,
            "both peers fire with the claimant's equipped support in the next battle")
    end
end
