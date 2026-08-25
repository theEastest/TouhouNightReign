local GameSession = require("tnr.core.game_session")
local LocalTransport = require("tnr.multiplayer.local_transport")
local SinglePlayerInputProvider = require("tnr.input.single_player")
local MapScene = require("tnr.map.map_scene")

local Bootstrap = {}

function Bootstrap.create(options)
    options = options or {}
    local session = GameSession.new(options)
    local transport = LocalTransport.new(session)
    local input = SinglePlayerInputProvider.new(options.input)
    local map_scene = MapScene.new(session)

    return {
        session = session,
        transport = transport,
        input = input,
        map_scene = map_scene,
        initialized = false,
    }
end

function Bootstrap:init()
    if self.initialized then
        return
    end
    self.session:start_new()
    self.initialized = true
end

function Bootstrap:update()
    if not self.initialized then
        self:init()
    end
    local player_input = self.input:poll(1)
    self.transport:submit_input(player_input)
    self.transport:update()
    return false
end

function Bootstrap:render()
    -- Rendering is intentionally an adapter seam for the LuaSTG runtime.
    -- The map scene already exposes a serializable view for a renderer/UI layer.
end

function Bootstrap:shutdown()
    self.initialized = false
end

return Bootstrap

