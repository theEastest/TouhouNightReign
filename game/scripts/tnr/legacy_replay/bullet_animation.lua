-- Bullet ANM control and presentation. Sprite operands 0..3 pass through
-- TH15's bullet descriptor callback (exe 0x41efd0), including spawn sprites.
local interpolate = require("tnr.legacy_replay.interpolation")
local Animation = {}
Animation.__index = Animation
function Animation.new(script, descriptor, color, spawn_effect)
    local self = setmetatable({script = script, descriptor = descriptor, color = color,
        pc = 1, time = -1, age = 0, sprite = 0, alpha = 255, sx = 1, sy = 1,
        blend = "", offsets = {}, interrupts = {}, tweens = {}, unhandled = {}}, Animation)
    local offset = 0
    for i, ins in ipairs(script) do
        self.offsets[offset] = i
        if ins.id == 5 then self.interrupts[ins[1]] = i + 1 end
        offset = offset + 8 + #ins * 4
    end
    self:run()
    if not spawn_effect and self.interrupts[2] then
        self.pc = self.interrupts[2]
        self.time = script[self.pc].time
        self.stopped = false
        self:run()
    end
    return self
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
        elseif id == 402 then self.sx, self.sy = ins[1], ins[2]
        elseif id == 403 then self.alpha = ins[1]
        elseif id == 409 then self:ramp("alpha", ins[3], ins[1], ins[2])
        elseif id == 412 then
            self:ramp("sx", ins[3], ins[1], ins[2]); self:ramp("sy", ins[4], ins[1], ins[2])
        elseif id == 302 then self.blend = ins[1] == 1 and "mul+add" or ""
        elseif id == 200 then
            self.pc = assert(self.offsets[ins[1]], "invalid bullet ANM jump")
            self.time = ins[2]
        elseif id == 3 or id == 1 then
            self.stopped = true
            if id == 1 then self.alpha = 0 end
            return
        elseif id ~= 0 and id ~= 5 and id ~= 100 then
            self.unhandled[id] = true
        end
    end
    error("bullet ANM instruction budget exhausted")
end
function Animation:advance_to(age)
    while self.age < age do
        self.age, self.time = self.age + 1, self.time + 1
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
return Animation
