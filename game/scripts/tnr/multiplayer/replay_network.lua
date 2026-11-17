-- A separate, generation-tagged channel on the existing LAN transport.
-- Shared ECL simulation is input-driven; hit/graze reports originate only on
-- the owning machine. The host orders those reports with future input ticks.
local C=require("tnr.core.constants").run_states
local Wire=require("tnr.multiplayer.lan_transport")
local N={};N.__index=N
N.VERSION=5
N.DELAY=3
local function empty() return {move_x=0,move_y=0,shoot=false,focus=false,bomb=false} end
function N.new(app,mode)
    return setmetatable({app=app,transport=app.transport,host=app.transport:is_host(),
        id=app.session.local_player_id,mode=mode,ready={},characters={},serial=0,
        phase="setup",silence=0,hashes={},remote_hashes={}},N)
end
function N:send(message)
    message.version=N.VERSION
    message.generation=message.generation or self.generation
    return self.transport:send_replay(message)
end
function N:select(lobby)
    local selected=self.app.replay.stage_cursor
    local character=self.app.replay.character_cursor
    self.app.replay:stop()
    self.app:close_preparation_overlay()
    self.app:open_replay_select()
    self.app.replay.stage_cursor=selected
    self.app.replay.character_cursor=character
    self.app.replay.mode_cursor=self.rules or 2
    self.app.replay.player_count_cursor=2
    self.app.replay.network_lobby=true
    self.app.replay.equipment_seed=self.equipment_seed or self.app.network_seed or 151
    self.loadouts={}
    self.lobby=lobby or (self.lobby or 0)+1
    self.ready={};self.phase="select";self.sent_tick=0;self.pending_result=nil
    self.revision=0;self.pending_rewards={};self.reward_pending=false
    self.menu_x=0;self.bomb_pending=false;self.bomb_was_down=false
    self.app.replay.network_status=nil
    self.app.replay_field=self.host and "stage" or "character"
    self.app.replay.message="各自选择自机，Enter 准备；房主选择关卡和规则"
end
function N:return_to_select()
    self:select()
    self:send({kind="select",lobby=self.lobby})
end
function N:launch(config)
    local r=self.app.replay
    self.rules=config.rules or 2
    self.generation=config.generation
    self.serial=config.serial
    r.stage_cursor=config.stage
    r.character_cursor=config.character_cursors[self.id]
    r.mode_cursor=config.rules or 2;r.player_count_cursor=2
    r.equipment_seed=config.equipment_seed
    r.network_config={seed=config.seed,local_player_id=self.id,characters=config.characters,loadouts=config.loadouts}
    assert(self.app:start_replay_stage())
    self.phase="loading";self.pending={};self.bundles={};self.hashes={};self.remote_hashes={}
    self.sent_tick=0;self.silence=0;self.pending_result=nil;self.local_outcome=nil
    self.dialogue_confirm_pending=false
    self.pending_rewards={}
    self.last_progress=self.transport.now and self.transport:now() or os.clock()
    for tick=1,N.DELAY do self.pending[tick]={[1]=empty(),[2]=empty()} end
    self:send({kind="loaded"})
end
function N:begin()
    self.serial=self.serial+1
    local r=self.app.replay
    local config={kind="start",stage=r.stage_cursor,rules=r.mode_cursor,equipment_seed=self.app.network_seed or 151,
        serial=self.serial,lobby=self.lobby,revision=self.revision,
        generation=tostring(self.app.network_seed or 151)..":"..self.serial,
        seed=(self.app.network_seed or 151)+self.serial*101,
        character_cursors=self.characters,characters={},loadouts=self.loadouts}
    for id=1,2 do config.characters[id]=r.CHARACTERS[self.characters[id]].key end
    self:send(config);self:launch(config)
