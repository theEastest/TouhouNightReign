-- Bullet ANM control and presentation. Sprite operands 0..3 pass through
-- TH15's bullet descriptor callback (exe 0x41efd0), including spawn sprites.
local interpolate = require("tnr.legacy_replay.interpolation")
local Geometry = require("tnr.legacy_replay.anm_geometry")
local Animation = {}
Animation.__index = Animation
function Animation.new(script, descriptor, color, spawn_effect, spawn_interrupt)
    local self = setmetatable({script = script, descriptor = descriptor, color = color,
        pc = 1, time = -1, age = 0, sprite = 0, alpha = 255, sx = 1, sy = 1,
        blend = "", rotation=0,rotation_speed=0,geometry_width=nil,geometry_height=nil,
        offsets = {}, interrupts = {}, tweens = {}, unhandled = {}}, Animation)
    local offset = 0
    for i, ins in ipairs(script) do
        self.offsets[offset] = i
        if ins.id == 5 then self.interrupts[ins[1]] = i + 1 end
        offset = offset + 8 + #ins * 4
    end
    self:run()
    local initial_interrupt=spawn_interrupt or (not spawn_effect and 2)
    if initial_interrupt then self:interrupt(initial_interrupt) end
    return self
end
function Animation:interrupt(id, random_angle)
    local pc = self.interrupts[id]
    if not pc or not self.script[pc] then return false end
    self.pc, self.time = pc, self.script[pc].time
    self.stopped, self.finished = false, false
    self.random_angle = random_angle
    self:run()
    return not self.finished
end
function Animation:ramp(key, target, duration, mode)
    if duration <= 0 then self[key], self.tweens[key] = target, nil; return end
    self.tweens[key] = {start = self[key], target = target, elapsed = 0, duration = duration, mode = mode}
end
function Animation:run()
    if self.stopped then return end
    for _ = 1, 128 do
        local ins = self.script[self.pc]
        if not ins or ins.time > self.time then return end
        self.pc = self.pc + 1
        local id = ins.id
        if id == 300 then self.sprite = ins[1]
        elseif id == 100 and ins[1] == 10000 then self.live = ins[2] ~= 0
        elseif id == 402 then self.sx, self.sy = ins[1], ins[2]
        elseif id == 403 then self.alpha = ins[1]
        elseif id == 409 then self:ramp("alpha", ins[3], ins[1], ins[2])
        elseif id == 412 then
            self:ramp("sx", ins[3], ins[1], ins[2]); self:ramp("sy", ins[4], ins[1], ins[2])
        elseif id == 303 then
            self.blend_mode,self.blend=ins[1],Geometry.blend(ins[1])
        elseif id == 302 then self.render_mode=ins[1]
        elseif id == 424 then self.rotate_auto=ins[1]~=0
        elseif id == 401 then
            local z = ins[3] or 0
            if z == 10010 and math.floor((ins.mask or 0) / 4) % 2 == 1 then z = self.random_angle or 0 end
            self.rotation = z
        elseif id == 415 then self.rotation_speed=ins[3] or 0
        elseif id == 603 then self.geometry_width,self.geometry_height=ins[1],ins[2]
        elseif id == 200 then
            self.pc = assert(self.offsets[ins[1]], "invalid bullet ANM jump")
            self.time = ins[2]
        elseif id == 3 or id == 1 then
            self.stopped = true
            if id == 1 then self.alpha, self.finished = 0, true end
            return
        elseif id ~= 0 and id ~= 5 and id ~= 100 then
            self.unhandled[id] = true
        end
    end
    error("bullet ANM instruction budget exhausted")
end
function Animation:advance_to(age)
    while not self.finished and self.age < age do
        self.age, self.time = self.age + 1, self.time + 1
        self.rotation=self.rotation+self.rotation_speed
        for key, tween in pairs(self.tweens) do
            tween.elapsed = tween.elapsed + 1
            local t = interpolate(tween.mode, tween.elapsed / tween.duration)
            self[key] = tween.start + (tween.target - tween.start) * t
            if tween.elapsed >= tween.duration then self.tweens[key] = nil end
        end
        self:run()
    end
end
function Animation:global_sprite()
    if self.descriptor.sprites[1] < 0 then return self.sprite end
    local variants = self.descriptor.variants[self.sprite + 1]
    return variants and variants[self.color + 1] or nil
end

function Animation.spawn_ticks(script, descriptor, interrupt)
    local animation = Animation.new(script, descriptor, 0, true, interrupt)
    local has_interrupt = interrupt and animation.interrupts[interrupt]
    for age = 0, 64 do
        animation:advance_to(age)
        if animation.live then
            -- 477510 starts at time zero. 41b0ef runs one more tick at birth;
            -- a spawn interrupt instead starts at its own time in that tick.
            return math.max(0, age - (has_interrupt and 0 or 2)), has_interrupt and 0 or 2
        end
        if animation.finished then break end
    end
end
return Animation
