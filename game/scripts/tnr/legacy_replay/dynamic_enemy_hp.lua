-- Weapon-based enemy HP scaling for modern TH15 replay runs.
local DynamicEnemyHp = {}

local function weapon_dps(definition)
    if not definition then return 0 end
    local metadata = definition.metadata or {}
    local damage = tonumber(metadata.damage_per_tick) or tonumber(definition.damage) or 0
    local interval = tonumber(metadata.tick_interval) or tonumber(definition.fire_interval) or 0
    if damage <= 0 or interval <= 0 then return 0 end
    local count = tonumber(metadata.projectile_count) or tonumber(definition.count) or 1
    local interval_multiplier = tonumber(metadata.fire_interval_multiplier) or 1
    local damage_multiplier = tonumber(metadata.damage_multiplier) or 1
    return math.max(0, damage * math.max(1, count) * 60
        / math.max(1, interval * interval_multiplier) * damage_multiplier)
end

DynamicEnemyHp.weapon_dps = weapon_dps

function DynamicEnemyHp.measure(session, network_loadouts, network_characters)
    local result = { total_dps = 0, max_weapon_dps = 0, weapon_slots = 0, players = {} }
    if not session or not session.players or not session.players.get_players then return result end
    local registry = session.equipment_registry
    if type(network_loadouts) == "table" then
        for player_id = 1, 2 do
            local descriptor = network_loadouts[player_id]
            if descriptor then
                local player_result = { dps = 0, slots = 0 }
                local character_id = network_characters and network_characters[player_id]
                local character = session.character_registry and session.character_registry.get
                    and session.character_registry:get(character_id) or nil
                player_result.slots = character
                    and ((tonumber(character.high_weapon_slots) or 0) + (tonumber(character.low_weapon_slots) or 0))
                    or (#(descriptor.high_weapons or {}) + #(descriptor.low_weapons or {}))
                for _, slot_type in ipairs({ "high_weapons", "low_weapons" }) do
                    for _, instance in ipairs(descriptor[slot_type] or {}) do
                        local definition = instance.definition
                            or (registry and registry.get and registry:get(instance.definition_id))
                        local dps = weapon_dps(definition)
                        player_result.dps = player_result.dps + dps
                        result.max_weapon_dps = math.max(result.max_weapon_dps, dps)
                    end
                end
                result.players[player_id] = player_result
                result.total_dps = result.total_dps + player_result.dps
                result.weapon_slots = result.weapon_slots + player_result.slots
            end
        end
        result.cap_dps = result.max_weapon_dps * result.weapon_slots
        return result
    end
    for _, player in ipairs(session.players:get_players()) do
        local loadout = player.loadout
        if loadout then
            local player_result = { dps = 0, slots = 0 }
            for _, slot_type in ipairs({ "high_weapons", "low_weapons" }) do
                local slots = loadout[slot_type] or {}
                player_result.slots = player_result.slots + #slots
                for _, instance in ipairs(slots) do
                    if instance and instance ~= false then
                        local definition = registry and registry.get
                            and registry:get(instance.definition_id) or nil
                        local dps = weapon_dps(definition)
                        player_result.dps = player_result.dps + dps
                        result.max_weapon_dps = math.max(result.max_weapon_dps, dps)
                    end
                end
            end
            result.players[player.player_id] = player_result
            result.total_dps = result.total_dps + player_result.dps
            result.weapon_slots = result.weapon_slots + player_result.slots
        end
    end
    result.cap_dps = result.max_weapon_dps * result.weapon_slots
    return result
end

function DynamicEnemyHp.multiplier(measurement, baseline_dps)
    measurement = measurement or {}
    local baseline = math.max(0, tonumber(baseline_dps) or 0)
    local current = math.max(0, tonumber(measurement.total_dps) or 0)
    local cap = math.max(0, tonumber(measurement.cap_dps) or 0)
    local span = cap - baseline
    local progress = 0
    if span > 1e-8 then
        progress = math.max(0, math.min(1, (current - baseline) / span))
    elseif cap > 0 and current >= cap and baseline < cap then
        progress = 1
    end
    return 0.5 + 1.5 * math.sin(progress * math.pi * 0.5)
end

return DynamicEnemyHp
