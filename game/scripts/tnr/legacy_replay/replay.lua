-- Legacy replay mode controller.
--
-- Wires the verified replay subsystems into the game: it owns the stage list,
-- the mode and player selection, and drives the stage runtime each frame. The
-- rest of the game only sees a run state and a render call.
--
-- This is the minimum playable path: single player, the modern ruleset, stage
-- select and a stage that runs until it finishes or the player gives up. The
-- classic ruleset and co-op share the same seams (interfaces.lua) and only need
-- the selection screens extended.

local StageRuntime = require("tnr.legacy_replay.stage_runtime")
local Interfaces = require("tnr.legacy_replay.interfaces")
local InputBridge = require("tnr.legacy_replay.input_bridge")
local Player = require("tnr.legacy_replay.player")
local DynamicEnemyHp = require("tnr.legacy_replay.dynamic_enemy_hp")

local Replay = {}

Replay.__index = Replay

-- The reference stages, in order, with the display name shown on the select
-- screen. The key is the compiled namespace prefix.
Replay.STAGES = {
    { key = "st01", name = "第一面" },
    { key = "st02", name = "第二面" },
    { key = "st03", name = "第三面" },
    { key = "st04", name = "第四面" },
    { key = "st05", name = "第五面" },
    { key = "st06", name = "第六面" },
}

-- The reference characters, mapped to their sht key and sheet.
Replay.CHARACTERS = {
    { key = "reimu", name = "博丽灵梦", sheet = "pl00" },
    { key = "marisa", name = "雾雨魔理沙", sheet = "pl01" },
    { key = "sanae", name = "东风谷早苗", sheet = "pl02" },
    { key = "reisen", name = "铃仙·优昙华院·因幡", sheet = "pl03" },
}

-- How many players a run can have. Co-op uses the project's existing two
-- player ids.
Replay.PLAYER_COUNTS = {
    { key = 1, name = "单人游戏" },
    { key = 2, name = "双人游戏" },
}

-- Training cards accompany equipment from the normal single-player pool.
Replay.REWARDS = {
    { key = "power", name = "火力锻体", description = "所有装备攻击力 +10%（加算）" },
    { key = "life", name = "残机增加", description = "残机 +1", team = function(session, id) session:add_life(id,1) end },
    { key = "bomb", name = "炸弹增加", description = "炸弹 +1", team = function(session, id) session:add_bomb(id,1) end },
    { key = "graze", name = "擦弹强化", description = "擦弹范围 +2", apply = function(player) player.grazebox = (player.grazebox or 6) + 2 end },
    { key = "score", name = "得点加成", description = "得分 +100 万", apply = function() end, score = 1000000 },
    { key = "speed", name = "机动力提升", description = "移速 +0.5", apply = function(player) player.definition = player.definition or {}; player.definition.move_unfocused = (player.definition.move_unfocused or 4.5) + 0.5 end },
}

-- Selectable rulesets.
Replay.MODES = {
    { key = "modern", name = "现代模式", description = "每关两次三选一：锻体 / 装备" },
    { key = "classic", name = "经典模式", description = "P 点火力；章节得分奖励残机碎片" },
}

---@param options table { lstg, chunks, anm, std, sht, session, audio }
function Replay.new(options)
    return setmetatable({
        lstg = options.lstg,
        chunks = options.chunks,
        anm = options.anm,
        std = options.std,
        sht = options.sht,
        session = options.session,
        audio = options.audio,
        -- The live input provider. Without it the roster falls back to the
        -- scripted stub and the ship cannot be steered at all.
        input_provider = options.input_provider,
        -- Selection cursors.
        stage_cursor = 1,
        mode_cursor = 1,
        character_cursor = 1,
        player_count_cursor = 1,
        -- Active run.
        runtime = nil,
        active_stage = nil,
        active_mode = nil,
        active_character = nil,
        message = nil,
        loaded = false,
    }, Replay)
end

--- Load the shared data tables once, on first entry.
function Replay:ensure_data()
    if self.loaded then return true end
    local ok, chunks = pcall(require, "tnr.legacy_replay.data.th15_all")
    local ok2, anm = pcall(require, "tnr.legacy_replay.data.th15_anm")
    local ok3, std = pcall(require, "tnr.legacy_replay.data.th15_std")
    local ok4, sht = pcall(require, "tnr.legacy_replay.data.th15_sht")
    if not (ok and ok2 and ok3 and ok4) then
        self.message = "重演数据缺失"
        return false
    end
    self.chunks, self.anm, self.std, self.sht = chunks, anm, std, sht
    self.loaded = true
    return true
