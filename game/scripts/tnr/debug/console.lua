local Command = require("tnr.core.command")
local DebugCommand = require("tnr.debug.debug_command")

local Console = {}
Console.__index = Console

function Console.new(session, options)
    return setmetatable({
        session = session,
        options = options or {},
        open = false,
        history = {},
        output = {},
    }, Console)
end

function Console:toggle()
    self.open = not self.open
    return self.open
end

function Console:write(line)
    self.history[#self.history + 1] = line
    local command, err = DebugCommand.parse(line)
    if not command then
        self.output[#self.output + 1] = err
        return nil, err
    end
    if command.type == "HELP" then
        for _, help_line in ipairs(DebugCommand.help()) do
            self.output[#self.output + 1] = help_line
        end
        return DebugCommand.help()
    end
    if command.type == Command.DEBUG_KILL_ALL then
        if self.options.on_kill_all then
            self.options.on_kill_all()
        else
            self.output[#self.output + 1] = "当前没有连接 BattleManager"
        end
        return true
    elseif command.type == Command.DEBUG_CLEAR or command.type == Command.DEBUG_CLEAR_REWARD then
        local result = self.session:dispatch({
            type = Command.COMPLETE_BATTLE,
            result = {
                encounter_id = self.session.current_encounter and self.session.current_encounter.id,
                clear_state = true,
                battle_score = 0,
                reward_eligible = command.type == Command.DEBUG_CLEAR_REWARD,
                debug_clear = true,
            },
        })
        return result
    end
    return self.session:dispatch(command)
end

return Console

