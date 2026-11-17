-- Source-data and rendering regressions. Passing these is not a visual acceptance test.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local BossUi = require("tnr.legacy_replay.boss_ui")
    local StageBackground = require("tnr.legacy_replay.stage_background")
    local StageRuntime = require("tnr.legacy_replay.stage_runtime")
    local anm = require("tnr.legacy_replay.data.th15_anm")
    local std = require("tnr.legacy_replay.data.th15_std")
    local face_entry
    for i, source in ipairs(anm.pl00) do
        if source.texture == "face/pl00/face_pl00pr.png" then face_entry = i end
    end
    local face_load
    StageRuntime.load_stage_assets({
        LoadTexture = function() end,
        GetTextureSize = function() return 2048, 2048 end,
        LoadImage = function(name, texture, x, y, w, h)
            if name == StageRuntime.image_name("pl00", face_entry, 1) then face_load = {x,y,w,h} end
        end,
    }, "st01", anm, {})
    assert_equal(face_load[1], 340, "portrait extraction canvas X offset is applied")
    assert_equal(face_load[2], 54, "portrait extraction canvas Y offset is applied")
    assert_equal(face_load[3], 236, "portrait rectangle keeps its unpadded width")

    local function close(a, b, tolerance, message)
        assert_true(math.abs(a - b) <= (tolerance or 0.5),
            string.format("%s: expected %.2f got %.2f", message, b, a))
    end

    -- Playfield geometry measured from the original capture. The field is
    -- Source front00 border strips: 64/768/448 px across a 1280x960 canvas.
    -- Fit at 0.75 scale, centred horizontally in the project's 1280x720.
    close(BossUi.PLAYFIELD_LEFT, 208, 0.1, "playfield left")
    close(BossUi.PLAYFIELD_RIGHT, 784, 0.1, "playfield right")
    close(BossUi.PLAYFIELD_BOTTOM, 24, 0.1, "playfield bottom")
    close(BossUi.PLAYFIELD_TOP, 696, 0.1, "playfield top")
    -- The field must keep the reference 384:448 aspect ratio exactly.
    local width = BossUi.PLAYFIELD_RIGHT - BossUi.PLAYFIELD_LEFT
    local height = BossUi.PLAYFIELD_TOP - BossUi.PLAYFIELD_BOTTOM
    close(width / height, 384 / 448, 0.001, "playfield aspect ratio")
    close(width / 384, BossUi.PLAYFIELD_SCALE, 0.0001, "px per game unit")

    -- Projection round trip: the field centre and the top left corner.
    local cx, cy = BossUi.project(0, 0)
    close(cx, BossUi.PLAYFIELD_LEFT + 192 * BossUi.PLAYFIELD_SCALE, 0.1, "field centre x")
    close(cy, BossUi.PLAYFIELD_TOP, 0.1, "field centre y sits at the top edge")

    -- Reference sprite sizes carried by the archive.
    local entry = anm.st01enm and anm.st01enm[1]
    assert_true(entry ~= nil, "stage 1 enemy archive compiles")
    assert_equal(entry.sprites[1].w, 64, "enemy sprite width from the reference")
    assert_equal(entry.sprites[1].h, 96, "enemy sprite height from the reference")

    -- Background layers: stage 1 has seven std entries, the first being the
    -- opaque forest base and the rest scrolling cloud detail.
    assert_true(#std.st01 == 7, "stage 1 exposes seven background entries")
    local background = StageBackground.new({
        lstg = {}, anm = anm, std = std,
        image_for = function(path) return path end,
        -- The reference st01a texture is 512x512 even though the anm header
        -- claims 1024x512; the renderer must use the real size.
        texture_sizes = { ["background/stage01/st01a.png"] = { 512, 512 },
                          ["background/stage01/st01d.png"] = { 256, 256 } },
    })
    background:set_stage("st01")
    assert_equal(#background.layers, 7, "every background entry becomes a layer")
    assert_true(background.layers[1].base, "the first layer is the base")
    assert_true(not background.layers[2].base, "the rest are detail layers")
    -- The base is opaque; the detail layers are translucent.
    assert_equal(background.layers[1].alpha, 255, "the base layer is opaque")
    assert_true(background.layers[2].alpha < 255, "detail layers are translucent")
    -- Source STD coordinates and camera transitions, not colours fitted to an
    -- unrelated screenshot. These checks do not certify visual fidelity.
    assert_equal(background.tint, nil, "no fixed violet overlay")
    assert_equal(std.st01[1].faces[1].x, 0, "instance x")
    assert_equal(std.st01[1].faces[1].y, -128, "instance y")
    assert_equal(std.st01[1].quads[1].position[3], 300, "quad depth")
    assert_equal(background.camera.position[3], -600, "opening camera depth")
    for _ = 1, 200 do background:update() end
    close(background.layers[5].alpha, 64, 0.001, "cloud alpha interpolates instead of moving")
    close(background.layers[2].position[1], 16 * 2 / 9, 0.001, "cloud uses mode 9 position interpolation")
    for _ = 201, 390 do background:update() end
    close(background.camera.position[2], 512, 0.001, "camera reset at frame 390")
    close(background.camera.position[3], -400, 0.001, "camera arrives at target depth")
    for _ = 391, 6230 do background:update() end
    assert_equal(background.camera.time, 5830, "STD jumps to its source timestamp")
    for _ = 1, 800 do background:update() end
    assert_equal(background.camera.time, 5830, "STD loop remains stable")

    -- Image naming: the loader and the renderer must agree on the pattern.
    assert_equal(StageRuntime.image_name("st01enm", 1, 3), "tnr-th15-st01enm-1-3",
        "sprite image naming")
    local renderer = StageRuntime.new({lstg = {}, anm = anm})
    local charge = renderer.adapter:animation(1, 156)
    charge:update()
    assert_true(charge.charge ~= nil, "effect type one starts a charge emitter")
    assert_equal(#charge.children, 4, "charge emits four particles on its first tick")
    assert_equal(charge.children[1].script, 152, "first charge sprite uses original ANM 152")
    assert_equal(charge.children[4].script, 153, "fourth charge sprite uses original ANM 153")
    for _ = 2, 50 do charge:update() end
    assert_equal(#charge.children, 200, "emission stops after fifty ticks")
    assert_equal(#(renderer.adapter.animations or {}), 0, "charge creates no screen transition")
    for _ = 51, 220 do charge:update() end
    assert_equal(#charge.children, 0, "charge particles finish their animation")
    local blue_ring, ring_w = renderer:bullet_image({sprite = 4, color_index = 6})
    assert_equal(blue_ring, "tnr-th15-bullet-1-71", "type 4 blue colour selects sprite 70, not script 4")
    assert_equal(ring_w, 16, "ring uses source sprite width")
    local big_ball = renderer:bullet_image({sprite = 18, color_index = 0})
    assert_equal(big_ball, "tnr-th15-bullet-2-1", "global sprite 368 resolves into second sheet")
    local curve_image,curve_width,curve_height=renderer:bullet_image({laser_kind="curve",sprite=0,color_index=2})
    assert_equal(curve_image,"tnr-th15-bullet-5-3","curved lasers use their original laser atlas and colour")
    assert_equal(curve_width,256,"the curve texture extends along the complete strip")
    assert_equal(curve_height,16,"the curve texture uses one colour row")
    local animated_curve=renderer:bullet_image({laser_kind="curve",sprite=1,anim_frame=4})
    assert_equal(animated_curve,"tnr-th15-bullet-9-3","the alternate curved laser uses its animated original atlas")
    local curve_quads={}
    require("tnr.legacy_replay.curve_laser").draw({RenderTexture=function(texture,blend,...)
        curve_quads[#curve_quads+1]={...}
    end},{width=16,nodes={{x=0,y=100,angle=0},{x=-10,y=100,angle=0},{x=-20,y=100,angle=0}}},
        {loaded_texture="laser1"},{x=0,y=32,w=256,h=16},0,448,1,{},"")
    assert_equal(#curve_quads,2,"a three-node curve produces a continuous two-quad strip")
    assert_equal(curve_quads[1][2][4],128,"the first segment ends at the texture midpoint")
    assert_equal(curve_quads[2][1][4],128,"the second segment continues at the same UV")
    assert_equal(curve_quads[2][2][4],256,"the texture reaches its end only at the tail")
    assert_equal(curve_quads[1][2][1],curve_quads[2][1][1],"neighboring curve segments share their edge")
    local solid_bullet,_,_,_,_,solid_width,solid_height=renderer:bullet_image({sprite=999,anim=1})
    assert_true(solid_bullet==nil,"ANM 603 bullet is rendered as geometry without a sprite")
    assert_equal(solid_width,8,"ANM 603 bullet preserves its source width")
    assert_equal(solid_height,8,"ANM 603 bullet preserves its source height")
    local spawning = {sprite = 4, color_index = 6, ex = {flags = 2, int1 = 1}, anim_frame = 8}
    local spawn_image = renderer:bullet_image(spawning)
    assert_true(spawn_image ~= blue_ring, "spawn effect uses its own descriptor sprite")
    close(spawning.legacy_bullet_animation.alpha, 136, 0.001, "spawn alpha follows ANM duration")
    spawning.anim_frame = 16
    assert_equal(renderer:bullet_image(spawning), blue_ring, "spawn jump reaches live bullet body")
    close(spawning.legacy_bullet_animation.alpha, 255, 0.001, "live bullet is opaque")
    local drop={kind="power",animation=112,animation_frame=1}
    local drop_image,drop_rect=renderer:item_image(drop)
    assert_true(drop_image~=nil and drop_rect.w>0,"item animation returns its actual sprite dimensions")
    close(drop.animation_vm.scale_x,.53125,1e-6,"item starts at half size and expands over sixteen ticks")
    close(drop.animation_vm.rotation,math.pi/4,1e-6,"new item rotates forty-five degrees per tick")
    drop.animation_frame=33;renderer:item_image(drop)
    assert_equal(drop.animation_vm.render_mode,0,"item becomes an unrotated sprite after thirty-two frames")
    local sky_draws={}
    local sky=StageBackground.new({anm=anm,std=std,lstg={
        Color=function(...) return {...} end,SetImageState=function() end,
        Render=function(...) sky_draws[#sky_draws+1]={...} end}})
    sky:set_stage("st06")
    for _=1,4000 do sky:update() end
    close(sky.layers[1].u,-.000033333334*4000,1e-6,"first sea layer scrolls left after its script stops")
    close(sky.layers[2].u,.000033333334*4000,1e-6,"second sea layer scrolls in the opposite direction")
    close(sky.layers[2].v,.00025*4000,1e-6,"second sea layer retains vertical texture motion")
    sky:draw_skyboxes()
    local moon
    for _,draw in ipairs(sky_draws) do
        if draw[1]=="tnr-th15-st06wl-3-1" then moon=draw end
    end
    assert_true(moon~=nil,"stage six creates the original moon sky layer")
    close(moon[2],(BossUi.PLAYFIELD_LEFT+BossUi.PLAYFIELD_RIGHT)/2,1e-6,"moon layer is horizontally centred")
    close(moon[3],BossUi.PLAYFIELD_TOP-60*BossUi.PLAYFIELD_SCALE,1e-6,
        "top-anchored sky layer uses y=-20 plus half its 160-unit height")
    local ring=sky.skyboxes[2].vm
    local quads={}
    require("tnr.legacy_replay.anm_geometry").draw_circle({
        Color=function(...) return {...} end,
        RenderTexture=function(texture,blend,...) quads[#quads+1]={...} end},
        ring,{loaded_texture="reference-ring"},{x=0,y=0,w=256,h=256},{256,256},0,0,1)
    assert_equal(#quads,127,"128 ring points form 127 closed segments")
    close(quads[1][1][1],480,1e-5,"source ring outer radius is radius plus half width")
    close(quads[1][4][1],0,1e-5,"source ring inner radius collapses to its centre")
    assert_equal(quads[1][1][6][1],1,"ring outer edge keeps primary alpha")
    assert_true(quads[1][4][6][1]>1,"ring centre uses the interpolating secondary alpha")
    close(quads[127][2][1],quads[1][1][1],1e-5,"ring seam closes geometrically")
    close(quads[127][2][5]-quads[1][1][5],256,1e-5,"texture wraps once around the full ring")

    local function capture_background_geometry(stage_key,texture_path)
        local source=anm[stage_key.."wl"]
        local cloned_anm={}
        for key,value in pairs(anm) do cloned_anm[key]=value end
        cloned_anm[stage_key.."wl"]={}
        local target_texture="capture:"..texture_path
        for i,entry in ipairs(source) do
            local copy={}
            for key,value in pairs(entry) do copy[key]=value end
            copy.loaded_texture="capture:"..entry.texture
            cloned_anm[stage_key.."wl"][i]=copy
        end
        local draws,depths=0,{}
        local lstg={
            Color=function(...) return {...} end,SetImageState=function() end,
            SetViewport=function() end,SetPerspective=function() end,SetFog=function() end,
            SetOrtho=function() end,Render4V=function() end,Render=function() end,
            SetTextureSamplerState=function() end,
            RenderTexture=function(texture,_,vertex)
                if texture==target_texture then
                    draws=draws+1
                    depths[vertex[3]]=true
                end
            end,
        }
        local bg=StageBackground.new({anm=cloned_anm,std=std,lstg=lstg,
            image_for=function(path) return path end,texture_sizes={}})
        bg:set_stage(stage_key)
        bg:update()
        bg:draw()
        return draws,bg,depths
    end
    local st02_ring_draws,st02_background=capture_background_geometry("st02","background/stage02/stg6bg8.png")
    assert_equal(st02_ring_draws,127,"stage two's original background ring renders all 128 points")
    local _,_,st02_depths=capture_background_geometry("st02","background/stage02/stg6bg5.png")
    assert_true(st02_depths[0] and st02_depths[-52],"stage two's scrolling surfaces render at both native depths")
    assert_equal(st02_depths[-104],nil,"stage two does not double the culling depth")
    local st04_cylinder_draws,st04_background=capture_background_geometry("st04","background/stage04/stage03b.png")
    assert_equal(st04_cylinder_draws,162,
        "stage four renders nine cylinder sections on each of its eighteen repeated faces")
    local has_stage2_ring,has_stage4_cylinder=false,false
    for _,box in pairs(st02_background.skyboxes) do
        if box.vm.texture_circle_max==128 then has_stage2_ring=true end
    end
    for _,layer in ipairs(st04_background.layers) do
        if layer.vm.texture_cylinder_segments==10 then has_stage4_cylinder=true end
    end
    assert_true(has_stage2_ring,"stage two links its ANM ring to the STD background layer")
    assert_true(has_stage4_cylinder,"stage four links its ANM cylinder to the STD background layer")

    -- The native culling volume can have a different origin from its quad.
    local std_vertex
    local composed=StageBackground.new({
        std={fixture={timeline={}, {position={10,20,30},faces={{x=1,y=2,z=3}},
            quads={{position={4,5,6},width=8,height=8}},width=8,height=8}}},
        image_for=function() return "fixture-image" end,
        lstg={
            Color=function(...) return {...} end,SetImageState=function() end,
            SetViewport=function() end,SetPerspective=function() end,SetFog=function() end,
            SetOrtho=function() end,Render4V=function(_,...) std_vertex={...} end,
        },
    })
    composed:set_stage("fixture");composed:draw()
    close(std_vertex[1],1,1e-6,"STD vertex uses the face and quad X origins")
    close(std_vertex[2],11,1e-6,"STD vertex uses the face and quad Y origins")
    close(std_vertex[3],9,1e-6,"STD vertex uses the face and quad Z origins")

    local sampled_quads={}
    local fixture_anm={fixturewl={{texture="fixture-background",width=8,height=8,
        loaded_texture="fixture-background-texture",sprites={{x=0,y=0,w=4,h=4}},scripts={[0]={
            {time=-1,id=300,0},{time=0,id=429,2,3},{time=0,id=425,0.125},
            {time=0,id=426,0.25},{time=0,id=312,0,1},{time=0,id=3}}}}}}
    local sampled=StageBackground.new({anm=fixture_anm,
        std={fixture={timeline={}, {faces={{x=0,y=0,z=0}},
            quads={{script=0,position={0,0,0},width=4,height=4}}}}},
        texture_sizes={['fixture-background']={8,8}},image_for=function() return "fixture-image" end,
        lstg={Color=function(...) return {...} end,SetImageState=function() end,
            SetViewport=function() end,SetPerspective=function() end,SetFog=function() end,
            SetOrtho=function() end,Render4V=function() end,Render=function() end,
            SetTextureSamplerState=function() end,
            RenderTexture=function(texture,blend,...) sampled_quads[#sampled_quads+1]={...} end}})
    sampled:set_stage("fixture");sampled:update();sampled:draw()
    assert_equal(#sampled_quads,2,"world background splits UVs where its scaled image wraps")
    assert_equal(sampled_quads[1][1][4],1,"world UV scroll advances in texture pixels")
    assert_equal(sampled_quads[1][2][4],8,"world UV scale reaches the texture seam before wrapping")
    assert_equal(sampled_quads[2][1][4],0,"world UV patch resumes from the wrapped edge")
    assert_equal(sampled_quads[1][1][5],2,"world V scroll advances independently")
    assert_equal(sampled_quads[1][4][5],7.5,"world V clamp samples the last texel center")

    -- Every stage must expose a background layout.
    for _, stage in ipairs({ "st01", "st02", "st03", "st04", "st05", "st06", "st07" }) do
        assert_true(std[stage] ~= nil, stage .. " must have a background config")
        local bg = StageBackground.new({
            lstg = {}, anm = anm, std = std,
            image_for = function(path) return path end,
            texture_sizes = {},
        })
        bg:set_stage(stage)
        assert_true(#bg.layers > 0, stage .. " must build at least one layer")
    end
end
