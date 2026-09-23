-- Perfect-clear tracking.
--
-- A player "perfectly clears" a spell card when, during that card, they used
-- no bomb and never entered a respawn (no miss). Each player is judged
-- independently, so in co-op one player can perfect a card while the other
-- does not.
--
-- The tracker snapshots each player's cumulative bomb/life-lost counters at
-- card start and compares them at card end. The adapter feeds it the per-player
-- totals it already maintains.

local PerfectTracker = {}

PerfectTracker.__index = PerfectTracker

function PerfectTracker.new()
    return setmetatable({
        -- Per-player cumulative counters at the last snapshot.
        snapshot = {},
        -- Number of spell cards each player has perfectly cleared.
        perfect_cards = {},
        -- Number of spell cards seen this encounter.
        total_cards = 0,
        -- Card index currently being tracked (nil when not in a card).
        active_card = nil,
    }, PerfectTracker)
end

local function counter(values, player_id)
    if not values then return 0 end
    local entry = values[player_id]
    if type(entry) == "table" then
        return tonumber(entry.bombs or entry.bomb_used) or 0, tonumber(entry.deaths or entry.life_lost) or 0
    end
    return 0, 0
end

--- Begin tracking a new spell card. `totals` maps player_id to
--- { bombs = n, deaths = n } cumulative for the encounter.
function PerfectTracker:begin_card(card_index, totals, player_ids)
    self.active_card = card_index
    self.total_cards = self.total_cards + 1
    self.snapshot = {}
    for _, player_id in ipairs(player_ids or {}) do
        local bombs, deaths = counter(totals, player_id)
        self.snapshot[player_id] = { bombs = bombs, deaths = deaths }
    end
end

--- End the current card. `totals` is the updated cumulative map. Returns a map
--- player_id -> boolean (true when the card was perfect for that player).
function PerfectTracker:end_card(totals, player_ids)
    local result = {}
    if self.active_card == nil then return result end
    for _, player_id in ipairs(player_ids or {}) do
        local before = self.snapshot[player_id] or { bombs = 0, deaths = 0 }
        local bombs, deaths = counter(totals, player_id)
        local perfect = bombs <= before.bombs and deaths <= before.deaths
        result[player_id] = perfect
        if perfect then
            self.perfect_cards[player_id] = (self.perfect_cards[player_id] or 0) + 1
        end
    end
    self.active_card = nil
    return result
end

--- Perfect counts for the encounter, per player.
function PerfectTracker:get_counts()
    local result = {}
    for player_id, count in pairs(self.perfect_cards) do result[player_id] = count end
    return result
end

--- How many players perfectly cleared at least one card.
function PerfectTracker:perfect_player_count(player_ids)
    local count = 0
    for _, player_id in ipairs(player_ids or {}) do
        if (self.perfect_cards[player_id] or 0) >= 1 then count = count + 1 end
    end
    return count
end

--- How many players perfectly cleared every card this encounter.
function PerfectTracker:full_perfect_player_count(player_ids)
    if self.total_cards <= 0 then return 0 end
    local count = 0
    for _, player_id in ipairs(player_ids or {}) do
        local perfect = self.perfect_cards[player_id] or 0
        -- At least one card and every card counted as perfect.
        if perfect >= 1 and perfect >= self.total_cards then count = count + 1 end
    end
    return count
end

function PerfectTracker:reset()
    self.snapshot = {}
    self.perfect_cards = {}
    self.total_cards = 0
    self.active_card = nil
end

return PerfectTracker