end
function N:signature()
    local r=self.app.replay;local s=r.runtime
    local state={frame=s.frames,rng=s.adapter.rng.state,rng_draws=s.adapter.rng.draws,life=s.session.party.team_life,
        bombs=s.session.team_bombs,bomb_fragments=s.session.bomb_fragments or 0,
        life_fragments=s.session.party.life_fragments,players={},enemies={},shots={},items={},modern={},
        slowdown=s.items.slowdown,item_serial=s.items.spawn_serial,
        chapter={s.chapter,s.adapter.chapter_targets,s.adapter.chapter_defeated},bomb_states={},blasts={}}
    for id=1,2 do
        local p=s.players[id]
        state.players[id]={p.x,p.y,p.alive,p.power,p.graze,p.score or 0,p.invulnerable,
            s.coop.respawns[id] or 0,p.deathbomb_frames or 0,p.option_anchors,p.chapter_graze or 0,p.point_rate or 10000}
        local b=p.classic_bomb
        if b then
            local orbs={}
            for i,orb in ipairs(b.orbs or {}) do orbs[i]={orb.x,orb.y,orb.angle,orb.speed,orb.dx,orb.dy} end
            state.bomb_states[id]={b.kind,b.age,b.x,b.y,b.layers or 0,b.angle or 0,orbs}
        else state.bomb_states[id]={p.bomb_frames or 0} end
    end
    for i,blast in ipairs(s.classic_blasts or {}) do
        local orbs={}
        for j,orb in ipairs(blast.orbs) do orbs[j]={orb.x,orb.y} end
        state.blasts[i]={blast.player_id,blast.age,orbs}
    end
    for i,e in ipairs(s.adapter.enemies) do
        state.enemies[i]={e.x,e.y,e.hp,e.legacy_deleted or false,
            e.legacy_base_x or e.x,e.legacy_base_y or e.y,e.legacy_rel_x or 0,e.legacy_rel_y or 0,
            e.legacy_chapter or 0,e.legacy_chapter_weight or 0,e.legacy_spell_failed or false}
    end
    for i,b in ipairs(s.adapter.shots) do
        state.shots[i]={b.x,b.y,b.vx,b.vy,b.sprite or b.anim,b.damage or 0,
            laser=b.laser_kind,length=b.length,width=b.draw_width,nodes=b.nodes,age=b.anim_frame}
    end
    for i,item in ipairs(s.items.list) do
        state.items[i]={item.kind,item.x,item.y,item.owner_player_id,item.vx,item.vy,item.attract_speed or 0,
            item.launch_delay or 0}
    end
    if s.modern then
        for id,d in pairs(s.modern.drivers) do
            state.modern[id]={d.p_gauge.value,d.p_gauge.hot_frames,d.p_rng and d.p_rng.state or 0,
                d.affixes.rng.state,d.affixes.shield,d.affixes.frost}
        end
        state.modern_shots={}
        for i,b in ipairs(s.modern.shots) do state.modern_shots[i]={b.x,b.y,b.damage,b.age or 0} end
    end
    local encoded=Wire.encode(state);local hash=5381
    for i=1,#encoded do hash=(hash*33+encoded:byte(i))%4294967296 end
    return tostring(hash)
end
function N:fail(message)
    self.phase="error"
    self.app.replay.message=message
    self.app.replay.network_status=nil
    self.app.session.run_state=C.REPLAY_SELECT
