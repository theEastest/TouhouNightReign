local Catalog = require("tnr.equipment.phase1_catalog")
local EquipmentInfo = require("tnr.ui.equipment_info")
local GameSession = require("tnr.core.game_session")

local function joined(lines)
    local parts = {}
    for _, line in ipairs(lines) do
        parts[#parts + 1] = tostring(line.text or line)
    end
    return table.concat(parts, " | ")
end

return function(assert_equal, assert_true)
    -- Rarity is localized and colored.
    local common_label = EquipmentInfo.rarity(Catalog.registry:get("hakurei_sealing_needle"))
    assert_equal(common_label, "普通", "common rarity is localized")
    assert_equal(EquipmentInfo.rarity(Catalog.registry:get("hakurei_dream_sealing_needle")), "传说",
        "legendary rarity is localized")

    -- A high-speed weapon reports its slot class plus the key firing numbers.
    local needle = Catalog.registry:get("hakurei_sealing_needle")
    assert_equal(EquipmentInfo.slot_label(needle), "高速武器", "high weapon slot label")
    local needle_text = joined(EquipmentInfo.describe(needle))
    assert_true(needle_text:find("封魔针", 1, true) ~= nil, "detail shows the display name")
    assert_true(needle_text:find("高速武器", 1, true) ~= nil, "detail shows the slot class")
    assert_true(needle_text:find("品质 普通", 1, true) ~= nil, "detail shows the rarity")
    assert_true(needle_text:find("高速发射成对的封魔针。", 1, true) ~= nil, "detail shows the description")
    assert_true(needle_text:find("伤害", 1, true) ~= nil, "weapon detail shows damage")
    assert_true(needle_text:find("间隔", 1, true) ~= nil, "weapon detail shows the fire interval")
    assert_true(needle_text:find("弹数", 1, true) ~= nil, "weapon detail shows the projectile count")

    -- A low-speed weapon is labelled as such.
    local ray = Catalog.registry:get("marisa_earthlight_ray")
    assert_equal(EquipmentInfo.slot_label(ray), "低速武器", "low weapon slot label")

    -- Supports report their entity count and activation mode.
    local orb = Catalog.registry:get("support_hakurei_yinyang_orb")
    local orb_text = joined(EquipmentInfo.describe(orb))
    assert_true(orb_text:find("子机数 4", 1, true) ~= nil, "support detail shows the entity count")
    assert_true(orb_text:find("激活 常时", 1, true) ~= nil, "support detail shows the activation mode")

    -- Modifiers report their conflict group.
    local formation = Catalog.registry:get("support_modifier_orbit_formation")
    local formation_text = joined(EquipmentInfo.describe(formation))
    assert_true(formation_text:find("冲突组 support_formation_override", 1, true) ~= nil,
        "modifier detail shows the conflict group")

    -- The category label must never appear twice in a row (the formatter
    -- de-duplicates overlapping category/slot labels such as "自身增益").
    for _, id in ipairs({
        "self_high_speed_casting", "support_hakurei_ward_array", "hakurei_persuasion_needle",
    }) do
        local definition = Catalog.registry:get(id)
        local category = EquipmentInfo.category(definition)
        local slot = EquipmentInfo.slot_label(definition)
        local text = joined(EquipmentInfo.describe(definition))
        if category and slot and category == slot then
            -- The two labels are identical; the header line must only show
            -- the value once. Count the exact "category   category" pattern.
            local doubled = category .. "   " .. category
            assert_true(text:find(doubled, 1, true) == nil, id .. " description must not repeat its category label")
        end
    end

    -- Non-equipment offers still produce readable lines.
    local session = GameSession.new({ run_seed = 321 }):start_new()
    local life_lines = EquipmentInfo.describe_offer(session, { kind = "LIFE", price = 0, amount = 1 })
    assert_true(joined(life_lines):find("队伍生命", 1, true) ~= nil, "life offer description")
    local bomb_lines = EquipmentInfo.describe_offer(session, { kind = "BOMB", price = 0, amount = 2 })
    assert_true(joined(bomb_lines):find("炸弹", 1, true) ~= nil, "bomb offer description")

    -- Equipment offers include the definition info and the price.
    local offer_lines = EquipmentInfo.describe_offer(session,
        { kind = "EQUIPMENT", definition_id = "hakurei_sealing_needle", price = 30 })
    local offer_text = joined(offer_lines)
    assert_true(offer_text:find("封魔针", 1, true) ~= nil, "equipment offer shows the name")
    assert_true(offer_text:find("价格 30G", 1, true) ~= nil, "equipment offer shows the price")

    -- Reward descriptions cover resources and equipment.
    local reward_resource = EquipmentInfo.describe_reward(session, { kind = "RESOURCE", resource = "life", amount = 1 })
    assert_true(joined(reward_resource):find("队伍生命", 1, true) ~= nil, "life reward description")
    local reward_equipment = EquipmentInfo.describe_reward(session, { kind = "EQUIPMENT", definition_id = "sanae_cobalt_spread" })
    assert_true(joined(reward_equipment):find("钴蓝散射", 1, true) ~= nil, "equipment reward description")
end
