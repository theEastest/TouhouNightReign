local FakeTransport = {}
FakeTransport.__index = FakeTransport

local REMOTE_INPUT_EDGES = {
    "bomb", "confirm", "cancel", "mouse_primary_pressed",
}

local function merge_remote_input(previous, incoming)
    if not previous then return incoming end
    local previous_tick = tonumber(previous.tick) or 0
    local incoming_tick = tonumber(incoming.tick) or 0
    if incoming_tick < previous_tick then return previous end
    local merged = {}
    for key, value in pairs(incoming) do
        merged[key] = value
    end
    for _, key in ipairs(REMOTE_INPUT_EDGES) do
        if previous[key] == true then
            merged[key] = true
            if key == "bomb" and merged.bomb_tick == nil then
                merged.bomb_tick = previous.bomb_tick or previous.tick
                merged.bomb_charged = previous.bomb_charged == true
                merged.bomb_success = previous.bomb_success == true
            end
        end
    end
    if incoming.bomb == true then
        merged.bomb_tick = incoming.bomb_tick or incoming.tick
    end
    return merged
end

local Bus = {}
Bus.__index = Bus

function Bus.new()
    return setmetatable({ endpoints = {}, sequence = 0 }, Bus)
end

function Bus:register(endpoint)
    self.endpoints[endpoint.endpoint_id] = endpoint
end

function Bus:deliver(sender, recipient_id, message)
    local recipient = self.endpoints[recipient_id]
    if not recipient or not recipient.connected then
        return false
    end
    self.sequence = self.sequence + 1
    message.sequence = self.sequence
    message.sender_id = sender.endpoint_id
    recipient.inbox[#recipient.inbox + 1] = message
    return true
end

function Bus:broadcast(sender, message)
    for endpoint_id, recipient in pairs(self.endpoints) do
        if endpoint_id ~= sender.endpoint_id and recipient.connected then
            self:deliver(sender, endpoint_id, {
                kind = message.kind,
                payload = message.payload,
                tick = message.tick,
            })
        end
    end
end

function FakeTransport.new(bus, options)
    options = options or {}
    local endpoint = setmetatable({
        bus = assert(bus, "fake transport bus is required"),
        role = options.role or "client",
        player_id = options.player_id or 1,
        endpoint_id = options.endpoint_id or ((options.role or "client") .. ":" .. tostring(options.player_id or 1)),
        peer_id = options.peer_id,
        connected = true,
        inbox = {},
        local_inputs = {},
        remote_inputs = {},
        events = {},
        last_snapshot = nil,
        last_peer_snapshot = nil,
        session = nil,
        last_ping = nil,
    }, FakeTransport)
    bus:register(endpoint)
    return endpoint
end

function FakeTransport.create_pair(options)
    options = options or {}
    local bus = Bus.new()
    local host = FakeTransport.new(bus, {
        role = "host", player_id = options.host_player_id or 1,
        endpoint_id = options.host_endpoint_id or "host",
        peer_id = options.client_endpoint_id or "client",
    })
    local client = FakeTransport.new(bus, {
        role = "client", player_id = options.client_player_id or 2,
        endpoint_id = options.client_endpoint_id or "client",
        peer_id = options.host_endpoint_id or "host",
    })
    return host, client, bus
end

function FakeTransport.create_room(player_count, options)
    options = options or {}
    player_count = math.max(1, math.floor(player_count or 2))
    local bus = Bus.new()
    local host = FakeTransport.new(bus, {
        role = "host",
        player_id = options.host_player_id or 0,
        endpoint_id = options.host_endpoint_id or "host",
    })
    local clients = {}
    for player_id = 1, player_count do
        clients[player_id] = FakeTransport.new(bus, {
            role = "client",
            player_id = player_id,
            endpoint_id = "client:" .. tostring(player_id),
            peer_id = host.endpoint_id,
        })
    end
    return host, clients, bus
end

function FakeTransport:attach_session(session)
    self.session = session
    return self
end

function FakeTransport:is_host()
    return self.role == "host"
end

function FakeTransport:send(payload)
    local kind = payload and payload.type and "command" or (payload and payload.kind) or "message"
    if self.role == "host" then
        if self.session and kind == "command" then
            self.session:dispatch(payload)
        end
        if self.peer_id then
            self.bus:deliver(self, self.peer_id, { kind = kind, payload = payload, tick = payload and payload.tick })
        else
            self.bus:broadcast(self, { kind = kind, payload = payload, tick = payload and payload.tick })
        end
        return true
    end
    if not self.peer_id then
        return false
    end
    return self.bus:deliver(self, self.peer_id, { kind = kind, payload = payload, tick = payload and payload.tick })
end

function FakeTransport:broadcast(event)
    if self.role ~= "host" then
        return false
    end
    self.bus:broadcast(self, { kind = "event", payload = event, tick = event and event.tick })
    return true
end

function FakeTransport:submit_input(player_input)
    if not player_input then
        return false
    end
    self.local_inputs[player_input.player_id] = player_input
    if self.role == "client" and self.peer_id then
        return self.bus:deliver(self, self.peer_id, {
            kind = "input", payload = player_input, tick = player_input.tick,
        })
    end
    return true
end

function FakeTransport:publish_snapshot(snapshot)
    if not self.connected then
        return false
    end
    self.bus:broadcast(self, { kind = "snapshot", payload = snapshot, tick = snapshot and snapshot.tick })
    return true
end

function FakeTransport:publish_peer_snapshot(snapshot)
    if not self.connected then return false end
    self.bus:broadcast(self, { kind = "peer_snapshot", payload = snapshot, tick = snapshot and snapshot.tick })
    return true
end

function FakeTransport:poll()
    local message = table.remove(self.inbox, 1)
    if not message then
        return nil
    end
    if message.kind == "input" and message.payload and message.payload.player_id then
        local player_id = message.payload.player_id
        local previous = self.remote_inputs[player_id]
        self.remote_inputs[player_id] = merge_remote_input(previous, message.payload)
    elseif message.kind == "event" then
        self.events[#self.events + 1] = message.payload
    elseif message.kind == "snapshot" then
        self.last_snapshot = message.payload
    elseif message.kind == "peer_snapshot" then
        self.last_peer_snapshot = message.payload
    end
    return message
end

function FakeTransport:consume_snapshot()
    local snapshot = self.last_snapshot
    self.last_snapshot = nil
    return snapshot
end

function FakeTransport:consume_peer_snapshot()
    local snapshot = self.last_peer_snapshot
    self.last_peer_snapshot = nil
    return snapshot
end

function FakeTransport:consume_inputs()
    local result = self.remote_inputs
    self.remote_inputs = {}
    return result
end

function FakeTransport:consume_events()
    local result = self.events
    self.events = {}
    return result
end

function FakeTransport:ping()
    self.last_ping = os.clock()
    if self.peer_id then
        return self.bus:deliver(self, self.peer_id, { kind = "ping", payload = { sent_at = self.last_ping } })
    end
    return false
end

function FakeTransport:update()
    while #self.inbox > 0 do
        local message = self:poll()
        if message.kind == "command" and self.session then
            self.session:dispatch(message.payload)
            if self.role == "host" then
                self.bus:broadcast(self, { kind = "command", payload = message.payload, tick = message.tick })
            end
        elseif message.kind == "ping" then
            self.bus:deliver(self, message.sender_id, { kind = "pong", payload = message.payload })
        end
    end
end

function FakeTransport:disconnect()
    self.connected = false
end

return FakeTransport
