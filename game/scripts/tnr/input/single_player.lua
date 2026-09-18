local PlayerInput = require("tnr.input.player_input")

local SinglePlayerInputProvider = {}
SinglePlayerInputProvider.__index = SinglePlayerInputProvider

function SinglePlayerInputProvider.new(options)
    return setmetatable({ tick = 0, options = options or {}, pending = {}, pending_by_player = {} }, SinglePlayerInputProvider)
end

function SinglePlayerInputProvider:set_pending(values, player_id)
    if player_id then
        self.pending_by_player[player_id] = values or {}
    else
        self.pending = values or {}
    end
end

function SinglePlayerInputProvider:poll(player_id)
    self.tick = self.tick + 1
    local values = self.pending_by_player[player_id] or self.pending
    self.pending_by_player[player_id] = nil
    self.pending = {}
    return PlayerInput.new(player_id, self.tick, values)
end

function SinglePlayerInputProvider:poll_all(player_ids)
    self.tick = self.tick + 1
    local result = {}
    for _, player_id in ipairs(player_ids or { 1 }) do
        local values = self.pending_by_player[player_id] or self.pending
        result[player_id] = PlayerInput.new(player_id, self.tick, values)
        self.pending_by_player[player_id] = nil
    end
    self.pending = {}
    return result
end

return SinglePlayerInputProvider
