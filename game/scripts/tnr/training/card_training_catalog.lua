local Content = require("tnr.stages.content_catalog")

local ids = {}
for id, card in pairs(Content.cards) do
    if card.is_spell and card.legacy_exact == true
            and card.legacy_boss and card.legacy_card_slot then
        ids[#ids + 1] = id
    end
end
table.sort(ids)

local result = {}
for _, id in ipairs(ids) do
    result[#result + 1] = Content.cards[id]
end

return result
