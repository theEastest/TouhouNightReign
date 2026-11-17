local Immutable = require("tnr.core.immutable")

local PreparationState = {}
PreparationState.__index = PreparationState

function PreparationState.new(player_ids)
    local self = setmetatable({
        selected_node_id = nil,
        player_ready = {},
        loadout_locked = {},
        pending_acquisition = {},
        pending_acquisition_queue = {},
    }, PreparationState)
    self:reset(player_ids or {})
    return self
end

function PreparationState:reset(player_ids, preserve_pending)
    self.selected_node_id = nil
    self.player_ready = {}
    self.loadout_locked = {}
    if not preserve_pending then
        self.pending_acquisition = {}
        self.pending_acquisition_queue = {}
    end
    for _, player_id in ipairs(player_ids or {}) do
        self.player_ready[player_id] = false
        self.loadout_locked[player_id] = false
    end
end

function PreparationState:set_selected_node(node_id)
    self.selected_node_id = node_id
end

function PreparationState:is_locked(player_id)
    return self.loadout_locked[player_id] == true
end

function PreparationState:can_edit(player_id)
    return self.player_ready[player_id] ~= true and self.loadout_locked[player_id] ~= true
end

function PreparationState:set_ready(player_id, value)
    if value == true then
        if self.pending_acquisition[player_id] ~= nil then
            return nil, "PENDING_ACQUISITION"
        end
        self.player_ready[player_id] = true
        self.loadout_locked[player_id] = true
    else
        self.player_ready[player_id] = false
        self.loadout_locked[player_id] = false
    end
    return self.player_ready[player_id]
end

function PreparationState:is_party_ready(player_ids)
    for _, player_id in ipairs(player_ids or {}) do
        if self.player_ready[player_id] ~= true or self.loadout_locked[player_id] ~= true then
            return false
        end
    end
    return #(player_ids or {}) > 0
end

function PreparationState:queue_acquisition(player_id, instance)
    if not self.pending_acquisition[player_id] then
        self.pending_acquisition[player_id] = instance
    else
        local queue = self.pending_acquisition_queue[player_id] or {}
        self.pending_acquisition_queue[player_id] = queue
        queue[#queue + 1] = instance
    end
end

function PreparationState:advance_acquisition(player_id)
    local queue = self.pending_acquisition_queue[player_id]
    self.pending_acquisition[player_id] = queue and table.remove(queue, 1) or nil
    if queue and #queue == 0 then self.pending_acquisition_queue[player_id] = nil end
end

function PreparationState:remove_acquisition(player_id, instance_id)
    local pending = self.pending_acquisition[player_id]
    if pending and pending.instance_id == instance_id then
        self:advance_acquisition(player_id)
        return true
    end
    local queue = self.pending_acquisition_queue[player_id] or {}
    for index, item in ipairs(queue) do
        if item.instance_id == instance_id then
            table.remove(queue, index)
            if #queue == 0 then self.pending_acquisition_queue[player_id] = nil end
            return true
        end
    end
    return false
end

function PreparationState:has_pending()
    for _, item in pairs(self.pending_acquisition) do
        if item ~= nil then return true end
    end
    return false
end

function PreparationState:to_table()
    return {
        selected_node_id = self.selected_node_id,
        player_ready = Immutable.copy(self.player_ready),
        loadout_locked = Immutable.copy(self.loadout_locked),
        pending_acquisition = Immutable.copy(self.pending_acquisition),
        pending_acquisition_queue = Immutable.copy(self.pending_acquisition_queue),
    }
end

function PreparationState.from_table(data)
    assert(type(data) == "table", "preparation state data is required")
    local result = PreparationState.new({})
    result.selected_node_id = data.selected_node_id
    result.player_ready = Immutable.copy(data.player_ready or {})
    result.loadout_locked = Immutable.copy(data.loadout_locked or {})
    result.pending_acquisition = Immutable.copy(data.pending_acquisition or {})
    result.pending_acquisition_queue = Immutable.copy(data.pending_acquisition_queue or {})
    return result
end

return PreparationState
