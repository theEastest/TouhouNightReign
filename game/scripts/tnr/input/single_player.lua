local PlayerInput = require("tnr.input.player_input")

local SinglePlayerInputProvider = {}
SinglePlayerInputProvider.__index = SinglePlayerInputProvider

function SinglePlayerInputProvider.new(options)
    return setmetatable({ tick = 0, options = options or {}, pending = {} }, SinglePlayerInputProvider)
end

function SinglePlayerInputProvider:set_pending(values)
    self.pending = values or {}
end

function SinglePlayerInputProvider:poll(player_id)
    self.tick = self.tick + 1
    local values = self.pending
    self.pending = {}
    return PlayerInput.new(player_id, self.tick, values)
end

return SinglePlayerInputProvider

