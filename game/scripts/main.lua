-- LuaSTG Sub entry point. Engine-specific rendering is kept in this thin adapter.
local lstg = require("lstg")
local Bootstrap = require("tnr.bootstrap")

local game = Bootstrap.create({ lstg = lstg, stage = rawget(_G, "stage") })

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
