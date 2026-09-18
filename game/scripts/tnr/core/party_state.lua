local PartyState = {}
PartyState.__index = PartyState

local Immutable = require("tnr.core.immutable")

function PartyState.new(player_ids, current_node_id, options)
    options = options or {}
    local ids = {}
    for index, player_id in ipairs(player_ids or {}) do
        ids[index] = player_id
    end
    return setmetatable({
        player_ids = ids,
        current_node_id = current_node_id,
        team_life = math.max(0, tonumber(options.team_life) or 3),
        life_fragments = math.max(0, tonumber(options.life_fragments) or 0),
    }, PartyState)
end

function PartyState:set_current_node(node_id)
    self.current_node_id = node_id
end

function PartyState:add_life_fragments(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    self.life_fragments = self.life_fragments + amount
    local gained = math.floor(self.life_fragments / 3)
    if gained > 0 then
        self.team_life = self.team_life + gained
        self.life_fragments = self.life_fragments % 3
    end
    return gained
end

function PartyState:add_team_life(amount)
    self.team_life = math.max(0, self.team_life + math.floor(tonumber(amount) or 0))
end

function PartyState:is_ready(players)
    for _, player_id in ipairs(self.player_ids) do
        local player = players and (players[player_id] or (players.get_player and players:get_player(player_id)))
        if not player or player.map_ready ~= true then
            return false
        end
    end
    return #self.player_ids > 0
end

function PartyState:to_table()
    return {
        player_ids = Immutable.copy(self.player_ids),
        current_node_id = self.current_node_id,
        team_life = self.team_life,
        life_fragments = self.life_fragments,
    }
end

function PartyState.from_table(data)
    assert(type(data) == "table", "party state data is required")
    return PartyState.new(data.player_ids, data.current_node_id, {
        team_life = data.team_life,
        life_fragments = data.life_fragments,
    })
end

return PartyState
