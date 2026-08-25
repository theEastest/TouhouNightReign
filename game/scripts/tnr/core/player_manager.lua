local PlayerState = require("tnr.core.player_state")

local PlayerManager = {}
PlayerManager.__index = PlayerManager

function PlayerManager.new()
    return setmetatable({ players = {}, order = {} }, PlayerManager)
end

function PlayerManager:add_player(player_id, options)
    if self.players[player_id] then
        return self.players[player_id]
    end
    local player = PlayerState.new(player_id, options)
    self.players[player_id] = player
    self.order[#self.order + 1] = player_id
    table.sort(self.order)
    return player
end

function PlayerManager:remove_player(player_id)
    if not self.players[player_id] then
        return false
    end
    self.players[player_id] = nil
    for index, id in ipairs(self.order) do
        if id == player_id then
            table.remove(self.order, index)
            break
        end
    end
    return true
end

function PlayerManager:get_player(player_id)
    return self.players[player_id]
end

function PlayerManager:get_players()
    local result = {}
    for _, player_id in ipairs(self.order) do
        result[#result + 1] = self.players[player_id]
    end
    return result
end

return PlayerManager

