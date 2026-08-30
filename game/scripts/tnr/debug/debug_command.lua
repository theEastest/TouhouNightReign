local Command = require("tnr.core.command")

local DebugCommand = {}

local HELP = {
    "god [on|off]        开启或关闭无敌",
    "kill_all            杀死当前战斗中的全部敌人",
    "clear               强制过关，不发放表现奖励",
    "clear_reward        强制过关并发放表现奖励",
    "money <amount>      增加 Money",
    "score <amount>      增加当前战斗分数",
    "life <amount>       增加残机",
    "bomb <amount>       增加 Bomb",
    "goto <node_id>      移动到指定地图节点",
    "map_reveal          显示全部地图节点",
    "give_equipment <id>  生成测试装备并放入仓库",
    "inventory            查看本地仓库",
    "loadout              查看当前配装",
    "runtime_loadout      查看 Runtime 配装描述",
    "runtime_weapon       查看 Runtime 武器状态",
    "runtime_support      查看 Runtime 子机状态",
    "runtime_modifiers    查看 Runtime Modifier 状态",
    "weight_debug         查看重量与速度策略",
    "loadout_hash         查看配装内容哈希",
    "discard <slot>       丢弃仓库物品",
    "ready               锁定当前配装",
    "unready             取消配装锁定",
    "help                显示调试命令",
}

local function split(line)
    local result = {}
    for token in string.gmatch(line or "", "%S+") do
        result[#result + 1] = token
    end
    return result
end

local function number_argument(tokens, name)
    local value = tonumber(tokens[2])
    if not value then
        return nil, name .. " 需要数字参数"
    end
    return value
end

function DebugCommand.help()
    return HELP
end

function DebugCommand.parse(line)
    local tokens = split(line)
    local name = string.lower(tokens[1] or "")
    if name == "" or name == "help" then
        return { type = "HELP" }
    elseif name == "god" then
        local mode = tokens[2] and string.lower(tokens[2])
        if mode and mode ~= "on" and mode ~= "off" then
            return nil, "god 参数只能是 on 或 off"
        end
        if mode == nil then
            return { type = Command.DEBUG_GOD, toggle = true }
        end
        return { type = Command.DEBUG_GOD, enabled = mode == "on" }
    elseif name == "kill_all" then
        return { type = Command.DEBUG_KILL_ALL }
    elseif name == "clear" or name == "clear_reward" then
        return { type = name == "clear" and Command.DEBUG_CLEAR or Command.DEBUG_CLEAR_REWARD }
    elseif name == "money" or name == "score" or name == "life" or name == "bomb" then
        local amount, err = number_argument(tokens, name)
        if not amount then
            return nil, err
        end
        local command_type = ({ money = Command.ADD_MONEY, score = Command.ADD_SCORE, life = Command.ADD_LIFE, bomb = Command.ADD_BOMB })[name]
        return { type = command_type, amount = amount, source = "debug", player_id = 1 }
    elseif name == "goto" then
        local node_id, err = number_argument(tokens, name)
        if not node_id then
            return nil, err
        end
        return { type = Command.DEBUG_GOTO, node_id = math.floor(node_id) }
    elseif name == "map_reveal" then
        return { type = Command.DEBUG_MAP_REVEAL }
    elseif name == "give_equipment" then
        if not tokens[2] or tokens[2] == "" then return nil, "give_equipment 需要 definition_id" end
        return { type = Command.DEBUG_GIVE_EQUIPMENT, definition_id = tokens[2] }
    elseif name == "inventory" then
        return { type = Command.DEBUG_INVENTORY }
    elseif name == "loadout" then
        return { type = Command.DEBUG_LOADOUT }
    elseif name == "runtime_loadout" then
        return { type = Command.DEBUG_RUNTIME_LOADOUT }
    elseif name == "runtime_weapon" then
        return { type = Command.DEBUG_RUNTIME_WEAPON }
    elseif name == "runtime_support" then
        return { type = Command.DEBUG_RUNTIME_SUPPORT }
    elseif name == "runtime_modifiers" then
        return { type = Command.DEBUG_RUNTIME_MODIFIERS }
    elseif name == "weight_debug" then
        return { type = Command.DEBUG_WEIGHT }
    elseif name == "loadout_hash" then
        return { type = Command.DEBUG_LOADOUT_HASH }
    elseif name == "discard" then
        local slot, err = number_argument(tokens, name)
        if not slot then return nil, err end
        return { type = Command.DEBUG_DISCARD, inventory_index = math.floor(slot) }
    elseif name == "ready" then
        return { type = Command.SET_READY }
    elseif name == "unready" then
        return { type = Command.CANCEL_READY }
    elseif name == "net_status" then
        return { type = Command.DEBUG_NET_STATUS }
    end
    return nil, "未知命令：" .. name
end

return DebugCommand
