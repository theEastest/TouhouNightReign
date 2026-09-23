local BattleResult = {}

function BattleResult.new(values)
    values = values or {}
    return {
        encounter_id = values.encounter_id,
        encounter_type = values.encounter_type,
        clear_state = values.clear_state or false,
        battle_score = values.battle_score or 0,
        money_collected = values.money_collected or 0,
        life_lost = values.life_lost or 0,
        bomb_used = values.bomb_used or 0,
        reward_eligible = values.reward_eligible == true,
        debug_clear = values.debug_clear == true,
        per_player_result = values.per_player_result or {},
        -- Reference-project stage score and money for this stage.
        stage_score = values.stage_score or 0,
        stage_money = values.stage_money or 0,
        -- Perfect-clear result: player_id -> number of perfectly cleared cards.
        perfect_counts = values.perfect_counts or {},
        perfect_total_cards = values.perfect_total_cards or 0,
    }
end

return BattleResult
