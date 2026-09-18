local EquipmentInstance = require("tnr.equipment.equipment_instance")
local Constants = require("tnr.core.constants")

local ShopService = {}
ShopService.__index = ShopService

local OFFER_TEMPLATES = {
    { kind = "LIFE", price = 0, amount = 1 },
    { kind = "BOMB", price = 0, amount = 2 },
}

local function stable_hash(seed)
    local text, hash = tostring(seed or ""), 0
    for index = 1, #text do hash = (hash * 131 + text:byte(index)) % 2147483647 end
    return hash
end

function ShopService.new(session)
    return setmetatable({ session = session, node_id = nil, offers = {}, purchases = {}, ready = {} }, ShopService)
end

function ShopService:open(node)
    assert(node, "shop node is required")
    self.node_id = node.id
    local seed = stable_hash(string.format("%s:%s:%s", self.session.run_seed, node.id, node.content_seed or 0))
    local definitions = self.session.equipment_registry:all()
    local function ids_for(kind)
        local ids = {}
        for id, definition in pairs(definitions) do
            if definition.test_only ~= true and definition.equipment_type == kind then ids[#ids + 1] = id end
        end
        table.sort(ids)
        return ids
    end
    local supports, weapons, modifiers = ids_for("SUPPORT"), ids_for("WEAPON"), {}
    for id, definition in pairs(definitions) do
        if definition.test_only ~= true
                and (definition.equipment_type == "SELF_MODIFIER" or definition.equipment_type == "SUPPORT_MODIFIER") then
            modifiers[#modifiers + 1] = id
        end
    end
    table.sort(modifiers)
    local function equipment_offer(ids, salt)
        if #ids == 0 then return { kind = "BOMB", price = 0, amount = 1 } end
        return { kind = "EQUIPMENT", definition_id = ids[(seed + salt) % #ids + 1], price = 0 }
    end
    self.offers = {
        { kind = "LIFE", price = 0, amount = 1, slot = 1 },
        { kind = "BOMB", price = 0, amount = 2, slot = 2 },
        equipment_offer(supports, 3),
        equipment_offer(weapons, 5),
        equipment_offer(modifiers, 7),
    }
    for index, offer in ipairs(self.offers) do offer.slot = index end
    self.purchases = {}
    self.ready = {}
    return self.offers
end

function ShopService:get_offers()
    return self.offers
end

function ShopService:purchase(player_id, slot)
    if self.session.run_state ~= Constants.run_states.SHOP then return nil, "NOT_SHOP" end
    player_id, slot = tonumber(player_id), tonumber(slot)
    local player, offer = self.session:get_player(player_id), self.offers[slot]
    if not player then return nil, "UNKNOWN_PLAYER" end
    if not offer then return nil, "UNKNOWN_OFFER" end
    local price = math.max(0, tonumber(offer.price) or 0)
    self.purchases[player_id] = self.purchases[player_id] or {}
    if self.purchases[player_id][slot] then return nil, "ALREADY_PURCHASED" end
    if player.money < price then return nil, "INSUFFICIENT_MONEY" end
    if offer.kind == "LIFE" then
        self.session:add_money(player_id, -price, "shop")
        self.session.party:add_team_life(offer.amount or 1)
        self.session:emit("LIFE_CHANGED", { player_id = player_id, amount = offer.amount or 1, source = "shop", team_life = self.session.party.team_life })
    elseif offer.kind == "LIFE_FRAGMENT" then
        self.session:add_money(player_id, -price, "shop")
        self.session.party:add_life_fragments(offer.amount or 1)
    elseif offer.kind == "BOMB" then
        self.session:add_money(player_id, -price, "shop")
        self.session:add_bomb(player_id, offer.amount or 1, "shop")
    elseif offer.kind == "EQUIPMENT" then
        local definition = self.session.equipment_registry:get(offer.definition_id)
        if not definition then return nil, "UNKNOWN_DEFINITION" end
        local instance = EquipmentInstance.new(definition, player_id)
        local acquired, err = self.session.acquisition_service:acquire(player_id, instance)
        if not acquired then return nil, err or "INVENTORY_FULL" end
        self.session:add_money(player_id, -price, "shop")
    else
        return nil, "UNSUPPORTED_OFFER"
    end
    self.purchases[player_id][slot] = true
    return true
end

function ShopService:set_ready(player_id, value)
    if self.session.run_state ~= Constants.run_states.SHOP then return nil, "NOT_SHOP" end
    player_id = tonumber(player_id)
    if not self.session:get_player(player_id) then return nil, "UNKNOWN_PLAYER" end
    if self.session.acquisition_service:get_pending(player_id) then return nil, "PENDING_ACQUISITION" end
    self.ready[player_id] = value == true
    for _, candidate_id in ipairs(self.session.party.player_ids or {}) do
        if self.ready[candidate_id] ~= true then return false end
    end
    self.session.run_state = Constants.run_states.MAP
    self.session.shop_service = nil
    self.session:emit("SHOP_CLOSED", { node_id = self.node_id })
    self.session:emit("MAP_ENTERED", { node_id = self.session.current_node_id })
    return true
end

return ShopService
