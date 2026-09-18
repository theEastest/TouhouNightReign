local CharacterRuntimeBridge = require("tnr.character.runtime.character_runtime_bridge")

local Commit = {}

function Commit.build(session, player_id)
    local descriptor = CharacterRuntimeBridge.new(session, player_id, session.equipment_registry):build_descriptor()
    return {
        player_id = descriptor.player_id,
        character_id = descriptor.character_id,
        definition_registry_hash = descriptor.definition_registry_hash,
        capacity = descriptor.capacity,
        weight = descriptor.weight,
        speed = descriptor.speed,
        high_weapons = descriptor.high_weapons,
        low_weapons = descriptor.low_weapons,
        supports = descriptor.supports,
        self_modifiers = descriptor.self_modifiers,
        support_modifiers = descriptor.support_modifiers,
        loadout_version = descriptor.loadout_version,
        loadout_hash = descriptor.loadout_hash,
    }
end

function Commit.validate(commit, expected_registry_hash)
    if type(commit) ~= "table" then return nil, "INVALID_COMMIT" end
    if tonumber(commit.player_id) == nil or type(commit.character_id) ~= "string" then return nil, "INVALID_IDENTITY" end
    if type(commit.loadout_hash) ~= "string" or commit.loadout_hash == "" then return nil, "MISSING_LOADOUT_HASH" end
    if type(commit.definition_registry_hash) ~= "string" or commit.definition_registry_hash == "" then
        return nil, "MISSING_DEFINITION_REGISTRY_HASH"
    end
    if expected_registry_hash and commit.definition_registry_hash ~= expected_registry_hash then
        return nil, "DEFINITION_REGISTRY_MISMATCH"
    end
    for _, field in ipairs({ "high_weapons", "low_weapons", "supports", "self_modifiers", "support_modifiers" }) do
        if type(commit[field]) ~= "table" then return nil, "INVALID_" .. field:upper() end
    end
    return true
end

function Commit.same_room(commit, room_generation)
    if not room_generation then return true end
    return commit and (commit.room_generation == nil or tostring(commit.room_generation) == tostring(room_generation))
end

return Commit
