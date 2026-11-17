-- Input bridge between the project's input provider and the replay roster.
--
-- The replay roster asks an input source for a normalised sample each frame. The
-- project already polls the keyboard, gamepad and network into a PlayerInput, so
-- this adapter is the only glue needed: a replay player's input source is either
-- the live provider or a scripted table, and the replay cannot tell the
-- difference.
--
-- Two sources are provided:
--   keyboard(provider, player_id)  live input from the existing provider
--   scripted(table)                a fixed or programmatic input, for tests and
--                                  for replaying a recorded run

local InputBridge = {}

--- Wrap the project's input provider for one player.
-- The provider is polled once per frame by the caller; this source simply
-- forwards the last polled value so every reader in a frame sees the same input.
function InputBridge.keyboard(provider, player_id)
    local source = {
        player_id = player_id or 1,
        cached = nil,
        frame = nil,
    }
    function source:sample()
        -- Refresh at most once per frame so a bomb press cannot be read twice.
        local tick = provider.tick
        if source.cached == nil or source.frame ~= tick then
            local ok, value = pcall(provider.poll, provider, source.player_id)
            if ok and value then
                source.cached = {
                    move_x = value.move_x or 0,
                    move_y = value.move_y or 0,
                    shoot = value.shoot == true,
                    focus = value.focus == true,
                    bomb = value.bomb == true or value.bomb_down == true,
                    confirm = value.confirm == true,
                    skip_dialogue = value.skip_dialogue == true,
                }
            else
                source.cached = source.cached or {}
            end
            source.frame = tick
        end
        return source.cached
    end
    return source
end

--- A scripted source: a fixed input, or a function called each frame.
function InputBridge.scripted(value)
    local source = { scripted = value }
    function source:sample()
        local v = source.scripted
        if type(v) == "function" then v = v() end
        return v or {}
    end
    return source
end

--- Record every input a player produced, so a run can be replayed or audited.
function InputBridge.recorder(player_id)
    local source = {
        player_id = player_id or 1,
        frames = {},
    }
    function source:record(input)
        -- Store only the axes and buttons the replay reads.
        source.frames[#source.frames + 1] = {
            move_x = input.move_x or 0,
            move_y = input.move_y or 0,
            shoot = input.shoot == true,
            focus = input.focus == true,
            bomb = input.bomb == true,
            confirm = input.confirm == true,
            skip_dialogue = input.skip_dialogue == true,
        }
    end
    function source:playback()
        local index = 0
        return InputBridge.scripted(function()
            index = index + 1
            return source.frames[index] or {}
        end)
    end
    return source
end

return InputBridge
