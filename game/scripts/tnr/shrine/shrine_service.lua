local RNG = require("tnr.core.rng")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local WeaponDefinition = require("tnr.equipment.weapon_definition")
local Affixes = require("tnr.equipment.affix_catalog")
local Immutable = require("tnr.core.immutable")

local ShrineService = {}
ShrineService.__index = ShrineService

ShrineService.OPERATIONS = {
    { key = "reforge", name = "重铸", description = "为一把武器或一个子机重新随机词条" },
    { key = "upgrade", name = "升级", description = "白色或蓝色武器升一级品质，数值提升 1.5 倍" },
    { key = "fusion", name = "融合", description = "选择两把武器，继承词条并随机合并属性" },
    { key = "search", name = "搜寻", description = "随机获得残机、炸弹或增益模块" },
    { key = "leave", name = "离开", description = "返回地图" },
}

local GROUPS = { "high_weapons", "low_weapons", "supports", "self_modifiers", "support_modifiers" }
local RARITY_NEXT = { COMMON = "RARE", RARE = "LEGENDARY" }

local function sorted_keys(values)
    local keys = {}
    for key in pairs(values or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    return keys
end

local function item_definition(session, instance)
    return instance and session.equipment_registry:get(instance.definition_id) or nil
end

function ShrineService.new(session, node)
    local seed = (tonumber(node and node.content_seed) or 1) + (tonumber(session.run_seed) or 1)
        + (tonumber(node and node.id) or 0) * 997
    return setmetatable({
        session = session,
        node = node,
        rng = RNG.new(seed),
        phase = "operation",
        operation_cursor = 1,
        target_cursor = 1,
        operation = nil,
        fusion_first = nil,
        action_index = 0,
        message = "选择一项神社服务",
        completed = false,
    }, ShrineService)
end

function ShrineService:operations()
    return ShrineService.OPERATIONS
end

function ShrineService:targets(operation, excluded_instance_id, player_id)
    player_id = tonumber(player_id) or self.active_player_id or self.session.local_player_id or 1
    local player = self.session:get_player(player_id)
    local loadout = player and player.loadout
    local result = {}
    if not loadout then return result end
    local function add(instance, source, group, index)
        if not instance or instance == false or instance.instance_id == excluded_instance_id then return end
        local definition = item_definition(self.session, instance)
        if not definition then return end
        local keep = false
        if operation == "reforge" then
            keep = definition.equipment_type == "WEAPON" or definition.equipment_type == "SUPPORT"
        elseif operation == "upgrade" then
            local rarity = instance.runtime_data and instance.runtime_data.rarity_override or definition.rarity
            keep = definition.equipment_type == "WEAPON" and RARITY_NEXT[rarity] ~= nil
        elseif operation == "fusion" then
            keep = definition.equipment_type == "WEAPON"
        end
        if keep then result[#result + 1] = { instance = instance, definition = definition,
            source = source, group = group, index = index } end
    end
    for index, instance in ipairs(loadout.inventory and loadout.inventory.items or {}) do
        add(instance, "inventory", nil, index)
    end
    for group, index, instance in loadout:iter_equipped() do
        add(instance, "equipped", group, index)
    end
    table.sort(result, function(left, right)
        local a = tostring(left.definition.display_name_zh or left.definition.display_name or left.instance.definition_id)
        local b = tostring(right.definition.display_name_zh or right.definition.display_name or right.instance.definition_id)
        if a ~= b then return a < b end
        if left.source ~= right.source then return left.source < right.source end
        if left.group ~= right.group then return tostring(left.group or "") < tostring(right.group or "") end
        return left.index < right.index
    end)
    return result
end

function ShrineService:begin_operation(index)
    if self.completed then return nil, "SHRINE_ALREADY_USED" end
    local entry = ShrineService.OPERATIONS[index]
    if not entry then return nil, "INVALID_SHRINE_OPERATION" end
    self.operation_cursor = index
    if entry.key == "leave" then
        self.completed = true
        return true, "leave"
    end
    self.operation = entry.key
    if entry.key == "search" then
        local ok, message = self:search()
        if ok then self.completed = true end
        return ok, message
    end
    self.phase = "target"
    self.target_cursor = 1
    self.fusion_first = nil
    local targets = self:targets(entry.key)
    if #targets == 0 or entry.key == "fusion" and #targets < 2 then
        self.phase = "operation"
        self.message = entry.key == "upgrade" and "没有可升级的白色或蓝色武器"
            or entry.key == "fusion" and "至少需要两把武器才能融合"
            or "没有符合条件的装备"
        return nil, self.message
    end
    self.message = entry.key == "fusion" and "选择第一把武器" or "选择目标装备"
    return true
end

function ShrineService:reforge(entry)
    local definition = entry.definition
    self.action_index = self.action_index + 1
    local seed = table.concat({ tostring(self.session.run_seed), tostring(self.node.id),
        tostring(self.action_index), tostring(entry.instance.definition_id) }, ":")
    if definition.equipment_type == "SUPPORT" then
        entry.instance.random_affixes = Affixes.roll_support(definition, seed)
    else
        -- Starter weapons are normally excluded from generated affixes, but a
        -- shrine reforge is an explicit player choice and should always change
        -- their traits as well.
        local reforge_definition = definition
        if definition.starter_only or definition.internal_only then
            local spec = definition.to_table and definition:to_table() or Immutable.copy(definition)
            spec.starter_only, spec.internal_only, spec.test_only = false, false, false
            reforge_definition = WeaponDefinition.new(spec)
        end
        entry.instance.random_affixes = Affixes.roll(reforge_definition, seed)
    end
    entry.instance.runtime_data = entry.instance.runtime_data or {}
    entry.instance.runtime_data.affix_growth = nil
    local player = self.session:get_player(self.active_player_id or self.session.local_player_id or 1)
    player.loadout.version = (player.loadout.version or 1) + 1
    self.message = "重铸完成"
    return true
end

function ShrineService:upgrade(entry)
    local instance = entry.instance
    local definition = entry.definition
    instance.runtime_data = instance.runtime_data or {}
    local current_rarity = instance.runtime_data.rarity_override or definition.rarity or "COMMON"
    local next_rarity = RARITY_NEXT[current_rarity]
    if not next_rarity then return nil, "只有白色或蓝色武器可以升级" end
    instance.runtime_data.rarity_override = next_rarity
    instance.runtime_data.stat_multiplier = (tonumber(instance.runtime_data.stat_multiplier) or 1) * 1.5
    local player = self.session:get_player(self.active_player_id or self.session.local_player_id or 1)
    player.loadout.version = (player.loadout.version or 1) + 1
    self.message = "品质提升至" .. ({ RARE = "蓝色", LEGENDARY = "传说" })[next_rarity] .. "，武器数值 ×1.5"
    return true
end

local function effective_definition(definition, instance)
    local result = definition.to_table and definition:to_table() or Immutable.copy(definition)
    local multiplier = tonumber(instance.runtime_data and instance.runtime_data.stat_multiplier) or 1
    if multiplier == 1 then return result end
    for _, key in ipairs({ "damage", "speed", "projectile_speed", "penetration", "status_buildup" }) do
        if tonumber(result[key]) then result[key] = result[key] * multiplier end
    end
    if tonumber(result.fire_interval) then result.fire_interval = math.max(1, result.fire_interval / multiplier) end
    if tonumber(result.count) then result.count = math.max(1, math.floor(result.count * multiplier + 0.5)) end
    local metadata = result.metadata or {}
    for key, value in pairs(metadata) do
        if type(value) == "number" and (key:find("damage") or key:find("projectile_speed")
                or key:find("projectile_count") or key:find("status_buildup")) then
            metadata[key] = value * multiplier
        end
    end
    result.metadata = metadata
    return result
end

local function merge_table(left, right, rng)
    local merged = {}
    for _, key in ipairs(sorted_keys(left)) do
        local value = left[key]
        local other = right and right[key]
        if other ~= nil then
            if rng:chance(0.5) then merged[key] = Immutable.copy(value)
            else merged[key] = Immutable.copy(other) end
        else
            merged[key] = Immutable.copy(value)
        end
    end
    for _, key in ipairs(sorted_keys(right)) do
        local value = right[key]
        if left == nil or left[key] == nil then merged[key] = Immutable.copy(value) end
    end
    return merged
end

function ShrineService:_fused_definition(first, second)
    local a = effective_definition(first.definition, first.instance)
    local b = effective_definition(second.definition, second.instance)
    self.action_index = self.action_index + 1
    local id = string.format("shrine_fused_%s_%s_%d", tostring(self.node.id), tostring(self.node.content_seed or 1), self.action_index)
    local excluded = { equipment_id = true, weapon_id = true, name = true, display_name = true,
        display_name_zh = true, display_name_en = true, equipment_type = true,
        dual_mode = true, allowed_slots = true, active_modes = true, type = true,
        test_only = true, internal_only = true, starter_only = true, exclusive_affix = true }
    local spec = {}
    for _, key in ipairs(sorted_keys(a)) do
        local value = a[key]
        if not excluded[key] then
            local other = b[key]
            if key == "metadata" then
                spec.metadata = merge_table(value, b.metadata, self.rng)
            elseif other ~= nil then
                if self.rng:chance(0.5) then spec[key] = Immutable.copy(value)
                else spec[key] = Immutable.copy(other) end
            else
                spec[key] = Immutable.copy(value)
            end
        end
    end
    for _, key in ipairs(sorted_keys(b)) do
        local value = b[key]
        if not excluded[key] and a[key] == nil then spec[key] = Immutable.copy(value) end
    end
    local first_name = tostring(first.definition.display_name_zh or first.definition.display_name or first.instance.definition_id)
    local second_name = tostring(second.definition.display_name_zh or second.definition.display_name or second.instance.definition_id)
    local first_rarity = first.instance.runtime_data and first.instance.runtime_data.rarity_override or first.definition.rarity
    local second_rarity = second.instance.runtime_data and second.instance.runtime_data.rarity_override or second.definition.rarity
    spec.weapon_id = id
    spec.display_name_zh, spec.display_name = first_name .. "-" .. second_name, first_name .. "-" .. second_name
    spec.display_name_en = tostring(first.definition.display_name_en or first_name) .. "-" .. tostring(second.definition.display_name_en or second_name)
    spec.description_zh = "神社融合武器：继承两把原武器的词条与随机合并属性。"
    spec.description = spec.description_zh
    spec.rarity = spec.rarity or first_rarity or second_rarity
    spec.equipment_type, spec.dual_mode = "WEAPON", true
    spec.active_modes = { HIGH = true, LOW = true }
    spec.allowed_slots = { HIGH_WEAPON = true, LOW_WEAPON = true }
    spec.metadata = spec.metadata or {}
    spec.metadata.fused = true
    spec.metadata.fused_from = { first.instance.definition_id, second.instance.definition_id }
    spec.damage = tonumber(spec.damage) or 1
    spec.fire_interval = tonumber(spec.fire_interval) or 30
    spec.projectile_type = spec.projectile_type or "reimu_bullet_red"
    spec.projectile_speed = tonumber(spec.projectile_speed) or 12
    spec.speed = tonumber(spec.speed) or spec.projectile_speed
    spec.count = tonumber(spec.count) or tonumber(spec.metadata.projectile_count) or 1
    spec.pattern = spec.pattern or "straight"
    spec.weight = tonumber(spec.weight) or 0
    return WeaponDefinition.new(spec), id
end

local function remove_entry(loadout, entry)
    if entry.source == "inventory" then
        local _, index = loadout.inventory:find(entry.instance.instance_id)
        if index then loadout.inventory:remove(index) end
    elseif loadout:get_slot(entry.group, entry.index) == entry.instance then
        loadout:set_slot(entry.group, entry.index, false)
    end
end

function ShrineService:fuse(first, second)
    if first.instance.instance_id == second.instance.instance_id then return nil, "不能融合两次同一把武器" end
    local player_id = self.active_player_id or self.session.local_player_id or 1
    local player = self.session:get_player(player_id)
    local loadout = player.loadout
    local inventory_frees = (first.source == "inventory" and 1 or 0) + (second.source == "inventory" and 1 or 0)
    local has_empty_slot = false
    for _, group in ipairs({ "high_weapons", "low_weapons" }) do
        for index = 1, #(loadout[group] or {}) do
            if loadout[group][index] == false or loadout[group][index] == first.instance or loadout[group][index] == second.instance then
                has_empty_slot = true
            end
        end
    end
    if loadout.inventory.capacity - loadout.inventory:count() + inventory_frees <= 0 and not has_empty_slot then
        return nil, "仓库已满且没有空武器槽，无法融合"
    end
    local definition, definition_id = self:_fused_definition(first, second)
    self.session.equipment_registry:register(definition)
    local affixes = {}
    for _, affix in ipairs(first.instance.random_affixes or {}) do affixes[#affixes + 1] = Immutable.copy(affix) end
    for _, affix in ipairs(second.instance.random_affixes or {}) do affixes[#affixes + 1] = Immutable.copy(affix) end
    local fused = EquipmentInstance.new(definition, player_id, {
        instance_id = definition_id .. "-instance",
        random_affixes = affixes,
    })
    remove_entry(loadout, first)
    remove_entry(loadout, second)
    local added = loadout.inventory:add(fused)
    if not added then
        local placed = false
        for _, group in ipairs({ "high_weapons", "low_weapons" }) do
            for index = 1, #(loadout[group] or {}) do
                if loadout[group][index] == false then
                    loadout:set_slot(group, index, fused)
                    placed = true
                    break
                end
            end
            if placed then break end
        end
    end
    loadout.version = (loadout.version or 1) + 1
    self.message = "融合完成：" .. tostring(definition.display_name_zh) .. " 已放入仓库"
    return true, self.message, definition_id
end

function ShrineService:search(player_id)
    player_id = tonumber(player_id) or self.active_player_id or self.session.local_player_id or 1
    local player = self.session:get_player(player_id)
    local reward = self.rng:next_int(1, 3)
    if reward == 1 then
        self.session:add_life(player_id, 1, "shrine_search")
        self.message = "搜寻获得残机 +1"
        return true, self.message
    elseif reward == 2 then
        self.session:add_bomb(player_id, 2, "shrine_search")
        self.message = "搜寻获得炸弹 +2"
        return true, self.message
    end
    local candidates = {}
    for id, definition in pairs(self.session.equipment_registry:all()) do
        if (definition.equipment_type == "SELF_MODIFIER" or definition.equipment_type == "SUPPORT_MODIFIER")
                and definition.test_only ~= true then candidates[#candidates + 1] = id end
    end
    table.sort(candidates)
    if #candidates == 0 or player.loadout.inventory:is_full() then
        self.session:add_bomb(player_id, 2, "shrine_search")
        self.message = "仓库无空位，搜寻改为炸弹 +2"
        return true, self.message
    end
    local id = candidates[self.rng:next_int(1, #candidates)]
    local definition = self.session.equipment_registry:get(id)
    self.action_index = self.action_index + 1
    local instance_id = string.format("shrine_search_%s_%s_%d_%s", tostring(self.node.id),
        tostring(self.node.content_seed or 1), self.action_index, tostring(id))
    local instance = EquipmentInstance.new(definition, player_id, { instance_id = instance_id })
    player.loadout.inventory:add(instance)
    player.loadout.version = (player.loadout.version or 1) + 1
    self.message = "搜寻获得增益模块：" .. tostring(definition.display_name_zh or definition.display_name)
    return true, self.message
end

function ShrineService:select_target(index)
    if self.phase ~= "target" or self.completed then return nil, "SHRINE_NOT_SELECTING_TARGET" end
    local targets = self:targets(self.operation, self.fusion_first and self.fusion_first.instance.instance_id or nil)
    local entry = targets[index]
    if not entry then return nil, "INVALID_SHRINE_TARGET" end
    self.target_cursor = index
    if self.operation == "fusion" and not self.fusion_first then
        self.fusion_first = entry
        self.target_cursor = 1
        self.message = "已选 " .. tostring(entry.definition.display_name_zh or entry.definition.display_name) .. "，再选择第二把武器"
        return true, self.message
    end
    local ok, message
    if self.operation == "reforge" then
        ok, message = self:reforge(entry)
    elseif self.operation == "upgrade" then
        ok, message = self:upgrade(entry)
    else
        ok, message = self:fuse(self.fusion_first, entry)
    end
    if ok then self.completed = true
    elseif message then self.message = message end
    return ok, message
end

function ShrineService:execute_action(operation_index, first_target_index, second_target_index, player_id)
    self.active_player_id = tonumber(player_id) or self.session.local_player_id or 1
    local operation = ShrineService.OPERATIONS[tonumber(operation_index) or 0]
    if not operation then return nil, "INVALID_SHRINE_OPERATION" end
    self.operation_cursor = tonumber(operation_index)
    self.operation = operation.key
    if operation.key == "leave" then
        self.completed = true
        return true
    elseif operation.key == "search" then
        local ok, err = self:search(self.active_player_id)
        if ok then self.completed = true end
        return ok, err
    end
    local targets = self:targets(operation.key, nil, self.active_player_id)
    local first, second
    if operation.key == "fusion" then
        first, second = targets[tonumber(first_target_index) or 0], targets[tonumber(second_target_index) or 0]
        if not first or not second then
            self.message = "请选择两把有效武器"
            return nil, self.message
        end
    else
        first = targets[tonumber(first_target_index) or 0]
        if not first then
            self.message = "请选择有效装备"
            return nil, self.message
        end
    end
    local ok, message
    if operation.key == "reforge" then ok, message = self:reforge(first)
    elseif operation.key == "upgrade" then ok, message = self:upgrade(first)
    else ok, message = self:fuse(first, second) end
    if ok then self.completed = true
    elseif message then self.message = message end
    return ok, message
end

return ShrineService
