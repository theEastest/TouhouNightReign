local Immutable = require("tnr.core.immutable")

local PreparationState = {}
PreparationState.__index = PreparationState

function PreparationState.new(player_ids)
    local self = setmetatable({
        selected_node_id = nil,
        player_ready = {},
        loadout_locked = {},
        pending_acquisition = {},
    }, PreparationState)
    self:reset(player_ids or {})
    return self
end

function PreparationState:reset(player_ids)
    self.selected_node_id = nil
    self.player_ready = {}
    self.loadout_locked = {}
    self.pending_acquisition = {}
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
    }
end

function PreparationState.from_table(data)
    assert(type(data) == "table", "preparation state data is required")
    local result = PreparationState.new({})
    result.selected_node_id = data.selected_node_id
    result.player_ready = Immutable.copy(data.player_ready or {})
    result.loadout_locked = Immutable.copy(data.loadout_locked or {})
    result.pending_acquisition = Immutable.copy(data.pending_acquisition or {})
    return result
end

return PreparationState
