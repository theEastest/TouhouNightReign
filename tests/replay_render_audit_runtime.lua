-- Engine rendering diagnostic, explicitly NOT a survival acceptance gate.
local root=assert(os.getenv("TNR_TEST_PROJECT_ROOT")):gsub("\\","/")
package.path=root.."/game/scripts/?.lua;"..package.path
local g=require("lstg")
local Replay=require("tnr.legacy_replay.replay")
local replay,n,done
local mode=os.getenv("TNR_TEST_MODE") or "classic"
local preview_frame=tonumber(os.getenv("TNR_TEST_PREVIEW_FRAME")) or 0
local preview_reported=false
local function report(s)
    local f=assert(io.open("render-audit.txt","a"));f:write(s,"\n");f:close()
end
local function start()
    replay.stage_cursor=n
    if preview_frame==0 or mode=="modern" then
        local ship_count=mode=="modern" and 3 or #Replay.CHARACTERS
        replay.character_cursor=(n-1)%ship_count+1
        replay.keyboard_input={shoot=true}
    end
    assert(replay:start_stage())
    local difficulty=tonumber(os.getenv("TNR_TEST_DIFFICULTY")) or 1
    replay.runtime.adapter.difficulty=difficulty
    replay.runtime.adapter.runtime.difficulty=difficulty
    report("START st0"..n.." difficulty="..difficulty.." mode="..mode)
end
function GameInit()
    g.LoadTexture("tnr-white-texture","assets/texture/white.png",false)
    g.LoadImage("tnr-white","tnr-white-texture",0,0,16,16)
    g.LoadTTF("Sans","assets/font/SourceHanSansCN-Bold.otf",48,48)
    replay=Replay.new({lstg=g});replay.mode_cursor=mode=="modern" and 1 or 2
    n=tonumber(os.getenv("TNR_TEST_STAGE")) or 1
    start()
end
function FrameFunc()
    if done then return true end
    local ok,err=xpcall(function()
        for _=1,120 do
            local s=replay.runtime
            if preview_frame>0 and s.frames>=preview_frame then
                if not preview_reported then report("PREVIEW "..n.." "..s.frames);preview_reported=true end
                return
            end
            for _,p in pairs(s.players) do p.invulnerable=999 end
            s:update()
            if s:timeline_finished() then
                report("TIMELINE st0"..n.." "..s.frames)
                if n==6 then done=true;report("RENDER_DIAGNOSTIC_PASS");return end
                n=n+1;replay:stop();start();break
            end
            assert(s.frames<100000,"timeline timeout")
        end
    end,debug.traceback)
    if not ok then report("ERROR "..err);done=true end
    return done or false
end
function RenderFunc()
    if done then return end
    local ok,err=xpcall(function()
        g.BeginScene();g.SetViewport(0,1280,0,720);g.SetOrtho(0,1280,0,720)
        g.RenderClear(g.Color(255,0,0,0))
        replay:_sync_stats();replay.runtime:draw()
        g.EndScene()
    end,debug.traceback)
    if not ok then report("ERROR "..err);done=true end
end
function GameExit() end
function FocusGainFunc() end
function FocusLoseFunc() end
