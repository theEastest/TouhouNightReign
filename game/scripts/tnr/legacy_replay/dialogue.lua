-- TH15 MSG timing/control. Presentation is separate from the ECL handshake.
-- Opcode reference: github.com/ExpHP/thpages/blob/master/js/tables/reference/msg.ts
local Dialogue = {}
Dialogue.__index = Dialogue
function Dialogue.new(options)
    return setmetatable({data = options.data, active = false, generation = 0,
        shoot_frames = 0, skip_frames = 0,
        completed = {}, unknown = {}, on_event = options.on_event}, Dialogue)
end
function Dialogue:start(entry)
    assert(not self.active, "cannot replace an active MSG entry")
    self.script = assert(self.data[entry], "missing MSG entry " .. tostring(entry))
    self.entry, self.pc, self.time, self.wait = entry, 1, 0, 0
    self.lines, self.faces, self.shown = {}, {player = 0, enemy = 0}, {}
    self.focus, self.position, self.style = "player", {112, 270}, 0
    self.active, self.stage_end, self.visible = true, false, true
    self.resume_available,self.resume_pending=false,false
    self.skippable, self.skip_latched = false, false
    self.clear_on_text = true
    self:run()
end
function Dialogue:event(kind, value)
    if self.on_event then self.on_event(kind, value) end
end
function Dialogue:fast_forwarding()
    -- 437f15..437f5c enables skipping after a new press and twenty held ticks.
    return self.skippable and self.skip_latched
        and (self.shoot_frames>=20 or self.skip_frames>=20)
end
function Dialogue:run(pressed)
    while self.active and self.wait == 0 do
        local ins = self.script[self.pc]
        if not ins then error("MSG entry ended without opcode 0") end
        if ins.time > self.time then return end
        self.pc = self.pc + 1
        local id = ins.id
        if id == 0 then
            self.active, self.visible = false, false
            self.generation = self.generation + 1
            self.completed[self.entry] = true
            self:event("complete", self.entry)
        elseif id == 1 then self.shown.player = true
        elseif id == 2 then self.shown.enemy = true
        elseif id == 4 then self.shown.player = false
        elseif id == 5 then self.shown.enemy = false
        elseif id == 6 then self.visible = false
        elseif id == 7 or id == 8 then
            self.focus = id == 7 and "player" or "enemy"
            self.clear_on_text = true
        elseif id == 9 then self.focus = nil
        elseif id == 10 then self.skippable = ins[1] ~= 0
        elseif id == 11 then
            if pressed or self:fast_forwarding() then self.clear_on_text = true
            else self.wait = ins[1] end
        elseif id == 12 then
            self.generation = self.generation + 1
            self.resume_pending = true
        elseif id == 13 then self.faces.player = ins[1]
        elseif id == 14 then self.faces.enemy = ins[1]
        elseif id == 17 or id == 15 or id == 16 then
            if self.clear_on_text or id == 15 then self.lines = {}; self.clear_on_text = false end
            self.lines[#self.lines + 1] = ins[1]
            self.visible = true
        elseif id == 18 then self.lines = {}; self.clear_on_text = true
        elseif id == 19 then self:event("boss_music")
        elseif id == 20 then self:event("boss_intro", ins[1])
        elseif id == 21 then
            self.stage_end = true
            self:event("stage_end", self.entry)
        elseif id == 22 then self:event("music_fade")
        elseif id == 28 then self.position = {ins[1], ins[2]}
        elseif id == 29 then self.style = ins[1]
        else self.unknown[id] = (self.unknown[id] or 0) + 1 end
    end
end
function Dialogue:_update(input, advance)
    input = input or {}
    local shoot_pressed = input.shoot and self.shoot_frames==0
    local skip_pressed = input.skip_dialogue and self.skip_frames==0
    local pressed = input.confirm or input.confirm_pressed or shoot_pressed
    self.shoot_frames = input.shoot and self.shoot_frames+1 or 0
    self.skip_frames = input.skip_dialogue and self.skip_frames+1 or 0
    if not self.active then return end
    self.skip_latched = self.skip_latched or shoot_pressed or skip_pressed
    if advance==false then return end
    local skipping = self:fast_forwarding()
    if self.wait > 0 then
        self.wait = self.wait - 1
        if pressed or skipping then self.wait = 0 end
        if self.wait > 0 then return end
        self.clear_on_text = true
        self:run(pressed)
        return
    end
    self.time = skipping and self.script[self.pc].time or self.time+1
    self:run(pressed)
end
function Dialogue:update(input,advance)
    -- 438f84 publishes a one-tick resume flag. All ECL waiters observe it
    -- before the next GUI tick; it is not consumed separately by each thread.
    self.resume_available=false
    self:_update(input,advance)
    self.resume_available=self.resume_pending==true
    self.resume_pending=false
end
return Dialogue
