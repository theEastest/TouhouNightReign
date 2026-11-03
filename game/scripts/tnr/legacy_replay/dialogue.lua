-- TH15 MSG timing/control. Presentation is separate from the ECL handshake.
-- Opcode reference: github.com/ExpHP/thpages/blob/master/js/tables/reference/msg.ts
local Dialogue = {}
Dialogue.__index = Dialogue
function Dialogue.new(options)
    return setmetatable({data = options.data, active = false, generation = 0,
        completed = {}, unknown = {}, on_event = options.on_event}, Dialogue)
end
function Dialogue:start(entry)
    assert(not self.active, "cannot replace an active MSG entry")
    self.script = assert(self.data[entry], "missing MSG entry " .. tostring(entry))
    self.entry, self.pc, self.time, self.wait = entry, 1, 0, 0
    self.lines, self.faces, self.shown = {}, {player = 0, enemy = 0}, {}
    self.focus, self.position, self.style = "player", {112, 270}, 0
    self.active, self.stage_end, self.visible = true, false, true
    self.clear_on_text = true
    self:run()
end
function Dialogue:event(kind, value)
    if self.on_event then self.on_event(kind, value) end
end
function Dialogue:run()
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
        elseif id == 11 then self.wait = ins[1]; self.wait_age = 0
        elseif id == 12 then self.generation = self.generation + 1
        elseif id == 13 then self.faces.player = ins[1]
        elseif id == 14 then self.faces.enemy = ins[1]
        elseif id == 17 or id == 15 or id == 16 then
            if self.clear_on_text or id == 15 then self.lines = {}; self.clear_on_text = false end
            self.lines[#self.lines + 1] = ins[1]
            self.visible = true
        elseif id == 18 then self.lines = {}; self.clear_on_text = true
        elseif id == 19 then self:event("boss_music")
        elseif id == 20 then self:event("boss_intro", ins[1])
        elseif id == 21 then self.stage_end = true
        elseif id == 22 then self:event("music_fade")
        elseif id == 28 then self.position = {ins[1], ins[2]}
        elseif id == 29 then self.style = ins[1]
        else self.unknown[id] = (self.unknown[id] or 0) + 1 end
    end
end
function Dialogue:update(input)
    input = input or {}
    local pressed = input.confirm_pressed or (input.shoot and not self.held)
    self.held = input.shoot == true
    if not self.active then return end
    if self.wait > 0 then
        self.wait_age = self.wait_age + 1
        self.wait = self.wait - 1
        if pressed then self.wait = 0 end
        if self.wait > 0 then return end
        self.clear_on_text = true
        self:run()
        return
    end
    self.time = self.time + 1
    self:run()
end
return Dialogue
