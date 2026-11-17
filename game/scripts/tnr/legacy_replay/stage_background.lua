-- STD scene geometry and ANM background layers. Visual parity remains under validation.
local StageBackground = {}
local StdCamera = require("tnr.legacy_replay.std_camera")
local AnmPlayer = require("tnr.legacy_replay.anm_player")

StageBackground.__index = StageBackground

local PLAYFIELD_WIDTH = 384
local PLAYFIELD_HEIGHT = 448
local Geometry = require("tnr.legacy_replay.boss_ui")
local AnmGeometry = require("tnr.legacy_replay.anm_geometry")
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
local function sync_layer(layer)
    local vm=layer.vm
    layer.sprite=vm.sprite
    layer.position={vm.x,vm.y,vm.z}
    layer.rotation,layer.rotation_y,layer.rotation_z=vm.rotation_x,vm.rotation_y,vm.rotation
    layer.scale_x,layer.scale_y=vm.scale_x,vm.scale_y
    layer.alpha=vm.alpha
    layer.color={vm.red,vm.green,vm.blue}
    layer.u,layer.v,layer.u_vel,layer.v_vel=vm.u,vm.v,vm.u_vel,vm.v_vel
    layer.texture_circle_max=vm.texture_circle_max
    layer.texture_cylinder_segments=vm.texture_cylinder_segments
end

