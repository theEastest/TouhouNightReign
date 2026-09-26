-- ANM animation player.
--
-- The reference games store sprite rectangles and animation scripts in `.anm`
-- archives. tools/compile_anm.py lowers a `thanm -l` dump into Lua tables;
-- this module plays those scripts and reports the current sprite rectangle so
-- the adapter can draw it with the engine's sprite API.
--
-- Instruction ids follow anm version 8 (see thtk thanm.c `formats_v8`). Only
-- the opcodes needed to render enemies and bullets are implemented; the rest
-- are recorded so an audit can list what still needs support.

local AnmPlayer = {}

AnmPlayer.__index = AnmPlayer

-- Opcodes used by the stage 1 enemy and bullet scripts.
local OP = {
    SET_ACTIVE_SPRITE = 300,
    JUMP = 200,
    STOP = 1,
    EXIT = 0,
    SET_SCALE = 2,
    SET_ALPHA = 3,
    SET_COLOR = 4,
    FLIP_X = 7,
    FLIP_Y = 8,
    SET_ROTATION = 9,
    JUMP_DEC = 200,
    JUMP_REL = 201,
    SET_POS = 17,
    SET_BLEND_ADD = 13,
    SET_BLEND_DEFAULT = 14,
    SET_VISIBILITY = 29,
    ANM_SET_SPRITE = 304,
    ANM_PLAY = 300,
    ANM_SET_MAIN = 306,
    ANM_PLAY_ABS = 308,
    ANM_SET_SPRITE_ALT = 303,
    POS_TIME_LINEAR = 18,
    POS_TIME_DECEL = 19,
    POS_TIME_ACCEL = 20,
    SET_ANGLE_VEL = 10,
    SET_SCALE_SPEED = 11,
    FADE = 12,
    SCALE_TIME = 30,
    COLOR_TIME = 63,
    ALPHA_TIME = 78,
    INTERRUPT_LABEL = 22,
}

AnmPlayer.OP = OP

---@param archive table one compiled archive entry (texture, sprites, scripts)
---@param archive_name string? the archive key the entry belongs to
---@param entry_index number? the entry position inside that archive
function AnmPlayer.new(archive, archive_name, entry_index)
    return setmetatable({
        archive = archive,
        archive_name = archive_name,
        entry_index = entry_index or 1,
        sprites = archive and archive.sprites or {},
        scripts = archive and archive.scripts or {},
        script = nil,
        pc = 1,
        frame = 0,
        sprite = 1,
        scale_x = 1,
        scale_y = 1,
        alpha = 255,
        rotation = 0,
        flip_x = false,
        flip_y = false,
        additive = false,
        visible = true,
        finished = false,
        loops = {},
        unhandled = {},
    }, AnmPlayer)
end

--- Start a script from its first instruction.
function AnmPlayer:play(script_id)
    if not self.scripts[script_id] then
        self.unhandled["script:" .. tostring(script_id)] =
            (self.unhandled["script:" .. tostring(script_id)] or 0) + 1
        return false
    end
    self.script = script_id
    self.pc = 1
    self.frame = 0
    self.finished = false
    self.loops = {}
    return true
end

--- Advance the animation by one frame.
function AnmPlayer:update()
    if self.finished or not self.script then return end
    self.frame = self.frame + 1
    local instructions = self.scripts[self.script]
    if not instructions then return end
    -- Execute every instruction whose time has arrived. Scripts list them in
    -- ascending time order, so stop as soon as the next one is in the future.
    local guard = 0
    while self.pc <= #instructions and guard < 256 do
        guard = guard + 1
        local instruction = instructions[self.pc]
        if instruction.time > self.frame then break end
        self.pc = self.pc + 1
        self:execute(instruction)
    end
end

--- Apply one instruction.
function AnmPlayer:execute(instruction)
    local id = instruction.id
    if id == OP.ANM_PLAY or id == OP.SET_ACTIVE_SPRITE then
        -- `id 300` sets the displayed sprite.
        local sprite = instruction[1]
        if sprite ~= nil then self.sprite = sprite + 1 end
    elseif id == OP.JUMP_DEC then
        -- { offset, count } jumps back `offset` instructions, repeating
        -- `count` times. A count of 0 loops forever.
        local offset, count = instruction[1] or 0, instruction[2] or 0
        local key = self.pc
        local used = (self.loops[key] or 0) + 1
        self.loops[key] = used
        if count == 0 or used < count then
            self.pc = math.max(1, self.pc - offset)
        end
    elseif id == OP.STOP or id == OP.EXIT then
        self.finished = true
    elseif id == OP.SET_SCALE then
        self.scale_x = instruction[1] or 1
        self.scale_y = instruction[2] or self.scale_x
    elseif id == OP.SET_ALPHA then
        self.alpha = instruction[1] or 255
    elseif id == OP.FLIP_X then
        self.flip_x = (instruction[1] or 0) ~= 0
    elseif id == OP.FLIP_Y then
        self.flip_y = (instruction[1] or 0) ~= 0
    elseif id == OP.SET_ROTATION then
        self.rotation = instruction[1] or 0
    elseif id == OP.SET_BLEND_ADD then
        self.additive = true
    elseif id == OP.SET_BLEND_DEFAULT then
        self.additive = false
    elseif id == OP.SET_VISIBILITY then
        self.visible = (instruction[1] or 0) ~= 0
    elseif id == OP.ANM_SET_SPRITE then
        -- Alternative sprite-set form used by some archives.
        local sprite = instruction[1]
        if sprite ~= nil then self.sprite = sprite + 1 end
    else
        -- Control/setup opcodes with no rendering effect, and anything not yet
        -- implemented. Record the unknown ones for the coverage audit.
        if id ~= OP.ANM_SET_MAIN and id ~= OP.ANM_PLAY_ABS and id ~= OP.JUMP_REL
                and id ~= OP.POS_TIME_LINEAR and id ~= OP.POS_TIME_DECEL
                and id ~= OP.POS_TIME_ACCEL and id ~= OP.SET_ANGLE_VEL
                and id ~= OP.SET_SCALE_SPEED and id ~= OP.FADE
                and id ~= OP.SCALE_TIME and id ~= OP.COLOR_TIME
                and id ~= OP.ALPHA_TIME and id ~= OP.INTERRUPT_LABEL
                and id ~= OP.SET_POS and id ~= OP.SET_COLOR
                and id ~= OP.ANM_SET_SPRITE_ALT then
            local key = "op:" .. tostring(id)
            self.unhandled[key] = (self.unhandled[key] or 0) + 1
        end
    end
end

--- Current sprite rectangle, or nil when the animation has no sprite yet.
function AnmPlayer:rect()
    return self.sprites[self.sprite]
end

return AnmPlayer
