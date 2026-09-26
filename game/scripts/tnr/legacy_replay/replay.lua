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

local Replay = {}

Replay.__index = Replay

-- The reference stages, in order, with the display name shown on the select
-- screen. The key is the compiled namespace prefix.
Replay.STAGES = {
    { key = "st01", name = "第一关　妖怪的森林" },
    { key = "st02", name = "第二关　红色狂气的洋馆" },
    { key = "st03", name = "第三关　永远与须臾之都" },
    { key = "st04", name = "第四关　火星的沙尘暴" },
    { key = "st05", name = "第五关　逆袭的月之都" },
    { key = "st06", name = "第六关　纯狐的静谧" },
    { key = "st07", name = "第七关　月面的决战" },
}

-- The reference characters, mapped to their sht key and sheet.
Replay.CHARACTERS = {
    { key = "reimu", name = "博丽灵梦", sheet = "pl00" },
    { key = "marisa", name = "雾雨魔理沙", sheet = "pl01" },
    { key = "sanae", name = "东风谷早苗", sheet = "pl02" },
    { key = "reisen", name = "铃仙·优昙华院·因幡", sheet = "pl03" },
}

-- Selectable rulesets.
Replay.MODES = {
    { key = "modern", name = "现代模式", description = "每关后两次三选一奖励" },
    { key = "classic", name = "传统模式", description = "原作 P 点与分数残机规则" },
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
        -- Selection cursors.
        stage_cursor = 1,
        mode_cursor = 1,
        character_cursor = 1,
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

    -- Load the stage's textures and sprites. This is the slow step, so it runs
    -- once when the stage starts rather than every frame.
    StageRuntime.load_stage_assets(self.lstg, stage.key, self.anm,
        { texture_sizes = self.texture_sizes })

    -- Build the ruleset and the session that pairs it with the roster.
    local ruleset = mode.key == "classic"
        and Interfaces.classic_mode() or Interfaces.modern_mode()
    local roster = Interfaces.PlayerRoster.new({ player_ids = { 1 } })
    -- The live keyboard drives the ship through the existing input provider.
    if self.input_provider then
        roster:set_input(1, InputBridge.keyboard(self.input_provider, 1))
    else
        roster:set_input(1, InputBridge.scripted(function()
            return self.keyboard_input or {}
        end))
    end
    local session = Interfaces.ReplaySession.new({ roster = roster, mode = ruleset })

    self.runtime = StageRuntime.new({
        lstg = self.lstg,
        stage = stage.key,
        anm = self.anm,
        std = self.std,
        chunks = self.chunks,
        sht = self.sht,
        session = session,
        character = character.key,
        texture_sizes = StageRuntime.texture_sizes,
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
    self.runtime:start()
    self.active_stage = stage.key
    self.active_mode = mode.key
    self.active_character = character.key
    self.render_scale = self.render_scale or 1
    return true
end

function Replay:is_active()
    return self.runtime ~= nil
end

--- Advance one frame. Returns the run state: "playing", "cleared" or "failed".
function Replay:update()
    if not self.runtime then return "playing" end
    self.runtime:update()
    self:_sync_stats()
    -- The stage is clear once the timeline has run every section, which happens
    -- after the boss script returns.
    if self.runtime:timeline_finished() then
        return "cleared"
    end
    -- All players out of lives.
    local alive = false
    for _, player_id in ipairs(self.runtime.session.roster:list()) do
        if (self.runtime.session.lives[player_id] or 0) > 0 then alive = true break end
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
end

--- Push the runtime's state into the HUD rows.
function Replay:_sync_stats()
    local runtime = self.runtime
    local session = runtime.session
    local player_id = session.roster:list()[1]
    local player = runtime.players[player_id]
    local stats = runtime.stats or {}
    runtime.stats = stats
    stats.power = player and math.floor(player.power or 0) or 0
    stats.graze = player and math.floor(player.graze or 0) or 0
    stats.lives = session.lives[player_id] or stats.lives or 3
    -- Score counts the graze and the point items the player collected.
    stats.score = math.floor((stats.score or 0) + (player and 0 or 0))
end

--- Leave the replay and free the runtime.
function Replay:stop()
    self.runtime = nil
    self.active_stage = nil
end

return Replay