end

--- The list of stages for the select screen.
function Replay:stage_list()
    return Replay.STAGES
end

function Replay:selected_stage()
    return Replay.STAGES[self.stage_cursor] or Replay.STAGES[1]
end

function Replay:selected_mode()
    return Replay.MODES[self.mode_cursor] or Replay.MODES[1]
end

function Replay:selected_character()
    return Replay.CHARACTERS[self.character_cursor] or Replay.CHARACTERS[1]
end

function Replay:selected_player_count()
    return Replay.PLAYER_COUNTS[self.player_count_cursor] or Replay.PLAYER_COUNTS[1]
end

-- A replay owns its equipment run: rewards must neither disappear when a
-- stage runtime is freed nor modify an unrelated single-player map save.
function Replay:get_equipment_session()
    local signature=(self.network_lobby and "network" or self:selected_character().key)..":"..self:selected_player_count().key
    if self.equipment_signature and self.equipment_signature~=signature then self:reset_progress() end
    if not self.equipment_session then
        local GameSession=require("tnr.core.game_session")
        local character=self:selected_character().key
        local local_id=self.session and self.session.local_player_id or 1
        self.equipment_session=GameSession.new({
            run_seed=self.equipment_seed,
            player_count=self:selected_player_count().key,
            local_player_id=self.network_lobby and local_id or 1,
            character_id=self.network_lobby and "reimu" or character,
            character_by_player=self.network_lobby and {[local_id]=character} or nil,
        })
        self.equipment_session:start_new()
        self.training_bonuses={}
        self.equipment_signature=signature
    end
    return self.equipment_session
end

function Replay:reset_progress()
    self.progress_key=nil;self.saved_team=nil
    self.equipment_session=nil
    self.training_bonuses=nil
    self.saved_resources=nil
    self.saved_score=nil
    self.saved_money=nil
    self.equipment_signature=nil
    self.dynamic_hp_baseline_dps=nil
end

function Replay:apply_training(player_id,player)
    local bonus=(self.training_bonuses or {})[player_id] or {}
    player.training_damage_bonus=bonus.power or 0
    player.grazebox=player.grazebox+(bonus.graze or 0)
    local speed=bonus.speed or 0
    player.definition.move_unfocused=(player.definition.move_unfocused or 4.5)+speed
    player.definition.move_unfocused_diagonal=(player.definition.move_unfocused_diagonal or 4.5/math.sqrt(2))+speed/math.sqrt(2)
end

--- Move a selection cursor with wraparound.
function Replay:move_cursor(name, delta, count)
    if delta == 0 then return end
    local current = self[name .. "_cursor"] or 1
    local next_index = ((current - 1 + delta) % count) + 1
    self[name .. "_cursor"] = next_index
end

-- ---------------------------------------------------------------------------
-- Starting and running a stage

