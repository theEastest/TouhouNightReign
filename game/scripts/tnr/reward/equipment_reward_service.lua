local EquipmentInstance = require("tnr.equipment.equipment_instance")

local EquipmentRewardService = {}
EquipmentRewardService.__index = EquipmentRewardService

function EquipmentRewardService.new(session)
    return setmetatable({ session = session }, EquipmentRewardService)
end

function EquipmentRewardService:grant(definition_id, player_id)
    local definition = self.session.equipment_registry:get(definition_id)
    if not definition then return nil, "UNKNOWN_DEFINITION" end
    player_id = tonumber(player_id) or self.session.local_player_id or 1
    local instance = EquipmentInstance.new(definition, player_id)
    local acquired, err = self.session.acquisition_service:acquire(player_id, instance)
    return {
        instance = instance,
        acquired = acquired ~= nil,
        pending = acquired == nil and err ~= nil,
        error = err,
    }
end

return EquipmentRewardService
