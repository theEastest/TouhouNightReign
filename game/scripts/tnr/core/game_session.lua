local Constants = require("tnr.core.constants")
local Command = require("tnr.core.command")
local Event = require("tnr.core.event")
local RNG = require("tnr.core.rng")
local PlayerManager = require("tnr.core.player_manager")
local PartyState = require("tnr.core.party_state")
local MapGenerator = require("tnr.map.map_generator")

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
        run_state = Constants.run_states.MAP,
        map = nil,
        current_node_id = nil,
        players = PlayerManager.new(),
        party = PartyState.new({}, nil),
        money = 0,
        total_score = 0,
        current_encounter = nil,
        battle_result = nil,
        visited_nodes = {},
        event_log = {},
        listeners = {},
        rng = {},
    }, GameSession)
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
    self.current_node_id = self.map.current_node_id
    self.players = PlayerManager.new()
    self.players:add_player(1, { character_id = "reimu", life = 3, bomb = 3 })
    self.party = PartyState.new({ 1 }, self.current_node_id)
    self.money = 0
    self.total_score = 0
    self.current_encounter = nil
    self.battle_result = nil
    self.visited_nodes = { [self.current_node_id] = true }
    self.event_log = {}
    self.rng = {
        map = RNG.new(self.run_seed),
        encounter = RNG.new(self.run_seed + 1),
        reward = RNG.new(self.run_seed + 2),
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

function GameSession:select_node(node_id, player_id)
    if self.run_state ~= Constants.run_states.MAP then
        return nil, "当前不在地图状态"
    end
    local node, err = self.map:select_node(node_id)
    if not node then
        return nil, err
    end
    self.current_node_id = node.id
    self.party:set_current_node(node.id)
    self.visited_nodes[node.id] = true
    self:emit(Event.NODE_SELECTED, { node_id = node.id, player_id = player_id or 1, node_type = node.type })

    if node.type == Constants.node_types.ENEMY or node.type == Constants.node_types.BOSS then
        self.run_state = Constants.run_states.ENCOUNTER
        self.current_encounter = {
            id = node.encounter_id,
            node_id = node.id,
            type = node.type,
            stage_id = node.type == Constants.node_types.BOSS and "test_boss_stage" or "test_enemy_stage",
        }
        self:emit(Event.ENCOUNTER_STARTED, { encounter = self.current_encounter })
    elseif node.type == Constants.node_types.SHOP or node.type == Constants.node_types.EVENT then
        self.run_state = Constants.run_states.PLACEHOLDER
        self:emit(Event.PLACEHOLDER_ENTERED, { node_id = node.id, node_type = node.type })
    end
    return node
end

function GameSession:return_to_map()
    if not self.map then
        return nil, "没有可返回的地图"
    end
    self.run_state = Constants.run_states.MAP
    self.current_encounter = nil
    self.battle_result = nil
    self:emit(Event.MAP_ENTERED, { node_id = self.current_node_id })
    return self.map:get_current_node()
end

function GameSession:dispatch(command)
    assert(type(command) == "table" and command.type, "invalid command")
    local command_type = command.type
    if command_type == Command.SELECT_NODE then
        return self:select_node(command.node_id, command.player_id)
    elseif command_type == Command.ADD_MONEY then
        return self:add_money(command.player_id or 1, command.amount, command.source)
    elseif command_type == Command.ADD_SCORE then
        return self:add_score(command.player_id or 1, command.amount, command.source)
    elseif command_type == Command.ADD_LIFE then
        return self:add_life(command.player_id or 1, command.amount, command.source)
    elseif command_type == Command.ADD_BOMB then
        return self:add_bomb(command.player_id or 1, command.amount, command.source)
    elseif command_type == Command.RETURN_TO_MAP then
        return self:return_to_map()
    end
    return nil, "unknown command: " .. tostring(command_type)
end

return GameSession

