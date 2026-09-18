local EquipmentRegistry = {}
EquipmentRegistry.__index = EquipmentRegistry

local function plain(value)
    if type(value) ~= "table" then return value end
    if type(value.to_table) == "function" then return plain(value:to_table()) end
    local raw = value.__immutable_raw
    if type(raw) == "table" then value = raw end
    local result = {}
    for key, item in pairs(value) do result[plain(key)] = plain(item) end
    return result
end

local function stable_encode(value, seen)
    local kind = type(value)
    if value == nil then return "n" end
    if kind == "boolean" then return value and "b1" or "b0" end
    if kind == "number" then return "d" .. string.format("%.17g", value) .. ";" end
    if kind == "string" then return "s" .. #value .. ":" .. value end
    if kind ~= "table" then return "<" .. kind .. ">" end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    local parts = { "t", tostring(#keys), ":" }
    for _, key in ipairs(keys) do
        parts[#parts + 1] = stable_encode(key, seen)
        parts[#parts + 1] = stable_encode(value[key], seen)
    end
    seen[value] = nil
    return table.concat(parts)
end

local function hash_string(value)
    local hash = 2166136261
    for index = 1, #value do
        hash = (hash * 65599 + string.byte(value, index)) % 4294967291
    end
    return string.format("%08x", hash % 4294967296)
end

function EquipmentRegistry.new(definitions)
    local self = setmetatable({ definitions = {} }, EquipmentRegistry)
    for _, definition in ipairs(definitions or {}) do
        self:register(definition)
    end
    return self
end

function EquipmentRegistry:register(definition)
    assert(definition and definition.equipment_id, "equipment definition is required")
    assert(not self.definitions[definition.equipment_id], "duplicate equipment definition: " .. definition.equipment_id)
    self.definitions[definition.equipment_id] = definition
    return definition
end

function EquipmentRegistry:get(definition_id)
    return self.definitions[definition_id]
end

function EquipmentRegistry:has(definition_id)
    return self:get(definition_id) ~= nil
end

function EquipmentRegistry:all()
    local result = {}
    for definition_id, definition in pairs(self.definitions) do
        result[definition_id] = definition
    end
    return result
end

-- Every peer hashes the complete immutable definition registry before a room
-- starts. Different balance data or projectile metadata must be rejected even
-- when the two players intentionally use different loadouts.
function EquipmentRegistry:hash()
    local definitions = {}
    for definition_id, definition in pairs(self.definitions) do
        definitions[definition_id] = plain(definition)
    end
    return hash_string(stable_encode(definitions))
end

return EquipmentRegistry
