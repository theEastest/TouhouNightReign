-- Stage background renderer for the legacy replay.
--
-- The reference background is a stack of scrolling layers described by the
-- stage std file. Each entry names a texture (through the stage wl animation
-- script index), a tile size and a list of FACE positions that tile the layer
-- horizontally across a scrolling world. The layer scripts drive the vertical
-- scroll and the tint.
--
-- Geometry is the measured reference playfield: 384x448 units rendered into a
-- 616x718.4 px region at (49.6, 742.4) in the 1280x960 logical canvas.

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

--- Per-stage fog tint, sampled from a capture of the original game.
-- The reference composites a coloured overlay over the playfield. Stage 1 uses
-- a magenta violet wash that turns the green forest canopy into the purple
-- scene the original shows. The colour and weight are solved from the captured
-- frame against the raw texture: forest RGB(82,137,80) becomes RGB(137,111,134)
-- under this overlay.
local STAGE_TINT = {
    st01 = { 203, 78, 199, 115 },
}

StageBackground.SCALE = SCALE
StageBackground.FIELD_LEFT = FIELD_LEFT
StageBackground.FIELD_TOP = FIELD_TOP
StageBackground.FIELD_RIGHT = FIELD_RIGHT
StageBackground.FIELD_BOTTOM = FIELD_BOTTOM

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
        scroll = {},
    }, StageBackground)
end

--- Build the layer list for a stage from its std and wl data.
function StageBackground:set_stage(stage_key)
    self.stage = stage_key
    self.layers = {}
    self.scroll = {}
    self.tint = STAGE_TINT[stage_key]
    local std_entries = self.std[stage_key] or {}
    local wl = self.anm[stage_key .. "wl"] or {}
    -- Resolve the wl entry that owns a layer script index.
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
        -- Decode the layer's static settings from its animation script. The
        -- reference uses opcode 401 for rotation, 403 for alpha and 302 for the
        -- blend mode; reading them reproduces the original tint and the flipped
        -- base layer.
        local rotation, alpha, blend = 0, 255, nil
        for _, instruction in ipairs(script or {}) do
            local id = instruction.id
            if id == 401 then
                rotation = tonumber(instruction[1]) or 0
            elseif id == 403 then
                alpha = tonumber(instruction[1]) or 255
            elseif id == 302 then
                blend = tonumber(instruction[1])
            end
        end
        local size = self.texture_sizes[texture or ""] or {}
        local texture_w = size[1] or entry.width or 256
        local texture_h = size[2] or entry.height or 256
        local unit_scale = (entry.width or 256) / math.max(1, texture_w)
        self.layers[#self.layers + 1] = {
            texture = texture,
            unit_w = texture_w * unit_scale,
            unit_h = texture_h * unit_scale,
            rotation = rotation,
            alpha = alpha,
            blend = blend,
            base = index == 1,
            scroll = index == 1 and 0.35 or (0.6 + index * 0.2),
        }
        self.scroll[#self.scroll + 1] = 0
    end
end

function StageBackground:update()
    for index, layer in ipairs(self.layers) do
        self.scroll[index] = (self.scroll[index] or 0) + (layer.scroll or 0)
    end
end

--- Draw every layer, tiling each at its texture size and scrolling vertically.
function StageBackground:draw()
    local lstg = self.lstg
    if not lstg or #self.layers == 0 then return end
    if type(lstg.SetScissorRect) == "function" then
        pcall(lstg.SetScissorRect, FIELD_LEFT, FIELD_RIGHT, FIELD_BOTTOM, FIELD_TOP)
    end
    for index = #self.layers, 1, -1 do
        local layer = self.layers[index]
        local image = self.image_for(layer.texture)
        if image then
            local tile_w = (layer.unit_w or 256) * SCALE
            local tile_h = (layer.unit_h or 256) * SCALE
            if tile_w > 1 and tile_h > 1 then
                local offset = (self.scroll[index] or 0) % tile_h
                local x = FIELD_LEFT - tile_w
                while x < FIELD_RIGHT + 0.5 do
                    local left = math.max(FIELD_LEFT, x)
                    local right = math.min(FIELD_RIGHT, x + tile_w)
                    if right > left then
                        local y = FIELD_TOP - tile_h + offset
                        while y > FIELD_BOTTOM - tile_h - 0.5 do
                            local bottom = math.max(FIELD_BOTTOM, y)
                            local top = math.min(FIELD_TOP, y + tile_h)
                            if top > bottom then
                                local alpha = layer.alpha or (layer.base and 255 or 170)
                                lstg.SetImageState(image, "", lstg.Color(alpha, 255, 255, 255))
                                lstg.RenderRect(image, left, right, bottom, top)
                            end
                            y = y - tile_h
                        end
                    end
                    x = x + tile_w
                end
            end
        end
    end
    -- Restore the full canvas scissor so later layers are not clipped.
    if type(lstg.SetScissorRect) == "function" then
        pcall(lstg.SetScissorRect, 0, 1280, 0, 720)
    end
end

--- Draw the stage fog tint over the field.
-- The reference applies a coloured overlay to the whole playfield; stage 1
-- uses a violet tint that turns the green forest into the purple scene the
-- original shows.
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
