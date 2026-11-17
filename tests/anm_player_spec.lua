-- Tests for the ANM animation player used by the legacy replay mode.
--
-- thtk `thanm -l` dumps sprite rectangles and animation scripts; the compiled
-- form is played here to pick the sprite shown each frame. These tests pin the
-- sprite indexing, the timed instruction schedule and the loop opcode.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local AnmPlayer = require("tnr.legacy_replay.anm_player")
    local AnmGeometry = require("tnr.legacy_replay.anm_geometry")
    local anm = require("tnr.legacy_replay.data.th15_anm")

    -- Masks distinguish literal values from variable operands. Destinations
    -- remain references even when their corresponding mask bit is set.
    local arithmetic=AnmPlayer.new({scripts={[0]={
        {time=0,id=101,mask=1,10004,0.4},
        {time=0,id=103,mask=1,10004,0.2},
        {time=0,id=117,mask=3,10005,10004,2},
        {time=0,id=402,mask=3,10004,10005},
        {time=0,id=6,3},
        {time=0,id=403,64},
        {time=0,id=3}}}})
    arithmetic:play(0);arithmetic:update()
    assert_true(math.abs(arithmetic.scale_x-0.6)<0.000001,"masked scale resolves F0")
    assert_true(math.abs(arithmetic.scale_y-1.2)<0.000001,"setMul resolves its source")
    assert_equal(arithmetic.alpha,255,"wait suspends same-time instructions")
    arithmetic:update();arithmetic:update()
    assert_equal(arithmetic.alpha,255,"wait lasts its full duration")
    arithmetic:update()
    assert_equal(arithmetic.alpha,64,"wait resumes without freezing the VM")
    local parent=AnmPlayer.new({scripts={
        [0]={{time=0,id=505,1,20,30},{time=0,id=504,1},{time=0,id=3}},
        [1]={{time=0,id=400,5,6,0},{time=0,id=3}}}})
    parent:play(0);parent:update()
    assert_equal(parent.children[1].x,5,"child position does not overwrite its creation offset")
    assert_equal(parent.children[1].offset_x,20,"child creation stores a separate offset")
    assert_equal(#parent.pending_roots,1,"root creation queues a detached animation")
    assert_equal(#parent.children,1,"root animation is not retained as a child")
    local effect_id
    local effect_vm=AnmPlayer.new({scripts={[0]={{time=0,id=508,63},{time=0,id=3}}}})
    effect_vm.on_effect=function(id,source) effect_id=id end
    effect_vm:play(0)
    effect_vm:update()
    assert_equal(effect_id,63,"effectNew delegates its effect type to the runtime")

    assert_true(anm.st01enm ~= nil, "the stage 1 enemy archive compiles")
    local archive = anm.st01enm and anm.st01enm[1]
    assert_true(archive ~= nil, "the stage 1 enemy archive has an entry")
    assert_equal(archive.texture, "stgenm/stage01/enm1.png", "the enemy texture is recorded")
    assert_true(#archive.sprites > 0, "the archive exposes sprite rectangles")

    -- Every sprite rectangle must be inside the texture the archive names.
    for index, sprite in ipairs(archive.sprites) do
        assert_true(sprite.w > 0 and sprite.h > 0,
            "sprite " .. index .. " must have a positive size")
        assert_true(sprite.x >= 0 and sprite.y >= 0,
            "sprite " .. index .. " must start inside the texture")
    end

    -- A sprite rect carries the position and size the renderer needs.
    local first = archive.sprites[1]
    assert_equal(first.w, 64, "the first stage 1 enemy sprite is 64 wide")
    assert_equal(first.h, 96, "the first stage 1 enemy sprite is 96 tall")

    -- Playing a script advances the displayed sprite over time.
    local player = AnmPlayer.new(archive)
    assert_true(player:play(0), "script 0 is available")
    player:update()
    assert_equal(player.sprite, 1, "the player starts on the first sprite")
    local sprites_seen = {}
    for _ = 1, 120 do
        player:update()
        sprites_seen[player.sprite] = true
    end
    local distinct = 0
    for _ in pairs(sprites_seen) do distinct = distinct + 1 end
    assert_true(distinct > 1, "the script cycles through several sprites")
    for entry_index,entry in ipairs(anm.enemy) do
        if entry.scripts[162] then
            local fairy=AnmPlayer.new(entry,"enemy",entry_index)
            fairy.archive_entries=anm.enemy
            fairy:play(162)
            fairy:update()
            local rect,texture_index=fairy:rect()
            assert_equal(texture_index,4,"fairy frame uses the archive-wide sprite index")
            assert_equal(rect.y,96,"fairy frame resolves to the correct atlas row")
            assert_equal(rect.h,32,"enemy culling uses the active fairy frame height")
            break
        end
    end

    -- Every script must keep its sprite index inside the sprite table. An out
    -- of range index would draw nothing at runtime.
    for script_id in pairs(archive.scripts) do
        local script_player = AnmPlayer.new(archive)
        script_player:play(script_id)
        for _ = 1, 400 do
            script_player:update()
            assert_true(script_player.sprite==0 or script_player.sprites[script_player.sprite] ~= nil,
                "script " .. script_id .. " must keep its sprite index in range")
            if script_player.finished then break end
        end
    end

    local title=AnmPlayer.new(anm.st02logo[1],"st02logo",1)
    title.archive_entries=anm.st02logo
    assert_true(title:play(0),"stage-two title has an animation controller")
    for _=1,420 do title:update() end
    assert_equal(#title.children,0,"the title components have all faded out")
    assert_equal(title.sprite,0,"the controller never draws the default title sprite")

    -- A jump's operands are a byte address and the local timeline to resume.
    -- All frames must keep the same dwell time on subsequent loop iterations.
    local looped={sprites=archive.sprites,scripts={[0]={
        {time=0,id=300,0},{time=7,id=300,1},{time=14,id=200,0,0}}}}
    local vm=AnmPlayer.new(looped);vm:play(0)
    for frame=0,139 do
        vm:update()
        assert_equal(vm.sprite,math.floor((frame%14)/7)+1,"loop dwell frame "..frame)
    end
    local reference=AnmPlayer.new(archive);reference:play(0)
    local samples={}
    for frame=0,335 do
        reference:update()
        if frame<112 then samples[frame]=reference.sprite
        else assert_equal(reference.sprite,samples[frame%112],"reference idle repeats on its 112-frame clock") end
    end
    local stopped=AnmPlayer.new({sprites=archive.sprites,scripts={[0]={
        {time=0,id=300,0},{time=5,id=3},{time=5,id=300,1}}}})
    stopped:play(0)
    for _=1,50 do stopped:update() end
    assert_equal(stopped.sprite,1,"stop freezes execution before following instruction")
    assert_true(stopped.visible,"stop keeps sprite visible")

    -- An unavailable script is recorded rather than crashing the caller.
    local missing = AnmPlayer.new(archive)
    assert_true(missing:play(9999) == false, "a missing script is rejected")
    assert_true(missing.unhandled["script:9999"] ~= nil, "the missing script is recorded")

    -- TH15 stores all three Euler angles, vector angular velocity, texture
    -- scale/scroll, and the sampler modes in the ANM VM.
    local extended=AnmPlayer.new({scripts={[0]={
        {time=0,id=401,0.1,0.2,0.3},
        {time=0,id=415,0.01,0.02,0.03},
        {time=0,id=429,2,3},
        {time=0,id=311,1},
        {time=0,id=312,0,1},
        {time=0,id=437,5},
        {time=0,id=600,10000},
        {time=0,id=609,10000},
        {time=0,id=427,2,0,0.5},
        {time=0,id=428,2,0,-0.25},
        {time=0,id=430,2,0,4,5}}}})
    extended:play(0);extended:update()
    assert_equal(extended.rotation_x,0.1,"rotate sets X angle")
    assert_equal(extended.rotation_y,0.2,"rotate sets Y angle")
    assert_equal(extended.rotation,0.3,"rotate sets Z angle")
    assert_equal(extended.uv_scale_x,2,"uvScale sets U scale")
    assert_equal(extended.uv_scale_y,3,"uvScale sets V scale")
    assert_equal(extended.resample_mode,1,"resample mode selects point filtering")
    assert_equal(extended.scroll_mode_x,0,"scroll mode preserves U wrapping")
    assert_equal(extended.scroll_mode_y,1,"scroll mode preserves V clamping")
    assert_equal(extended.rotation_system,5,"rotation system stores the ZYX order")
    assert_equal(extended.texture_circle_max,10000,"textureCircle stores its vertex buffer capacity")
    assert_equal(extended.texture_cylinder_segments,10000,"textureCylinder3D stores its vertex buffer capacity")
    extended:update()
    assert_equal(extended.u_vel,0.25,"U velocity tween advances in source units")
    assert_equal(extended.v_vel,-0.125,"V velocity tween advances in source units")
    assert_equal(extended.uv_scale_x,3,"UV scale tween advances both axes")
    assert_equal(extended.uv_scale_y,4,"V scale tween advances")
    assert_true(math.abs(extended.rotation-0.33)<1e-6,"angular velocity advances Z rotation")

    local rectangle=AnmPlayer.new({scripts={[0]={
        {time=0,id=404,64,80,96},{time=0,id=303,2},{time=0,id=603,8,12},{time=0,id=3}}}})
    rectangle:play(0);rectangle:update()
    assert_equal(rectangle.geometry_width,8,"ANM 603 stores the custom rectangle width")
    assert_equal(rectangle.geometry_height,12,"ANM 603 stores the custom rectangle height")
    local rectangle_draws={}
    assert_true(AnmGeometry.draw_rect({Color=function(...) return {...} end,
        RenderTexture=function(texture,blend,...) rectangle_draws[#rectangle_draws+1]={texture,blend,...} end},
        rectangle,100,200,rectangle.geometry_width,rectangle.geometry_height,2,3),
        "ANM 603 uses a solid quad when no sprite is selected")
    assert_equal(rectangle_draws[1][1],"tnr-white-texture","ANM 603 quad uses the white source texture")
    assert_equal(rectangle_draws[1][2],"mul+rev","ANM 303 mode two uses reverse subtraction for custom geometry")
    assert_equal(rectangle_draws[1][3][1],92,"ANM 603 width is centered around its origin")
    assert_equal(rectangle_draws[1][3][2],182,"ANM 603 height is centered around its origin")
    assert_equal(rectangle_draws[1][4][1],108,"ANM 603 right edge respects scale")
    assert_equal(rectangle_draws[1][4][2],182,"ANM 603 lower edge is consistent")

    local curve=AnmPlayer.new({scripts={[0]={
        {time=0,id=400,8,10,3},{time=0,id=420,4,20,30,7,8,-8,0,-4,4,0},
        {time=0,id=3}}}})
    curve:play(0);curve:update();curve:update();curve:update()
    assert_equal(curve.x,15.5,"ANM 420 uses both tangent vectors along the horizontal axis")
    assert_equal(curve.y,18.5,"ANM 420 preserves signed tangents independently along each axis")
    assert_equal(curve.z,5,"ANM 420 interpolates depth with the same interval")
    curve:update();curve:update()
    assert_equal(curve.x,20,"ANM 420 arrives at the target before the next curve starts")

    local wrapped=AnmGeometry.uv_patches(510,530,10,20,512,256,0,1,false)
    assert_equal(#wrapped,2,"U wrap splits a quad at the texture seam")
    assert_equal(wrapped[1].sampler,"linear+wrap","wrapped axis enables texture repeat")
    assert_equal(wrapped[1].uv[2][1],512,"first U patch ends at the texture edge")
    assert_equal(wrapped[2].uv[1][1],0,"next U patch resumes at the opposite edge")
    assert_equal(wrapped[2].uv[1][2],10,"clamped V axis keeps its original coordinate")
    local mirrored=AnmGeometry.uv_patches(510,530,20,30,512,256,2,1,true)
    assert_equal(#mirrored,2,"mirror addressing splits at the texture seam")
    assert_equal(mirrored[1].uv[2][1],511.5,"point-filter mirror stays on the last source texel")
    assert_equal(mirrored[2].uv[1][1],511.5,"next mirrored region reflects from the edge")
    assert_equal(mirrored[1].sampler,"point+clamp","point filtering and mirrored addressing use point sampling")
    local point_clamp=AnmGeometry.uv_patches(510,530,250,270,512,256,0,1,true)
    assert_equal(point_clamp[1].uv[4][2],255.99999,
        "point-filter clamp avoids wrapping the edge on a mixed-mode texture")
    local rx,ry=AnmGeometry.rotate3(0,1,0,math.pi/2,math.pi/2,0,0)
    assert_true(math.abs(rx-1)<1e-6,"XYZ rotation applies axes in source order")
    assert_true(math.abs(ry)<1e-6,"XYZ rotation second component")
    local yx,yy=AnmGeometry.rotate3(0,1,0,math.pi/2,math.pi/2,0,2)
    assert_true(math.abs(yx-rx)>0.1 or math.abs(yy-ry)>0.1,
        "rotation-system modes select a distinct Euler order")

    local ring_quads={}
    local ring_vm={texture_circle_max=4,vars={[10000]=4,[10001]=2},scale_x=4,scale_y=10,
        alpha=255,red=255,green=255,blue=255,alpha2=255,red2=255,green2=255,blue2=255,
        color_mode=1,rotation=0,rotation_x=0,rotation_y=0,rotation_system=0,uv_scale_x=1}
    AnmGeometry.draw_world_circle({Color=function(...) return {...} end,
        RenderTexture=function(texture,blend,...) ring_quads[#ring_quads+1]={...} end},ring_vm,
        {loaded_texture="ring",width=64,height=32},{x=3,y=5,w=16,h=32},{64,32},{0,0,0})
    assert_equal(#ring_quads,3,"textureCircle uses I0 points for I0-1 mesh segments")
    assert_equal(ring_quads[1][1][1],12,"textureCircle outer radius includes half the signed width")
    assert_equal(ring_quads[1][1][4],19,"positive textureCircle scale reverses the source radial axis")
    assert_equal(ring_quads[1][3][4],3,"textureCircle maps its inner edge to the opposite side of the image")
    assert_equal(ring_quads[3][2][5]-ring_quads[1][1][5],64,
        "textureCircle repeats the full texture height I1 times around the shape")

    local cylinder_quads={}
    local cylinder_vm={texture_cylinder_segments=4,vars={[10000]=4,[10001]=2,[10004]=math.pi/2,
        [10005]=12,[10006]=8,[10007]=math.pi/2},alpha=255,red=255,green=255,blue=255,
        alpha2=255,red2=255,green2=255,blue2=255,color_mode=0,rotation=0,rotation_x=0,
        rotation_y=0,rotation_system=0,uv_scale_x=1,uv_scale_y=1}
    AnmGeometry.draw_world_cylinder({Color=function(...) return {...} end,
        RenderTexture=function(texture,blend,...) cylinder_quads[#cylinder_quads+1]={...} end},cylinder_vm,
        {loaded_texture="cylinder",width=64,height=32},{x=2,y=3,w=16,h=32},{64,32},{0,0,0})
    assert_equal(#cylinder_quads,3,"textureCylinder3D renders I0-1 angular sections")
    assert_true(math.abs(cylinder_quads[1][1][1]-8*math.cos(math.pi/4))<1e-6,
        "textureCylinder3D places the first point at F3-F0/2")
    assert_equal(cylinder_quads[1][1][2],6,"textureCylinder3D height spans plus and minus F1/2")
    assert_equal(cylinder_quads[3][2][5]-cylinder_quads[1][1][5],64,
        "textureCylinder3D repeats the full source texture height I1 times")
end
