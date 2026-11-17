-- Executed in two LuaSTG processes by the TCP validation harness.
local root=assert(os.getenv('TNR_TEST_PROJECT_ROOT')):gsub('\\','/')
package.path=root..'/game/scripts/?.lua;'..root..'/game/scripts/?/init.lua;'..package.path
local role=assert(os.getenv('TNR_TEST_ROLE'))
local scenario=assert(os.getenv('TNR_TEST_SCENARIO'))
local id=role=='host' and 1 or 2
local LAN=require('tnr.multiplayer.lan_transport')
local Session=require('tnr.core.game_session')
local Instance=require('tnr.equipment.equipment_instance')
local Shop=require('tnr.shop.shop_service')
local g=require('lstg')
local session,transport,connected,sent,frame,seen_peer,done,delayed= nil,nil,false,false,0,false,false,nil
local disconnect_reason
local phase=0
local go,seen_go=false,false
local extended=scenario:match('^shop_') or scenario:match('^reward_')
local floor_test=scenario:match('^floor_')
local function log(s) local f=assert(io.open('result.txt','a'));f:write(s,'\n');f:close() end
local function toggle(p) return {type='TOGGLE_SUPPORT',player_id=p,slot_index=1} end
function GameInit()
  transport=LAN.new({mode=role,player_id=id,host='127.0.0.1',port=assert(tonumber(os.getenv('TNR_TEST_PORT'))),
    on_disconnect=function(reason) disconnect_reason=reason end})
  session=Session.new({run_seed=8,player_count=2,local_player_id=id}):start_new()
  transport:attach_session(session)
  local definition=session.equipment_registry:get('test_high_weapon')
  if role=='client' then for i=1,9 do Instance.new(definition,2) end end
  if floor_test then
    session.run_state='FLOOR_CLEAR'
    for p=1,2 do
      if scenario=='floor_both' or (p==1 and scenario=='floor_pending1') or (p==2 and scenario~='floor_pending1') then
        local inventory=session:get_player(p).loadout.inventory
        for i=1,inventory.capacity do inventory:add(Instance.new(definition,p)) end
        session.preparation:queue_acquisition(p,Instance.new(definition,p))
      end
    end
    if scenario=='floor_cross' and role=='host' then
      local queue=transport._queue
      transport._queue=function(self,kind,payload)
        if kind=='prep_prepare' and delayed==nil then delayed={kind=kind,payload=payload};return end
        queue(self,kind,payload)
      end
      local handle=transport._handle_preparation
      transport._handle_preparation=function(self,kind,payload)
        if kind=='prep_prepare' and delayed then
          local message=delayed;delayed=false;queue(self,message.kind,message.payload)
        end
        return handle(self,kind,payload)
      end
    end
  end
  if scenario=='pending' or scenario=='ids' then
    local inventory=session:get_player(2).loadout.inventory
    for i=1,12 do inventory:add(Instance.new(definition,2)) end
    session.preparation:queue_acquisition(2,Instance.new(definition,2))
    log('INVENTORY_FIRST_ID='..tostring(inventory.items[1].instance_id))
  elseif scenario=='capacity' and role=='host' then
    session:get_player(2).current_capacity=42
  elseif scenario=='race' then
    session.run_state='SHOP';session.shop_service=Shop.new(session)
    session.shop_service:open({id='race',content_seed=7});session.shop_service.ready[1]=true
    if role=='host' then
      local queue=transport._queue
      transport._queue=function(self,kind,payload)
        if kind=='prep_prepare' and not delayed then delayed={kind=kind,payload=payload};return end
        queue(self,kind,payload)
      end
      local handle=transport._handle_preparation
      transport._handle_preparation=function(self,kind,payload)
        if kind=='prep_prepare' and delayed then
          local p=delayed;delayed=false;queue(self,p.kind,p.payload)
        end
        return handle(self,kind,payload)
      end
    end
  end
  if scenario:match('^shop_') then
    session.run_state='SHOP';session.shop_service=Shop.new(session)
    session.shop_service:open({id='test-shop',content_seed=7})
    session:get_player(2).money=10;session.money=10
    session.shop_service.offers[1].price=2
    session.shop_service.offers[2].price=2
    session.shop_service.offers[3].price=2
    if scenario=='shop_pending_accept' or scenario=='shop_pending_reject' then
      local inventory=session:get_player(2).loadout.inventory
      for i=1,inventory.capacity do inventory:add(Instance.new(definition,2)) end
    end
    if role=='host' then
      if scenario=='shop_mismatch_purchase' then session.shop_service.purchases[2]={[2]=true}
      elseif scenario=='shop_mismatch_money' then session:get_player(2).money=9
      elseif scenario=='shop_mismatch_session_money' then session.money=9
      elseif scenario=='shop_mismatch_bomb' then session:get_player(2).bomb=4
      elseif scenario=='shop_mismatch_life' then session.party.team_life=4
      elseif scenario=='shop_mismatch_fragment' then session.party.life_fragments=1
      elseif scenario=='shop_mismatch_inventory' then session:get_player(2).loadout.inventory:add(Instance.new(definition,2))
      elseif scenario=='shop_mismatch_offer' then session.shop_service.offers[2].amount=8 end
    end
    if scenario=='shop_rejected' then session.shop_service.purchases[2]={[2]=true} end
  elseif scenario=='reward_race' or scenario=='reward_unclaim_race' then
    session.run_state='REWARD';session.reward_required=scenario=='reward_unclaim_race' and 2 or 1
    session.reward_choices={{kind='EQUIPMENT',definition_id='test_high_weapon'}, {kind='RESOURCE',resource='bomb',amount=1}}
    local inventory=session:get_player(1).loadout.inventory
    for i=1,inventory.capacity do inventory:add(Instance.new(definition,1)) end
    assert(session:claim_reward(1,1))
    if scenario=='reward_unclaim_race' then assert(session:claim_reward(2,2)) end
    if role=='host' then
      local queue=transport._queue
      transport._queue=function(self,kind,payload)
        if kind=='prep_prepare' and not delayed then delayed={kind=kind,payload=payload};return end
        queue(self,kind,payload)
      end
      local handle=transport._handle_preparation
      transport._handle_preparation=function(self,kind,payload)
        if kind=='prep_prepare' and delayed then
          local p=delayed;delayed=false;queue(self,p.kind,p.payload)
        end
        return handle(self,kind,payload)
      end
    end
  end
  if scenario=='shop_disconnect' and role=='client' then
    local handle=transport._handle_preparation
    transport._handle_preparation=function(self,kind,payload)
      handle(self,kind,payload)
      if kind=='prep_commit' and self.connected then
        self:disconnect('injected link failure before acknowledgement')
        assert(disconnect_reason and disconnect_reason:find('配装操作未确认',1,true))
        log('VERDICT=PASS shop_disconnect unconfirmed client');done=true
      end
    end
  end
