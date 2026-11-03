-- Coin counts retain the old power-to-money conversion. P counts use the
-- previous blue-point pool (faith was already folded into that pool).
local Plan = { large_p_every = 5 }
function Plan.from_legacy(drop)
    local power = math.max(0, math.floor(tonumber(drop and drop[1]) or 0))
    local points = math.max(0, math.floor((tonumber(drop and drop[2]) or 0) + (tonumber(drop and drop[3]) or 0)))
    local large = math.floor(points / Plan.large_p_every)
    return { money = power >= 400 and 1 or math.floor(power / 100) + power % 100,
        small_p = points - large, large_p = large }
end
return Plan
