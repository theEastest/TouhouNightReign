local Constants = require("tnr.core.constants")
local Command = require("tnr.core.command")
local Event = require("tnr.core.event")
local RNG = require("tnr.core.rng")
local PlayerManager = require("tnr.core.player_manager")
local PartyState = require("tnr.core.party_state")
local MapGenerator = require("tnr.map.map_generator")
local BattleResult = require("tnr.battle.battle_result")
local RewardService = require("tnr.reward.reward_service")
local EncounterManager = require("tnr.encounter.encounter_manager")
local EncounterDefinitions = require("tnr.encounter.definitions")
local PreparationState = require("tnr.preparation.preparation_state")
local LoadoutService = require("tnr.equipment.loadout_service")
local AcquisitionService = require("tnr.equipment.acquisition_service")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local Phase1Catalog = require("tnr.equipment.phase1_catalog")
local LegacyStateAdapter = require("tnr.core.legacy_state_adapter")
local LoadoutCommit = require("tnr.multiplayer.loadout_commit")

local GameSession = {}
GameSession.__index = GameSession

local function copy_event(event)
    local result = {}
    for key, value in pairs(event) do
        result[key] = value
    end
    return result
end

function GameSession.new(options)
    options = options or {}
    local self = setmetatable({
        map_config = options.map_config,
        default_seed = options.run_seed,
        run_seed = nil,
        run_state = Constants.run_states.MENU,
        map = nil,
        current_node_id = nil,
        players = PlayerManager.new(),
        party = PartyState.new({}, nil),
        preparation = PreparationState.new({}),
        equipment_registry = options.equipment_registry or Phase1Catalog.registry,
        preparation_required = options.preparation_required == true,
        _committing_prepared = false,
        money = 0,
        total_score = 0,
        current_encounter = nil,
        battle_result = nil,
        visited_nodes = {},
        node_votes = {},
        battle_failure_votes = {},
        event_log = {},
        listeners = {},
        rng = {},
        reward_service = RewardService.new(options.reward_thresholds),
        encounter_manager = EncounterManager.new(EncounterDefinitions),
        god_mode = {},
        player_count = math.max(1, math.min(2, math.floor(options.player_count or 1))),
        local_player_id = options.local_player_id or 1,
        room_generation = nil,
        loadout_commits = {},
    }, GameSession)
    self.legacy_state_adapter = LegacyStateAdapter.new(self)
    self.loadout_service = LoadoutService.new(self, self.equipment_registry)
    self.acquisition_service = AcquisitionService.new(self)
    return self
end