--- Start the selected stage with the selected mode and character.
function Replay:start_stage()
    if not self:ensure_data() then return false end
    local stage = self:selected_stage()
    local mode = self:selected_mode()
    local character = self:selected_character()
    local progress_key=mode.key..":"..self:selected_player_count().key..":"..
        (self.network_config and table.concat(self.network_config.characters,",") or character.key)
    if self.progress_key~=progress_key then
        self.saved_resources=nil;self.saved_score=nil;self.saved_money=nil;self.saved_team=nil
        self.progress_key=progress_key
    end
    self.last_result=nil

    local equipment_session = mode.key == "modern" and self:get_equipment_session() or nil
    local hp_measurement = equipment_session and DynamicEnemyHp.measure(equipment_session,
        self.network_config and self.network_config.loadouts,
        self.network_config and self.network_config.characters) or nil
    if hp_measurement and self.dynamic_hp_baseline_dps == nil then
        -- The loadout at the beginning of the run is the 0.5x reference point.
        self.dynamic_hp_baseline_dps = hp_measurement.total_dps
    end
    local enemy_hp_multiplier = hp_measurement
        and DynamicEnemyHp.multiplier(hp_measurement, self.dynamic_hp_baseline_dps) or 0.5

    -- Load the stage's textures and sprites. This is the slow step, so it runs
    -- once when the stage starts rather than every frame.
    StageRuntime.load_stage_assets(self.lstg, stage.key, self.anm,
        { texture_sizes = self.texture_sizes })

    -- Build the ruleset and the session that pairs it with the roster. In
    -- co-op both players share the stage, which the existing team life and
    -- revive logic covers.
    local ruleset = mode.key == "classic"
        and Interfaces.classic_mode() or Interfaces.modern_mode()
    local player_count = self:selected_player_count().key
    local player_ids = player_count > 1 and { 1, 2 } or { 1 }
    local roster = Interfaces.PlayerRoster.new({ player_ids = player_ids })
    for _, player_id in ipairs(player_ids) do
        if self.input_provider then
            local keyboard = InputBridge.keyboard(self.input_provider, player_id)
            roster:set_input(player_id, InputBridge.scripted(function()
                if self.frame_inputs then return self.frame_inputs[player_id] or {} end
                return keyboard:sample()
            end))
        else
            roster:set_input(player_id, InputBridge.scripted(function()
                return self.keyboard_input or {}
            end))
        end
    end
    local session = Interfaces.ReplaySession.new({ roster = roster, mode = ruleset })
    self.runtime = StageRuntime.new({
        seed = self.network_config and self.network_config.seed or math.random(0,0xffff),
        lstg = self.lstg,
        stage = stage.key,
        anm = self.anm,
        std = self.std,
        chunks = self.chunks,
        sht = self.sht,
        session = session,
        equipment_session = equipment_session,
        enemy_hp_multiplier = enemy_hp_multiplier,
        character = self.network_config and self.network_config.characters[1] or character.key,
        texture_sizes = StageRuntime.texture_sizes,
        audio = self.audio,
        networked = self.network_config~=nil,
        local_player_id = self.network_config and self.network_config.local_player_id or 1,
        characters = self.network_config and self.network_config.characters,
        loadouts = self.network_config and self.network_config.loadouts,
    })
    -- Seed the HUD from the session so the readout is consistent from frame one.
    self.runtime.stats = {
        hiscore = 1000000,
        score = 0,
        lives = 3,
        spellcards = 0,
        power = 0,
        max_point = 0,
        graze = 0,
    }
    do
        for id,player in pairs(self.runtime.players) do
            if mode.key=="modern" then self:apply_training(id,player) end
            local saved=self.saved_resources and self.saved_resources[id]
            if saved then
                session.lives_left[id],session.bombs_left[id]=saved.life,saved.bomb
                session.power[id]=saved.power or session.power[id]
                player.power=session:get_power(id)*100
                player.score=saved.score or 0;player.point_rate=saved.point_rate or 10000
                player.graze=saved.graze or 0
                player.life_piece=saved.life_piece or 0;player.bomb_piece=saved.bomb_piece or 0
                if not session:is_coop() then self.runtime.point_rate=player.point_rate end
            end
        end
        if session.party and self.saved_team then
            session.party.team_life=self.saved_team.life
            session.team_bombs=self.saved_team.bombs
            session.party.life_fragments=self.saved_team.life_fragments
            session.bomb_fragments=self.saved_team.bomb_fragments
        end
        self.runtime.stats.score=self.saved_score or 0
        session.money=self.saved_money or 0
    end
    self.runtime:start()
    -- The stage's own track. The reference plays one recording per stage, so a
    -- replay should not run over the menu music.
    if self.audio and self.audio.play_replay_bgm then
        pcall(function() self.audio:play_replay_bgm(stage.key) end)
    end
    self.active_stage = stage.key
    self.active_mode = mode.key
    self.active_character = character.key
    self.render_scale = self.render_scale or 1
    -- Between-stage rewards are pending once the stage clears.
    self.reward_round = 0
    self.reward_cursor = 1
    self.reward_choices = nil
    return true
end

