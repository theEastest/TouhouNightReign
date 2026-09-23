local RewardService = {}
RewardService.__index = RewardService

function RewardService.new(config, options)
    options = options or {}
    return setmetatable({
        -- Additive thresholds: every satisfied tier contributes, so a higher
        -- stage score grants the lower tiers as well.
        thresholds = config or {
            { score = 10000, money = 100 },
            { score = 50000, bomb = 1 },
            { score = 100000, life = 1 },
        },
        equipment_pool = options.equipment_pool or {},
        equipment_registry = options.equipment_registry,
    }, RewardService)
end

local function hash_text(value, seed)
    local hash = tonumber(seed) or 1
    for index = 1, #value do
        hash = (hash * 31 + value:byte(index)) % 2147483647
    end
    return hash
end

local function sorted_ids(definitions, predicate)
    local result = {}
    for definition_id, definition in pairs(definitions or {}) do
        if definition.test_only ~= true and predicate(definition) then result[#result + 1] = definition_id end
    end
    table.sort(result)
    return result
end

-- Generates a stable set for an encounter.  The encounter seed is shared by
-- both peers, so reward cards do not depend on frame timing or local RNG.
function RewardService:generate_choices(battle_result, run_seed)
    local definitions = self.equipment_registry and self.equipment_registry:all() or {}
    local weapons = sorted_ids(definitions, function(definition)
        return definition.equipment_type == "WEAPON"
    end)
    local modifiers = sorted_ids(definitions, function(definition)
        return definition.equipment_type == "SELF_MODIFIER"
            or definition.equipment_type == "SUPPORT_MODIFIER"
    end)
    local supports = sorted_ids(definitions, function(definition)
        return definition.equipment_type == "SUPPORT"
    end)
    local key = tostring(run_seed or 0) .. ":" .. tostring(battle_result and battle_result.encounter_id or "")
    local hash = hash_text(key, 17)
    local function equipment_choice(pool, offset)
        if #pool == 0 then return nil end
        local id = pool[((math.floor(hash / offset) % #pool) + 1)]
        return { kind = "EQUIPMENT", definition_id = id }
    end
    local function resource_choice(offset)
        return { kind = "RESOURCE", resource = (math.floor(hash / offset) % 2 == 0) and "bomb" or "life", amount = 1 }
    end
    local third_choice = (hash % 4 == 0)
        and resource_choice(11)
        or (equipment_choice(modifiers, 7) or resource_choice(7))
    local choices
    if battle_result and battle_result.encounter_type == "ELITE" then
        -- Elite rooms provide a guaranteed legendary weapon in addition to
        -- the two selections from the three ordinary reward cards.
        choices = {
            equipment_choice(weapons, 3) or resource_choice(3),
            equipment_choice(supports, 5) or resource_choice(5),
            third_choice,
        }
    else
        -- Enemy rooms deliberately expose all useful reward categories.
        choices = {
            equipment_choice(weapons, 3) or resource_choice(3),
            equipment_choice(supports, 5) or resource_choice(5),
            third_choice,
        }
    end
    local guaranteed
    if battle_result and battle_result.encounter_type == "ELITE" then
        local legendary = sorted_ids(definitions, function(definition)
            return definition.equipment_type == "WEAPON" and definition.rarity == "LEGENDARY"
        end)
        if #legendary > 0 then guaranteed = legendary[(hash % #legendary) + 1] end
    end
    return choices, guaranteed
end

function RewardService:calculate(battle_result)
    local reward = { money = 0, life = 0, bomb = 0, equipment_definition_id = nil }
    if not battle_result.reward_eligible then
        return reward
    end
    -- Additive tiers: every threshold at or below the score contributes its
    -- reward, so a 100k stage pays 100 money + 1 bomb + 1 life cumulatively.
    -- Prefer the reference stage score; fall back to the battle score when the
    -- stage score was not reported (for example a direct manager call).
    local score = tonumber(battle_result.stage_score) or 0
    if score <= 0 then score = tonumber(battle_result.battle_score) or 0 end
    for _, threshold in ipairs(self.thresholds) do
        if score >= threshold.score then
            reward.money = reward.money + (threshold.money or 0)
            reward.life = reward.life + (threshold.life or 0)
            reward.bomb = reward.bomb + (threshold.bomb or 0)
        end
    end
    return reward
end

return RewardService
