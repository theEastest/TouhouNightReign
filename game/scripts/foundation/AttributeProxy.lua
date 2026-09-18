-- Small compatibility implementation for THlib's virtual attributes.
local M = {}

function M.createProxy(key)
    return { key = key }
end

function M.applyProxies(target, proxies)
    local storage = rawget(target, "__attribute_proxy_storage") or {}
    rawset(target, "__attribute_proxy_storage", storage)
    local previous = getmetatable(target)
    local previous_index = previous and previous.__index
    local previous_newindex = previous and previous.__newindex
    local index = {}
    if type(previous_index) == "table" then
        for key, value in pairs(previous_index) do
            index[key] = value
        end
    end
    setmetatable(target, {
        __index = function(self, key)
            local proxy = proxies[key]
            if proxy and proxy.getter then
                return proxy:getter(key, storage)
            end
            if type(previous_index) == "function" then
                return previous_index(self, key)
            end
            return index[key]
        end,
        __newindex = function(self, key, value)
            local proxy = proxies[key]
            if proxy and proxy.setter then
                return proxy:setter(key, value, storage)
            end
            if type(previous_newindex) == "function" then
                return previous_newindex(self, key, value)
            end
            rawset(self, key, value)
        end,
    })
end

return M
