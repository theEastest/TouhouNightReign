local LocalTransport = {}
LocalTransport.__index = LocalTransport

function LocalTransport.new(session)
    return setmetatable({ session = session, commands = {}, inputs = {} }, LocalTransport)
end

function LocalTransport:send(command)
    self.commands[#self.commands + 1] = command
end

function LocalTransport:submit_input(player_input)
    self.inputs[#self.inputs + 1] = player_input
end

function LocalTransport:broadcast(event)
    return event
end

function LocalTransport:poll()
    local command = table.remove(self.commands, 1)
    if command then
        return command
    end
    return table.remove(self.inputs, 1)
end

function LocalTransport:update()
    while #self.commands > 0 do
        local command = table.remove(self.commands, 1)
        self.session:dispatch(command)
    end
    -- Input is intentionally retained as an abstraction seam. Battle adapters consume it.
end

return LocalTransport