--- Build the choices for the next reward round, or nil when there are none.
-- The modern ruleset offers two rounds of three picks after each stage; the
-- classic ruleset offers none.
function Replay:next_reward_round()
    if not self.last_result or self.last_result.outcome ~= "cleared" then return nil end
    local rounds = self.runtime and self.runtime.session:reward_rounds() or 0
    -- A replay that has not started a stage yet has no reward counter, so treat
    -- it as zero instead of comparing against nil.
    local claimed = self.reward_round or 0
    if claimed >= rounds then return nil end
    self.reward_round = claimed + 1
    self.reward_cursor = 1
    self.reward_message=nil
    local roster=self.runtime.session.roster
    local ids=roster and roster:list() or {1}
    self.reward_player_id=ids[((self.reward_round-1)%#ids)+1]
    -- Pick three distinct rewards, seeded by the stage and round so the same
    -- run offers the same choices.
    local pool = {}
    for index, reward in ipairs(Replay.REWARDS) do pool[index] = reward end
    local choices = {}
    local seed = (self.runtime and self.runtime.frames or 0) + self.reward_round * 7
    for pick = 1, 3 do
        local index = ((seed * 31 + pick * 17) % #pool) + 1
        choices[#choices + 1] = table.remove(pool, index)
    end
    if self.active_mode=="modern" then
        local equipment=self:get_equipment_session()
        local generated=equipment.reward_service:generate_choices({
            encounter_id=tostring(self.active_stage)..":"..self.reward_round..":"..tostring(self.runtime.frames),
            encounter_type="ENEMY",
        },equipment.run_seed)
        -- Keep one training card; rotate through all existing reward categories.
        local info=require("tnr.ui.equipment_info")
        for slot=2,3 do
            local choice=generated[((self.reward_round+slot-3)%#generated)+1]
            if choice.kind=="EQUIPMENT" then
                local definition=equipment.equipment_registry:get(choice.definition_id)
                choice.name=info.display_name(definition,choice.definition_id)
                choice.description=info.category(definition).." · "..info.rarity(definition).." · 领取后进入仓库"
            else
                choice.name=choice.resource=="life" and "残机增加" or "Bomb 增加"
                choice.description="+"..tostring(choice.amount or 1)
            end
            choices[slot]=choice
        end
    end
    self.reward_choices = choices
    return choices
end

function Replay:can_claim_reward()
    local reward=(self.reward_choices or {})[self.reward_cursor or 1]
    if not reward or not self.runtime or self.active_mode=="classic" then return false end
    if reward.kind=="EQUIPMENT" then
        local player=self:get_equipment_session():get_player(self.reward_player_id or 1)
        if not player or player.loadout.inventory:is_full() then
            self.reward_message="仓库已满，请按 Tab 配装或清理后再领取"
            return false
        end
    end
    return true
end

--- Apply shared rewards on both peers and grant equipment on its owner's peer.
function Replay:claim_reward(local_player_id)
    local reward=(self.reward_choices or {})[self.reward_cursor or 1]
    local session=self.runtime and self.runtime.session
    if not reward or not session or self.active_mode=="classic" then return false end
    if reward.kind=="EQUIPMENT" then
        local owner=self.reward_player_id or 1
        if not local_player_id or local_player_id==owner then
            if not self:can_claim_reward() then return false end
            local service=self:get_equipment_session().equipment_reward_service
            local result=service:grant(reward.definition_id,owner,reward.random_affixes)
            if not result or not result.acquired then
                self.reward_message="装备领取失败，请检查仓库"
                return false
            end
        end
        self.reward_choices=nil
        return true
    end
    if session then
        for _, player_id in ipairs({self.reward_player_id or 1}) do
            if reward.kind=="RESOURCE" then
                if reward.resource=="life" then session:add_life(player_id,reward.amount or 1)
                else session:add_bomb(player_id,reward.amount or 1) end
            end
            if reward.team then reward.team(session, player_id) end
            local player = self.runtime.players[player_id]
            if player and reward.apply then reward.apply(player) end
            self.training_bonuses=self.training_bonuses or {}
            self.training_bonuses[player_id]=self.training_bonuses[player_id] or {}
            local bonus=self.training_bonuses[player_id]
            local amount=({power=.1,graze=2,speed=.5})[reward.key]
            if amount then bonus[reward.key]=(bonus[reward.key] or 0)+amount end
        end
        if reward.score then
            local stats = self.runtime.stats or {}
            self.runtime.stats = stats
            stats.score = (stats.score or 0) + reward.score
            session.score = stats.score
        end
    end
    self.reward_choices = nil
    return true
end

function Replay:is_active()
    return self.runtime ~= nil
end

--- Advance one frame. Returns the run state: "playing", "cleared" or "failed".
function Replay:update(inputs)
    if not self.runtime then return "playing" end
    self.frame_inputs = {}
    for id,value in pairs(inputs or {}) do
        local input={};for k,v in pairs(value) do input[k]=v end
        if value.bomb_down~=nil then input.bomb=value.bomb_down end
        self.frame_inputs[id]=input
    end
    local pilot=not self.network_config and os.getenv("TNR_REPLAY_PILOT")=="1"
    local batch=pilot and math.max(1,math.min(120,tonumber(os.getenv("TNR_REPLAY_BATCH")) or 1)) or 1
    for _=1,batch do
        if pilot then
            for _,id in ipairs(self.runtime.session.roster:list()) do
                self.frame_inputs[id]=require("tnr.debug.replay_pilot").sample(self.runtime,id)
            end
        end
        self.runtime:update()
        if self.runtime:timeline_finished() or self.runtime.session:life_count(1)<0 then break end
    end
    self:_sync_stats()
    -- The stage is clear once the timeline has run every section, which happens
    -- after the boss script returns.
    if self.runtime:timeline_finished() then
        return "cleared"
    end
    -- All players out of lives.
    -- The replay session tracks lives itself: it starts from the ruleset and is
    -- reduced on every hit. A run with no lives left is a failure.
    if self.runtime.session.team_defeated then return "failed" end
    local lives = self.runtime.session.lives_left or {}
    local alive = #self.runtime.session.roster:list() == 0
    for _, player_id in ipairs(self.runtime.session.roster:list()) do
        if (lives[player_id] or 0) >= 0 then alive = true break end
    end
    if not alive then return "failed" end
    return "playing"
end

--- Finish the current stage and record the result.
function Replay:finish_stage(outcome)
    if not self.runtime then return end
    self.last_result = {
        outcome = outcome or "cleared",
        stage = self.active_stage,
        character = self.active_character,
        mode = self.active_mode,
        score = self.runtime.stats and self.runtime.stats.score or 0,
        graze = self.runtime.stats and self.runtime.stats.graze or 0,
        frames = self.runtime.frames,
        -- The modern ruleset offers reward picks between stages.
        rewards = outcome == "cleared"
            and self.runtime.session:finish_stage(self.active_stage) or {},
    }
    local path=os.getenv("TNR_REPLAY_AUDIT_OUTPUT")
    if os.getenv("TNR_REPLAY_PILOT")=="1" and path then
        local f=assert(io.open(path,"w"))
        f:write(string.format("%s\t%s\t%d\t%d\t%d\n",outcome,self.active_mode,self.runtime.frames,
            self.runtime.session:life_count(1),self.runtime.session.bombs_left[1]))
        for _,entry in ipairs(self.runtime.adapter:missing_report()) do f:write("unhandled\t"..entry[1].."\n") end
        f:close()
    end
end

--- Push the runtime's state into the HUD rows.
function Replay:_sync_stats()
    local runtime = self.runtime
    local session = runtime.session
    local player_id = runtime.local_player_id or session.roster:list()[1]
    local player = runtime.players[player_id]
    local stats = runtime.stats or {}
    runtime.stats = stats
    stats.power = player and (player.power or 0) / 100 or 0
    stats.graze = player and math.floor(player.graze or 0) or 0
    stats.chapter_graze = player and (player.chapter_graze or 0) or 0
    stats.lives = session:life_count(player_id)
    stats.spellcards = session:bomb_count(player_id)
    stats.life_pieces = session.party and session.party.life_fragments or player and player.life_piece or 0
    stats.bomb_pieces = session.party and (session.bomb_fragments or 0) or player and player.bomb_piece or 0
    stats.max_point = session:is_coop() and (player.point_rate or 10000) or runtime.point_rate or 10000
    -- Score counts the graze and the point items the player collected.
    stats.score = math.floor(session:is_coop() and (player.score or 0) or stats.score or 0)
end

--- Leave the replay and free the runtime.
function Replay:stop()
    if self.runtime and self.runtime.modern then self.runtime.modern:save_progress() end
    if self.runtime and self.last_result
            and self.last_result.outcome=="cleared" then
        self.saved_resources={}
        for _,id in ipairs(self.runtime.session.roster:list()) do
            local p=self.runtime.players[id]
            self.saved_resources[id]={life=self.runtime.session:life_count(id),bomb=self.runtime.session:bomb_count(id),
                power=self.runtime.session:get_power(id),score=p.score,point_rate=p.point_rate,
                graze=p.graze,life_piece=p.life_piece,bomb_piece=p.bomb_piece}
        end
        local s=self.runtime.session
        if s.party then self.saved_team={life=s.party.team_life,bombs=s.team_bombs,
            life_fragments=s.party.life_fragments,bomb_fragments=s.bomb_fragments} end
        self.saved_score=self.runtime.stats.score
        self.saved_money=self.runtime.session.money or 0
    end
    self.runtime = nil
    self.active_stage = nil
end

return Replay
