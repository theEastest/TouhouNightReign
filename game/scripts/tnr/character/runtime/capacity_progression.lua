local CapacityProgression = {}
CapacityProgression.__index = CapacityProgression

local DEFAULT_THRESHOLDS = {
    { score = 0, capacity = 100, level = 0 },
    { score = 1000, capacity = 120, level = 1 },
    { score = 5000, capacity = 150, level = 2 },
}

local function copy_thresholds(source)
    local result = {}
    for _, threshold in ipairs(source or DEFAULT_THRESHOLDS) do
        result[#result + 1] = {
            score = math.max(0, tonumber(threshold.score) or 0),
            capacity = math.max(0, tonumber(threshold.capacity) or 0),
            level = math.max(0, tonumber(threshold.level) or 0),
        }
    end
    table.sort(result, function(left, right) return left.score < right.score end)
    return result
end

function CapacityProgression.new(thresholds)
    return setmetatable({ thresholds = copy_thresholds(thresholds) }, CapacityProgression)
end

function CapacityProgression:resolve(score)
    score = math.max(0, tonumber(score) or 0)
    local selected = self.thresholds[1]
    for _, threshold in ipairs(self.thresholds) do
        if score >= threshold.score then selected = threshold else break end
    end
    return selected.capacity, selected.level
end

function CapacityProgression:apply(player)
    assert(player, "player is required")
    local capacity, level = self:resolve(player.score)
    local changed = player.current_capacity ~= capacity or player.capacity_level ~= level
    player:set_capacity(capacity, level)
    return changed, capacity, level
end

return CapacityProgression
