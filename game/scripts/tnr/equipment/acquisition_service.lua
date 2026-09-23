local AcquisitionService = {}
AcquisitionService.__index = AcquisitionService
local Constants = require("tnr.core.constants")

function AcquisitionService.new(session)
    return setmetatable({ session = session }, AcquisitionService)
end

function AcquisitionService:acquire(player_id, instance)
    local player = self.session:get_player(player_id)
    if not player then return nil, "UNKNOWN_PLAYER" end
    local run_state = self.session.run_state
    if run_state ~= Constants.run_states.MAP
            and run_state ~= Constants.run_states.MAP_PREPARATION
            and run_state ~= Constants.run_states.SHOP
            and run_state ~= Constants.run_states.REWARD then
        return nil, "NOT_MAP"
    end
    if self.session.preparation and self.session.preparation:is_locked(player_id) then
        return nil, "LOADOUT_LOCKED"
    end
    if not instance or instance.owner_player_id ~= player_id then return nil, "WRONG_OWNER" end
    if instance.equipment_type == "RELIC" then return nil, "NOT_EQUIPPABLE" end
    if not self.session.equipment_registry:get(instance.definition_id) then return nil, "UNKNOWN_DEFINITION" end
    if self:get_pending(player_id) then return nil, "PENDING_ACQUISITION" end
    local inventory = player.loadout.inventory
    local added, err = inventory:add(instance)
    if added then return added end
    self.session.preparation.pending_acquisition[player_id] = instance
    return nil, err
end

function AcquisitionService:get_pending(player_id)
    return self.session.preparation.pending_acquisition[player_id]
end

function AcquisitionService:accept_pending(player_id, discard_index)
    if self.session.run_state ~= Constants.run_states.MAP and self.session.run_state ~= Constants.run_states.MAP_PREPARATION
            and self.session.run_state ~= Constants.run_states.SHOP then
        return nil, "NOT_MAP"
    end
    if self.session.preparation and self.session.preparation:is_locked(player_id) then
        return nil, "LOADOUT_LOCKED"
    end
    local pending = self:get_pending(player_id)
    if not pending then return nil, "NO_PENDING_ACQUISITION" end
    local player = self.session:get_player(player_id)
    local inventory = player.loadout.inventory
    local discarded, err = inventory:remove(discard_index)
    if not discarded then return nil, err end
    local added, add_err = inventory:add(pending)
    if not added then
        table.insert(inventory.items, discard_index, discarded)
        return nil, add_err
    end
    self.session.preparation.pending_acquisition[player_id] = nil
    return added, discarded
end

function AcquisitionService:reject_pending(player_id)
    if self.session.run_state ~= Constants.run_states.MAP and self.session.run_state ~= Constants.run_states.MAP_PREPARATION
            and self.session.run_state ~= Constants.run_states.SHOP then
        return nil, "NOT_MAP"
    end
    if self.session.preparation and self.session.preparation:is_locked(player_id) then
        return nil, "LOADOUT_LOCKED"
    end
    if not self:get_pending(player_id) then return nil, "NO_PENDING_ACQUISITION" end
    self.session.preparation.pending_acquisition[player_id] = nil
    return true
end

return AcquisitionService
