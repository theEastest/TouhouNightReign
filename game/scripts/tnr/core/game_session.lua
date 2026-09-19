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
local CapacityProgression = require("tnr.character.runtime.capacity_progression")
local LegacyStateAdapter = require("tnr.core.legacy_state_adapter")
local LoadoutCommit = require("tnr.multiplayer.loadout_commit")
local ShopService = require("tnr.shop.shop_service")
local RelicRuntime = require("tnr.relic.relic_runtime")
local EquipmentRewardService = require("tnr.reward.equipment_reward_service")

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
        reward_service = nil,
        capacity_progression = CapacityProgression.new(options.capacity_thresholds),
        encounter_manager = EncounterManager.new(EncounterDefinitions),
        god_mode = {},
        player_count = math.max(1, math.min(2, math.floor(options.player_count or 1))),
        local_player_id = options.local_player_id or 1,
        room_generation = nil,
        loadout_commits = {},
        shop_service = nil,
        relic_catalog = Phase1Catalog.relics,
        relic_runtime = nil,
        relic_choices = {},
        reward_choices = {},
        reward_claims = {},
        reward_result = nil,
        reward_required = 1,
        reward_guaranteed_definition_id = nil,
        pending_reward_claims = {},
    }, GameSession)
    self.legacy_state_adapter = LegacyStateAdapter.new(self)
    local equipment_reward_pool = options.equipment_reward_pool
    if not equipment_reward_pool then
        equipment_reward_pool = {}
        for definition_id, definition in pairs(self.equipment_registry:all()) do
            if definition.test_only ~= true and definition.equipment_type == "WEAPON" then
                equipment_reward_pool[#equipment_reward_pool + 1] = definition_id
            end
        end
        table.sort(equipment_reward_pool)
    end
    self.reward_service = RewardService.new(options.reward_thresholds, {
        equipment_pool = equipment_reward_pool,
        equipment_registry = self.equipment_registry,
    })
    self.loadout_service = LoadoutService.new(self, self.equipment_registry)
    self.acquisition_service = AcquisitionService.new(self)
    self.equipment_reward_service = EquipmentRewardService.new(self)
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
    run_seed = tonumber(run_seed) or self.default_seed
    if not run_seed then
        local seconds = os.time()
        local micros = math.floor((os.clock() % 1) * 1000000)
        run_seed = (seconds * 1103515245 + micros) % 2147483647
    end
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
    self.shop_service = nil
    self.relic_runtime = RelicRuntime.new(self)
    self.relic_choices = {}
    self.reward_choices = {}
    self.reward_claims = {}
    self.reward_result = nil
    self.reward_required = 1
    self.reward_guaranteed_definition_id = nil
    self.pending_reward_claims = {}
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
    for _, player_id in ipairs(player_ids) do
        self.relic_runtime:emit("ON_BATTLE_START", player_id)
    end
    return self
end

-- The host selects the seed once and sends it to the peer. Hosts dispatch
-- their own command synchronously, so matching seeds must not rebuild state.
function GameSession:set_run_seed(run_seed)
    run_seed = tonumber(run_seed)
    if not run_seed or run_seed % 1 ~= 0 or run_seed < 1 or run_seed > 2147483647 then
        return nil, "INVALID_RUN_SEED"
    end
    run_seed = math.floor(run_seed)
    if self.run_seed == run_seed and self.map then return self.run_seed end
    self:start_new(run_seed)
    return self.run_seed
end

function GameSession:get_player(player_id)
    return self.players:get_player(player_id)
end

function GameSession:add_money(player_id, amount, source)
    local player = assert(self:get_player(player_id), "unknown player")
    amount = tonumber(amount) or 0
    player:add_money(amount)
    -- Keep the legacy aggregate in step with both rewards and shop spending.
    self.money = math.max(0, self.money + amount)
    return self:emit("MONEY_ADDED", { player_id = player_id, amount = amount, source = source })
end

function GameSession:add_score(player_id, amount, source)
    local player = assert(self:get_player(player_id), "unknown player")
    player:add_score(amount)
    self.total_score = self.total_score + math.max(0, amount or 0)
    local changed, capacity, level = self.capacity_progression:apply(player)
    self:emit("SCORE_ADDED", { player_id = player_id, amount = amount, source = source })
    if changed then
        self:emit("CAPACITY_CHANGED", {
            player_id = player_id, capacity = capacity, level = level, source = source,
        })
    end
    return self.event_log[#self.event_log]
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
    -- In a networked room the host (local player 1) is the only authority
    -- that advances the map. The client records votes locally but waits for
    -- the host's SYNC_NODE command so both peers can never diverge onto
    -- different nodes from a late or reordered vote packet.
    if self.player_count > 1 and self.local_player_id ~= 1 then
        return vote_event
    end
    return self:select_node(agreed_node_id, player_id)
end

function GameSession:_advance_node(node, player_id)
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
        if self.relic_runtime then
            for _, encounter_player_id in ipairs(self.party.player_ids or {}) do
                self.relic_runtime:emit("ON_BATTLE_START", encounter_player_id)
            end
        end
        self:emit(Event.ENCOUNTER_STARTED, { encounter = self.current_encounter })
    elseif node.type == Constants.node_types.SHOP then
        self.run_state = Constants.run_states.SHOP
        self.shop_service = ShopService.new(self)
        self.shop_service:open(node)
        self:emit(Event.SHOP_ENTERED, { node_id = node.id, offers = self.shop_service:get_offers() })
    elseif node.type == Constants.node_types.EVENT then
        self.run_state = Constants.run_states.PLACEHOLDER
        self:emit(Event.PLACEHOLDER_ENTERED, { node_id = node.id, node_type = node.type })
    end
    return node
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
    return self:_advance_node(node, player_id)
end

function GameSession:sync_node(node_id, player_id)
    -- Authoritative node mirror for a network client. The host already
    -- validated the vote and advanced; the client simply follows the exact
    -- node so both peers stay on the same node even when a late vote or
    -- reordered packet would otherwise make `is_adjacent` disagree.
    if self.run_state ~= Constants.run_states.MAP
            and self.run_state ~= Constants.run_states.MAP_PREPARATION then
        return nil, "当前不在地图状态"
    end
    node_id = tonumber(node_id)
    if node_id == self.current_node_id then
        -- Already on the authoritative node (for example the host's own
        -- local dispatch of its broadcast). Do not re-emit node/encounter
        -- events for a node we are already standing on.
        return self.map:get_node(node_id)
    end
    local node, err = self.map:force_select_node(node_id)
    if not node then
        return nil, err
    end
    return self:_advance_node(node, player_id)
end

function GameSession:shop_purchase(player_id, slot)
    if not self.shop_service then return nil, "NO_SHOP" end
    local result, err = self.shop_service:purchase(player_id, slot)
    if result then self:emit(Event.INVENTORY_CHANGED, { player_id = player_id, operation = "SHOP_PURCHASE", slot = slot }) end
    return result, err
end

function GameSession:shop_ready(player_id)
    if not self.shop_service then return nil, "NO_SHOP" end
    return self.shop_service:set_ready(player_id, true)
end

function GameSession:choose_relic(player_id, relic_id)
    if self.run_state ~= Constants.run_states.RELIC_SELECT then return nil, "NOT_RELIC_SELECT" end
    player_id = tonumber(player_id) or self.local_player_id
    local choices = self.relic_choices[player_id] or {}
    local allowed = false
    for _, candidate in ipairs(choices) do if candidate == relic_id then allowed = true break end end
    if not allowed then return nil, "INVALID_RELIC_CHOICE" end
    local result, err = self.relic_runtime:add(player_id, relic_id)
    if not result then return nil, err end
    self.relic_choices[player_id] = { selected = relic_id }
    self:emit(Event.RELIC_CHANGED, { player_id = player_id, relic_id = relic_id })
    for _, candidate_id in ipairs(self.party.player_ids or {}) do
        local selected = self.relic_choices[candidate_id]
        if not selected or not selected.selected then return true end
    end
    self.run_state = Constants.run_states.RUN_CLEAR
    self:emit(Event.RUN_CLEARED, { result = self.battle_result, relics = self.relic_choices })
    return true
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
    local expected_registry_hash = self.equipment_registry and self.equipment_registry.hash
        and self.equipment_registry:hash() or nil
    local ok, err = LoadoutCommit.validate(descriptor, expected_registry_hash)
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
    values = values or {}
    local result = BattleResult.new(values)
    if self.current_encounter then
        result.encounter_id = result.encounter_id or self.current_encounter.id
        result.encounter_type = result.encounter_type or self.current_encounter.type
    end
    self.battle_result = result
    if result.clear_state then
        local encounter = self.current_encounter
        local is_boss = encounter and encounter.type == Constants.node_types.BOSS
        self:emit(Event.BATTLE_CLEARED, { result = result })
        local reward = { money = 0, life = 0, bomb = 0, equipment_definition_id = nil }
        if result.reward_eligible then
            reward = self.reward_service:calculate(result)
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
        end
        if self.relic_runtime then
            for _, encounter_player_id in ipairs(self.party.player_ids or {}) do
                self.relic_runtime:emit("ON_BATTLE_CLEAR", encounter_player_id)
                if is_boss then self.relic_runtime:emit("ON_BOSS_CLEAR", encounter_player_id) end
            end
        end
        if is_boss then
            self.run_state = Constants.run_states.RELIC_SELECT
            -- Preserve the result for the clear screen, but invalidate the
            -- native room before notifying listeners so delayed packets from
            -- this encounter cannot contaminate a future run.
            self.current_encounter = nil
            self.room_generation = nil
            self.relic_choices = {}
            local relic_ids = { "reimu_initial_relic_plus", "test_relic", "test_relic_bonus" }
            for _, player_id in ipairs(self.party.player_ids or {}) do
                self.relic_choices[player_id] = {}
                for index, relic_id in ipairs(relic_ids) do
                    self.relic_choices[player_id][index] = relic_id
                end
            end
            self:emit(Event.RELIC_CHOICE_ENTERED, { choices = self.relic_choices })
        elseif encounter and (encounter.type == Constants.node_types.ENEMY
                or encounter.type == Constants.node_types.ELITE) then
            self.run_state = Constants.run_states.REWARD
            self.current_encounter = nil
            self.room_generation = nil
            self.reward_result = reward
            local choices, guaranteed_id = self.reward_service:generate_choices(result, self.run_seed)
            self.reward_choices = choices
            self.reward_required = (encounter.type == Constants.node_types.ELITE) and 2 or 1
            self.reward_guaranteed_definition_id = guaranteed_id
            self.reward_claims = {}
            if guaranteed_id then
                for _, reward_player_id in ipairs(self.party.player_ids or {}) do
                    local guaranteed_result, guaranteed_err = self.equipment_reward_service:grant(guaranteed_id, reward_player_id)
                    if guaranteed_result then
                        self:emit(Event.REWARD_GRANTED, {
                            result = result,
                            reward = { kind = "GUARANTEED", definition_id = guaranteed_id,
                                equipment = guaranteed_result.instance:to_table(),
                                equipment_acquired = guaranteed_result.acquired,
                                equipment_pending = guaranteed_result.pending,
                                acquisition_error = guaranteed_result.error },
                        })
                    else
                        self:emit(Event.REWARD_GRANTED, {
                            result = result,
                            reward = { kind = "GUARANTEED", definition_id = guaranteed_id,
                                acquisition_error = guaranteed_err },
                        })
                    end
                end
            end
            self:emit(Event.REWARD_CHOICE_ENTERED, {
                result = result,
                reward = reward,
                choices = self.reward_choices,
            })
            -- A peer can receive the other player's selection a few frames
            -- before its local stage reports clear. Replay that command after
            -- the local reward screen is created instead of dropping it.
            local pending = self.pending_reward_claims
            self.pending_reward_claims = {}
            for pending_player_id, pending_choice_index in pairs(pending) do
                self:claim_reward(pending_player_id, pending_choice_index)
            end
        else
            -- AcquisitionService deliberately accepts rewards only after the
            -- Legacy room has handed control back to the map.
            self:return_to_map()
        end
        if reward.equipment_definition_id and not (encounter and (encounter.type == Constants.node_types.ENEMY
                or encounter.type == Constants.node_types.ELITE)) then
            local player_id = tonumber(values.player_id) or self.local_player_id or 1
            local equipment_result, equipment_err = self.equipment_reward_service:grant(
                reward.equipment_definition_id, player_id)
            if equipment_result then
                reward.equipment = equipment_result.instance:to_table()
                reward.equipment_acquired = equipment_result.acquired
                reward.equipment_pending = equipment_result.pending
                reward.acquisition_error = equipment_result.error
            else
                reward.acquisition_error = equipment_err
            end
        end
        self:emit(Event.REWARD_GRANTED, { result = result, reward = reward })
    else
        self.run_state = Constants.run_states.RUN_FAILED
        self:emit(Event.BATTLE_FAILED, { result = result })
    end
    return result
end

function GameSession:claim_reward(player_id, choice_index)
    if self.run_state ~= Constants.run_states.REWARD then
        return nil, "NOT_REWARD_SELECT"
    end
    player_id = tonumber(player_id) or self.local_player_id or 1
    choice_index = tonumber(choice_index)
    if not choice_index or choice_index % 1 ~= 0 or choice_index < 1 or choice_index > #self.reward_choices then
        return nil, "INVALID_REWARD_CHOICE"
    end
    local valid_player = false
    for _, candidate_id in ipairs(self.party.player_ids or {}) do
        if candidate_id == player_id then valid_player = true break end
    end
    if not valid_player then return nil, "UNKNOWN_PLAYER" end
    local choice = self.reward_choices[choice_index]
    if not choice then return nil, "REWARD_NOT_AVAILABLE" end
    self.reward_claims[player_id] = self.reward_claims[player_id] or {}
    if #self.reward_claims[player_id] >= self.reward_required then return self.reward_claims[player_id] end
    for _, previous in ipairs(self.reward_claims[player_id]) do
        if previous.choice_index == choice_index then return nil, "REWARD_ALREADY_SELECTED" end
    end
    local definition_id = choice.definition_id
    local equipment_result, equipment_err
    if choice.kind == "EQUIPMENT" then
        equipment_result, equipment_err = self.equipment_reward_service:grant(definition_id, player_id)
        if not equipment_result then return nil, equipment_err end
    elseif choice.kind == "RESOURCE" then
        if choice.resource == "bomb" then
            self:add_bomb(player_id, choice.amount or 1, "reward")
        elseif choice.resource == "life" then
            self.party:add_team_life(choice.amount or 1)
            self:emit(Event.LIFE_CHANGED, { player_id = player_id, amount = choice.amount or 1, source = "reward", team_life = self.party.team_life })
        else
            return nil, "UNKNOWN_REWARD_RESOURCE"
        end
    else
        return nil, "UNKNOWN_REWARD_KIND"
    end
    local claim = {
        player_id = player_id,
        choice_index = choice_index,
        definition_id = definition_id,
        kind = choice.kind,
        resource = choice.resource,
        amount = choice.amount,
        equipment = equipment_result and equipment_result.instance:to_table() or nil,
        acquired = equipment_result and equipment_result.acquired or true,
        pending = equipment_result and equipment_result.pending or false,
        error = equipment_result and equipment_result.error or nil,
    }
    self.reward_claims[player_id][#self.reward_claims[player_id] + 1] = claim
    self:emit(Event.REWARD_CLAIMED, { claim = claim, choices = self.reward_choices })
    local all_claimed = #(self.party.player_ids or {}) > 0
    for _, candidate_id in ipairs(self.party.player_ids or {}) do
        if #(self.reward_claims[candidate_id] or {}) < self.reward_required then all_claimed = false break end
    end
    if all_claimed then
        local reward = self.reward_result or { money = 0, life = 0, bomb = 0 }
        self.reward_result = nil
        self.reward_choices = {}
        self.reward_claims = {}
        self.reward_required = 1
        self.reward_guaranteed_definition_id = nil
        self.pending_reward_claims = {}
        self:return_to_map()
        self:emit(Event.REWARD_GRANTED, { reward = reward, claim = claim })
    end
    return claim
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
    elseif node.type == Constants.node_types.SHOP then
        self.run_state = Constants.run_states.SHOP
        self.shop_service = ShopService.new(self)
        self.shop_service:open(node)
        self:emit(Event.SHOP_ENTERED, { node_id = node.id, offers = self.shop_service:get_offers(), debug = true })
    elseif node.type == Constants.node_types.EVENT then
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
    elseif command_type == Command.SYNC_NODE then
        return self:sync_node(command.node_id, command.player_id)
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
    elseif command_type == Command.SHOP_PURCHASE then
        return self:shop_purchase(command.player_id or self.local_player_id, command.slot)
    elseif command_type == Command.SHOP_READY then
        return self:shop_ready(command.player_id or self.local_player_id)
    elseif command_type == Command.RELIC_CHOICE then
        return self:choose_relic(command.player_id or self.local_player_id, command.relic_id)
    elseif command_type == Command.CLAIM_REWARD then
        if self.run_state ~= Constants.run_states.REWARD then
            local pending_player_id = tonumber(command.player_id) or self.local_player_id
            self.pending_reward_claims[pending_player_id] = tonumber(command.choice_index)
            return false, "REWARD_PENDING"
        end
        return self:claim_reward(command.player_id or self.local_player_id, command.choice_index)
    elseif command_type == Command.SET_READY then
        if self.run_state == Constants.run_states.MAP then
            local opened, open_err = self:enter_preparation()
            if not opened then return nil, open_err end
        end
        local player_id = command.player_id or self.local_player_id
        if command.commit then
            local committed, commit_err = self:commit_loadout(player_id, command.commit)
            if not committed then return nil, commit_err end
        end
        return self:set_player_ready(player_id, true)
    elseif command_type == Command.CANCEL_READY then
        return self:set_player_ready(command.player_id or self.local_player_id, false)
    elseif command_type == Command.SET_RUN_SEED then
        return self:set_run_seed(command.run_seed)
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
