-- Stage background renderer for the legacy replay.
--
-- The reference background is a stack of scrolling layers described by the
-- stage std file. Each entry names a texture (through the stage wl animation
-- script index), a tile size and a list of FACE positions that tile the layer
-- horizontally across a scrolling world.
--
-- Each layer also runs its own animation script, and that script is what drives
-- the scroll: opcode 407 ramps the layer position over a frame count and
-- opcode 200 loops it. Reproducing that gives the original parallax rather than
-- a guessed uniform scroll speed.
--
-- Geometry is the measured reference playfield: 384x448 units rendered into a
-- 462x538.8 px region at (37.2, 556.8) in the 1280x720 canvas.

local StageBackground = {}

StageBackground.__index = StageBackground

local PLAYFIELD_WIDTH = 384
local PLAYFIELD_HEIGHT = 448
local CANVAS_SCALE = 720 / 960
local SCALE = 616.0 / 384 * CANVAS_SCALE
local FIELD_LEFT = 49.6 * CANVAS_SCALE
local FIELD_TOP = 742.4 * CANVAS_SCALE
local FIELD_RIGHT = FIELD_LEFT + PLAYFIELD_WIDTH * SCALE
local FIELD_BOTTOM = FIELD_TOP - PLAYFIELD_HEIGHT * SCALE

StageBackground.SCALE = SCALE
StageBackground.FIELD_LEFT = FIELD_LEFT
StageBackground.FIELD_TOP = FIELD_TOP
StageBackground.FIELD_RIGHT = FIELD_RIGHT
StageBackground.FIELD_BOTTOM = FIELD_BOTTOM

--- Per-stage fog tint, sampled from a capture of the original game.
-- The reference composites a coloured overlay over the playfield. Stage 1 uses
-- a magenta violet wash that turns the green forest canopy into the purple
-- scene the original shows. The colour and weight are solved from the captured
-- frame against the raw texture: forest RGB(82,137,80) becomes RGB(137,111,134)
-- under this overlay.
local STAGE_TINT = {
    st01 = { 203, 78, 199, 115 },
}

-- Layer animation opcodes.
local OP_POS_RAMP = 407   -- ramp the layer position over N frames
local OP_LOOP = 200       -- loop back a number of instructions
local OP_STOP = 3
local OP_SPRITE = 300
local OP_ROTATE = 401
local OP_ALPHA = 403
local OP_BLEND = 302
local OP_LAYER = 305
local OP_MOVE = 409

---@param options table { lstg, anm, std, image_for, texture_sizes }
function StageBackground.new(options)
    return setmetatable({
        lstg = options.lstg,
        anm = options.anm or {},
        std = options.std or {},
        image_for = options.image_for or function(path) return path end,
        texture_sizes = options.texture_sizes or {},
        stage = nil,
        layers = {},
    }, StageBackground)
end