end
function N:receive(m)
    if type(m)~="table" then return end
    if m.version~=N.VERSION then self:fail("联机版本不一致，请使用同一版本");return end
    if m.kind=="room" and not self.host then
        self.mode=m.mode
        self.equipment_seed=m.equipment_seed
        if self.mode=="replay" and self.phase=="setup" then
            if self.app.replay.MODES[m.rules] then self.rules=m.rules end
            self:select(m.lobby)
            self.revision=tonumber(m.revision) or 0
            if self.app.replay.STAGES[m.stage] then self.app.replay.stage_cursor=m.stage end
        end
        return
    end
    if self.mode~="replay" then return end
    if m.kind=="lobby" and not self.host and self.phase=="select" and m.lobby==self.lobby then
        if type(m.revision)~="number" or m.revision<self.revision then return end
        self.revision=m.revision
        if self.app.replay.STAGES[m.stage] then self.app.replay.stage_cursor=m.stage end
        if self.app.replay.MODES[m.rules] then self.rules=m.rules;self.app.replay.mode_cursor=m.rules end
        self.ready={}
        return
    end
    if m.kind=="ready" and self.phase=="select" and m.lobby==self.lobby and m.revision==self.revision then
        local peer=3-self.id
        local cursor=tonumber(m.character)
        if cursor and self.app.replay.CHARACTERS[cursor] then
            self.ready[peer]=m.ready==true;self.characters[peer]=cursor
            self.loadouts[peer]=m.loadout
        end
        return
    end
    if m.kind=="start" and not self.host and self.phase=="select" then
        if not self.app.replay.STAGES[m.stage] or not m.character_cursors
                or not m.characters or not tonumber(m.seed) or m.serial~=self.serial+1
                or m.lobby~=self.lobby or m.revision~=self.revision then return end
        for id=1,2 do
            local c=self.app.replay.CHARACTERS[m.character_cursors[id]]
            if not c or c.key~=m.characters[id] then return end
        end
        self:launch(m);return
    end
    if m.generation~=self.generation then return end
    if not self.host and (m.kind=="reward_open" or m.kind=="reward_apply")
            and (self.phase=="playing" or self.phase=="await_result") then
        self.pending_rewards[#self.pending_rewards+1]=m
        return
    end
    if m.kind=="loaded" and self.host and self.phase=="loading" then
        self:send({kind="go"});self.phase="playing"
    elseif m.kind=="go" and not self.host and self.phase=="loading" then self.phase="playing"
    elseif m.kind=="input" and self.host and self.phase=="playing" then
        local tick=tonumber(m.tick)
        local frame=self.app.replay.runtime.frames
        if tick and tick%1==0 and tick>frame and tick<=frame+N.DELAY+10 and type(m.input)=="table" then
            self.pending[tick]=self.pending[tick] or {}
            self.pending[tick][2]=self.pending[tick][2] or m.input
        end
    elseif m.kind=="bundle" and not self.host and self.phase=="playing" then
        local tick=tonumber(m.tick)
        local frame=self.app.replay.runtime.frames
        if tick and tick>frame and tick<=frame+N.DELAY+10 then self.bundles[tick]=m.inputs end
    elseif m.kind=="hash" then
        if self.hashes[m.tick] and self.hashes[m.tick]~=m.hash then
            self:send({kind="error",message="关卡状态不同步，帧 "..tostring(m.tick)})
            self:fail("关卡状态不同步，帧 "..tostring(m.tick))
        else self.remote_hashes[m.tick]=m.hash end
    elseif m.kind=="error" then self:fail(tostring(m.message))
    elseif m.kind=="result" and not self.host and (self.phase=="playing" or self.phase=="await_result") then
        self.pending_result=m
    elseif m.kind=="reward_open" and not self.host and self.phase=="result" then
        self:open_rewards()
    elseif m.kind=="reward_pick" and self.host and self.phase=="reward" then
        if self.app.replay.reward_player_id==2 and m.round==self.app.replay.reward_round then
            self:reward_pick(m.index)
        end
    elseif m.kind=="reward_apply" and not self.host and self.phase=="reward" then
        if m.round==self.app.replay.reward_round and not self:reward_pick(m.index) then
            local message=self.app.replay.reward_message or "奖励同步失败"
            self:send({kind="error",message=message});self:fail(message)
        end
    elseif m.kind=="advance_result" and self.host and self.phase=="result" then
        self:advance_result()
    elseif m.kind=="back" then
        if self.host and self.phase~="select" then self:return_to_select() end
    elseif m.kind=="select" and not self.host and m.lobby==(self.lobby or 0)+1 then self:select(m.lobby)
    elseif m.kind=="leave" then
        self.app:_on_network_disconnect("对方退出了重演联机")
        self.mode="closed"
    end
end
function N:advance_result()
    if self:open_rewards() then self:send({kind="reward_open"})
    else self:return_to_select() end
end
function N:open_rewards()
    self.reward_pending=false
    local r=self.app.replay
    if r:next_reward_round() then
        if r.reward_player_id~=self.id then r.reward_message="等待队友领取奖励" end
        self.phase="reward";self.app.session.run_state=C.REPLAY_REWARD
        return true
    end
    return false
end
function N:reward_pick(index)
    local r=self.app.replay
    if type(index)~="number" or not (r.reward_choices or {})[index] then return false end
    r.reward_cursor=index
    local round=r.reward_round
    if not r:claim_reward(self.id) then return false end
    if self.host then self:send({kind="reward_apply",round=round,index=index}) end
    if not self:open_rewards() then
        self.phase="reward_done"
        if self.host then self:return_to_select() end
    end
    return true
end
function N:step(input)
    local r=self.app.replay;local s=r.runtime
    local bomb=input.bomb_down==true or input.bomb==true
    if bomb and not self.bomb_was_down then self.bomb_pending=true end
    self.bomb_was_down=bomb
    self.dialogue_confirm_pending=self.dialogue_confirm_pending or input.confirm==true
    if not s:simulation_step_due() then
        -- The final boss lowers the game clock. Accumulate those engine
        -- frames without sending or consuming an input for a simulation tick.
        s:update()
        return false
    end
    local target=s.frames+N.DELAY+1
    if self.sent_tick<target then
        local value={move_x=math.max(-1,math.min(1,tonumber(input.move_x) or 0)),
            move_y=math.max(-1,math.min(1,tonumber(input.move_y) or 0)),
            shoot=input.shoot==true,focus=input.focus==true,bomb=self.bomb_pending or bomb,
            confirm=self.dialogue_confirm_pending,skip_dialogue=input.skip_dialogue==true,
            hit=s.local_hit==true,graze=s.local_graze or 0,
            grazing=s.local_grazing==true,graze_drops=s.local_graze_drops or {}}
        s.local_hit=nil;s.local_graze=0
        s.local_grazing=false;s.local_graze_drops={}
        self.bomb_pending=false
        self.dialogue_confirm_pending=false
        self.sent_tick=target
        if self.host then self.pending[target]=self.pending[target] or {};self.pending[target][1]=value
        else self:send({kind="input",tick=target,input=value}) end
    end
    local tick=s.frames+1
    local inputs=self.host and self.pending[tick] or self.bundles[tick]
    if not inputs or not inputs[1] or not inputs[2] then return false end
    if self.host then self:send({kind="bundle",tick=tick,inputs=inputs});self.pending[tick]=nil
    else self.bundles[tick]=nil end
    for id=1,2 do
        local p=s.players[id]
        s:add_graze(id,tonumber(inputs[id].graze) or 0)
        if inputs[id].grazing then s.items:on_graze(id) end
        for _,drop in ipairs(inputs[id].graze_drops or {}) do s.items:spawn_graze(drop[1],drop[2],id) end
        if inputs[id].hit and p.alive and p.invulnerable<=0 then s:on_player_contact(id,p) end
    end
    local outcome=r:update(inputs)
    if tick%60==0 then
        local hash=self:signature();self.hashes[tick]=hash
        self:send({kind="hash",tick=tick,hash=hash})
        if self.remote_hashes[tick] and self.remote_hashes[tick]~=hash then self:fail("关卡状态不同步，帧 "..tick) end
    end
    if outcome~="playing" then
        if self.host then
            self:send({kind="result",outcome=outcome,tick=tick})
            r:finish_stage(outcome);self.app.session.run_state=C.REPLAY_RESULT;self.phase="result"
        else self.local_outcome=outcome;self.phase="await_result" end
    end
    return true
end
function N:update(input)
    if not self.transport.consume_replay or not self.transport.send_replay then return false end
    self.transport:update()
    if self.app.replay_network~=self then return true end
    if self.host and self.transport.connected and not self.room_sent then
        if self.mode=="replay" and self.phase~="select" then self:select() end
        local r=self.app.replay
        self:send({kind="room",mode=self.mode,lobby=self.lobby,revision=self.revision,
            stage=r.stage_cursor,rules=r.mode_cursor,equipment_seed=self.app.network_seed or 151})
        if self.mode=="replay" and self.ready[1] then
            self:send({kind="ready",lobby=self.lobby,revision=self.revision,ready=true,
                character=self.characters[1],loadout=self.loadouts[1]})
        end
        self.room_sent=true
    end
    for _,m in ipairs(self.transport:consume_replay()) do self:receive(m) end
    if self.app.replay_network~=self then return true end
    if not self.mode then
        if input.cancel then self.app:_on_network_disconnect("已取消连接") end
        return true
    end
    if self.mode~="replay" then return false end
    self.silence=self.silence+1
    if self.phase=="select" then
        local r=self.app.replay
        if self.app.preparation_overlay then
            self.app:_update_ui_mouse()
            self.app.ui_mouse_down=input.mouse_primary_down==true
            self.app:_update_replay_loadout(input);return true
        elseif input.tab and r.mode_cursor==1 and not self.ready[self.id] then
            r.reward_player_id=self.id;r:get_equipment_session()
            self.app:open_preparation_overlay();return true
        end
        if input.cancel then
            self:send({kind="leave"});self.transport:update()
            self.app:_on_network_disconnect("已退出重演联机");self.mode="closed";return true
        end
        if not self.ready[self.id] then
            if self.host and (input.move_x or 0)~=0 and self.menu_x==0 then
                local fields={"stage","character","mode"}
                for i,f in ipairs(fields) do if self.app.replay_field==f then
                    self.app.replay_field=fields[(i-1+(input.move_x>0 and 1 or -1))%#fields+1];break
                end end
            end
            do
                local field=self.host and self.app.replay_field or "character"
                local previous=r[field.."_cursor"]
                r[field.."_cursor"]=self.app:_scroll_step("replay_lan_"..field,r[field.."_cursor"],
                    field=="stage" and #r.STAGES or field=="mode" and #r.MODES or #r.CHARACTERS,7,input.move_y)
                if (field=="stage" or field=="mode") and previous~=r[field.."_cursor"] then
                    self.rules=r.mode_cursor;self.ready={}
                    self.revision=self.revision+1
                    self:send({kind="lobby",lobby=self.lobby,revision=self.revision,stage=r.stage_cursor,rules=r.mode_cursor})
                end
            end
        end
        self.menu_x=input.move_x or 0
        if input.confirm then
            self.ready[self.id]=not self.ready[self.id]
            self.characters[self.id]=r.character_cursor
            if r.mode_cursor==1 then
                self.loadouts[self.id]=require("tnr.character.runtime.character_runtime_bridge").new(r:get_equipment_session(),self.id):build_descriptor()
            end
            self:send({kind="ready",lobby=self.lobby,revision=self.revision,ready=self.ready[self.id],character=r.character_cursor,loadout=self.loadouts[self.id]})
        end
        r.message=(self.ready[self.id] and "已准备，等待队友；Enter 取消准备" or "选择自机后 Enter 准备").." · 团队生命 / 共享 Bomb"
        r.network_status={}
        for id=1,2 do
            local c=r.CHARACTERS[self.characters[id] or (id==self.id and r.character_cursor or 0)]
            r.network_status[id]=string.format("P%d %s：%s",id,c and c.name or "等待选择",
                self.ready[id] and "已准备" or "未准备")
        end
        if self.host and self.ready[1] and self.ready[2] then self:begin() end
    elseif self.phase=="playing" then
        if input.cancel then self:send({kind="back"});if self.host then self:return_to_select() end
        else if self:step(input) then
            self.silence=0
            self.last_progress=self.transport.now and self.transport:now() or os.clock()
        end end
    elseif self.phase=="reward" then
        local r=self.app.replay
        if r.reward_player_id==self.id and not self.reward_pending then
            if self.app.preparation_overlay then
                self.app:_update_ui_mouse()
                self.app.ui_mouse_down=input.mouse_primary_down==true
                self.app:_update_replay_loadout(input)
                return true
            elseif input.tab then
                self.app:open_preparation_overlay()
                return true
            end
            r.reward_cursor=self.app:_scroll_step("replay_reward",r.reward_cursor,#r.reward_choices,3,input.move_y)
            if input.confirm then
                if self.host then self:reward_pick(r.reward_cursor)
                elseif r:can_claim_reward() then
                    self.reward_pending=self:send({kind="reward_pick",round=r.reward_round,index=r.reward_cursor})
                    if self.reward_pending then r.reward_message="正在确认领取" end
                end
            end
        end
    elseif self.phase=="result" or self.phase=="error" then
        if input.confirm or input.cancel then
            if self.phase=="result" and input.confirm then
                if self.host then self:advance_result() else self:send({kind="advance_result"}) end
            elseif self.host then self:return_to_select()
            else self:send({kind="back"}) end
        end
    end
    if self.pending_result and self.app.replay.runtime and self.app.replay.runtime.frames>=self.pending_result.tick then
        self.app.replay:finish_stage(self.pending_result.outcome)
        self.app.session.run_state=C.REPLAY_RESULT;self.phase="result";self.pending_result=nil
        local queued=self.pending_rewards;self.pending_rewards={}
        for _,message in ipairs(queued) do self:receive(message) end
    end
    local now=self.transport.now and self.transport:now() or os.clock()
    if (self.phase=="playing" or self.phase=="loading" or self.phase=="await_result")
            and self.last_progress and now-self.last_progress>10 then
        self:fail("等待队友超时，请检查网络后重新连接")
    end
    self.transport:update()
    return true
end
return N
