-- Player-facing equipment information formatter.
--
-- The shop, the loadout preparation screen and the reward screen all need to
-- show the same description of an item. Centralizing the formatting here keeps
-- the three screens consistent and makes the guide data (rarity, slot class,
-- fire interval, damage, ...) the single source of truth.

local EquipmentInfo = {}

local RARITY_LABELS = {
    COMMON = "普通",
    RARE = "稀有",
    LEGENDARY = "传说",
}

local RARITY_COLORS = {
    COMMON = { 255, 210, 214, 224 },
    RARE = { 255, 120, 196, 255 },
    LEGENDARY = { 255, 255, 196, 92 },
}

local SLOT_LABELS = {
    HIGH_WEAPON = "高速武器",
    LOW_WEAPON = "低速武器",
    SUPPORT = "子机",
}

local TYPE_LABELS = {
    WEAPON = "武器",
    SUPPORT = "子机",
    SELF_MODIFIER = "自身增益",
    SUPPORT_MODIFIER = "子机增益",
}

local ACTIVATION_LABELS = {
    ALWAYS = "常时",
    PASSIVE = "被动",
    INDEPENDENT = "独立",
}

local TARGETING_LABELS = {
    NONE = "无",
    FORWARD = "前方",
    NEAREST_ENEMY = "最近敌人",
    LAST_DIRECTION = "保持朝向",
}

local PATTERN_LABELS = {
    straight = "直射",
    fan = "扇形",
    spread = "扩散",
    beam = "光束",
}

local FORMATION_LABELS = {
    FOLLOW = "跟随",
    ORBIT = "环绕",
    FRONT = "阵前",
}

local function is_weapon(definition)
    return definition and definition.equipment_type == "WEAPON"
end

local function is_support(definition)
    return definition and definition.equipment_type == "SUPPORT"
end

local function is_modifier(definition)
    return definition and (definition.equipment_type == "SELF_MODIFIER"
        or definition.equipment_type == "SUPPORT_MODIFIER")
end

local function number_text(value, digits)
    local number = tonumber(value)
    if number == nil then return nil end
    if digits and digits > 0 then
        return string.format("%." .. digits .. "f", number)
    end
    if number % 1 == 0 then
        return tostring(math.floor(number))
    end
    return string.format("%.2f", number)
end

--- Chinese display name of a definition (falls back through the aliases).
function EquipmentInfo.display_name(definition, fallback_id)
    if definition then
        return tostring(definition.display_name_zh or definition.display_name
            or definition.display_name_en or definition.equipment_id or fallback_id or "未知装备")
    end
    return tostring(fallback_id or "未知装备")
end

--- Rarity label plus color, used by the detail panel.
function EquipmentInfo.rarity(definition)
    local rarity = definition and definition.rarity or "COMMON"
    return RARITY_LABELS[rarity] or tostring(rarity), RARITY_COLORS[rarity] or RARITY_COLORS.COMMON
end