--- Build the layer list for a stage from its std and wl data.
function StageBackground:set_stage(stage_key)
    self.stage = stage_key
    self.layers = {}
    self.tint = STAGE_TINT[stage_key]
    local std_entries = self.std[stage_key] or {}
    local wl = self.anm[stage_key .. "wl"] or {}
    local function find_entry(script_index)
        for _, entry in ipairs(wl) do
            if entry.scripts and entry.scripts[script_index] then
                return entry
            end
        end
        return wl[1]
    end
    for index, entry in ipairs(std_entries) do
        local wl_entry = find_entry(entry.script or 0)
        local texture = wl_entry and wl_entry.texture
        local script = wl_entry and wl_entry.scripts and wl_entry.scripts[entry.script or 0]
        local size = self.texture_sizes[texture or ""] or {}
        local texture_w = size[1] or entry.width or 256
        local texture_h = size[2] or entry.height or 256
        local unit_scale = (entry.width or 256) / math.max(1, texture_w)
        local layer = {
            texture = texture,
            unit_w = texture_w * unit_scale,
            unit_h = texture_h * unit_scale,
            script = script or {},
            base = index == 1,
            -- Layer animation state, advanced by the script each frame.
            timer = 0,
            pc = 1,
            rotation = 0,
            alpha = index == 1 and 255 or 192,
            scroll = 0,
            scroll_speed = 0,
            loop_pc = nil,
            loop_count = 0,
            finished = false,
        }
        -- Read the static settings from the script before it starts running.
        for _, instruction in ipairs(layer.script) do
            if instruction.id == OP_ALPHA and instruction[1] then
                layer.alpha = tonumber(instruction[1]) or layer.alpha
            elseif instruction.id == OP_ROTATE and instruction[1] then
                layer.rotation = tonumber(instruction[1]) or 0
            end
        end
        self.layers[#self.layers + 1] = layer
    end
end

--- Advance one layer's animation script by a frame.
-- The scripts are a frame timeline: every instruction carries the frame it runs
-- on, so this walks forward executing whatever is due and honours the loop
-- opcode so a layer repeats forever like the reference.
function StageBackground:advance_layer(layer)
    if layer.finished then
        -- A stopped layer still scrolls at whatever rate it had.
        layer.scroll = layer.scroll + layer.scroll_speed
        return
    end
    layer.timer = layer.timer + 1
    local script = layer.script
    local guard = 0
    while layer.pc <= #script and guard < 64 do
        guard = guard + 1
        local instruction = script[layer.pc]
        if instruction.time > layer.timer then break end
        layer.pc = layer.pc + 1
        local id = instruction.id
        if id == OP_POS_RAMP then
            -- 407(frames, mode, delta, ...): move the layer by delta units over
            -- the given number of frames.
            local frames = math.max(1, tonumber(instruction[1]) or 1)
            local delta = tonumber(instruction[3]) or 0
            layer.scroll_speed = delta / frames
        elseif id == OP_MOVE then
            local frames = math.max(1, tonumber(instruction[1]) or 1)
            layer.scroll_speed = (tonumber(instruction[3]) or 0) / frames
        elseif id == OP_ALPHA then
            layer.alpha = tonumber(instruction[1]) or layer.alpha
        elseif id == OP_ROTATE then
            layer.rotation = tonumber(instruction[1]) or layer.rotation
        elseif id == OP_BLEND then
            layer.blend = tonumber(instruction[1])
        elseif id == OP_LOOP then
            -- 200(offset, count): jump back offset instructions; a count of 0
            -- loops forever.
            local offset = tonumber(instruction[1]) or 0
            local count = tonumber(instruction[2]) or 0
            layer.loop_count = layer.loop_count + 1
            if count == 0 or layer.loop_count < count then
                layer.pc = math.max(1, layer.pc - offset)
            else
                layer.loop_count = 0
            end
        elseif id == OP_STOP then
            layer.finished = true
        end
    end
    layer.scroll = layer.scroll + layer.scroll_speed
end

function StageBackground:update()
    for _, layer in ipairs(self.layers) do
        self:advance_layer(layer)
    end
end

--- Draw every layer, tiling each at its texture size and scrolling by its own
-- script-driven offset.
function StageBackground:draw()
    local lstg = self.lstg
    if not lstg or #self.layers == 0 then return end
    if type(lstg.SetScissorRect) == "function" then
        pcall(lstg.SetScissorRect, FIELD_LEFT, FIELD_RIGHT, FIELD_BOTTOM, FIELD_TOP)
    end
    -- Detail layers draw first so the base covers the gaps.
    for index = #self.layers, 1, -1 do
        local layer = self.layers[index]
        local image = self.image_for(layer.texture)
        if image then
            local tile_w = layer.unit_w * SCALE
            local tile_h = layer.unit_h * SCALE
            if tile_w > 1 and tile_h > 1 then
                local offset = (layer.scroll or 0) * SCALE % tile_h
                local x = FIELD_LEFT - tile_w
                while x < FIELD_RIGHT + 0.5 do
                    local left = math.max(FIELD_LEFT, x)
                    local right = math.min(FIELD_RIGHT, x + tile_w)
                    if right > left then
                        local y = FIELD_TOP - tile_h + offset
                        local flipped = layer.rotation and math.abs(layer.rotation - math.pi) < 0.01
                        while y > FIELD_BOTTOM - tile_h - 0.5 do
                            local bottom = math.max(FIELD_BOTTOM, y)
                            local top = math.min(FIELD_TOP, y + tile_h)
                            if top > bottom then
                                lstg.SetImageState(image, "", lstg.Color(layer.alpha or 255, 255, 255, 255))
                                if flipped then
                                    -- The reference rotates the base layer 180
                                    -- degrees, which swaps the vertex order.
                                    lstg.RenderRect(image, right, left, top, bottom)
                                else
                                    lstg.RenderRect(image, left, right, bottom, top)
                                end
                            end
                            y = y - tile_h
                        end
                    end
                    x = x + tile_w
                end
            end
        end
    end
    if type(lstg.SetScissorRect) == "function" then
        pcall(lstg.SetScissorRect, 0, 1280, 0, 720)
    end
end

--- Draw the stage fog tint over the field.
function StageBackground:draw_fog()
    local lstg = self.lstg
    if not lstg or not self.tint then return end
    if type(lstg.SetScissorRect) == "function" then
        pcall(lstg.SetScissorRect, FIELD_LEFT, FIELD_RIGHT, FIELD_BOTTOM, FIELD_TOP)
    end
    local tint = self.tint
    lstg.SetImageState("tnr-white", "", lstg.Color(tint[4], tint[1], tint[2], tint[3]))
    lstg.RenderRect("tnr-white", FIELD_LEFT, FIELD_RIGHT, FIELD_BOTTOM, FIELD_TOP)
    if type(lstg.SetScissorRect) == "function" then
        pcall(lstg.SetScissorRect, 0, 1280, 0, 720)
    end
end

return StageBackground
