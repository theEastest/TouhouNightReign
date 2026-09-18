-- Real-engine regression: run via tools/test_er_desaturate.ps1.
local root = assert(os.getenv("TNR_TEST_PROJECT_ROOT")):gsub("\\", "/")
package.path = root .. "/game/scripts/?.lua;" .. root .. "/game/scripts/?/init.lua;" .. package.path
local lstg = require("lstg")
lstg.DoFile("scripts/main.lua")
local game_init = GameInit
local frames, effect_calls = 0, 0
local difficulty_index = 0
local difficulties = { "Normal", "Lunatic" }
local result_lines = {}

function GameInit()
    game_init()
    -- Use the same intercepted LoadFX call as the original activity export.
    lstg.LoadFX("er_desaturate", "er_desaturate.fx")
    for _, name in ipairs({ "test_scene", "test_mask", "test_output" }) do
        lstg.CreateRenderTarget(name)
    end
    local post_effect = lstg.PostEffect
    lstg.PostEffect = function(target, effect, ...)
        local result = post_effect(target, effect, ...)
        if effect == "er_desaturate" then effect_calls = effect_calls + 1 end
        return result
    end
    PostEffect = lstg.PostEffect
end

local function start_next_boss()
    difficulty_index = difficulty_index + 1
    frames, effect_calls = 0, 0
    local ok, err = TNRNativeLegacy.start_card("tenka_lsc:" .. difficulties[difficulty_index], 1, true)
    assert(ok, err)
    -- Start at the last-spell intro without requiring the preceding boss's BGM.
    ext.sc_pr = true
end

function FrameFunc()
    if difficulty_index == 0 then return false end
    frames = frames + 1
    local state = TNRNativeLegacy.state()
    if state.player then state.player.protect = 9999 end
    TNRNativeLegacy.update({ _native_input_override = true, player_id = 1 })
    if frames == 720 then
        assert(effect_calls >= 120, "Tenka scene did not execute the desaturation composite")
        result_lines[#result_lines + 1] = difficulties[difficulty_index] .. ": " .. effect_calls .. " composites passed"
        if difficulty_index < #difficulties then
            start_next_boss()
        else
            local file = assert(io.open("er_desaturate.result", "w"))
            file:write("passed\n", table.concat(result_lines, "\n"), "\n")
            file:close()
            return true
        end
    end
    return false
end

function RenderFunc()
    if difficulty_index == 0 then
        lstg.BeginScene()
        lstg.SetViewport(0, 1280, 0, 720)
        lstg.SetOrtho(0, 1280, 0, 720)
        lstg.PushRenderTarget("test_scene")
        lstg.RenderClear(lstg.Color(255, 40, 120, 200))
        lstg.PopRenderTarget()
        lstg.PushRenderTarget("test_mask")
        lstg.RenderClear(lstg.Color(255, 0, 0, 0))
        lstg.SetImageState("tnr-white", "", lstg.Color(255, 255, 255, 255))
        lstg.RenderRect("tnr-white", 0, 640, 0, 720)
        -- A single-channel mask must retain color, just like the original FX.
        lstg.SetImageState("tnr-white", "", lstg.Color(255, 255, 0, 0))
        lstg.RenderRect("tnr-white", 640, 1280, 0, 360)
        lstg.PopRenderTarget()
        lstg.PushRenderTarget("test_output")
        lstg.PostEffect("test_scene", "er_desaturate", "", { tex = "test_mask" })
        lstg.PopRenderTarget()
        lstg.EndScene()
        lstg.SaveTexture("test_output", "mask-test.png")
        lstg.SetImageState("tnr-white", "", lstg.Color(255, 255, 255, 255))
        start_next_boss()
    else
        TNRNativeLegacy.render()
        if frames == 650 then
            lstg.Snapshot("tenka-" .. difficulties[difficulty_index] .. ".png")
        end
    end
end
