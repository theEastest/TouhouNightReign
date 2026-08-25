-- LuaSTG Sub entry point. Engine-specific rendering is kept in this thin adapter.
local lstg = require("lstg")
local Bootstrap = require("tnr.bootstrap")

local game = Bootstrap.create({ lstg = lstg, stage = rawget(_G, "stage") })

function GameInit()
    lstg.LoadTexture("tnr-white-texture", "assets/texture/white.png", false)
    lstg.LoadImage("tnr-white", "tnr-white-texture", 0, 0, 16, 16)
    if not lstg.LoadTTF("Sans", "C:/Windows/Fonts/msyh.ttc", 48, 48) then
        lstg.LoadTTF("Sans", "C:/Windows/Fonts/msyh.ttf", 48, 48)
    end
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
