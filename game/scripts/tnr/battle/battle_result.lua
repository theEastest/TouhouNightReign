local BattleResult = {}

function BattleResult.new(values)
    values = values or {}
    return {
        encounter_id = values.encounter_id,
        clear_state = values.clear_state or false,
        battle_score = values.battle_score or 0,
        money_collected = values.money_collected or 0,
        life_lost = values.life_lost or 0,
        bomb_used = values.bomb_used or 0,
        reward_eligible = values.reward_eligible == true,
        debug_clear = values.debug_clear == true,
        per_player_result = values.per_player_result or {},
    }
end

return BattleResult

