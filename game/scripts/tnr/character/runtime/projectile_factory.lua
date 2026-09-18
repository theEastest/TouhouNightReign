-- Shared projectile descriptor normalization.  Backends consume this plain
-- data rather than re-reading equipment definitions or inventing their own
-- damage/timing rules.
local Factory = {}

local function copy_table(value)
    if type(value) ~= "table" then return value end
    local raw = value.__immutable_raw
    if type(raw) == "table" then value = raw end
    local result = {}
    for key, item in pairs(value) do result[key] = copy_table(item) end
    return result
end

function Factory.from_shot(shot, owner_player_id, source_instance_id)
    shot = shot or {}
    return {
        owner_player_id = tonumber(shot.owner_player_id or owner_player_id) or 1,
        source_instance_id = shot.source_instance_id or source_instance_id,
        source_type = shot.source_type or "weapon",
        projectile_type = shot.projectile_type or "default",
        x = tonumber(shot.x) or 0,
        y = tonumber(shot.y) or 0,
        angle = tonumber(shot.angle) or 90,
        speed = tonumber(shot.speed) or 0,
        damage = tonumber(shot.damage) or 0,
        scale = tonumber(shot.scale) or 1,
        hitbox_scale = tonumber(shot.hitbox_scale) or 1,
        radius = tonumber(shot.radius) or 4,
        penetration = tonumber(shot.penetration) or 0,
        targeting = shot.targeting,
        metadata = copy_table(shot.metadata or {}),
    }
end

return Factory