--- Equipment category label (weapon / support / modifier and slot class).
function EquipmentInfo.category(definition)
    if not definition then return "未知类别" end
    local pieces = {}
    local base = TYPE_LABELS[definition.equipment_type] or tostring(definition.equipment_type or "装备")
    pieces[#pieces + 1] = base
    return table.concat(pieces, " ")
end

--- Slot class label, for example "高速武器" or "低速武器".
function EquipmentInfo.slot_label(definition)
    if not definition then return nil end
    local labels = {}
    if is_weapon(definition) then
        if definition.type == "LOW_WEAPON" or definition.slot == "LOW" then
            labels[#labels + 1] = SLOT_LABELS.LOW_WEAPON
        else
            labels[#labels + 1] = SLOT_LABELS.HIGH_WEAPON
        end
        if definition.dual_mode then labels[#labels + 1] = "（双模式）" end
    elseif is_support(definition) then
        labels[#labels + 1] = SLOT_LABELS.SUPPORT
    elseif is_modifier(definition) then
        labels[#labels + 1] = TYPE_LABELS[definition.equipment_type] or "增益"
    end
    if #labels == 0 then return nil end
    return table.concat(labels, " ")
end

--- Build the ordered player-facing lines for an equipment definition.
--- Returns a list of { text = string, color = {r,g,b,a}? } entries.
function EquipmentInfo.describe(definition)
    local lines = {}
    if not definition then
        lines[#lines + 1] = { text = "没有选中物品", color = "muted" }
        return lines
    end

    local rarity_label, rarity_color = EquipmentInfo.rarity(definition)
    lines[#lines + 1] = { text = EquipmentInfo.display_name(definition), color = rarity_color }

    local meta = {}
    local seen = {}
    local function push(value)
        if value and value ~= "" and not seen[value] then
            seen[value] = true
            meta[#meta + 1] = value
        end
    end
    push(EquipmentInfo.category(definition))
    push(EquipmentInfo.slot_label(definition))
    meta[#meta + 1] = "品质 " .. rarity_label
    lines[#lines + 1] = { text = table.concat(meta, "   "), color = "muted" }

    local weight = number_text(definition.weight)
    if weight and tonumber(definition.weight) and tonumber(definition.weight) > 0 then
        lines[#lines + 1] = { text = "重量 " .. weight, color = "muted" }
    end

    if definition.description and definition.description ~= "" then
        lines[#lines + 1] = { text = tostring(definition.description), color = "text" }
    end

    if is_weapon(definition) then
        local stats = {}
        local damage = number_text(definition.damage, 2)
        if damage then stats[#stats + 1] = "伤害 " .. damage end
        local interval = number_text(definition.fire_interval)
        if interval then stats[#stats + 1] = "间隔 " .. interval .. " 帧" end
        local count = number_text(definition.count)
        if count then stats[#stats + 1] = "弹数 " .. count end
        if #stats > 0 then lines[#lines + 1] = { text = table.concat(stats, "   "), color = "active_line" } end

        local extra = {}
        local speed = number_text(definition.projectile_speed)
        if speed then extra[#extra + 1] = "弹速 " .. speed end
        local penetration = tonumber(definition.penetration)
        if penetration and penetration > 0 then extra[#extra + 1] = "穿透 " .. penetration end
        if definition.targeting and TARGETING_LABELS[definition.targeting] then
            extra[#extra + 1] = "追踪 " .. TARGETING_LABELS[definition.targeting]
        elseif definition.targeting then
            extra[#extra + 1] = "追踪 " .. tostring(definition.targeting)
        end
        if definition.pattern and PATTERN_LABELS[definition.pattern] then
            extra[#extra + 1] = "弹型 " .. PATTERN_LABELS[definition.pattern]
        end
        if #extra > 0 then lines[#lines + 1] = { text = table.concat(extra, "   "), color = "muted" } end
    elseif is_support(definition) then
        local stats = {}
        local count = number_text(definition.entity_count)
        if count then stats[#stats + 1] = "子机数 " .. count end
        if definition.activation_mode then
            stats[#stats + 1] = "激活 " .. (ACTIVATION_LABELS[definition.activation_mode] or tostring(definition.activation_mode))
        end
        if #stats > 0 then lines[#lines + 1] = { text = table.concat(stats, "   "), color = "active_line" } end
        local formation = definition.formation
        if formation and formation.type then
            lines[#lines + 1] = { text = "编队 " .. (FORMATION_LABELS[formation.type] or tostring(formation.type)), color = "muted" }
        end
        local metadata = definition.metadata or {}
        local support_stats = {}
        local high_damage = number_text(metadata.high_damage, 2)
        if high_damage then support_stats[#support_stats + 1] = "高速伤害 " .. high_damage end
        local low_damage = number_text(metadata.low_damage, 2)
        if low_damage then support_stats[#support_stats + 1] = "低速伤害 " .. low_damage end
        if #support_stats > 0 then lines[#lines + 1] = { text = table.concat(support_stats, "   "), color = "muted" } end
    elseif is_modifier(definition) then
        if definition.conflict_group and definition.conflict_group ~= "" then
            lines[#lines + 1] = { text = "冲突组 " .. tostring(definition.conflict_group), color = "muted" }
        end
    end

    if definition.tags and #definition.tags > 0 then
        lines[#lines + 1] = { text = "标签 " .. table.concat(definition.tags, " / "), color = "muted" }
    end

    return lines
end

--- Describe a shop / reward offer that is not a plain equipment definition.
function EquipmentInfo.describe_offer(session, offer)
    if not offer then
        return { { text = "没有选中物品", color = "muted" } }
    end
    if offer.kind == "EQUIPMENT" then
        local definition = session and session.equipment_registry
            and session.equipment_registry:get(offer.definition_id) or nil
        local lines = EquipmentInfo.describe(definition)
        local price = tonumber(offer.price) or 0
        lines[#lines + 1] = { text = "价格 " .. price .. "G", color = "active_line" }
        return lines
    elseif offer.kind == "LIFE" then
        return {
            { text = "队伍生命", color = "text" },
            { text = "恢复 1 点队伍生命。", color = "text" },
            { text = "价格 " .. tostring(tonumber(offer.price) or 0) .. "G", color = "active_line" },
        }
    elseif offer.kind == "LIFE_FRAGMENT" then
        return {
            { text = "生命碎片", color = "text" },
            { text = "收集碎片可兑换额外的队伍生命。", color = "text" },
            { text = "价格 " .. tostring(tonumber(offer.price) or 0) .. "G", color = "active_line" },
        }
    elseif offer.kind == "BOMB" then
        return {
            { text = "炸弹", color = "text" },
            { text = "为当前玩家补充 " .. tostring(tonumber(offer.amount) or 1) .. " 枚炸弹。", color = "text" },
            { text = "价格 " .. tostring(tonumber(offer.price) or 0) .. "G", color = "active_line" },
        }
    end
    return {
        { text = tostring(offer.kind or "物品"), color = "text" },
        { text = "价格 " .. tostring(tonumber(offer.price) or 0) .. "G", color = "active_line" },
    }
end

--- Describe a reward choice (either a resource or an equipment definition).
function EquipmentInfo.describe_reward(session, choice)
    if not choice then
        return { { text = "没有选中奖励", color = "muted" } }
    end
    if choice.kind == "RESOURCE" then
        if choice.resource == "life" then
            return {
                { text = "队伍生命", color = "text" },
                { text = "恢复 " .. tostring(tonumber(choice.amount) or 1) .. " 点队伍生命。", color = "text" },
            }
        end
        return {
            { text = "炸弹", color = "text" },
            { text = "补充 " .. tostring(tonumber(choice.amount) or 1) .. " 枚炸弹。", color = "text" },
        }
    end
    local definition = session and session.equipment_registry
        and session.equipment_registry:get(choice.definition_id) or nil
    return EquipmentInfo.describe(definition)
end

--- Describe a relic by id.
function EquipmentInfo.describe_relic(session, relic_id)
    local catalog = session and session.relic_catalog
    local relic = catalog and catalog[relic_id] or nil
    if not relic then
        return { { text = tostring(relic_id or "未知遗物"), color = "text" } }
    end
    local lines = {}
    lines[#lines + 1] = { text = EquipmentInfo.display_name(relic), color = "text" }
    if relic.description and relic.description ~= "" then
        lines[#lines + 1] = { text = tostring(relic.description), color = "text" }
    elseif relic.character_relic then
        lines[#lines + 1] = { text = "角色专属遗物。", color = "text" }
    end
    return lines
end

--- Short one-line label for cards / lists.
function EquipmentInfo.short_label(definition, fallback_id)
    return EquipmentInfo.display_name(definition, fallback_id)
end

return EquipmentInfo