function GameSession:on(event_type, listener)
    assert(type(listener) == "function", "listener must be a function")
    self.listeners[event_type] = self.listeners[event_type] or {}
    self.listeners[event_type][#self.listeners[event_type] + 1] = listener
end

function GameSession:emit(event_type, payload)
    local event = payload or {}
    event.type = event_type
    self.event_log[#self.event_log + 1] = copy_event(event)
    for _, listener in ipairs(self.listeners[event_type] or {}) do
        listener(event)
    end
    for _, listener in ipairs(self.listeners["*"] or {}) do
        listener(event)
    end
    return event
end

function GameSession:start_new(run_seed)
    run_seed = tonumber(run_seed) or self.default_seed or os.time()
    self.run_seed = math.floor(run_seed)
    self.run_state = Constants.run_states.MAP
    self.map = MapGenerator.generate(self.run_seed, self.map_config)
    self.map:reveal()
    self.current_node_id = self.map.current_node_id
    self.players = PlayerManager.new()
    local player_ids = {}
    for player_id = 1, self.player_count do
        player_ids[#player_ids + 1] = player_id
        self.players:add_player(player_id, { character_id = "reimu", life = 3, bomb = 3 })
    end
    self.party = PartyState.new(player_ids, self.current_node_id)
    self.preparation:reset(player_ids)
    for _, player_id in ipairs(player_ids) do
        local player = self:get_player(player_id)
        if player.character_id == "reimu" then
            player.loadout:set_slot("high_weapons", 1, EquipmentInstance.new(Phase1Catalog.initial.high_weapon, player_id))
            player.loadout:set_slot("low_weapons", 1, EquipmentInstance.new(Phase1Catalog.initial.low_weapon, player_id))
            player.loadout:set_slot("supports", 1, EquipmentInstance.new(Phase1Catalog.initial.support, player_id))
            player.loadout.character_relic = Phase1Catalog.initial.relic.relic_id
            player.loadout:set_definition_lookup(self.equipment_registry)
        end
    end
    self.money = 0
    self.total_score = 0
    self.current_encounter = nil
    self.room_generation = nil
    self.loadout_commits = {}
    self.battle_result = nil
    self.god_mode = {}
    self.node_votes = {}
    self.battle_failure_votes = {}
    self.visited_nodes = { [self.current_node_id] = true }
    self.event_log = {}
    self.rng = {
        map = RNG.new(self.run_seed),
        encounter = RNG.new(self.run_seed + 1),
        reward = RNG.new(self.run_seed + 2),
        battle = RNG.new(self.run_seed + 11),
        enemy = RNG.new(self.run_seed + 23),
        boss = RNG.new(self.run_seed + 37),
        pattern = RNG.new(self.run_seed + 53),
        visual = RNG.new(self.run_seed + 97),
    }
    self:emit(Event.MAP_ENTERED, { node_id = self.current_node_id, run_seed = self.run_seed })
    return self
end

function GameSession:get_player(player_id)
    return self.players:get_player(player_id)
end

function GameSession:add_money(player_id, amount, source)
    local player = assert(self:get_player(player_id), "unknown player")
    player:add_money(amount)
    self.money = self.money + math.max(0, amount or 0)
    return self:emit("MONEY_ADDED", { player_id = player_id, amount = amount, source = source })
end

function GameSession:add_score(player_id, amount, source)
    local player = assert(self:get_player(player_id), "unknown player")
    player:add_score(amount)
    self.total_score = self.total_score + math.max(0, amount or 0)
    return self:emit("SCORE_ADDED", { player_id = player_id, amount = amount, source = source })
end

function GameSession:add_life(player_id, amount, source)
    local player = assert(self:get_player(player_id), "unknown player")
    player:add_life(amount)
    return self:emit("LIFE_CHANGED", { player_id = player_id, amount = amount, source = source })
end

function GameSession:add_bomb(player_id, amount, source)
    local player = assert(self:get_player(player_id), "unknown player")
    player:add_bomb(amount)
    return self:emit("BOMB_CHANGED", { player_id = player_id, amount = amount, source = source })
end

function GameSession:get_map_vote_message()
    local player_ids = self.party and self.party.player_ids or {}
    if #player_ids <= 1 then
        return ""
    end

    local voted = {}
    local first_node_id
    local all_same = true
    for _, player_id in ipairs(player_ids) do
        local node_id = self.node_votes[player_id]
        if node_id then
            voted[#voted + 1] = player_id
            if first_node_id == nil then
                first_node_id = node_id
            elseif node_id ~= first_node_id then
                all_same = false
            end
        end
    end

    if #voted == 0 then
        return "等待 P1 和 P2 选择同一个节点"
    elseif #voted < #player_ids then
        local waiting = {}
        for _, player_id in ipairs(player_ids) do
            if not self.node_votes[player_id] then
                waiting[#waiting + 1] = "P" .. tostring(player_id)
            end
        end
        local voter_id = voted[1]
        return string.format("P%d 已选择节点 %d，等待 %s", voter_id, self.node_votes[voter_id], table.concat(waiting, " / "))
    elseif not all_same then
        return "P1 和 P2 选择不一致，请重新选择节点"
    end
    return ""
end

function GameSession:vote_node(node_id, player_id)
    if self.run_state ~= Constants.run_states.MAP then
        return nil, "not on map"
    end
    player_id = tonumber(player_id)
    node_id = tonumber(node_id)

    local party_member = false
    for _, candidate_id in ipairs(self.party.player_ids or {}) do
        if candidate_id == player_id then
            party_member = true
            break
        end
    end
    if not party_member then
        return nil, "unknown party player"
    end
    if not node_id or not self.map:get_node(node_id) then
        return nil, "unknown node"
    end
    if not self.map:is_adjacent(node_id) then
        return nil, "node is not adjacent"
    end

    self.node_votes[player_id] = node_id
    local vote_event = self:emit(Event.MAP_VOTE_CHANGED, {
        player_id = player_id,
        node_id = node_id,
    })

    local agreed_node_id
    for _, candidate_id in ipairs(self.party.player_ids or {}) do
        local candidate_node_id = self.node_votes[candidate_id]
        if not candidate_node_id then
            return vote_event
        end
        if agreed_node_id and agreed_node_id ~= candidate_node_id then
            return vote_event
        end
        agreed_node_id = candidate_node_id
    end
    return self:select_node(agreed_node_id, player_id)
end

function GameSession:select_node(node_id, player_id)
    if self.run_state ~= Constants.run_states.MAP then
        return nil, "当前不在地图状态"
    end
    if self.preparation_required and not self._committing_prepared then
        node_id = tonumber(node_id)
        if not node_id or not self.map:is_adjacent(node_id) then return nil, "节点不是当前节点的相邻节点" end
        self.preparation:set_selected_node(node_id)
        self.run_state = Constants.run_states.MAP_PREPARATION
        self:emit(Event.PREPARATION_CHANGED, { open = true, selected_node_id = node_id })
        return self.map:get_node(node_id)
    end
    local node, err = self.map:select_node(node_id)
    if not node then
        return nil, err
    end
    self.node_votes = {}
    self.current_node_id = node.id
    self.party:set_current_node(node.id)
    self.visited_nodes[node.id] = true
    self:emit(Event.NODE_SELECTED, { node_id = node.id, player_id = player_id or 1, node_type = node.type })

    if node.type == Constants.node_types.ENEMY or node.type == Constants.node_types.ELITE or node.type == Constants.node_types.BOSS then
        self.run_state = Constants.run_states.ENCOUNTER
        local definition = self.encounter_manager:get(node.encounter_id)
        assert(definition, "missing encounter definition: " .. tostring(node.encounter_id))
        self.current_encounter = {
            id = definition.id,
            node_id = node.id,
            type = definition.type,
            stage_id = definition.stage_id,
            reward_table = definition.reward_table,
            content_seed = node.content_seed,
            room_generation = string.format("%s:%s:%s", tostring(self.run_seed), tostring(node.id), tostring(node.content_seed or "0")),
        }
        self.room_generation = self.current_encounter.room_generation
        self:emit(Event.ENCOUNTER_STARTED, { encounter = self.current_encounter })
    elseif node.type == Constants.node_types.SHOP or node.type == Constants.node_types.EVENT then
        self.run_state = Constants.run_states.PLACEHOLDER
        self:emit(Event.PLACEHOLDER_ENTERED, { node_id = node.id, node_type = node.type })
    end
    return node
end

function GameSession:enter_preparation(selected_node_id)
    if self.run_state ~= Constants.run_states.MAP then
        return nil, "当前不在地图状态"
    end
    if selected_node_id ~= nil then
        selected_node_id = tonumber(selected_node_id)
        if not selected_node_id or not self.map:is_adjacent(selected_node_id) then
            return nil, "节点不是当前节点的相邻节点"
        end
        self.preparation:set_selected_node(selected_node_id)
    end
    self.run_state = Constants.run_states.MAP_PREPARATION
    self:emit(Event.PREPARATION_CHANGED, { open = true, selected_node_id = self.preparation.selected_node_id })
    return self.preparation
end

function GameSession:leave_preparation()
    if self.run_state ~= Constants.run_states.MAP_PREPARATION then
        return nil, "当前不在地图整备状态"
    end
    self.run_state = Constants.run_states.MAP
    self.preparation:reset(self.party.player_ids)
    self:emit(Event.PREPARATION_CHANGED, { open = false })
    return true
end

function GameSession:commit_prepared_node()
    if self.run_state ~= Constants.run_states.MAP_PREPARATION then return nil, "当前不在地图整备状态" end
    local node_id = self.preparation.selected_node_id
    if not node_id then return nil, "尚未选择目标节点" end
    if not self.preparation:is_party_ready(self.party.player_ids) then return nil, "队伍尚未全部Ready" end
    if not self:all_loadouts_committed() then return nil, "队伍尚未提交完整配装" end
    for _, player_id in ipairs(self.party.player_ids) do
        local ok, err = self.loadout_service:validate(player_id)
        if not ok then return nil, "玩家 P" .. tostring(player_id) .. " 配装无效: " .. tostring(err) end
    end
    self.run_state = Constants.run_states.MAP
    self.preparation:reset(self.party.player_ids)
    self._committing_prepared = true
    local result, err = self:select_node(node_id, self.local_player_id)
    self._committing_prepared = false
    return result, err
end

function GameSession:set_player_ready(player_id, value)
    if self.run_state ~= Constants.run_states.MAP_PREPARATION then return nil, "当前不在地图整备状态" end
    player_id = tonumber(player_id)
    if not self:get_player(player_id) then return nil, "未知的队伍玩家" end
    if value == true and not self.loadout_commits[player_id] then
        local commit, commit_err = self:commit_loadout(player_id)
        if not commit then return nil, commit_err end
    elseif value ~= true then
        self.loadout_commits[player_id] = nil
    end
    local ready, err = self.preparation:set_ready(player_id, value == true)
    if ready == nil then return nil, err end
    self:get_player(player_id):set_map_ready(value == true)
    self:emit(Event.PLAYER_READY_CHANGED, { player_id = player_id, ready = ready })
    return ready
end

function GameSession:build_loadout_commit(player_id)
    player_id = tonumber(player_id) or self.local_player_id or 1
    if not self:get_player(player_id) then return nil, "UNKNOWN_PLAYER" end
    return LoadoutCommit.build(self, player_id)
end

function GameSession:commit_loadout(player_id, descriptor)
    player_id = tonumber(player_id) or self.local_player_id or 1
    if not self:get_player(player_id) then return nil, "UNKNOWN_PLAYER" end
    if descriptor == nil then descriptor = self:build_loadout_commit(player_id) end
    local ok, err = LoadoutCommit.validate(descriptor)
    if not ok then return nil, err end
    if not LoadoutCommit.same_room(descriptor, self.room_generation) then
        return nil, "STALE_LOADOUT_COMMIT"
    end
    descriptor.player_id = player_id
    descriptor.room_generation = self.room_generation
    self.loadout_commits[player_id] = descriptor
    self:emit(Event.LOADOUT_COMMIT_CHANGED, {
        player_id = player_id,
        loadout_hash = descriptor.loadout_hash,
        loadout_version = descriptor.loadout_version,
    })
    return descriptor
end

function GameSession:is_loadout_committed(player_id)
    return self.loadout_commits[tonumber(player_id)] ~= nil
end

function GameSession:all_loadouts_committed()
    for _, player_id in ipairs(self.party.player_ids or {}) do
        if not self:is_loadout_committed(player_id) then return false end
    end
    return #(self.party.player_ids or {}) > 0
end

function GameSession:return_to_map()
    if not self.map then
        return nil, "没有可返回的地图"
    end
    self.run_state = Constants.run_states.MAP
    self.preparation:reset(self.party.player_ids)
    for _, player_id in ipairs(self.party.player_ids or {}) do
        local player = self:get_player(player_id)
        if player then player:set_map_ready(false) end
    end
    self.current_encounter = nil
    self.loadout_commits = {}
    self.node_votes = {}
    self:emit(Event.MAP_ENTERED, { node_id = self.current_node_id })
    return self.map:get_current_node()
end

function GameSession:complete_battle(values)
    local result = BattleResult.new(values)
    self.battle_result = result
    if result.clear_state then
        self:emit(Event.BATTLE_CLEARED, { result = result })
        if result.reward_eligible then
            local reward = self.reward_service:calculate(result)
            local player_id = values.player_id or 1
            if reward.money > 0 then
                self:add_money(player_id, reward.money, "battle_reward")
            end
            if reward.life > 0 then
                self:add_life(player_id, reward.life, "battle_reward")
            end
            if reward.bomb > 0 then
                self:add_bomb(player_id, reward.bomb, "battle_reward")
            end
            self:emit(Event.REWARD_GRANTED, { result = result, reward = reward })
        end
        if self.current_encounter and self.current_encounter.type == Constants.node_types.BOSS then
            self.run_state = Constants.run_states.RUN_CLEAR
            self:emit(Event.RUN_CLEARED, { result = result })
        else
            self:return_to_map()
        end
    else
        self.run_state = Constants.run_states.RUN_FAILED
        self:emit(Event.BATTLE_FAILED, { result = result })
    end
    return result
end

function GameSession:vote_battle_failure(choice, player_id)
    if self.run_state ~= Constants.run_states.RUN_FAILED then
        return nil, "当前没有等待处理的战斗失败"
    end
    choice = tostring(choice or "")
    if choice ~= "RETRY_ENCOUNTER" and choice ~= "RESTART_RUN" and choice ~= "RETURN_MENU" then
        return nil, "无效的失败处理选项"
    end
    player_id = tonumber(player_id) or self.local_player_id or 1
    local valid_player = false
    for _, candidate_id in ipairs(self.party.player_ids or {}) do
        if candidate_id == player_id then
            valid_player = true
            break
        end
    end
    if not valid_player then
        return nil, "未知的队伍玩家"
    end
    self.battle_failure_votes[player_id] = choice
    self:emit(Event.BATTLE_FAILURE_VOTE_CHANGED, {
        player_id = player_id,
        choice = choice,
    })
    local agreed
    for _, candidate_id in ipairs(self.party.player_ids or {}) do
        local candidate_choice = self.battle_failure_votes[candidate_id]
        if not candidate_choice then
            return self.battle_failure_votes
        end
        if agreed and agreed ~= candidate_choice then
            return self.battle_failure_votes
        end
        agreed = candidate_choice
    end
    self.battle_failure_votes = {}
    return self:emit(Event.BATTLE_FAILURE_ACTION, { choice = agreed })
end

function GameSession:debug_goto(node_id)
    local node = self.map and self.map:get_node(node_id)
    if not node then
        return nil, "unknown node"
    end
    self.map.current_node_id = node_id
    self.node_votes = {}
    node.visited = true
    self.current_node_id = node_id
    self.party:set_current_node(node_id)
    self.visited_nodes[node_id] = true
    self:emit(Event.NODE_SELECTED, { node_id = node_id, player_id = 1, debug = true, node_type = node.type })
    if node.type == Constants.node_types.ENEMY or node.type == Constants.node_types.ELITE or node.type == Constants.node_types.BOSS then
        self.run_state = Constants.run_states.ENCOUNTER
        local definition = self.encounter_manager:get(node.encounter_id)
        assert(definition, "missing encounter definition: " .. tostring(node.encounter_id))
        self.current_encounter = {
            id = definition.id,
            node_id = node.id,
            type = definition.type,
            stage_id = definition.stage_id,
            reward_table = definition.reward_table,
            content_seed = node.content_seed,
            room_generation = string.format("%s:%s:%s", tostring(self.run_seed), tostring(node.id), tostring(node.content_seed or "0")),
        }
        self.room_generation = self.current_encounter.room_generation
        self:emit(Event.ENCOUNTER_STARTED, { encounter = self.current_encounter, debug = true })
    elseif node.type == Constants.node_types.SHOP or node.type == Constants.node_types.EVENT then
        self.run_state = Constants.run_states.PLACEHOLDER
        self:emit(Event.PLACEHOLDER_ENTERED, { node_id = node.id, node_type = node.type, debug = true })
    end
    return node
end

function GameSession:dispatch(command)
    assert(type(command) == "table" and command.type, "invalid command")
    local command_type = command.type
    if command_type == Command.SELECT_NODE then
        return self:select_node(command.node_id, command.player_id)
    elseif command_type == Command.VOTE_NODE then
        return self:vote_node(command.node_id, command.player_id)
    elseif command_type == Command.ADD_MONEY then
        return self:add_money(command.player_id or 1, command.amount, command.source)
    elseif command_type == Command.ADD_SCORE then
        return self:add_score(command.player_id or 1, command.amount, command.source)
    elseif command_type == Command.ADD_LIFE then
        return self:add_life(command.player_id or 1, command.amount, command.source)
    elseif command_type == Command.ADD_BOMB then
        return self:add_bomb(command.player_id or 1, command.amount, command.source)
    elseif command_type == Command.OPEN_PREPARATION then
        return self:enter_preparation(command.node_id)
    elseif command_type == Command.CLOSE_PREPARATION then
        return self:leave_preparation()
    elseif command_type == Command.EQUIP_ITEM then
        local result, err = self.loadout_service:equip_from_inventory(command.player_id or self.local_player_id, command.inventory_index, command.slot_type, command.slot_index)
        if not result then return nil, err end
        self:emit(Event.LOADOUT_CHANGED, { player_id = command.player_id or self.local_player_id, operation = command_type })
        return result
    elseif command_type == Command.UNEQUIP_ITEM then
        local result, err = self.loadout_service:unequip(command.player_id or self.local_player_id, command.slot_type, command.slot_index)
        if not result then return nil, err end
        self:emit(Event.LOADOUT_CHANGED, { player_id = command.player_id or self.local_player_id, operation = command_type })
        return result
    elseif command_type == Command.MOVE_INVENTORY_ITEM then
        local result, err = self.loadout_service:move_inventory(command.player_id or self.local_player_id, command.from_index, command.to_index)
        if not result then return nil, err end
        self:emit(Event.INVENTORY_CHANGED, { player_id = command.player_id or self.local_player_id, operation = command_type })
        return result
    elseif command_type == Command.DISCARD_ITEM then
        local result, err = self.loadout_service:discard_inventory(command.player_id or self.local_player_id, command.inventory_index)
        if not result then return nil, err end
        self:emit(Event.INVENTORY_CHANGED, { player_id = command.player_id or self.local_player_id, operation = command_type })
        return result
    elseif command_type == Command.ACQUIRE_ITEM then
        local instance = command.instance
        if type(instance) == "table" and not instance.definition_id then instance = EquipmentInstance.from_table(instance) end
        local result, err = self.acquisition_service:acquire(command.player_id or self.local_player_id, instance)
        self:emit(Event.INVENTORY_CHANGED, { player_id = command.player_id or self.local_player_id, operation = command_type, pending = result == nil })
        return result, err
    elseif command_type == Command.ACCEPT_PENDING_ITEM then
        local result, err = self.acquisition_service:accept_pending(command.player_id or self.local_player_id, command.discard_index)
        if not result then return nil, err end
        self:emit(Event.INVENTORY_CHANGED, { player_id = command.player_id or self.local_player_id, operation = command_type })
        return result
    elseif command_type == Command.REJECT_PENDING_ITEM then
        local result, err = self.acquisition_service:reject_pending(command.player_id or self.local_player_id)
        if not result then return nil, err end
        self:emit(Event.INVENTORY_CHANGED, { player_id = command.player_id or self.local_player_id, operation = command_type })
        return result
    elseif command_type == Command.SET_READY then
        if self.run_state == Constants.run_states.MAP then
            local opened, open_err = self:enter_preparation()
            if not opened then return nil, open_err end
        end
        return self:set_player_ready(command.player_id or self.local_player_id, true)
    elseif command_type == Command.CANCEL_READY then
        return self:set_player_ready(command.player_id or self.local_player_id, false)
    elseif command_type == Command.LOADOUT_COMMIT then
        return self:commit_loadout(command.player_id or self.local_player_id, command.commit or command.descriptor)
    elseif command_type == Command.RETURN_TO_MAP then
        return self:return_to_map()
    elseif command_type == Command.COMPLETE_BATTLE then
        return self:complete_battle(command.result or command)
    elseif command_type == Command.BATTLE_FAILURE_VOTE then
        return self:vote_battle_failure(command.choice, command.player_id)
    elseif command_type == Command.NATIVE_LEAVE_BATTLE then
        -- This is a transport-level barrier for native LAN rooms. It does
        -- not mutate the run on its own; Bootstrap turns the event into the
        -- same menu transition on both peers.
        return self:emit("NATIVE_PEER_LEAVE", {
            player_id = tonumber(command.player_id) or 0,
        })
    elseif command_type == Command.START_ENCOUNTER_AT then
        -- The map vote has already selected the encounter on both peers.
        -- This command is only a synchronized start barrier; Bootstrap owns
        -- the delayed native stage transition.
        return self:emit(Event.ENCOUNTER_START_AT, {
            start_at = tonumber(command.start_at),
            node_id = command.node_id,
            encounter_id = command.encounter_id,
            content_seed = command.content_seed,
            room_generation = command.room_generation,
            player_id = tonumber(command.player_id) or 0,
        })
    elseif command_type == Command.ENCOUNTER_READY then
        return self:emit(Event.ENCOUNTER_READY, {
            node_id = tonumber(command.node_id),
            encounter_id = command.encounter_id,
            content_seed = command.content_seed,
            room_generation = command.room_generation,
            player_id = tonumber(command.player_id) or 0,
        })
    elseif command_type == Command.DEBUG_GOD then
        local player_id = command.player_id or 1
        if command.toggle then
            self.god_mode[player_id] = not self.god_mode[player_id]
        else
            self.god_mode[player_id] = command.enabled == true
        end
        return self:emit(Event.DEBUG_CHANGED, { command = command, god = self.god_mode[player_id] })
    elseif command_type == Command.DEBUG_GOTO then
        return self:debug_goto(command.node_id)
    elseif command_type == Command.DEBUG_MAP_REVEAL then
        self.map:reveal()
        return self:emit(Event.DEBUG_CHANGED, { command = command, map_revealed = true })
    end
    return nil, "unknown command: " .. tostring(command_type)
end

return GameSession