end
function FrameFunc()
 frame=frame+1
 local ok,err=xpcall(function()
  if not connected then
    if not transport.connected and not transport.listening then transport:connect() end
    transport:update()
    if transport.connected then connected=true;log('CONNECTED '..role) end
    return
  end
  transport:update()
  if done and not transport.connected then return true end
  if floor_test then
    assert(transport.connected,'unexpected floor disconnect: '..tostring(disconnect_reason))
    local peer=transport:consume_peer_snapshot()
    if peer and peer.ready then seen_peer=true end
    if peer and peer.go then seen_go=true end
    transport:publish_peer_snapshot({ready=true,go=go})
    if seen_peer and not sent and (scenario~='floor_cross' or role=='host' or seen_go) then
      if role=='host' then assert(transport:send({type='ADVANCE_FLOOR',player_id=1}));go=true
      elseif scenario=='floor_cross' then assert(transport:send({type='REJECT_PENDING_ITEM',player_id=2})) end
      sent=true
    end
    local result=transport:consume_preparation_result()
    if result and not done then
      if phase==0 then
        assert(not result.ok and session.run_state=='FLOOR_CLEAR')
        if scenario=='floor_both' or scenario=='floor_pending1' then
          assert(session.acquisition_service:get_pending(1))
          if role=='host' then assert(transport:send({type='REJECT_PENDING_ITEM',player_id=1})) end
        else
          assert(session.acquisition_service:get_pending(2))
          if role=='client' then assert(transport:send({type='REJECT_PENDING_ITEM',player_id=2})) end
        end
        phase=1
      elseif phase==1 then
        assert(result.ok and session.run_state=='FLOOR_CLEAR')
        if scenario=='floor_both' then
          assert(not session.acquisition_service:get_pending(1) and session.acquisition_service:get_pending(2))
          if role=='client' then assert(transport:send({type='REJECT_PENDING_ITEM',player_id=2})) end
          phase=2
        else
          assert(not session.acquisition_service:get_pending(1) and not session.acquisition_service:get_pending(2))
          if role=='host' then assert(transport:send({type='ADVANCE_FLOOR',player_id=1})) end
          phase=3
        end
      elseif phase==2 then
        assert(result.ok and not session.acquisition_service:get_pending(2))
        if role=='host' then assert(transport:send({type='ADVANCE_FLOOR',player_id=1})) end
        phase=3
      else
        assert(result.ok and session.run_state=='MAP' and session.floor==2)
        done=true;log('VERDICT=PASS '..scenario..' pending preserved, retry advanced')
      end
    end
    if done and frame>500 then return true end
    if frame>4000 then error('floor timeout phase='..phase) end
    return
  end
  if extended then
    if not transport.connected then
      if scenario:match('^shop_mismatch_') then
        assert(session:get_player(2).bomb==(scenario=='shop_mismatch_bomb' and role=='host' and 4 or 3))
        log('VERDICT=PASS '..scenario..' stopped before mutation');return true
      elseif scenario=='shop_disconnect' then
        assert(disconnect_reason and disconnect_reason:find('配装操作未确认',1,true))
        log('VERDICT=PASS shop_disconnect unconfirmed host');return true
      end
      error('unexpected disconnect: '..tostring(transport.last_error))
    end
    local peer=transport:consume_peer_snapshot()
    if peer and peer.ready then seen_peer=true end
    if peer and peer.go then seen_go=true end
    transport:publish_peer_snapshot({ready=true,go=go})
    local reward_race=scenario=='reward_race' or scenario=='reward_unclaim_race'
    if seen_peer and not sent and (not reward_race or role=='host' or seen_go) then
      if scenario=='reward_race' or scenario=='reward_unclaim_race' then
        if role=='host' then assert(transport:send({type='ACCEPT_PENDING_ITEM',player_id=1,discard_index=1}));go=true
        else assert(transport:send({type=scenario=='reward_race' and 'CLAIM_REWARD' or 'UNCLAIM_REWARD',player_id=2,choice_index=2})) end
      elseif role=='client' then
        local slot=(scenario=='shop_pending_accept' or scenario=='shop_pending_reject' or scenario=='shop_equipment') and 3 or (scenario=='shop_life' and 1 or 2)
        assert(transport:send({type='SHOP_PURCHASE',player_id=2,slot=slot}))
      end
      sent=true
    end
    local result=transport:consume_preparation_result()
    if result and not done then
      if (scenario=='reward_race' or scenario=='reward_unclaim_race') and phase==0 then
        assert(result.ok==false and session.run_state=='REWARD');phase=1
        if role=='client' then assert(transport:send({type=scenario=='reward_race' and 'CLAIM_REWARD' or 'UNCLAIM_REWARD',player_id=2,choice_index=2})) end
      elseif scenario=='reward_race' or scenario=='reward_unclaim_race' then
        assert(result.ok and session.run_state==(scenario=='reward_race' and 'MAP' or 'REWARD'))
        assert(session:get_player(2).bomb==(scenario=='reward_race' and 4 or 3) and session.acquisition_service:get_pending(1))
        done=true;log('VERDICT=PASS '..scenario..' rejected and retried exactly once')
      elseif scenario=='shop_rejected' then
        assert(not result.ok and result.error=='ALREADY_PURCHASED')
        assert(session:get_player(2).bomb==3 and session:get_player(2).money==10)
        done=true;log('VERDICT=PASS shop_rejected')
      elseif scenario=='shop_pending_accept' or scenario=='shop_pending_reject' then
        assert(result.ok)
        if phase==0 then
          assert(session.acquisition_service:get_pending(2) and session:get_player(2).money==10)
          phase=1
          if role=='client' then
            assert(transport:send({type=scenario=='shop_pending_accept' and 'ACCEPT_PENDING_ITEM' or 'REJECT_PENDING_ITEM',player_id=2,discard_index=12}))
          end
        else
          assert(not session.acquisition_service:get_pending(2))
          assert(session:get_player(2).money==(scenario=='shop_pending_accept' and 8 or 10))
          assert((session.shop_service.purchases[2][3]==true)==(scenario=='shop_pending_accept'))
          done=true;log('VERDICT=PASS '..scenario)
        end
      elseif scenario=='shop_life' then
        assert(result.ok and session.party.team_life==4 and session:get_player(2).money==8)
        assert(session.shop_service.purchases[2][1]==true)
        done=true;log('VERDICT=PASS '..scenario)
      elseif scenario=='shop_equipment' then
        assert(result.ok and session:get_player(2).loadout.inventory:count()==1 and session:get_player(2).money==8)
        assert(session.shop_service.purchases[2][3]==true)
        done=true;log('VERDICT=PASS '..scenario)
      else
        assert(result.ok and session:get_player(2).bomb==5 and session:get_player(2).money==8)
        assert(session.shop_service.purchases[2][2]==true)
        done=true;log('VERDICT=PASS '..scenario)
      end
    end
    if done and frame>500 then return true end
    if frame>4000 then error('timeout scenario='..scenario..' phase='..phase) end
    return
  end
  if scenario=='capacity' and not transport.connected then
    assert(session:get_player(2).loadout.supports[1].runtime_data.enabled~=false)
    log('VERDICT=PASS preexisting current_capacity mismatch detected before mutation');return true
  end
  assert(transport.connected,'unexpected disconnect: '..tostring(transport.last_error))
  local peer=transport:consume_peer_snapshot()
  if peer and peer.ready then seen_peer=true end
  if peer and peer.go then seen_go=true end
  transport:publish_peer_snapshot({ready=true,go=go})
  if seen_peer and not sent and (scenario~='race' or role=='host' or seen_go) then
    if scenario=='race' and role=='host' then assert(transport:send_preparation(toggle(1)));sent=true;go=true
    elseif scenario=='race' and role=='client' then assert(transport:send({type='SHOP_READY',player_id=2}));sent=true
    elseif role=='client' then
      if scenario=='capacity' then assert(transport:send_preparation(toggle(2)))
      else assert(transport:send({type='ACCEPT_PENDING_ITEM',player_id=2,discard_index=scenario=='pending' and 99 or 12})) end
      sent=true
    end
  end
  local result=transport.preparation_result
  if result and not done then
    if scenario=='pending' then
      assert(result.ok==false and result.error=='UNKNOWN_ITEM')
      assert(session.acquisition_service:get_pending(2)~=nil)
      assert(session:get_player(2).loadout.inventory:count()==12)
    elseif scenario=='ids' then
      assert(result.ok==true and session.acquisition_service:get_pending(2)==nil)
      assert(session:get_player(2).loadout.inventory:count()==12)
    elseif scenario=='race' then
      assert(result.ok==false and session.run_state=='SHOP')
    end
    done=true;log('VERDICT=PASS '..scenario..' result='..tostring(result.ok))
  end
  if done and frame>500 then return true end
  if frame>4000 then error('timeout scenario='..scenario) end
 end,debug.traceback)
 if not ok then log('FAIL '..tostring(err));transport:disconnect();return true end
 return err==true
end
function RenderFunc() g.BeginScene();g.RenderClear(g.Color(255,0,0,0));g.EndScene() end
function GameExit() if transport then transport:disconnect() end end
function FocusGainFunc() end
function FocusLoseFunc() end
