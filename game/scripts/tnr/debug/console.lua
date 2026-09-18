local Command = require("tnr.core.command")
local DebugCommand = require("tnr.debug.debug_command")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local CharacterRuntimeBridge = require("tnr.character.runtime.character_runtime_bridge")

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
    elseif command.type == Command.DEBUG_VALIDATION_RUN then
            self.session:start_new(require("tnr.core.constants").validation_run_seed)
        return self.session.run_seed
    elseif command.type == Command.DEBUG_RUN_STATE then
        return {
            run_state = self.session.run_state,
            run_seed = self.session.run_seed,
            node_id = self.session.current_node_id,
            room_generation = self.session.room_generation,
        }
    elseif command.type == Command.DEBUG_FORCE_SHOP then
        for _, node in ipairs(self.session.map and self.session.map.nodes or {}) do
            if node.type == require("tnr.core.constants").node_types.SHOP then
                return self.session:debug_goto(node.id)
            end
        end
        return nil, "当前地图没有商店节点"
    elseif command.type == Command.DEBUG_GIVE_RELIC then
        local player_id = self.session.local_player_id or 1
        local runtime = self.session.relic_runtime
        if not runtime then return nil, "RelicRuntime 尚未初始化" end
        return runtime:add(player_id, command.relic_id)
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
    elseif command.type == Command.DEBUG_GIVE_EQUIPMENT then
        local definition = self.session.equipment_registry and self.session.equipment_registry:get(command.definition_id)
        if not definition then
            local message = "未知装备 definition_id: " .. tostring(command.definition_id)
            self.output[#self.output + 1] = message
            return nil, message
        end
        local instance = EquipmentInstance.new(definition, self.session.local_player_id or 1)
        return self.session:dispatch({ type = Command.ACQUIRE_ITEM, player_id = self.session.local_player_id or 1, instance = instance })
    elseif command.type == Command.DEBUG_INVENTORY then
        local player = self.session:get_player(self.session.local_player_id or 1)
        return player and player.loadout.inventory:to_table() or nil, "UNKNOWN_PLAYER"
    elseif command.type == Command.DEBUG_LOADOUT then
        local player = self.session:get_player(self.session.local_player_id or 1)
        return player and player.loadout:debug_summary() or nil, "UNKNOWN_PLAYER"
    elseif command.type == Command.DEBUG_RUNTIME_LOADOUT
            or command.type == Command.DEBUG_RUNTIME_WEAPON
            or command.type == Command.DEBUG_RUNTIME_SUPPORT
            or command.type == Command.DEBUG_RUNTIME_MODIFIERS
            or command.type == Command.DEBUG_WEIGHT
            or command.type == Command.DEBUG_LOADOUT_HASH then
        local bridge = CharacterRuntimeBridge.new(self.session,
            self.session.local_player_id or 1, self.session.equipment_registry)
        local runtime = bridge:create_runtime()
        if command.type == Command.DEBUG_RUNTIME_LOADOUT then return runtime.descriptor end
        if command.type == Command.DEBUG_RUNTIME_WEAPON then return runtime.weapon_manager:to_table() end
        if command.type == Command.DEBUG_RUNTIME_SUPPORT then return runtime.support_manager:to_table() end
        if command.type == Command.DEBUG_RUNTIME_MODIFIERS then return runtime.modifier_runtime:to_table() end
        if command.type == Command.DEBUG_WEIGHT then return runtime.descriptor.speed end
        return runtime.descriptor.loadout_hash
    elseif command.type == Command.DEBUG_DISCARD then
        return self.session:dispatch({ type = Command.DISCARD_ITEM, player_id = self.session.local_player_id or 1, inventory_index = command.inventory_index })
    elseif command.type == Command.DEBUG_NET_STATUS then
        if self.options.on_net_status then
            return self.options.on_net_status()
        end
        return nil, "Native sync audit is unavailable"
    end
    return self.session:dispatch(command)
end

return Console
