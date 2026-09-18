local PlayerState = {}
PlayerState.__index = PlayerState

local ReimuDefinition = require("tnr.character.reimu_definition")
local Loadout = require("tnr.character.loadout")
local Inventory = require("tnr.equipment.inventory")
local Immutable = require("tnr.core.immutable")

function PlayerState.new(player_id, options)
    options = options or {}
    local character_definition = options.character_definition or ReimuDefinition
    local inventory = options.inventory or Inventory.new(character_definition.inventory_slots)
    local loadout = options.loadout or Loadout.new(character_definition, { inventory = inventory })
    if not loadout.inventory then
        loadout.inventory = inventory
    end
    return setmetatable({
        player_id = assert(player_id, "player_id is required"),
        money = options.money or 0,
        score = options.score or 0,
        graze = options.graze or 0,
        life = options.life or 3,
        bomb = options.bomb or 3,
        alive = options.alive ~= false,
        character_id = options.character_id or "reimu",
        respawning = options.respawning == true,
        respawn_timer = tonumber(options.respawn_timer) or 0,
        map_ready = options.map_ready == true,
        base_capacity = tonumber(options.base_capacity) or character_definition.base_capacity,
        current_capacity = tonumber(options.current_capacity) or character_definition.base_capacity,
        capacity_level = tonumber(options.capacity_level) or 0,
        relics = options.relics or {},
        loadout = loadout,
        legacy_life_compat = true,
    }, PlayerState)
end

function PlayerState:add_money(amount)
    self.money = math.max(0, self.money + (amount or 0))
end

function PlayerState:add_score(amount)
    self.score = math.max(0, self.score + (amount or 0))
end

function PlayerState:add_life(amount)
    self.life = math.max(0, self.life + (amount or 0))
    self.alive = self.life > 0
end

function PlayerState:add_bomb(amount)
    self.bomb = math.max(0, self.bomb + (amount or 0))
end

function PlayerState:add_graze(amount)
    self.graze = math.max(0, self.graze + (amount or 0))
end

function PlayerState:set_respawning(value, timer)
    self.respawning = value == true
    self.respawn_timer = math.max(0, tonumber(timer) or 0)
    if self.respawning then
        self.alive = false
    end
end

function PlayerState:set_map_ready(value)
    self.map_ready = value == true
end

function PlayerState:set_capacity(value, level)
    self.current_capacity = math.max(0, tonumber(value) or self.base_capacity)
    if level ~= nil then
        self.capacity_level = math.max(0, tonumber(level) or 0)
    end
end

function PlayerState:to_table()
    return {
        player_id = self.player_id,
        character_id = self.character_id,
        money = self.money,
        score = self.score,
        graze = self.graze,
        bomb = self.bomb,
        life = self.life,
        alive = self.alive,
        respawning = self.respawning,
        respawn_timer = self.respawn_timer,
        map_ready = self.map_ready,
        base_capacity = self.base_capacity,
        current_capacity = self.current_capacity,
        capacity_level = self.capacity_level,
        relics = self.relics,
        loadout = self.loadout and self.loadout:to_table() or nil,
        legacy_life_compat = self.legacy_life_compat,
    }
end

function PlayerState.from_table(data, character_definition)
    assert(type(data) == "table", "player state data is required")
    character_definition = character_definition or ReimuDefinition
    local inventory
    if data.loadout and data.loadout.inventory then
        inventory = Inventory.from_table(data.loadout.inventory)
    end
    local loadout
    if data.loadout then
        loadout = Loadout.from_table(data.loadout, character_definition, inventory)
    end
    return PlayerState.new(data.player_id, {
        character_id = data.character_id,
        character_definition = character_definition,
        money = data.money,
        score = data.score,
        graze = data.graze,
        bomb = data.bomb,
        life = data.life,
        alive = data.alive,
        respawning = data.respawning,
        respawn_timer = data.respawn_timer,
        map_ready = data.map_ready,
        base_capacity = data.base_capacity,
        current_capacity = data.current_capacity,
        capacity_level = data.capacity_level,
        relics = data.relics,
        loadout = loadout,
        inventory = inventory,
    })
end

return PlayerState
