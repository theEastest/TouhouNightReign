-- Boundary between the formal TNR state model and the legacy lstg globals.
-- The adapter deliberately copies values; it never shares mutable tables with
-- the native object pool. This keeps native compatibility fields from becoming
-- a second source of truth.
local LegacyStateAdapter = {}
LegacyStateAdapter.__index = LegacyStateAdapter

local function number(value, default)
    value = tonumber(value)
    if value == nil then return default end
    return value
end

function LegacyStateAdapter.new(session)
    return setmetatable({ session = session, last_pull = {} }, LegacyStateAdapter)
end

function LegacyStateAdapter:player(player_id)
    return self.session and self.session.get_player and self.session:get_player(player_id) or nil
end

function LegacyStateAdapter:read_player(player_id, legacy)
    local player = self:player(player_id)
    local source = type(legacy) == "table" and legacy or {}
    return {
        player_id = tonumber(player_id),
        bomb = number(source.bomb, player and player.bomb or 0),
        score = number(source.score, player and player.score or 0),
        graze = number(source.graze, player and player.graze or 0),
        life = number(source.life, player and player.life or 0),
        alive = source.alive ~= false and (player == nil or player.alive ~= false),
        respawning = source.respawning == true or (player and player.respawning == true) or false,
        respawn_timer = number(source.respawn_timer, player and player.respawn_timer or 0),
    }
end

function LegacyStateAdapter:apply_player_delta(player_id, delta)
    local player = assert(self:player(player_id), "unknown player")
    delta = delta or {}
    if delta.score ~= nil then player.score = math.max(0, number(player.score, 0) + number(delta.score, 0)) end
    if delta.graze ~= nil then player.graze = math.max(0, number(player.graze, 0) + number(delta.graze, 0)) end
    if delta.bomb ~= nil then player.bomb = math.max(0, number(player.bomb, 0) + number(delta.bomb, 0)) end
    if delta.life ~= nil then player.life = math.max(0, number(player.life, 0) + number(delta.life, 0)) end
    if delta.alive ~= nil then player.alive = delta.alive == true end
    if delta.respawning ~= nil then player.respawning = delta.respawning == true end
    if delta.respawn_timer ~= nil then player.respawn_timer = math.max(0, number(delta.respawn_timer, 0)) end
    return player
end

function LegacyStateAdapter:apply_player_snapshot(player_id, snapshot)
    local player = assert(self:player(player_id), "unknown player")
    snapshot = snapshot or {}
    if snapshot.alive ~= nil then player.alive = snapshot.alive == true end
    if snapshot.respawning ~= nil then player.respawning = snapshot.respawning == true end
    if snapshot.respawn_timer ~= nil then player.respawn_timer = math.max(0, number(snapshot.respawn_timer, 0)) end
    return player
end

function LegacyStateAdapter:mirror_to_legacy(player_id, legacy, values)
    if type(legacy) ~= "table" then return false end
    values = values or self:read_player(player_id, legacy)
    -- Only compatibility fields are mirrored. Ownership remains in PlayerState.
    for _, key in ipairs({ "bomb", "score", "graze", "life" }) do
        if values[key] ~= nil then legacy[key] = values[key] end
    end
    return true
end

function LegacyStateAdapter:record_bomb_use(player_id)
    local player = assert(self:player(player_id), "unknown player")
    if player.bomb <= 0 then return false, "no bombs" end
    player.bomb = player.bomb - 1
    return true
end

function LegacyStateAdapter:team_life()
    return self.session and self.session.party and number(self.session.party.team_life, 0) or 0
end

function LegacyStateAdapter:set_team_life(value)
    if not (self.session and self.session.party) then return nil end
    self.session.party.team_life = math.max(0, number(value, self:team_life()))
    return self.session.party.team_life
end

function LegacyStateAdapter:consume_legacy_delta(player_id, delta)
    -- Native snapshots should provide deltas, not authoritative per-frame
    -- totals. Store the last observed report for diagnostics and apply once.
    delta = delta or {}
    self.last_pull[player_id] = {
        score = number(delta.score, 0),
        graze = number(delta.graze, 0),
        bomb = number(delta.bomb, 0),
        life = number(delta.life, 0),
    }
    return self:apply_player_delta(player_id, self.last_pull[player_id])
end

return LegacyStateAdapter
