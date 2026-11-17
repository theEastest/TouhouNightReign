return function(eq,ok)
    local Fake=require("tnr.multiplayer.fake_transport")
    local Bootstrap=require("tnr.bootstrap")
    local Network=require("tnr.multiplayer.replay_network")
    local links={Fake.create_pair()}
    local apps={}
    for id=1,2 do
        local role=id==1 and "host" or "client"
        local app=Bootstrap.create({run_seed=151,lan_transport_factory=function()
            links[id].connect=function() return true end
            return links[id]
        end})
        app.replay.lstg={}
        ok(app:start_network_game({mode=role,host="127.0.0.1",port=27123,seed=151,
            play_mode=id==1 and "replay" or "map"}),"normal LAN entry starts replay room")
        apps[id]=app
    end
    -- The host can change settings and ready before the socket accepts P2.
    local host,client=apps[1],apps[2]
    links[1].connected,links[2].connected=false,false
    host.replay_field="mode"
    for _,direction in ipairs({1,0,1}) do
        host.input:set_pending({move_y=direction},1)
        host:update()
    end
    host.input:set_pending({confirm=true},1);host:update()
    links[1].connected,links[2].connected=true,true
    host:update();client:update()
    eq(host.replay_network.revision,2,"host made two lobby edits before connecting")
    eq(client.replay_network.revision,2,"new client receives the current lobby revision")
    ok(client.replay_network.ready[1],"new client receives existing host readiness")
    for cycle=1,1100 do
        for id,app in ipairs(apps) do
            local n=app.replay_network
            local frame=app.replay.runtime and app.replay.runtime.frames or 0
            app.input:set_pending({confirm=n.phase=="select" and not n.ready[id],
                move_x=id==1 and -1 or 1,shoot=true,bomb=frame==(id==1 and 20 or 40)},id)
            app:update()
            ok(n.phase~="error","network must not desync: "..tostring(app.replay.message))
        end
    end
    local a,b=apps[1].replay.runtime,apps[2].replay.runtime
    ok(a.frames>=1000 and b.frames>=1000,"both peers advance without input starvation")
    eq(a.players[1].x,b.players[1].x,"host position replicated")
    eq(a.players[2].x,b.players[2].x,"client position replicated")
    ok(a.players[1].shots_fired>0 and a.players[2].shots_fired>0,"both peers shoot")
    eq(a.session:bomb_count(1),a.session:bomb_count(2),"Bomb pool shared between players")
    eq(a.session:bomb_count(1),1,"two Bomb presses consume two total")
    eq(a.session:bomb_count(1),b.session:bomb_count(2),"Bomb pool replicated")
    local before_slow=math.min(a.frames,b.frames)
    for _,s in ipairs({a,b}) do s.time_scale=.25;s.time_accumulator=0 end
    for _=1,36 do
        for id,app in ipairs(apps) do app.input:set_pending({},id);app:update() end
    end
    local slow_steps=math.min(a.frames,b.frames)-before_slow
    ok(slow_steps>=7 and slow_steps<=10,"quarter speed still advances synchronized inputs")
    for _,s in ipairs({a,b}) do s.time_scale=1;s.time_accumulator=0 end
    local generation=apps[1].replay_network.generation
    apps[1].replay_network:receive({version=Network.VERSION,generation="old",kind="input",tick=a.frames+1,input={shoot=true}})
    eq(apps[1].replay_network.generation,generation,"old generation cannot replace room")
    for _=1,10 do
        for id,app in ipairs(apps) do
            app.input:set_pending({skip_dialogue=id==2},id)
            app:update()
        end
    end
    ok(a.dialogue.skip_frames>0,"client Ctrl reaches host replay dialogue")
    eq(a.dialogue.skip_frames,b.dialogue.skip_frames,"both peers process the same dialogue input")
    -- A reported local collision must be ordered once on both machines.
    for _,s in ipairs({a,b}) do for _,p in pairs(s.players) do p.invulnerable=0 end end
    a.local_hit=true
    for _=1,15 do for _,app in ipairs(apps) do app.input:set_pending({},app.session.local_player_id);app:update() end end
    ok(not a.players[1].alive and not b.players[1].alive,"owner hit reaches both peers")
    eq(a.session.party.team_life,3,"solo network miss keeps shared life")
    eq(a.session:bomb_count(1),1,"solo miss keeps the current shared Bomb stock")
    b.local_hit=true
    for _=1,15 do for _,app in ipairs(apps) do app.input:set_pending({},app.session.local_player_id);app:update() end end
    eq(a.session.party.team_life,2,"network team wipe spends once")
    eq(b.session.party.team_life,2,"team life agrees after wipe")
    eq(a.session:bomb_count(1),3,"a classic team life loss refills the shared Bombs once")
    eq(b.session:bomb_count(2),3,"refilled Bombs are visible on the client")
    -- Either peer can return both players to selection; a new generation
    -- cannot consume inputs, readiness or results left over from the old one.
    apps[2].input:set_pending({cancel=true},2);apps[2]:update()
    for _=1,8 do for _,app in ipairs(apps) do app.input:set_pending({},app.session.local_player_id);app:update() end end
    eq(apps[1].replay_network.phase,"select","client escape returns host")
    eq(apps[2].replay_network.phase,"select","client escape returns client")
    apps[1].replay_network:receive({version=Network.VERSION,kind="ready",lobby=1,ready=true,character=4})
    ok(not apps[1].replay_network.ready[2],"stale ready ignored")
    for cycle=1,150 do for id,app in ipairs(apps) do
        local n=app.replay_network
        app.replay.character_cursor=id+1
        app.input:set_pending({confirm=n.phase=="select" and not n.ready[id]},id);app:update()
        ok(n.phase~="error","restart remains synchronized")
    end end
    a,b=apps[1].replay.runtime,apps[2].replay.runtime
    ok(apps[1].replay_network.generation~=generation,"restart has a new generation")
    eq(a.players[1].archive,"pl01","host character selection used")
    eq(a.players[2].archive,"pl02","client character selection used")
    eq(a.session:bomb_count(1),3,"new round resets shared Bomb stock")
    for _,s in ipairs({a,b}) do
        for index=1,5 do
            local owner=index%2+1;local p=s.players[owner]
            s.items:spawn("bomb_piece",p.x,p.y,owner)
        end
    end
    for _=1,10 do for _,app in ipairs(apps) do app.input:set_pending({},app.session.local_player_id);app:update() end end
    eq(a.session:bomb_count(1),4,"both players' Bomb fragments fill the shared stock")
    eq(b.session:bomb_count(2),4,"shared fragment pickup agrees on peer")
    local n=apps[2].replay_network
    n:receive({version=Network.VERSION,kind="result",generation=generation,tick=1,outcome="cleared"})
    ok(not n.pending_result,"stale result cannot end new round")
    -- Co-op life rules, independent of transport.
    local before=a.session:life_count(1)
    a.coop:hit(1)
    eq(a.session:life_count(1),before,"solo miss does not consume team life")
    eq(a.coop.respawns[1],600,"solo respawn waits ten seconds")
    eq(a.coop.focus,2,"death transfers aggro immediately")
    a.coop:hit(2)
    eq(a.session:life_count(1),before-1,"one team wipe spends one life")
    ok(a.players[1].alive and a.players[2].alive,"surviving team life revives both players")
    local p2=a.players[2]
    a.items:spawn("power",p2.x,p2.y,2);a.items:update()
    local items=a.items:drain_collected();local found=false
    for _,item in ipairs(items) do if item.owner_player_id==2 then found=true end end
    ok(found,"P2 can collect their own drop")
    a.session:add_bomb(2,-8);a.session:add_bomb(2,1)
    for _,p in pairs(a.players) do p.bomb_frames=0 end
    ok(a:use_bomb(1),"one remaining Bomb can be spent")
    ok(not a:use_bomb(2),"same-frame second use cannot overspend shared stock")
    a.coop:hit(1)
    for _=1,599 do a.coop:update() end
    ok(not a.players[1].alive,"solo respawn waits full ten seconds")
    a.coop:update();ok(a.players[1].alive,"solo respawn at 600 frames")
    a.session.party.team_life=1
    a.coop:hit(1);a.coop:hit(2)
    eq(apps[1].replay:update({}),"failed","last team life ends the round")
    eq(a.coop.wipes,2,"team wipes counted once each")
    apps[1].replay_network:receive({version=Network.VERSION,generation=apps[1].replay_network.generation,kind="leave"})
    eq(apps[1].session.run_state,"MENU","peer leave returns to menu")
    ok(not apps[1].replay.network_config,"leaving clears replay network state")
    local menu=Bootstrap.create({})
    menu:open_network_menu("host");menu.network_menu.cursor=3
    menu:_update_network_menu({move_x=1})
    eq(menu.network_menu.play_mode,"replay","host can select replay from LAN menu")
    menu:_update_network_menu({move_x=1})
    eq(menu.network_menu.play_mode,"replay","held direction does not flicker between modes")
    menu.network_menu:backspace()
    eq(menu.network_menu.play_mode,"replay","backspace does not edit enum field")
end
