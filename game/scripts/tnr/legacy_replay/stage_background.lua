-- STD scene geometry and ANM background layers. Visual parity remains under validation.
local StageBackground = {}
local StdCamera = require("tnr.legacy_replay.std_camera")

StageBackground.__index = StageBackground

local PLAYFIELD_WIDTH = 384
local PLAYFIELD_HEIGHT = 448
local Geometry = require("tnr.legacy_replay.boss_ui")
local SCALE = Geometry.PLAYFIELD_SCALE
local FIELD_LEFT = Geometry.PLAYFIELD_LEFT
local FIELD_TOP = Geometry.PLAYFIELD_TOP
local FIELD_RIGHT = FIELD_LEFT + PLAYFIELD_WIDTH * SCALE
local FIELD_BOTTOM = FIELD_TOP - PLAYFIELD_HEIGHT * SCALE

StageBackground.SCALE = SCALE
StageBackground.FIELD_LEFT = FIELD_LEFT
StageBackground.FIELD_TOP = FIELD_TOP
StageBackground.FIELD_RIGHT = FIELD_RIGHT
StageBackground.FIELD_BOTTOM = FIELD_BOTTOM

local STAGE_TINT = {}
local interpolate = require("tnr.legacy_replay.interpolation")

-- Layer animation opcodes.
local OP_LOOP = 200       -- jump to byte offset and timestamp
local OP_STOP = 3
local OP_ROTATE = 401
local OP_ALPHA = 403
local OP_BLEND = 302

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
    self.camera = stage_key == "st01" and std_entries.timeline and StdCamera.new(std_entries.timeline) or nil
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
            geometry = entry,
            unit_w = texture_w * unit_scale,
            unit_h = texture_h * unit_scale,
            script = script or {},
            base = index == 1,
            -- Layer animation state, advanced by the script each frame.
            timer = -1,
            position = {0, 0, 0},
            tweens = {},
            offsets = {},
            pc = 1,
            rotation = 0,
            alpha = index == 1 and 255 or 192,
            scroll = 0,
            scroll_speed = 0,
            loop_pc = nil,
            loop_count = 0,
            finished = false,
        }
        local offset = 0
        for pc, instruction in ipairs(layer.script) do
            layer.offsets[offset] = pc
            offset = offset + 8 + 4 * #instruction
        end
        self:advance_layer(layer)
        self.layers[#self.layers + 1] = layer
    end
end

--- Advance one layer's animation script by a frame.
-- The scripts are a frame timeline: every instruction carries the frame it runs
-- on, so this walks forward executing whatever is due and honours the loop
-- opcode so a layer repeats forever like the reference.
function StageBackground:advance_layer(layer)
    for key, tween in pairs(layer.tweens) do
        tween.elapsed = math.min(tween.duration, tween.elapsed + 1)
        local t = interpolate(tween.mode, tween.elapsed / tween.duration)
        if key == "alpha" then
            layer.alpha = tween.from + (tween.target - tween.from) * t
        else
            for i = 1, 3 do layer.position[i] = tween.from[i] + (tween.target[i] - tween.from[i]) * t end
        end
        if tween.elapsed == tween.duration then layer.tweens[key] = nil end
    end
    if layer.finished then return end
    layer.timer = layer.timer + 1
    for _ = 1, 64 do
        local instruction = layer.script[layer.pc]
        if not instruction or instruction.time > layer.timer then return end
        layer.pc = layer.pc + 1
        local id = instruction.id
        if id == 407 or id == 409 then
            local key = id == 407 and "position" or "alpha"
            layer.tweens[key] = {
                from = key == "alpha" and layer.alpha or {layer.position[1], layer.position[2], layer.position[3]},
                target = key == "alpha" and instruction[3] or {instruction[3], instruction[4], instruction[5]},
                elapsed = 0, duration = math.max(1, instruction[1]), mode = instruction[2],
            }
        elseif id == OP_ALPHA then layer.alpha = instruction[1]
        elseif id == OP_ROTATE then layer.rotation = instruction[1]
        elseif id == OP_BLEND then layer.blend = instruction[1]
        elseif id == OP_LOOP then
            layer.pc = assert(layer.offsets[instruction[1]], "invalid background ANM byte offset")
            layer.timer = instruction[2]
        elseif id == OP_STOP then
            layer.finished = true
            return
        end
    end
    error("background ANM instruction budget exhausted")
end

function StageBackground:update()
    if self.camera then self.camera:update() end
    for _, layer in ipairs(self.layers) do
        self:advance_layer(layer)
    end
end

-- Render STD instances in world space. The engine clips the quads in the
-- perspective viewport, so edge tiles retain their UVs instead of stretching.
function StageBackground:draw_world()
    local g, camera = self.lstg, self.camera
    local p, d, up = camera.position, camera.direction, camera.up
    g.SetViewport(FIELD_LEFT, FIELD_RIGHT, FIELD_BOTTOM, FIELD_TOP)
    g.SetPerspective(p[1], p[2], p[3], p[1] + d[1], p[2] + d[2], p[3] + d[3],
        up[1], up[2], up[3], camera.fov, PLAYFIELD_WIDTH / PLAYFIELD_HEIGHT, 1, 10000)
    local fog = camera.fog
    -- thtk prints the four colour bytes in memory order (BGRA).
    g.SetFog(fog[5], fog[6], g.Color(255, fog[3], fog[2], fog[1]))
    for _, layer in ipairs(self.layers) do
        local image = self.image_for(layer.texture)
        if image then
            g.SetImageState(image, "", g.Color(layer.alpha or 255, 255, 255, 255))
            for _, face in ipairs(layer.geometry.faces or {}) do
                for _, quad in ipairs(layer.geometry.quads or {}) do
                    local position = quad.position or {0, 0, 0}
                    local x, y, z = face.x + position[1] + layer.position[1], face.y + position[2] + layer.position[2], face.z + position[3] + layer.position[3]
                    local w, h = quad.width / 2, quad.height / 2
                    local c, s = math.cos(layer.rotation or 0), math.sin(layer.rotation or 0)
                    g.Render4V(image,
                        x - w, y + h * c, z + h * s,
                        x + w, y + h * c, z + h * s,
                        x + w, y - h * c, z - h * s,
                        x - w, y - h * c, z - h * s)
                end
            end
        end
    end
    g.SetFog()
    g.SetViewport(0, 1280, 0, 720)
    g.SetOrtho(0, 1280, 0, 720)
end

--- Draw every layer, tiling each at its texture size and scrolling by its own
-- script-driven offset.
function StageBackground:draw()
    local lstg = self.lstg
    if not lstg or #self.layers == 0 then return end
    if self.camera and lstg.SetPerspective and lstg.Render4V and lstg.SetFog
            and lstg.SetViewport and lstg.SetOrtho then
        self:draw_world()
        return
    end
    if type(lstg.SetScissorRect) == "function" then
        pcall(lstg.SetScissorRect, FIELD_LEFT, FIELD_RIGHT, FIELD_BOTTOM, FIELD_TOP)
    end
    -- Draw opaque geometry before translucent detail.
    for index = 1, #self.layers do
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
