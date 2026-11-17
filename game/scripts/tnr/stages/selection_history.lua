-- Deterministic without-replacement selection shared by native room pickers.
local History = {}
History.__index = History

function History.new()
    return setmetatable({ buckets = {} }, History)
end

function History:reset()
    self.buckets = {}
end

function History:used(bucket)
    bucket = tostring(bucket or "default")
    self.buckets[bucket] = self.buckets[bucket] or {}
    return self.buckets[bucket]
end

function History:has(bucket, key)
    if key == nil then return false end
    return self:used(bucket)[tostring(key)] == true
end

function History:mark(bucket, key)
    if key == nil then return false end
    self:used(bucket)[tostring(key)] = true
    return true
end

function History:filter(bucket, entries, key_fn)
    local result = {}
    local used = self:used(bucket)
    for _, entry in ipairs(entries or {}) do
        local key = key_fn(entry)
        if key ~= nil and not used[tostring(key)] then
            result[#result + 1] = entry
        end
    end
    return result
end

function History:pick(bucket, entries, seed, salt, key_fn)
    local available = self:filter(bucket, entries, key_fn)
    if #available == 0 then return nil, "POOL_EXHAUSTED" end
    table.sort(available, function(left, right)
        return tostring(key_fn(left)) < tostring(key_fn(right))
    end)
    local normalized_seed = math.floor(tonumber(seed) or 1) % 2147483647
    local normalized_salt = math.floor(tonumber(salt) or 0)
    local mixed = (normalized_seed + normalized_salt * 1103515245 + 12345) % 2147483647
    local selected = available[(mixed % #available) + 1]
    self:mark(bucket, key_fn(selected))
    return selected
end

return History
