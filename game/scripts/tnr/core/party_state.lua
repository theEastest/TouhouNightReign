local PartyState = {}
PartyState.__index = PartyState

function PartyState.new(player_ids, current_node_id)
    local ids = {}
    for index, player_id in ipairs(player_ids or {}) do
        ids[index] = player_id
    end
    return setmetatable({
        player_ids = ids,
        current_node_id = current_node_id,
    }, PartyState)
end

function PartyState:set_current_node(node_id)
    self.current_node_id = node_id
end

return PartyState

