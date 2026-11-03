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
    assert_true(math.abs(mover.x) <= Player.FIELD_HALF_WIDTH,
        "the ship cannot leave the field horizontally")
    mover.y = -1000
    mover:move(0, 0, false)
    assert_true(mover.y >= Player.FIELD_TOP, "the ship cannot leave the field vertically")

    -- Diagonal movement is not faster than straight movement.
    local straight = Player.new({ definition = reimu })
    straight:move(0, 1, false)
    local diagonal = Player.new({ definition = reimu })
    diagonal:move(1, 1, false)
    local straight_gain = math.abs(straight.y - (Player.FIELD_BOTTOM - 64))
    local diagonal_gain = math.abs(diagonal.y - (Player.FIELD_BOTTOM - 64))
    -- The reference diagonal speed is the per-axis value, so a diagonal covers
    -- less ground per axis than a straight move but the same total distance.
    local diagonal_total = math.sqrt(
        (diagonal.x - 0) ^ 2 + (diagonal.y - (Player.FIELD_BOTTOM - 64)) ^ 2)
    assert_true(diagonal_gain <= straight_gain + 1e-6,
        "a diagonal move is not faster on a single axis")
    assert_true(math.abs(diagonal_total - straight_gain) <= 1e-3,
        "a diagonal covers the same total distance as a straight move")

    -- Hit, graze and collect boxes.
    local target = Player.new({ definition = reimu })
    target.x, target.y = 0, 200
    assert_true(target:hits(0, 200), "a direct hit registers")
    assert_true(not target:hits(10, 200), "a distant point misses")
    assert_true(target:hits(5, 200, 4), "bullet radius contributes to contact")
    assert_true(not target:grazes(5, 200, 4), "a hit cannot also graze")
    assert_true(target:grazes(9, 200, 4), "bullet edge contributes to grazing")
    assert_true(target:grazes(0, 205), "a nearby point grazes")
    assert_true(not target:grazes(0, 220), "a far point does not graze")
    assert_true(target:collects(0, 210), "an item within the item box collects")

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
