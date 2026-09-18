local Content = require("tnr.stages.content_catalog")
local result = {}
for _, card in pairs(Content.cards) do
    if not card.is_spell and card.legacy_exact == true
            and card.legacy_boss and card.legacy_card_slot then
        result[#result + 1] = card
    end
end
table.sort(result, function(left, right) return left.id < right.id end)
return result
