local Immutable = require("tnr.core.immutable")

local Inventory = {}
Inventory.__index = Inventory

function Inventory.new(capacity, items)
    capacity = tonumber(capacity)
    assert(capacity and capacity >= 0 and capacity % 1 == 0, "inventory capacity must be a non-negative integer")
    local self = setmetatable({ capacity = capacity, items = {} }, Inventory)
    for _, item in ipairs(items or {}) do
        assert(#self.items < capacity, "initial inventory exceeds capacity")
        self.items[#self.items + 1] = item
    end
    return self
end

function Inventory:count()
    return #self.items
end

function Inventory:is_full()
    return self:count() >= self.capacity
end

function Inventory:add(item)
    assert(item ~= nil, "inventory item is required")
    if self:is_full() then
        return nil, "INVENTORY_FULL"
    end
    self.items[#self.items + 1] = item
    return item
end

function Inventory:remove(index)
    if type(index) ~= "number" or index < 1 or index > #self.items then
        return nil, "UNKNOWN_ITEM"
    end
    return table.remove(self.items, index)
end

function Inventory:find(instance_id)
    for index, item in ipairs(self.items) do
        if item.instance_id == instance_id then
            return item, index
        end
    end
    return nil
end

function Inventory:to_table()
    return { capacity = self.capacity, items = Immutable.copy(self.items) }
end

function Inventory.from_table(data)
    assert(type(data) == "table", "inventory data is required")
    return Inventory.new(data.capacity, data.items)
end

return Inventory
