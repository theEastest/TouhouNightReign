-- Representative native rooms for New Multiplayer Task Book 1/3.
-- IDs are sourced from the actual Legacy content catalog; no fallback room is
-- listed here. Resource preflight may replace these candidates after launch.
local Content = require("tnr.stages.content_catalog")
local NativeResourcePreflight = require("tnr.stages.native_resource_preflight")

local function first_matching(predicate)
    local ids = {}
    for id, value in pairs(Content.cards or {}) do
        if predicate(value) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local id = ids[1]
    return id and Content.cards[id] or nil
end

local function first_wave()
    local ids = {}
    for id, value in pairs(Content.enemy_waves or {}) do
        if value.legacy_exact == true and (tonumber(value.duration_seconds) or 0) > 10 then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    local id = ids[1]
    return id and Content.enemy_waves[id] or nil
end

local catalog = {
    ROOM_A = {
        id = "ROOM_A", kind = "ENEMY", room_type = "enemy",
        encounter_id = "ordinary_stage_01", wave = first_wave(),
    },
    ROOM_B = {
        id = "ROOM_B", kind = "BOSS_NONSpell", room_type = "boss",
        encounter_id = "boss_stage_01",
        card = first_matching(function(card)
            return card.legacy_exact == true and card.is_spell ~= true
                and card.legacy_boss and card.legacy_card_slot
        end),
    },
    ROOM_C = {
        id = "ROOM_C", kind = "BOSS_SPELL", room_type = "boss",
        encounter_id = "boss_stage_01",
        card = first_matching(function(card)
            return card.legacy_exact == true and card.is_spell == true
                and card.legacy_boss and card.legacy_card_slot
        end),
    },
}

function catalog.preflight(root)
    return NativeResourcePreflight.run(root, { "ROOM_A", "ROOM_B", "ROOM_C" })
end

function catalog.validate()
    return catalog.ROOM_A.wave ~= nil and catalog.ROOM_B.card ~= nil and catalog.ROOM_C.card ~= nil
end

return catalog
