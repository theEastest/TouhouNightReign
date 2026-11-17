local LAN = require("tnr.multiplayer.lan_transport")
local Session = require("tnr.core.game_session")
local Instance = require("tnr.equipment.equipment_instance")
local Command = require("tnr.core.command")
local Bootstrap = require("tnr.bootstrap")

return function(eq, truth)
    local function pair()
        local host = LAN.new({mode="host",player_id=1,socket={}})
        local client = LAN.new({mode="client",player_id=2,socket={}})
        host:attach_session(Session.new({run_seed=8,player_count=2,local_player_id=1}):start_new())
        client:attach_session(Session.new({run_seed=8,player_count=2,local_player_id=2}):start_new())
        host.connected=true;client.connected=true
        host.socket_handle={send=function(_, payload) return #payload end, close=function() end}
        local wire = {}
        local function enqueue(sender, recipient, kind, payload)
            wire[#wire+1]={sender=sender,recipient=recipient,kind=kind,payload=payload}
        end
        host._queue=function(_,kind,payload) enqueue(host,client,kind,payload) end
        client._queue=function(_,kind,payload) enqueue(client,host,kind,payload) end
        local function pump()
            local limit=0
            while #wire>0 do
                limit=limit+1;assert(limit<30,"transaction did not settle")
                local message=table.remove(wire,1)
                if message.recipient.connected then message.recipient:_handle_preparation(message.kind,message.payload) end
                if host.connected then host:_flush() end
            end
        end
        return host,client,wire,pump
    end
    local function toggle(player)
        return {type=Command.TOGGLE_SUPPORT,player_id=player,slot_index=1}
    end
    do
        local host,client,wire,pump=pair()
        truth(client:send_preparation(toggle(2)) == true, "client starts transaction")
        local request=wire[1].payload
        pump()
        eq(host.session:get_player(2).loadout.supports[1].runtime_data.enabled,false,"host applies confirmed operation")
        eq(client.session:get_player(2).loadout.supports[1].runtime_data.enabled,false,"client applies confirmed operation")
        eq(host.preparation_pending,nil,"host clears confirmed operation")
        eq(client.preparation_pending,nil,"client clears confirmed operation")
        host:_handle_preparation("prep_prepare",request);pump()
        eq(host.session:get_player(2).loadout.supports[1].runtime_data.enabled,false,"replayed request cannot toggle twice")
        eq(client.session:get_player(2).loadout.supports[1].runtime_data.enabled,false,"replay is not sent back for execution")
    end
    do
        local host,client,_,pump=pair()
        for _,transport in ipairs({host,client}) do
            local inventory=transport.session:get_player(1).loadout.inventory
            local definition=transport.session.equipment_registry:get("test_high_weapon")
            for i=1,inventory.capacity do inventory:add(Instance.new(definition,1)) end
        end
        truth(host:send_preparation({type=Command.DISCARD_EQUIPPED_ITEM,player_id=1,slot_type="high_weapons",slot_index=1}) == true,"host requests discard")
        pump()
        eq(host.preparation_result.error,"INVENTORY_FULL","host reports failed atomic discard")
        eq(client.preparation_result.error,"INVENTORY_FULL","client receives failed atomic discard")
        truth(host.session:get_player(1).loadout.high_weapons[1] ~= false,"host keeps equipped item")
        truth(client.session:get_player(1).loadout.high_weapons[1] ~= false,"client keeps equipped item")
    end
    do
        local host,client,_,pump=pair()
        local definition=host.session.equipment_registry:get("test_high_weapon")
        host.session:get_player(2).loadout.inventory:add(Instance.new(definition,2))
        truth(client:send_preparation(toggle(2)) == true,"request starts with different peer state")
        pump()
        eq(host.connected,false,"different preconditions stop host")
        eq(client.connected,false,"different preconditions stop client")
        truth(host.session:get_player(2).loadout.supports[1].runtime_data.enabled ~= false,"host does not apply on mismatch")
        truth(client.session:get_player(2).loadout.supports[1].runtime_data.enabled ~= false,"client does not apply on mismatch")
    end
    do
        local host,client,_,pump=pair()
        truth(host:send_preparation(toggle(1)) == true,"host request queued")
        truth(client:send_preparation(toggle(2)) == true,"client request queued")
        pump()
        eq(host.preparation_result.ok,false,"host simultaneous request rejected")
        eq(client.preparation_result.ok,false,"client simultaneous request rejected")
        truth(host.session:get_player(1).loadout.supports[1].runtime_data.enabled ~= false,"simultaneous host request not applied")
        truth(client.session:get_player(2).loadout.supports[1].runtime_data.enabled ~= false,"simultaneous client request not applied")
    end
    do
        local host,client,_,pump=pair()
        for _,transport in ipairs({host,client}) do
            local session=transport.session
            local definition=session.equipment_registry:get("test_high_weapon")
            for i=1,12 do session:get_player(2).loadout.inventory:add(Instance.new(definition,2)) end
            session.preparation:queue_acquisition(2,Instance.new(definition,2))
        end
        truth(client:send({type=Command.ACCEPT_PENDING_ITEM,player_id=2,discard_index=99}),"pending accept uses transaction")
        pump()
        truth(host.connected and client.connected,"host rejection leaves connection healthy")
        eq(client.preparation_result.error,"UNKNOWN_ITEM","client sees host rejection")
        truth(host.session.acquisition_service:get_pending(2) ~= nil,"host retains rejected item")
        truth(client.session.acquisition_service:get_pending(2) ~= nil,"client retains rejected item")
        truth(client:send({type=Command.ACCEPT_PENDING_ITEM,player_id=2,discard_index=12}),"valid accept queued")
        pump()
        eq(host.session.acquisition_service:get_pending(2),nil,"host accepted pending item")
        eq(client.session.acquisition_service:get_pending(2),nil,"client accepted pending item")
        truth(host.connected and client.connected,"different instance IDs do not break confirmation")
        for _,transport in ipairs({host,client}) do
            local definition=transport.session.equipment_registry:get("test_high_weapon")
            transport.session.preparation:queue_acquisition(2,Instance.new(definition,2))
        end
        truth(client:send({type=Command.REJECT_PENDING_ITEM,player_id=2}),"reject pending uses transaction")
        pump()
        eq(host.session.acquisition_service:get_pending(2),nil,"host rejected pending item")
        eq(client.session.acquisition_service:get_pending(2),nil,"client rejected pending item")
    end
    do
        local host,client,_,pump=pair()
        for _,transport in ipairs({host,client}) do
            local s=transport.session
            s.run_state="SHOP";s.shop_service=require("tnr.shop.shop_service").new(s)
            s.shop_service:open({id="normal",content_seed=7})
        end
        truth(host:send({type=Command.SHOP_READY,player_id=1}),"first ready queued")
        pump()
        truth(host.preparation_result.ok and client.preparation_result.ok,"first ready false return is successful")
        truth(host.session.shop_service.ready[1] and client.session.shop_service.ready[1],"first ready synchronized")
        truth(client:send({type=Command.SHOP_READY,player_id=2}),"second ready queued")
        pump()
        eq(host.session.run_state,"MAP","second ready closes host shop")
        eq(client.session.run_state,"MAP","second ready closes client shop")
    end
    do
        local host,client,_,pump=pair()
        for _,transport in ipairs({host,client}) do
            local session=transport.session
            session.run_state="ENCOUNTER"
            session.current_encounter={id="early-reward",type=require("tnr.core.constants").node_types.ELITE,
                stage_id="test_enemy_stage"}
        end
        truth(host:send({type=Command.CLAIM_REWARD,player_id=1,choice_index=1}),"early reward claim starts transaction")
        pump()
        truth(host.connected and client.connected,"deferred claim remains connected")
        truth(host.preparation_result.ok and client.preparation_result.ok,"deferred claim is confirmed on both peers")
        eq(host.session.pending_reward_claims[1],1,"host records deferred reward choice")
        eq(client.session.pending_reward_claims[1],1,"client records deferred reward choice")
        for _,transport in ipairs({host,client}) do
            transport.session:complete_battle({clear_state=true,reward_eligible=false})
            eq(transport.session.run_state,"REWARD","battle completion opens the reward screen")
            eq(transport.session.pending_reward_claims[1],nil,"battle completion consumes deferred reward choice")
            eq(#transport.session.reward_claims[1],1,"deferred reward choice is applied")
        end
    end
    do
        local host,client,_,pump=pair()
        for _,transport in ipairs({host,client}) do
            local s=transport.session
            s.run_state="SHOP"
            s.shop_service=require("tnr.shop.shop_service").new(s)
            s.shop_service:open({id="race",content_seed=7})
            s.shop_service.ready[1]=true
        end
        truth(host:send_preparation(toggle(1)),"host starts shop equipment change")
        truth(client:send({type=Command.SHOP_READY,player_id=2}),"concurrent ready starts transaction")
        pump()
        truth(host.connected and client.connected,"concurrent shop ready stays connected")
        eq(host.session.run_state,"SHOP","race leaves host in shop")
        eq(client.session.run_state,"SHOP","race leaves client in shop")
        truth(client:send({type=Command.SHOP_READY,player_id=2}),"ready can be retried")
        pump()
        eq(host.session.run_state,"MAP","ready retry closes host shop")
        eq(client.session.run_state,"MAP","ready retry closes client shop")
    end
    do
        for _,field in ipairs({"current_capacity","character_id"}) do
            local host,client,_,pump=pair()
            host.session:get_player(2)[field]=field == "character_id" and "other" or 42
            truth(client:send_preparation(toggle(2)),"divergent "..field.." request queued")
            pump()
            eq(host.connected,false,"divergent "..field.." aborts before applying")
            truth(client.session:get_player(2).loadout.supports[1].runtime_data.enabled ~= false,"divergent field did not apply")
        end
    end
    do
        local host,client,wire=pair()
        local host_reason,client_reason
        host.options.on_disconnect=function(reason) host_reason=reason end
        client.options.on_disconnect=function(reason) client_reason=reason end
        truth(client:send_preparation(toggle(2)) == true,"disconnect fixture request starts")
        local request=table.remove(wire,1)
        host:_handle_preparation(request.kind,request.payload)
        truth(host.preparation_pending ~= nil,"host has unconfirmed committed operation")
        host:disconnect("injected link failure")
        client:disconnect("injected link failure")
        truth(host_reason:find("配装操作未确认",1,true) ~= nil,"host reports unconfirmed operation")
        truth(client_reason:find("配装操作未确认",1,true) ~= nil,"client reports unconfirmed operation")
    end
    do
        local host,client,wire=pair()
        local reason
        host.options.on_disconnect=function(value) reason=value end
        truth(client:send_preparation(toggle(2)),"request starts before final send failure")
        for _=1,3 do
            local message=table.remove(wire,1)
            message.recipient:_handle_preparation(message.kind,message.payload)
        end
        eq(host.preparation_pending.phase,"sending_done","host retains final confirmation until send")
        eq(host.preparation_result,nil,"host has not reported success before final send")
        eq(client.preparation_pending.phase,"done","client awaits final confirmation")
        host.outgoing={"final confirmation"}
        host.socket_handle={send=function() return nil,"closed" end,close=function() end}
        host:_flush()
        truth(reason:find("配装操作未确认",1,true) ~= nil,"final send failure reports unconfirmed")
        eq(host.preparation_result,nil,"final send failure cannot report success")
    end
    do
        local app=Bootstrap.create({run_seed=8,player_count=1})
        app.network_menu:close()
        app:_on_network_disconnect("配装操作未确认：测试")
        truth(app.network_menu:is_open(),"disconnect opens a visible network error screen")
        truth(app.network_menu.status:find("配装操作未确认",1,true) ~= nil,"visible error describes unconfirmed operation")
        truth(app.network_menu.status_is_error,"disconnect message is rendered as an error")
    end
end
