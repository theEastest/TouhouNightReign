local BattleResult = require("tnr.battle.battle_result")
local Command = require("tnr.core.command")

local BattleManager = {}
BattleManager.__index = BattleManager

function BattleManager.new(session)
    return setmetatable({ session = session, active = nil }, BattleManager)
end

function BattleManager:begin(encounter)
    self.active = {
        encounter_id = encounter.id,
        encounter_type = encounter.type,
        battle_score = 0,
        money_collected = 0,
        life_lost = 0,
        bomb_used = 0,
        per_player = {},
    }
    return self.active
end

function BattleManager:ensure_active()
    assert(self.active, "no active battle")
    return self.active
end

function BattleManager:add_score(amount, player_id, source)
    local battle = self:ensure_active()
    amount = math.max(0, amount or 0)
    battle.battle_score = battle.battle_score + amount
    player_id = player_id or 1
    battle.per_player[player_id] = battle.per_player[player_id] or { score = 0, graze = 0, life_lost = 0, bomb_used = 0 }
    battle.per_player[player_id].score = battle.per_player[player_id].score + amount
    self.session:dispatch({ type = Command.ADD_SCORE, player_id = player_id, amount = amount, source = source or "battle" })
end

function BattleManager:collect_money(amount, player_id, source)
    local battle = self:ensure_active()
    amount = math.max(0, amount or 0)
    battle.money_collected = battle.money_collected + amount
    self.session:dispatch({ type = Command.ADD_MONEY, player_id = player_id or 1, amount = amount, source = source or "item" })
end

function BattleManager:record_life_lost(amount)
    local battle = self:ensure_active()
    battle.life_lost = battle.life_lost + math.max(0, amount or 1)
end

function BattleManager:record_player_life_lost(player_id, amount)
    local battle = self:ensure_active()
    amount = math.max(0, amount or 1)
    battle.life_lost = battle.life_lost + amount
    battle.per_player[player_id] = battle.per_player[player_id] or { score = 0, graze = 0, life_lost = 0, bomb_used = 0 }
    battle.per_player[player_id].life_lost = battle.per_player[player_id].life_lost + amount
end

function BattleManager:record_graze(player_id, amount)
    local battle = self:ensure_active()
    amount = math.max(0, amount or 1)
    battle.per_player[player_id] = battle.per_player[player_id] or { score = 0, graze = 0, life_lost = 0, bomb_used = 0 }
    battle.per_player[player_id].graze = battle.per_player[player_id].graze + amount
    self.session:get_player(player_id):add_graze(amount)
end

function BattleManager:use_bomb(player_id)
    local battle = self:ensure_active()
    local player = self.session:get_player(player_id or 1)
    if not player or player.bomb <= 0 then
        return false
    end
    battle.bomb_used = battle.bomb_used + 1
    battle.per_player[player_id or 1] = battle.per_player[player_id or 1] or { score = 0, graze = 0, life_lost = 0, bomb_used = 0 }
    battle.per_player[player_id or 1].bomb_used = battle.per_player[player_id or 1].bomb_used + 1
    self.session:dispatch({ type = Command.ADD_BOMB, player_id = player_id or 1, amount = -1, source = "battle" })
    return true
end

function BattleManager:complete(clear_state, options)
    local battle = self:ensure_active()
    options = options or {}
    local result = BattleResult.new({
        encounter_id = battle.encounter_id,
        encounter_type = battle.encounter_type,
        clear_state = clear_state == true,
        battle_score = battle.battle_score,
        money_collected = battle.money_collected,
        life_lost = battle.life_lost,
        bomb_used = battle.bomb_used,
        reward_eligible = options.reward_eligible == true,
        debug_clear = options.debug_clear == true,
        player_id = options.player_id or 1,
        per_player_result = battle.per_player,
        -- Reference stage score/money and perfect-clear result.
        stage_score = options.stage_score,
        stage_money = options.stage_money,
        perfect_counts = options.perfect_counts,
        perfect_total_cards = options.perfect_total_cards,
    })
    self.active = nil
    return self.session:dispatch({ type = Command.COMPLETE_BATTLE, result = result })
end

return BattleManager