-- Layer animation opcodes.
local OP_LOOP = 200       -- jump to byte offset and timestamp
local OP_STOP = 3
local OP_ROTATE = 401
local OP_ALPHA = 403
local OP_BLEND = 303

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
    self.skyboxes={}
    self.tint = STAGE_TINT[stage_key]
    local std_entries = self.std[stage_key] or {}
    self.camera = std_entries.timeline and StdCamera.new(std_entries.timeline) or nil
    local wl = self.anm[stage_key .. "wl"] or {}
    local function find_entry(script_index)
        for _, entry in ipairs(wl) do
            if entry.scripts and entry.scripts[script_index] then
                return entry
            end
        end
        return wl[1]
    end
    local surfaces={}
    for _,entry in ipairs(std_entries) do
        for _,quad in ipairs(entry.quads or {}) do
            surfaces[#surfaces+1]={script=quad.script or entry.script,width=quad.width,height=quad.height,
                position=entry.position,faces=entry.faces,quads={quad}}
        end
        if #(entry.quads or {})==0 then surfaces[#surfaces+1]=entry end
    end
    for index, entry in ipairs(surfaces) do
        local wl_entry = find_entry(entry.script or 0)
        local texture = wl_entry and wl_entry.texture
        local script = wl_entry and wl_entry.scripts and wl_entry.scripts[entry.script or 0]
        local vm
        if wl_entry and script then
            local entry_index=1
            for i,candidate in ipairs(wl) do if candidate==wl_entry then entry_index=i;break end end
            vm=AnmPlayer.new(wl_entry,stage_key.."wl",entry_index)
            vm.archive_entries=wl
            vm:play(entry.script or 0)
            -- Background scripts start with timestamp -1 and then execute
            -- timestamp 0 before the first visible game frame.
            vm:update()
        else
            vm=AnmPlayer.new({scripts={}},stage_key.."wl")
        end
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
            vm=vm,
            base = index == 1,
        }
        sync_layer(layer)
        self.layers[#self.layers + 1] = layer
    end
end

--- Advance one layer's animation script by a frame.
-- The scripts are a frame timeline: every instruction carries the frame it runs
-- on, so this walks forward executing whatever is due and honours the loop
-- opcode so a layer repeats forever like the reference.
function StageBackground:advance_layer(layer)
    if layer.vm then layer.vm:update();sync_layer(layer) end
end

function StageBackground:update()
    if self.camera then self.camera:update() end
    for _, layer in ipairs(self.layers) do
        self:advance_layer(layer)
    end
    for slot,source in pairs(self.camera and self.camera.sprites or {}) do
        local box=self.skyboxes[slot]
        if not box or box.generation~=source.generation then
            for _,entry in ipairs(self.anm[self.stage.."wl"] or {}) do
                if entry.scripts[source.script] then
                    local vm=AnmPlayer.new(entry,self.stage.."wl");vm:play(source.script)
                    box={vm=vm,generation=source.generation,layer=source.layer};self.skyboxes[slot]=box;break
                end
            end
        end
        if box then box.vm:update() end
    end
end

function StageBackground:draw_skyboxes()
    local g=self.lstg
    if not g.Render then return end
    local ordered={}
    for slot,box in pairs(self.skyboxes or {}) do box.slot=slot;ordered[#ordered+1]=box end
    table.sort(ordered,function(a,b) if a.layer==b.layer then return a.slot<b.slot end;return a.layer<b.layer end)
    for _,box in ipairs(ordered) do
        local vm=box.vm
        if vm.visible and not vm.finished then
            local image,rect,entry=self:image_for_layer({sprite=vm.sprite})
            if image then
                local circle=vm.texture_circle_max and require("tnr.legacy_replay.anm_geometry").draw_circle(
                    g,vm,entry,rect,self.texture_sizes[entry.texture] or {entry.width,entry.height},
                    (FIELD_LEFT+FIELD_RIGHT)/2+vm.x*SCALE,FIELD_TOP-vm.y*SCALE,SCALE)
                if not circle then
                local c=vm.color
                g.SetImageState(image,AnmGeometry.blend(vm.blend_mode),g.Color(vm.alpha,c[1],c[2],c[3]))
                -- STD background sprites use the field's top-centre origin.
                -- st06wl 2..5 explicitly anchor at the top (421 65536):
                -- their y=-20 is the top edge, not the image centre.
                local dx=rect and (vm.anchor_x==1 and rect.w/2 or vm.anchor_x==2 and -rect.w/2 or 0) or 0
                local dy=rect and (vm.anchor_y==1 and rect.h/2 or vm.anchor_y==2 and -rect.h/2 or 0) or 0
                dx=dx*vm.scale_x;dy=dy*vm.scale_y
                local ca,sa=math.cos(vm.rotation),math.sin(vm.rotation)
                g.Render(image,(FIELD_LEFT+FIELD_RIGHT)/2+(vm.x+dx*ca-dy*sa)*SCALE,
                    FIELD_TOP-(vm.y+dx*sa+dy*ca)*SCALE,-math.deg(vm.rotation),vm.scale_x*SCALE,vm.scale_y*SCALE)
                end
            end
        end
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
        if layer.vm and layer.vm.visible and not layer.vm.finished then
        local image,rect,entry = self:image_for_layer(layer)
        if image then
            local vm=layer.vm
            local color=layer.color or {255,255,255}
            local tint=g.Color(layer.alpha or 255,color[1],color[2],color[3])
            local blend=AnmGeometry.blend(layer.vm.blend_mode)
            g.SetImageState(image,blend,tint)
            for _, face in ipairs(layer.geometry.faces or {}) do
                for _, quad in ipairs(layer.geometry.quads or {}) do
                    local position = quad.position or {0, 0, 0}
                    -- TH15 40f050 uses the entry origin for culling. The
                    -- renderer at 40f952 places the quad at face + quad.
                    local x = face.x + position[1] + layer.position[1]
                    local y = face.y + position[2] + layer.position[2]
                    local z = face.z + position[3] + layer.position[3]
                    local sx=vm.scale_x*(vm.scale2_x or 1)
                    local sy=vm.scale_y*(vm.scale2_y or 1)
                    local w, h = quad.width*sx / 2, quad.height*sy / 2
                    local vertices={}
                    for _,v in ipairs({{-w,h},{w,h},{w,-h},{-w,-h}}) do
                        local xx,yy,zz=AnmGeometry.rotate3(v[1],v[2],0,
                            layer.vm.rotation_x,layer.vm.rotation_y,layer.vm.rotation,
                            layer.vm.rotation_system)
                        vertices[#vertices+1]=x+xx;vertices[#vertices+1]=y+yy;vertices[#vertices+1]=z+zz
                    end
                    if g.RenderTexture and entry and entry.loaded_texture and rect then
                        local center={x,y,z}
                        local special=AnmGeometry.draw_world_circle(g,layer.vm,entry,rect,
                            self.texture_sizes[entry.texture] or {entry.width,entry.height},center,blend)
                        if not special then
                            special=AnmGeometry.draw_world_cylinder(g,layer.vm,entry,rect,
                                self.texture_sizes[entry.texture] or {entry.width,entry.height},center,blend)
                        end
                        if not special then
                            local size=self.texture_sizes[entry.texture] or {entry.width,entry.height}
                            local texture_w,texture_h=size[1] or rect.w,size[2] or rect.h
                            local u0=rect.x+(entry.offset_x or 0)+(vm.u or 0)*texture_w
                            local v0=rect.y+(entry.offset_y or 0)+(vm.v or 0)*texture_h
                            local u1=u0+rect.w*(vm.uv_scale_x or 1)*(vm.flip_x and -1 or 1)
                            local v1=v0+rect.h*(vm.uv_scale_y or 1)*(vm.flip_y and -1 or 1)
                            local patches=AnmGeometry.uv_patches(u0,u1,v0,v1,texture_w,texture_h,
                                vm.scroll_mode_x,vm.scroll_mode_y,vm.resample_mode==1)
                            local function world_vertex(s,t,uv_s,uv_t)
                                local top_x=vertices[1]+(vertices[4]-vertices[1])*s
                                local top_y=vertices[2]+(vertices[5]-vertices[2])*s
                                local top_z=vertices[3]+(vertices[6]-vertices[3])*s
                                local bottom_x=vertices[10]+(vertices[7]-vertices[10])*s
                                local bottom_y=vertices[11]+(vertices[8]-vertices[11])*s
                                local bottom_z=vertices[12]+(vertices[9]-vertices[12])*s
                                local amount=vm.color_mode==2 and s or vm.color_mode==3 and t or 0
                                local vertex_tint=g.Color(
                                    vm.alpha+(vm.alpha2-vm.alpha)*amount,
                                    vm.red+(vm.red2-vm.red)*amount,
                                    vm.green+(vm.green2-vm.green)*amount,
                                    vm.blue+(vm.blue2-vm.blue)*amount)
                                return {top_x+(bottom_x-top_x)*t,top_y+(bottom_y-top_y)*t,
                                    top_z+(bottom_z-top_z)*t,uv_s,uv_t,vertex_tint}
                            end
                            for _,patch in ipairs(patches) do
                                if g.SetTextureSamplerState then
                                    g.SetTextureSamplerState(entry.loaded_texture,patch.sampler)
                                end
                                local a,b,c,d=patch.uv[1],patch.uv[2],patch.uv[3],patch.uv[4]
                                g.RenderTexture(entry.loaded_texture,blend,
                                    world_vertex(patch.s0,patch.t0,a[1],a[2]),
                                    world_vertex(patch.s1,patch.t0,b[1],b[2]),
                                    world_vertex(patch.s1,patch.t1,c[1],c[2]),
                                    world_vertex(patch.s0,patch.t1,d[1],d[2]))
                            end
                        end
                    else g.Render4V(image,(table.unpack or unpack)(vertices)) end
                end
            end
        end
        end
    end
    g.SetFog()
    g.SetViewport(0, 1280, 0, 720)
    g.SetOrtho(0, 1280, 0, 720)
end

function StageBackground:image_for_layer(layer)
    local sprite=layer.sprite
    if sprite then
        for i,entry in ipairs(self.anm[self.stage.."wl"] or {}) do
            if sprite>=1 and sprite<=#entry.sprites then
                return string.format("tnr-th15-%swl-%d-%d",self.stage,i,sprite),entry.sprites[sprite],entry
            end
            sprite=sprite-#entry.sprites
        end
    end
    return self.image_for(layer.texture)
end

--- Draw every layer, tiling each at its texture size and scrolling by its own
-- script-driven offset.
function StageBackground:draw()
    local lstg = self.lstg
    if not lstg or #self.layers == 0 then return end
    if lstg.SetScissorRect then lstg.SetScissorRect(FIELD_LEFT,FIELD_RIGHT,FIELD_BOTTOM,FIELD_TOP) end
    self:draw_skyboxes()
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
                        local flipped = layer.rotation_z and math.abs(layer.rotation_z - math.pi) < 0.01
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
