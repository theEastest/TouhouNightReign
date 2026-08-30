local Immutable = {}

local function clone(value, seen)
    if type(value) ~= "table" then
        return value
    end
    -- LuaJIT 5.1 does not invoke __pairs. Immutable proxies expose their
    -- backing table through this private read-only view so serialization and
    -- runtime descriptors retain nested definition metadata.
    local backing = value.__immutable_raw
    if type(backing) == "table" then value = backing end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[clone(key, seen)] = clone(item, seen)
    end
    return result
end

function Immutable.copy(value)
    return clone(value)
end

function Immutable.freeze(data, methods)
    assert(type(data) == "table", "immutable data must be a table")
    local seen = {}
    local function wrap(value)
        if type(value) ~= "table" then
            return value
        end
        if seen[value] then
            return seen[value]
        end
        local raw = {}
        local proxy = {}
        seen[value] = proxy
        for key, item in pairs(value) do
            raw[wrap(key)] = wrap(item)
        end
        local meta = {}
        meta.__index = function(_, key)
            if key == "__immutable_raw" then return raw end
            if raw[key] ~= nil then
                return raw[key]
            end
            return value == data and methods and methods[key] or nil
        end
        meta.__newindex = function(_, key)
            error("immutable definition cannot be modified: " .. tostring(key), 2)
        end
        meta.__pairs = function()
            return next, raw, nil
        end
        meta.__len = function()
            return #raw
        end
        meta.__metatable = false
        setmetatable(proxy, meta)
        return proxy
    end
    return wrap(data)
end

-- Kept as a separate helper because runtime state uses mutable tables while
-- definitions use the deep immutable wrapper above.
function Immutable.freeze_shallow(data, methods)
    local proxy = {}
    local meta = {}
    meta.__index = function(_, key)
        if data[key] ~= nil then
            return data[key]
        end
        return methods and methods[key]
    end
    meta.__newindex = function(_, key)
        error("immutable definition cannot be modified: " .. tostring(key), 2)
    end
    meta.__pairs = function()
        return next, data, nil
    end
    meta.__len = function()
        return #data
    end
    meta.__metatable = false
    return setmetatable(proxy, meta)
end

return Immutable
