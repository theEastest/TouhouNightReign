local LANTransport = {}
LANTransport.__index = LANTransport

function LANTransport.new(options)
    return setmetatable({ options = options or {}, connected = false }, LANTransport)
end

function LANTransport:send(_command)
    return nil, "LAN transport is not implemented in the first prototype"
end

function LANTransport:broadcast(_event)
    return nil, "LAN transport is not implemented in the first prototype"
end

function LANTransport:poll()
    return nil
end

function LANTransport:update()
end

return LANTransport

