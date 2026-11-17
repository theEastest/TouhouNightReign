-- Small deterministic projectile previews for the equipment catalog.
-- They reuse the same projectile art renderer as live modern combat while
-- keeping the preview motion inside a short, eight-frame UI loop.
local NativeProjectile = require("tnr.character.runtime.native_projectile")
local Immutable = require("tnr.core.immutable")

local WeaponPreview = { FRAME_COUNT = 8 }
local PI = math.pi

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function projectile_count(definition, metadata, prefix)
    local count = metadata[prefix .. "projectile_count"]
        or metadata.projectile_count or definition.count or 1
    return clamp(math.floor(tonumber(count) or 1), 1, 8)
end

local function shot_angles(metadata, count)
    local configured = metadata.spread_angles
    local result = {}
    if type(configured) == "table" then
        for index, value in ipairs(configured) do
            if index > count then break end
            result[index] = tonumber(value) or 0
        end
    end
    if #result == 0 then
        local spread = tonumber(metadata.spread) or 0
        if count == 1 or spread == 0 then
            for index = 1, count do result[index] = 0 end
        else
            for index = 1, count do
                result[index] = -spread * 0.5 + spread * (index - 1) / (count - 1)
            end
        end
    end
    while #result < count do result[#result + 1] = 0 end
    return result
end

local function variants(definition, metadata)
    if definition.dual_mode and (metadata.high_projectile_type or metadata.low_projectile_type) then
        local result = {}
        for _, prefix in ipairs({ "high_", "low_" }) do
            local kind = metadata[prefix .. "projectile_type"]
            if kind then
                result[#result + 1] = {
                    projectile_type = kind,
                    count = projectile_count(definition, metadata, prefix),
                    speed = tonumber(metadata[prefix .. "projectile_speed"])
                        or tonumber(definition.projectile_speed) or 0,
                    beam = metadata[prefix .. "beam"] == true,
                    spread_angles = nil,
                    offset_x = prefix == "high_" and -24 or 24,
                }
            end
        end
        if #result > 0 then return result end
    end
    return { {
        projectile_type = metadata.preview_projectile_type or definition.projectile_type,
        count = projectile_count(definition, metadata, ""),
        speed = tonumber(definition.projectile_speed) or tonumber(metadata.projectile_speed) or 0,
        beam = metadata.beam == true or definition.pattern == "beam",
        spread_angles = shot_angles(metadata, projectile_count(definition, metadata, "")),
        offset_x = 0,
    } }
end

--- Return the projectiles visible on one of the preview's eight loop frames.
function WeaponPreview.sample(definition, frame, center_x, bottom_y)
    if not definition or definition.equipment_type ~= "WEAPON" then return {} end
    local phase = math.floor(tonumber(frame) or 0) % WeaponPreview.FRAME_COUNT
    center_x, bottom_y = tonumber(center_x) or 0, tonumber(bottom_y) or 0
    local metadata = Immutable.copy(definition.metadata or {})
    local result = {}

    for _, variant in ipairs(variants(definition, metadata)) do
        if variant.projectile_type then
            local volleys = variant.beam and { 0, 5 } or { 0, 4 }
            for _, fired_at in ipairs(volleys) do
                local age = phase - fired_at
                if age >= 0 then
                    local angles = variant.spread_angles or shot_angles(metadata, variant.count)
                    for shot_index = 1, variant.count do
                        local angle = PI * 0.5 + math.rad(angles[shot_index] or 0)
                        local side = variant.count > 1 and angles[shot_index] == 0
                            and (shot_index - (variant.count + 1) * 0.5) * 10 or 0
                        local speed = clamp(variant.speed * 0.45, 3, 9)
                        local beam = variant.beam
                        result[#result + 1] = {
                            projectile_type = variant.projectile_type,
                            angle = angle,
                            x = center_x + variant.offset_x + side + math.cos(angle) * speed * age,
                            y = bottom_y + math.sin(angle) * speed * age,
                            scale = 1,
                            hitbox_scale = 1,
                            beam = beam,
                            beam_width = beam and (6 + phase * 0.5) or nil,
                            beam_length = beam and (30 + age * 8) or nil,
                            field = false,
                            age = age,
                        }
                    end
                end
            end
        end
    end

    if metadata.legendary_effect == "wind_field" and phase >= 3 then
        result[#result + 1] = {
            field = true,
            projectile_type = "sanae_wind",
            x = center_x,
            y = bottom_y + 52,
            angle = PI * 0.5,
            scale = 1,
            hitbox_scale = 1,
            field_radius = 18 + (phase - 3) * 2,
            age = phase - 3,
        }
    end

    return result
end

--- Draw one loop frame using the native game's projectile art and animation.
function WeaponPreview.draw(lstg, definition, frame, center_x, bottom_y, scale)
    if not lstg or type(lstg.Render) ~= "function" then return 0 end
    local count = 0
    for _, projectile in ipairs(WeaponPreview.sample(definition, frame, center_x, bottom_y)) do
        local ok = pcall(NativeProjectile.render_projectile, lstg, projectile,
            projectile.x, projectile.y, scale or 0.45, 245)
        if ok then count = count + 1 end
    end
    return count
end

return WeaponPreview
