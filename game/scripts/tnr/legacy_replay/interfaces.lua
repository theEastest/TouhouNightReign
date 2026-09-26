-- Shared interfaces for the legacy replay player modes.
--
-- The replay supports four combinations: a single player or two players (co-op)
-- crossed with the classic ruleset (power meter, score extends) or the modern
-- ruleset (current ships, two reward picks between stages). This module owns
-- the contracts those combinations are built from, so the gameplay code never
-- branches on the specific combination.
--
-- Three seams:
--   PlayerRoster  -- who is playing, their ids and their input sources.
--   PlayerMode    -- the ruleset: starting ship, drop and score behaviour,
--                    and what happens between stages.
--   ReplaySession -- the coordinator that pairs a roster with a mode and
--                    exposes the surface a room drives.
--
-- A new ruleset is one table implementing PlayerMode's methods; a new player
-- arrangement is one PlayerRoster. Nothing else changes.

local Interfaces = {}

-- ---------------------------------------------------------------------------
-- Player roster

local PlayerRoster = {}
PlayerRoster.__index = PlayerRoster

---@param options table { player_ids = {1, 2}, local_player_id = 1 }
function PlayerRoster.new(options)
    options = options or {}
    local ids = options.player_ids or { 1 }
    local roster = setmetatable({
        ids = {},
        local_player_id = tonumber(options.local_player_id) or 1,
        inputs = {},
    }, PlayerRoster)
    for _, id in ipairs(ids) do
        roster.ids[#roster.ids + 1] = tonumber(id) or 1
    end
    if #roster.ids == 0 then roster.ids[1] = 1 end
    return roster
end

--- Number of players in this run.
function PlayerRoster:count()
    return #self.ids
end

--- True when this is a co-operative run.
function PlayerRoster:is_coop()
    return #self.ids > 1
end

--- Every player id, in seating order.
function PlayerRoster:list()
    return self.ids
end

--- Attach an input source to a player. The replay reads movement and the shot,
-- bomb and focus buttons through this, so a keyboard, a network packet and a
-- scripted test all look the same.
function PlayerRoster:set_input(player_id, source)
    self.inputs[player_id] = source
end

function PlayerRoster:input_for(player_id)
    return self.inputs[player_id]
end

--- The input state for this frame, normalised to the shared shape.
function PlayerRoster:sample(player_id)
    local source = self.inputs[player_id]
    if not source then
        return { move_x = 0, move_y = 0, shoot = false, focus = false, bomb = false }
    end
    local value = source.sample and source.sample() or source
    return {
        move_x = tonumber(value.move_x) or 0,
        move_y = tonumber(value.move_y) or 0,
        shoot = value.shoot == true,
        focus = value.focus == true,
        bomb = value.bomb == true,
    }
end

Interfaces.PlayerRoster = PlayerRoster

-- ---------------------------------------------------------------------------
-- Player mode

--- The methods a ruleset provides.
-- Implementations only override what differs from the modern default; the
-- defaults below describe the modern ruleset.
local PlayerMode = {}
PlayerMode.__index = PlayerMode

PlayerMode.id = "modern"

--- Starting number of lives and bombs for a player.
function PlayerMode:starting_resources()
    return { lives = 3, bombs = 3, power = 0 }
end

--- Called once when the run starts. A mode can place its own ship class and
-- register the stat block the HUD reads.
function PlayerMode:on_run_start(session)
end

--- Called when a player's shot connects, before damage is applied. A classic
-- mode uses this to award power; the modern mode leaves drops to the item
-- system.
function PlayerMode:on_hit(session, player_id, enemy, damage)
end

--- Called when an enemy dies. Returns an optional drop override so a ruleset
-- can replace the default item table.
function PlayerMode:on_enemy_defeated(session, player_id, enemy)
    return nil
end

--- Called when a player is hit.
function PlayerMode:on_player_hit(session, player_id)
end

--- Called when a player collects an item.
function PlayerMode:on_item_collected(session, player_id, item)
end

--- Score threshold behaviour. The classic ruleset grants an extend every N
-- points; the modern one does not.
function PlayerMode:score_extend_threshold()
    return nil
end

--- How many reward choices a player makes after finishing a stage.
-- The modern ruleset offers two rounds of three; the classic one offers none.
function PlayerMode:rewards_per_stage()
    return 2
end

--- Number of options in each reward round.
function PlayerMode:reward_choice_count()
    return 3
end

--- Called between stages so a mode can apply its own progression.
function PlayerMode:on_stage_clear(session, stage_key)
end

Interfaces.PlayerMode = PlayerMode

--- Build a mode from a definition table, filling in the defaults.
function Interfaces.mode(definition)
    local mode = {}
    for key, value in pairs(definition or {}) do mode[key] = value end
    return setmetatable(mode, { __index = PlayerMode })
end

-- ---------------------------------------------------------------------------
-- Classic ruleset
--
-- Reference behaviour: power rises with collection, a score threshold grants an
-- extra life, and there are no between-stage reward picks.

local CLASSIC_POWER_PER_LARGE = 1.0
local CLASSIC_POWER_PER_SMALL = 0.05
local CLASSIC_EXTEND_SCORE = 10000000

Interfaces.classic_mode = function()
    return Interfaces.mode({
        id = "classic",
        power_per_large = CLASSIC_POWER_PER_LARGE,
        power_per_small = CLASSIC_POWER_PER_SMALL,
        extend_score = CLASSIC_EXTEND_SCORE,
        next_extend = CLASSIC_EXTEND_SCORE,
        starting_resources = function()
            return { lives = 2, bombs = 3, power = 0 }
        end,
        rewards_per_stage = function() return 0 end,
        score_extend_threshold = function(self) return self.extend_score end,
        on_item_collected = function(self, session, player_id, item)
            -- Power items raise the classic power meter.
            if item and item.kind == "power_large" then
                session:add_power(player_id, self.power_per_large)
            elseif item and item.kind == "power" then
                session:add_power(player_id, self.power_per_small)
            end
        end,
        on_score_changed = function(self, session, player_id, score)
            -- Grant an extra life each time the threshold is crossed.
            if not self.extend_score then return end
            -- A session without player state (a bare harness) has nothing to
            -- grant to, so skip instead of erroring.
            if not session.players or not session.get_player then return end
            if not session:get_player(player_id) then return end
            while score >= self.next_extend do
                session:add_life(player_id, 1, "score_extend")
                self.next_extend = self.next_extend + self.extend_score
            end
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Modern ruleset
--
-- The project's current ships, score handled by the reward and money systems,
-- and two rounds of three reward picks between stages.

Interfaces.modern_mode = function()
    return Interfaces.mode({
        id = "modern",
        starting_resources = function()
            return { lives = 3, bombs = 3, power = 0 }
        end,
        rewards_per_stage = function() return 2 end,
        reward_choice_count = function() return 3 end,
    })
end

-- ---------------------------------------------------------------------------
-- Replay session
--
-- Pairs a roster with a mode. Rooms only talk to this object.

local ReplaySession = {}
ReplaySession.__index = ReplaySession

---@param options table { roster, mode, stage, on_reward }
function ReplaySession.new(options)
    options = options or {}
    local mode = options.mode or Interfaces.modern_mode()
    local roster = options.roster or PlayerRoster.new({ player_ids = { 1 } })
    local session = setmetatable({
        roster = roster,
        mode = mode,
        stage = options.stage,
        on_reward = options.on_reward,
        power = {},
        stage_index = 0,
        pending_rewards = {},
        -- Team lives and bombs, seeded from the ruleset. The replay reduces these
        -- directly because it runs outside the roguelike's player profiles.
        lives_left = {},
        bombs_left = {},
        score = 0,
    }, ReplaySession)
    local resources = mode:starting_resources()
    for _, player_id in ipairs(roster:list()) do
        session.lives_left[player_id] = resources.lives or 3
        session.bombs_left[player_id] = resources.bombs or 3
        session.power[player_id] = resources.power or 0
    end
    return session
end

function ReplaySession:life_count(player_id)
    return self.lives_left[player_id] or 0
end

--- Reduce a player's lives. Returns false when they have none left.
function ReplaySession:lose_life(player_id)
    local current = self.lives_left[player_id] or 0
    if current <= 0 then return false end
    self.lives_left[player_id] = current - 1
    return true
end

function ReplaySession:add_power(player_id, amount)
    self.power[player_id] = (self.power[player_id] or 0) + (tonumber(amount) or 0)
end

function ReplaySession:get_power(player_id)
    return self.power[player_id] or 0
end

function ReplaySession:is_coop()
    return self.roster:is_coop()
end

function ReplaySession:mode_id()
    return self.mode.id
end

--- Resolve a reward pick request into the number of rounds to run.
function ReplaySession:reward_rounds()
    local rounds = self.mode:rewards_per_stage()
    if self:is_coop() then
        -- In co-op each player picks in turn, so the round count doubles.
        rounds = rounds * self.roster:count()
    end
    return rounds or 0
end

function ReplaySession:choice_count()
    return self.mode:reward_choice_count() or 3
end

function ReplaySession:add_power(player_id, amount)
    self.power[player_id] = (self.power[player_id] or 0) + (tonumber(amount) or 0)
end

--- Called at a stage boundary. The mode decides whether rewards follow.
function ReplaySession:finish_stage(stage_key)
    self.stage_index = self.stage_index + 1
    self.mode:on_stage_clear(self, stage_key)
    local rounds = self:reward_rounds()
    self.pending_rewards = {}
    for index = 1, rounds do
        self.pending_rewards[index] = {
            -- Round-robin between players in co-op.
            player_id = self.roster:list()[((index - 1) % self.roster:count()) + 1],
            choices = self:choice_count(),
        }
    end
    return self.pending_rewards
end

Interfaces.ReplaySession = ReplaySession

return Interfaces
