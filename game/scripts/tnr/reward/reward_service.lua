local RewardService = {}
RewardService.__index = RewardService

function RewardService.new(config)
    return setmetatable({
        thresholds = config or {
            { score = 10000, money = 100 },
            { score = 50000, bomb = 1 },
            { score = 100000, life = 1 },
        },
    }, RewardService)
end

function RewardService:calculate(battle_result)
    local reward = { money = 0, life = 0, bomb = 0 }
    if not battle_result.reward_eligible then
        return reward
    end
    for _, threshold in ipairs(self.thresholds) do
        if battle_result.battle_score >= threshold.score then
            reward.money = reward.money + (threshold.money or 0)
            reward.life = reward.life + (threshold.life or 0)
            reward.bomb = reward.bomb + (threshold.bomb or 0)
        end
    end
    return reward
end

return RewardService

