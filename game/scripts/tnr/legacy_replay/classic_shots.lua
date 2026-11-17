-- Native player-shot callbacks selected by the original SHT data.
local Rules = require("tnr.legacy_replay.reference_rules")
local AnmPlayer = require("tnr.legacy_replay.anm_player")
local f32 = Rules.float32
local atan2 = math.atan2 or math.atan
local pi, tau = f32(math.pi), f32(2 * math.pi)
local small_turn, large_turn = f32(math.pi / 12), f32(math.pi / 4)
local acceleration, idle_acceleration, steering = f32(.2), f32(.1), f32(.08)

local M = {}

function M.animation(entries, name, index, seed)
    local script = (index or 0) + 5
    for i, entry in ipairs(entries or {}) do
        if entry.scripts[script] then
            local vm = AnmPlayer.new(entry, name, i)
            vm.archive_entries = entries
            vm.random_state = seed or vm.random_state
            vm:play(script)
            return vm
        end
    end
end

function M.sprite(vm)
    return vm:rect()
end

function M.inside_field(shot)
    local vm = shot.player_animation
    local rect = M.sprite(vm)
    if not rect then return true end
    local half_w = rect.w * vm.scale_x * vm.scale2_x / 2
    local half_h = rect.h * vm.scale_y * vm.scale2_y / 2
    local angle = vm.rotate_auto and shot.angle or vm.rotation
    local c, s = math.cos(angle), math.sin(angle)
    local x = shot.x + vm.x + (vm.offset_x or 0)
    local y = shot.y + vm.y + (vm.offset_y or 0)
    -- 459297..45938a checks whether at least one vertex of the previous
    -- sprite quad is in the field, before publishing its new position.
    for sx = -1, 1, 2 do
        for sy = -1, 1, 2 do
            local dx, dy = sx * half_w, sy * half_h
            local px, py = x + dx * c - dy * s, y + dx * s + dy * c
            if px > -192 and px < 192 and py > 0 and py < 448 then return true end
        end
    end
    return false
end

function M.hit(shot)
    local vm = shot.player_animation
    if not vm or not vm:interrupt(1) then
        shot.deleted = true
        return
    end
    -- 459910 switches to the non-damaging ANM branch at one eighth speed.
    shot.spent = true
    shot.speed = f32(shot.speed * .125)
    shot.vx, shot.vy = f32(math.cos(shot.angle) * shot.speed), f32(math.sin(shot.angle) * shot.speed)
end

local function exists(enemy)
    return not enemy.legacy_removed and (not enemy.legacy_deleted or enemy.legacy_delete_after_init)
end

local function can_track(enemy)
    local flags = enemy.legacy_flags or 0
    -- 4303d0 and 459a6d exclude 0x21 and 0x0c000000.
    return flags % 2 == 0 and math.floor(flags / 32) % 2 == 0
        and math.floor(flags / 0x4000000) % 4 == 0
end

local function acquire(x, y, enemies)
    local nearest, best = nil, 256 * 256
    for _, enemy in ipairs(enemies) do
        if exists(enemy) and can_track(enemy) then
            local dx, dy = f32(enemy.x - x), f32(enemy.y - y)
            local dist2 = f32(f32(dx * dx) + f32(dy * dy))
            if dist2 < best then nearest, best = enemy, dist2 end
        end
    end
    return nearest
end

function M.advance_homing(shot, enemies)
    local x, y, angle, speed = shot.x, shot.y, shot.angle, shot.speed
    shot.previous_x, shot.previous_y = x, y
    -- 4589de backs out the initial velocity. 45922a runs the callback on
    -- that position even on the launch tick, before stepping the projectile.
    if shot.just_fired then
        x = f32(x - f32(math.cos(angle) * speed))
        y = f32(y - f32(math.sin(angle) * speed))
    end

    local target = shot.homing_target or acquire(x, y, enemies)
    if target and not exists(target) then target = nil end
    shot.homing_target = target
    if not target or not can_track(target) then
        speed = math.min(16, f32(speed + idle_acceleration))
    elseif (shot.anim_frame or 0) < 60 then
        local desired = f32(atan2(f32(target.y - y), f32(target.x - x)))
        local delta = f32(desired - angle)
        if delta > pi then delta = f32(desired - f32(angle + tau)) end
        if delta < -pi then delta = f32(desired - f32(angle - tau)) end
        local turn = math.abs(delta)
        if turn >= large_turn then speed = math.max(4, f32(speed - acceleration))
        elseif turn < small_turn then speed = math.min(16, f32(speed + acceleration)) end
        angle = f32(angle + f32(delta * steering))
        if angle > pi then angle = f32(angle - tau) end
        if angle < -pi then angle = f32(angle + tau) end
    else
        speed = f32(speed + acceleration)
    end

    shot.angle, shot.speed = angle, speed
    shot.vx, shot.vy = f32(math.cos(angle) * speed), f32(math.sin(angle) * speed)
    shot.x = Rules.motion_coordinate(f32(x + shot.vx))
    shot.y = Rules.motion_coordinate(f32(y + shot.vy))
    shot.just_fired = nil
end

return M
