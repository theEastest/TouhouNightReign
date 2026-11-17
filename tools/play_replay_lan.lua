package.path="game/scripts/?.lua;"..package.path
local Fake=require("tnr.multiplayer.fake_transport")
local Bootstrap=require("tnr.bootstrap")
local Network=require("tnr.multiplayer.replay_network")
local Pilot=require("tnr.debug.replay_pilot")
local links={Fake.create_pair()};local apps={}
local rules=arg[1]=="modern" and 1 or 2
local stage_index=tonumber((arg[2] or "st01"):match("%d+")) or 1
assert(stage_index>=1 and stage_index<=6,"regular stage must be st01..st06")
for id=1,2 do
    local a=Bootstrap.create({transport=links[id],network_role=id==1 and "host" or "client",local_player_id=id,player_count=2,run_seed=151})
    a.replay.lstg={};a.network_seed=151
    a.replay_network=Network.new(a,id==1 and "replay" or nil)
    apps[id]=a
end
for cycle=1,60000 do
    for id,a in ipairs(apps) do
        -- Deliberately give the client fewer update opportunities.
        if id==1 or cycle%7~=0 then
            local n=a.replay_network;local input={}
            if n.phase=="select" then
                a.replay.mode_cursor=rules
                a.replay.stage_cursor=stage_index
                a.replay.character_cursor=id
                input.confirm=not n.ready[id]
            elseif n.phase=="playing" then input=Pilot.sample(a.replay.runtime,id) end
            a.input:set_pending(input,id);a:update()
            assert(n.phase~="error",a.replay.message)
        end
    end
    if cycle%5000==0 then print(cycle,apps[1].replay.runtime.frames,apps[2].replay.runtime.frames) end
    if apps[1].replay_network.phase=="result" and apps[2].replay_network.phase=="result" then break end
end
for id,a in ipairs(apps) do
    assert(a.replay_network.phase=="result","missing synchronized result")
    local r=a.replay.last_result
    print(id,r.outcome,r.frames,a.replay.runtime.session.party.team_life,a.replay.runtime.session.team_bombs,a.replay_network:signature())
    if r.outcome~="cleared" then
        local s=a.replay.runtime
        for player_id,p in ipairs(s.players or {}) do
            local gauge=p.combat_runtime and p.combat_runtime.p_gauge
            print("PLAYER",id,player_id,"misses",p.misses or 0,"alive",p.alive,"pos",p.x,p.y,
                "power",p.power,"volleys",p.shots_fired or 0,"p",gauge and gauge.value or "classic",
                "bombs",s.session.bombs_left[player_id] or 0,
                "invuln",p.invulnerable)
        end
        local boss=s.adapter.boss_object
        print("WORLD",id,"enemies",#s.adapter.enemies,"shots",#s.adapter.shots,
            "boss",boss and boss.legacy_ecl or "none",boss and boss.x or "-",boss and boss.y or "-",
            "bomb_resource",s.session.team_bombs,"modern_shots",s.modern and #s.modern.shots or 0)
        if s.modern then
            for player_id,d in pairs(s.modern.drivers) do
                print("DRIVER",id,player_id,"weapons",#d.weapon_manager.weapons,"p",d.p_gauge.value,
                    "hot",d.p_gauge.hot_frames,"shots",d.shots_fired or 0)
            end
        end
    end
    assert(r.outcome=="cleared","pilot failed stage")
end
assert(apps[1].replay_network:signature()==apps[2].replay_network:signature(),"final worlds differ")
print("input-only delayed-peer "..(arg[1] or "classic").." co-op clear passed")
