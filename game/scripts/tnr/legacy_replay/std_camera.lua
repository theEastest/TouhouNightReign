-- STD camera timeline. Byte offsets are retained by compile_std for jumps.
local Camera = {}
Camera.__index = Camera
local ease = require("tnr.legacy_replay.interpolation")
local function copy(v) local r = {}; for i, n in ipairs(v) do r[i] = n end; return r end
local function color(n)
    return { math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
        math.floor(n / 256) % 256, n % 256 }
end
function Camera.new(script)
    local self = setmetatable({script = script or {}, pc = 1, time = 0,
        position = {0, 0, -600}, direction = {0, 0, 1}, up = {0, 1, 0},
        fov = math.pi / 5, fog = {0, 0, 0, 0, 400, 1400},
        tweens = {}, offsets = {}, unhandled = {}}, Camera)
    for i, ins in ipairs(self.script) do self.offsets[ins.offset] = i end
    self:execute_due()
    return self
end
function Camera:ramp(key, duration, mode, target)
    self.tweens[key] = {from = copy(self[key]), target = target, elapsed = 0,
        duration = math.max(1, duration), mode = mode}
end
function Camera:execute_due()
    for _ = 1, 128 do
        local ins = self.script[self.pc]
        if not ins or ins.time > self.time then return end
        self.pc = self.pc + 1
        local a, id = ins.args, ins.id
        if id == 1 then
            local target = self.offsets[a[1]]
            if not target then error("STD jump has no instruction at offset " .. tostring(a[1])) end
            self.pc, self.time = target, a[2]
        elseif id == 2 or id == 4 or id == 6 then
            local key = id == 2 and "position" or id == 4 and "direction" or "up"
            self[key], self.tweens[key] = copy(a), nil
        elseif id == 3 or id == 5 then
            self:ramp(id == 3 and "position" or "direction", a[1], a[2], {a[3], a[4], a[5]})
        elseif id == 7 then self.fov = a[1]
        elseif id == 8 then
            self.fog = color(a[1]); self.fog[5], self.fog[6] = a[2], a[3]
            self.tweens.fog = nil
        elseif id == 9 then
            local target = color(a[3]); target[5], target[6] = a[4], a[5]
            self:ramp("fog", a[1], a[2], target)
        else
            -- Includes background interrupts: expose rather than silently claiming support.
            self.unhandled[id] = (self.unhandled[id] or 0) + 1
        end
    end
    error("STD camera instruction budget exhausted")
end
function Camera:update()
    for key, tween in pairs(self.tweens) do
        tween.elapsed = math.min(tween.duration, tween.elapsed + 1)
        local t = ease(tween.mode, tween.elapsed / tween.duration)
        for i, value in ipairs(tween.target) do
            self[key][i] = tween.from[i] + (value - tween.from[i]) * t
        end
        if tween.elapsed == tween.duration then self.tweens[key] = nil end
    end
    self.time = self.time + 1
    self:execute_due()
end
return Camera
