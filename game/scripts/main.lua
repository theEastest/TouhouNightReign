-- LuaSTG Sub entry point. Engine-specific rendering is kept in this thin adapter.
local Bootstrap = require("tnr.bootstrap")

local game = Bootstrap.create()

function GameInit()
    game:init()
end

function GameExit()
    game:shutdown()
end

function FrameFunc()
    return game:update()
end

function RenderFunc()
    game:render()
end

