-- All amounts are percentages of a full gauge; fixed simulation rate is 60 Hz.
local Gauge = {}
Gauge.__index = Gauge
Gauge.rarity_cost = { COMMON = 3.33, UNCOMMON = 4, RARE = 5, EPIC = 6, LEGENDARY = 7 }
function Gauge.new()
    return setmetatable({ value = 100, maximum = 100, progress = 0, dry_frames = 0,
        idle_frames = 0, hot_frames = 0, buff_frames = 0, triggers = 0, frame = 0,
        hazard_frames = 0, hazard = 0, resting = false, progress_maximum = 100, rest_delay = 60, hot_duration = 300, hooks = {} }, Gauge)
end
-- Personal upgrades can adjust rates, capacity, pickup amount and trigger effects.
function Gauge:on(event, callback)
    self.hooks[event] = self.hooks[event] or {}
    table.insert(self.hooks[event], callback)
end
function Gauge:emit(event, data)
    for _, callback in ipairs(self.hooks[event] or {}) do callback(data, self) end
    return data
end
function Gauge:restore(percent, source)
    local data = self:emit("restore", { percent = percent, source = source })
    local before = self.value
    self.value = math.min(self.maximum, self.value + math.max(0, data.percent) * self.maximum / 100)
    self:emit("restored", {source=source,before=before,after=self.value,amount=self.value-before})
end
function Gauge:add_points(points, source)
    local before=self.value
    self.value=math.min(self.maximum,self.value+math.max(0,points))
    self:emit("restored",{source=source,before=before,after=self.value,amount=self.value-before})
end
function Gauge:damage_multiplier()
    return self.buff_frames > 0 and 1 + self.triggers * 0.1 or 1
end
function Gauge:update_progress(input)
    if self.value < 30 then
        self.dry_frames = 0
        self.progress = self.progress + 0.1
        if self.progress >= self.progress_maximum - 1e-8 then
            self.progress = 0
            self.triggers = self.triggers + 1
            self.buff_frames = 600
            self.hazard_frames = 600
            self.event = input.choose_hazard and input.choose_hazard() or ((self.triggers - 1) % 3 + 1)
            self.hazard = self.event
            self:emit("trigger", { hazard = self.event, count = self.triggers })
        end
    else
        self.dry_frames = self.dry_frames + 1
        if self.dry_frames >= 300 then self.progress = 0 end
    end
end
function Gauge:set_maximum(value)
    self.maximum = math.max(1, tonumber(value) or 100)
    self.value = math.min(self.value, self.maximum)
end
function Gauge:step(input)
    if input.paused then return end
    self.frame = self.frame + 1
    self.event = nil
    self.buff_frames = math.max(0, self.buff_frames - 1)
    self.hazard_frames = math.max(0, self.hazard_frames - 1)
    self.resting = false
    if self.hot_frames > 0 then
        self.hot_frames = self.hot_frames - 1
        self.idle_frames = 0
        if self.hot_frames == 0 then self.value = self.maximum end
        self:update_progress(input)
        return
    end
    if input.attack_allowed == false then
        self.idle_frames = 0
        self.dry_frames = self.dry_frames + 1
        if self.dry_frames >= 300 then self.progress = 0 end
        return
    end
    if input.firing or input.moving then self.idle_frames = 0
    else self.idle_frames = self.idle_frames + 1 end
    local low = self.value < 30
    self.resting = self.idle_frames > self.rest_delay
    local rates = self:emit("rates", { regeneration = (input.supports or 0) * 100 / 30 * (low and 2 or 1),
        resting = self.resting and 33 or 0, consumption = input.firing and (input.cost or 0) or 0 })
    -- Exhaustion takes precedence over regeneration and blocks this frame's shot.
    self.value = math.max(0, self.value - rates.consumption * self.maximum / 6000)
    if self.value < self.maximum * 0.01 then
        self.hot_frames = self.hot_duration
        if self.hot_frames == 0 then self.value = self.maximum end
        self.idle_frames = 0
        self.resting = false
        self:emit("exhausted", {})
    else
        self:restore((rates.regeneration + rates.resting) / 60, "regeneration")
    end
    self:update_progress(input)
end
function Gauge:to_table()
    local result = {}
    for key, value in pairs(self) do
        if type(value) == "number" or type(value) == "boolean" then result[key] = value end
    end
    result.event = nil
    return result
end
function Gauge:apply_snapshot(snapshot)
    for key, value in pairs(snapshot or {}) do
        if key ~= "event" and (type(self[key]) == "number" or type(self[key]) == "boolean")
            and type(value) == type(self[key]) then self[key] = value end
    end
end
return Gauge
