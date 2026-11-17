-- Tests for the legacy replay player ship and item system.
--
-- The player is built from the stage's `.sht` data, so these tests pin the
-- reference numbers: the hit, graze and item boxes, the movement speeds, the
-- power level mapping and the shooter set selection. The item tests pin the
-- drop table conversion and the fall then attract then collect lifecycle.

return function(assert_equal, assert_true)
    package.path = "game/scripts/?.lua;game/scripts/?/init.lua;" .. package.path
    local Player = require("tnr.legacy_replay.player")
    local Items = require("tnr.legacy_replay.items")
    local sht = require("tnr.legacy_replay.data.th15_sht")
    local float32 = require("tnr.legacy_replay.reference_rules").float32

    local function close(a, b, tolerance, message)
        assert_true(math.abs(a - b) <= (tolerance or 1e-6),
            string.format("%s: expected %.4f got %.4f", message, b, a))
    end

    -- Every reference character must compile with its stats.
    for _, character in ipairs({ "reimu", "marisa", "sanae", "reisen" }) do
        local definition = sht[character]
        assert_true(definition ~= nil, character .. " must have an sht definition")
        assert_true(definition.hitbox ~= nil and definition.hitbox > 0,
            character .. " must have a hit box")
        assert_true(definition.grazebox ~= nil and definition.grazebox > 0,
            character .. " must have a graze box")
        assert_true(definition.move_unfocused ~= nil and definition.move_focused ~= nil,
            character .. " must have both movement speeds")
        assert_true(#(definition.shooters or {}) > 0,
            character .. " must have shooter sets")
        assert_true(definition.options ~= nil, character .. " must have option positions")
    end

    -- Reimu's reference numbers.
    local reimu = sht.reimu
    close(reimu.hitbox, 2.0, 1e-6, "reimu hit box")
    close(reimu.grazebox, 6.0, 1e-6, "reimu graze box")
    close(reimu.itembox, 28.0, 1e-6, "reimu item box")
    close(reimu.move_unfocused, 4.5, 1e-6, "reimu unfocused speed")
    close(reimu.move_focused, 2.0, 1e-6, "reimu focused speed")
    -- Marisa is faster and has a larger hit box, which is the reference trade.
    close(sht.marisa.move_unfocused, 5.0, 1e-6, "marisa unfocused speed")
    assert_true(sht.marisa.hitbox > reimu.hitbox, "marisa has a larger hit box")

    -- A player built from that definition exposes the same numbers.
    local player = Player.new({ definition = reimu })
    close(player.y, 400, 1e-6, "TH15 initializes the player at y=400")
    close(player.hitbox, 2.0, 1e-6, "player hit box comes from the definition")
    close(player:speed(), 4.5, 1e-6, "unfocused speed")
    player.focus = true
    close(player:speed(), 2.0, 1e-6, "focused speed")
    player.focus = false

    -- Power maps onto four fire levels.
    player.power = 0
    assert_equal(player:power_level(), 1, "no power is level one")
    player.power = 100
    assert_equal(player:power_level(), 2, "100 power selects the first upgraded shooter set")
    player.power = 400
    assert_equal(player:power_level(), 5, "400 power selects the fifth shooter set")

    -- Native 45690f rebuilds and resets every option slot when the power
    -- level changes, but a focus transition alone retains interpolation.
    for _, character in ipairs({ "reimu", "marisa", "sanae", "reisen" }) do
        local first = Player.new({ definition=sht[character], x=20, y=200, power=399 })
        local second = Player.new({ definition=sht[character], x=-30, y=240, power=399 })
        first:update_options(); second:update_options()
        local second_x,second_y=second.option_anchors[1][1],second.option_anchors[1][2]
        first.x=first.x+10;first:update_options()
        first.power=400;first:update_options()
        local layout=first.definition.options.unfocused[first:power_level()-1]
        for index,offset in ipairs(layout) do
            assert_equal(first.option_anchors[index][1],math.modf((first.x+offset[1])*128),character.." level-up option x")
            assert_equal(first.option_anchors[index][2],math.modf((first.y+offset[2])*128),character.." level-up option y")
        end
        assert_equal(second.option_anchors[1][1],second_x,character.." other player's option x stays independent")
        assert_equal(second.option_anchors[1][2],second_y,character.." other player's option y stays independent")
        first.focus=true;first:update_options()
        local focus_layout=first.definition.options.focused[first:power_level()-1]
        if focus_layout[1][1]~=layout[1][1] then
            assert_true(first.option_anchors[1][1]~=math.modf((first.x+focus_layout[1][1])*128),
                character.." focus change keeps option interpolation")
        end
        first.power=299;first:update_options()
        local lower=first.definition.options.focused[first:power_level()-1]
        for index,offset in ipairs(lower) do
            assert_equal(first.option_anchors[index][1],math.modf((first.x+offset[1])*128),character.." level-down option x")
            assert_equal(first.option_anchors[index][2],math.modf((first.y+offset[2])*128),character.." level-down option y")
        end
        assert_equal(#first.option_anchors,#lower,character.." level-down removes extra slots")
    end

    -- Shooter sets are selected by focus state and power level.
    player.power = 0
    local unfocused = player:current_shooters()
    assert_true(unfocused ~= nil, "an unfocused shooter set exists")
    assert_equal(unfocused.kind, "unfocused", "the unfocused set is selected")
    assert_equal(#unfocused.sources, 2, "level one unfocused fires two sources")
    player.focus = true
    local focused = player:current_shooters()
    assert_equal(focused.kind, "focused", "the focused set is selected")
    player.focus = false

    -- Firing produces one bullet per source with the reference angle.
    local bullets = player:fire()
    assert_equal(#bullets, #unfocused.sources, "one bullet per shooter source")
    close(bullets[1].angle, -1.570796, 1e-4, "the first source fires straight up")
    assert_true(bullets[1].damage and bullets[1].damage > 0, "bullets carry damage")
    assert_equal(player.shots_fired, 1, "the fire counter advances")

    -- Movement clamps to the field.
    local mover = Player.new({ definition = reimu })
    mover.x = 1000
    mover:move(0, 0, false)
    close(mover.x,184,1e-6,"TH15 right movement limit")
    mover.y = -1000
    mover:move(0, 0, false)
    close(mover.y,32,1e-6,"TH15 top movement limit")
    mover.y = 1000
    mover:move(0,0,false)
    close(mover.y,432,1e-6,"TH15 bottom movement limit")

    -- Diagonal movement is not faster than straight movement.
    local straight = Player.new({ definition = reimu })
    straight:move(0, 1, false)
    local diagonal = Player.new({ definition = reimu })
    diagonal:move(1, 1, false)
    close(straight.y,395.5,1e-6,"straight movement retains the original speed")
    close(diagonal.x,407/128,1e-6,"diagonal speed truncates to the native fixed-point unit")
    close(diagonal.y,400-407/128,1e-6,"diagonal movement uses the same quantized step per axis")

    -- Hit, graze and collect boxes.
    local target = Player.new({ definition = reimu })
    target.x, target.y = 0, 200
    assert_true(target:hits(0, 200), "a direct hit registers")
    assert_true(not target:hits(10, 200), "a distant point misses")
    assert_true(target:hits(4, 200, 4), "native sum of squared radii registers contact")
    assert_true(not target:hits(5, 200, 4), "native collision does not sum radii before squaring")
    assert_true(not target:grazes(4, 200, 4), "a hit cannot also graze")
    assert_true(target:grazes(9, 200, 4), "bullet edge contributes to grazing")
    assert_true(target:grazes(0, 205), "a nearby point grazes")
    assert_true(target:grazes(0, 240), "native graze reach includes forty units")
    assert_true(not target:grazes(0, 243), "outside native graze reach")
    assert_true(target:collects(0, 210), "an item within the item box collects")
    assert_true(not target:collects(0, 216), "attraction is not collection")
    assert_true(target:attracts(0,230), "unfocused attraction half width is thirty")
    target.focus=true
    assert_true(target:attracts(0,250), "focused attraction half width is fifty")

    local fall=Items.new({})
    local falling=fall:spawn("power",0,100);falling.vy=2
    fall:on_graze(1);fall:update()
    close(falling.y,float32(100.6),1e-6,"graze slows falling to thirty percent")
    close(fall.slowdown,.4,1e-6,"native item manager recovers the shared factor once per frame")
    fall:update()
    close(falling.y,float32(float32(100.6)+.8),1e-6,"all players share the recovering slowdown")
    close(fall.slowdown,.5,1e-6,"factor advances by one tenth after item motion")
    fall:on_graze(2)
    close(fall.slowdown,.3,1e-6,"either co-op player sets the shared native slowdown")
    falling.timer=32;fall:on_graze(1);local before_y=falling.y;fall:update()
    assert_true(falling.slowed_visual,"slowed mature items show the reference tint")
    assert_true(math.abs(falling.draw_offset_x)<=1 and math.abs(falling.draw_offset_y)<=1,"slowdown jitter remains within one unit")
    close(falling.y,float32(before_y+.6),1e-6,"cosmetic jitter never changes item physics")
    local graze_collector=Player.new({definition=reimu,y=300})
    local graze_items=Items.new({player=graze_collector})
    local graze_item=graze_items:spawn_graze(0,100,1,-math.pi/2)
    graze_items:update()
    assert_equal(graze_item.launch_delay,1,"first graze drop waits one tick before its sprite appears")
    graze_items:update()
    assert_equal(graze_item.launch_delay,nil,"next tick activates the graze sprite")
    assert_equal(graze_item.y,100,"activation preserves the exact drop origin")
    graze_item.timer=31
    graze_items:on_graze(1);graze_items:update()
    close(graze_item.y,float32(97.8),1e-6,"launched graze items rise at full speed during slowdown")
    assert_true(not graze_item.slowed_visual,"graze launch does not use free fall tint")
    graze_item.vy=-.01
    local apex_y=graze_item.y
    graze_items:update()
    assert_true(graze_item.attracted,"graze item homes as soon as it reaches its apex")
    close(graze_item.y,float32(float32(apex_y-.01)+graze_collector.attract_speed),1e-6,
        "graze homing moves on the apex frame")
    local collector=Player.new({definition=reimu});collector.x=100;collector.y=100
    local reacquire=Items.new({player=collector})
    local pickup=reacquire:spawn("point",-100,250)
    reacquire:update();assert_true(pickup.auto_collect,"above line begins auto collection")
    collector.alive=false;reacquire:update()
    assert_true(not pickup.attracted and not pickup.auto_collect,"death clears homing and its full-value marker")
    collector.alive=true;reacquire:update()
    assert_true(pickup.attracted and pickup.auto_collect,"revived collector reacquires the same item")

    -- Normal stage-two demo, slot 580 on frame 1940. Clamping the
    -- speed to 12 makes this point item miss the pickup box on frame 1944.
    local demo_ship=Player.new({definition=reimu,x=-168.3984375,y=147.8359375})
    local demo_items=Items.new({player=demo_ship})
    local blue=demo_items:spawn("point",-130.68258666992188,112.71746063232422)
    blue.attracted,blue.auto_collect,blue.attract_speed=true,true,11.999993324279785
    for frame=1941,1944 do
        demo_ship.y=demo_ship.y+4.5
        demo_items:update()
        if frame==1942 then
            close(blue.y,130.7916717529297,1e-5,"native auto-collection trajectory at frame 1942")
        elseif frame<1944 then
            assert_equal(demo_items:count(),1,"blue point is still flying")
        end
    end
    assert_equal(demo_items:drain_collected()[1],blue,"blue point enters pickup box on native frame 1944")

    -- The drop table converts to the reference item counts.
    local items = Items.new({})
    local spawned = items:spawn_drop({ 380, 3, 4 }, 0, 100)
    -- 380 power is 3 large and 80 small; faith and point become 7 points.
    assert_equal(#spawned, 3 + 80 + 7, "the drop table expands to the right count")
    local kinds = {}
    for _, item in ipairs(spawned) do kinds[item.kind] = (kinds[item.kind] or 0) + 1 end
    assert_equal(kinds[Items.KIND.POWER_LARGE], 3, "large power items")
    assert_equal(kinds[Items.KIND.POWER], 80, "small power items")
    assert_equal(kinds[Items.KIND.POINT], 7, "point items")
    -- A full power drop is the F card.
    local full = items:spawn_drop({ 400, 0, 0 }, 0, 100)
    assert_equal(#full, 1, "a full power drop is one item")
    assert_equal(full[1].kind, Items.KIND.FULL_POWER, "the full power drop is the F card")

    -- Items fall, then attract to the player and are collected.
    local carrier = Player.new({ definition = reimu })
    carrier.x, carrier.y = 0, 100
    local field = Items.new({ player = carrier })
    field:spawn_drop({ 10, 0, 10 }, 0, 60)
    local collected = 0
    for _ = 1, 900 do
        field:update()
        collected = collected + #field:drain_collected()
    end
    assert_equal(collected, 20, "every item is eventually collected")
    assert_equal(field:count(), 0, "the field empties once everything is collected")
end
