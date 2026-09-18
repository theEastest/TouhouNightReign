local Content = require("tnr.stages.content_catalog")
local result = {}
for _, wave in pairs(Content.enemy_waves or {}) do
    -- Keep the practice selector aligned with the original wave catalog and
    -- discard editor fragments shorter than ten seconds.
    if wave.legacy_exact == true and (tonumber(wave.duration_seconds) or 0) >= 10 then
        result[#result + 1] = wave
    end
end
table.sort(result, function(left, right)
    if (left.difficulty or 0) ~= (right.difficulty or 0) then
        return (left.difficulty or 0) < (right.difficulty or 0)
    end
    if (left.legacy_stage or "") ~= (right.legacy_stage or "") then
        return (left.legacy_stage or "") < (right.legacy_stage or "")
    end
    return left.id < right.id
end)
return result
