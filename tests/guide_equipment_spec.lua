local Catalog = require("tnr.equipment.phase1_catalog")
local EquipmentInstance = require("tnr.equipment.equipment_instance")
local GameSession = require("tnr.core.game_session")
local WeaponRuntimeManager = require("tnr.equipment.runtime.weapon_runtime_manager")
local SupportRuntimeManager = require("tnr.equipment.runtime.support_runtime_manager")
local ModifierRuntime = require("tnr.equipment.runtime.modifier_runtime")
local StageAdapter = require("tnr.battle.stage_adapter")

return function(assert_equal, assert_true)
    local production = {
        "hakurei_sealing_needle", "hakurei_persuasion_needle", "hakurei_dream_sealing_needle",
        "marisa_magic_missile", "marisa_earthlight_ray", "marisa_master_spark_weapon",
        "sanae_sky_serpent", "sanae_cobalt_spread", "sanae_yasaka_divine_wind",
        "self_duplex_barrier", "self_giant_yinyang_projectile", "self_high_speed_casting",
        "self_magic_penetration", "self_homing_formula", "self_afterglow",
        "support_hakurei_yinyang_orb", "support_marisa_orreries_sun", "support_sanae_snakeskin_amulet",
        "support_hakurei_ward_array", "support_modifier_front_formation",
        "support_modifier_orbit_formation", "support_modifier_high_phantom_charge",
        "support_modifier_low_phantom_edge", "support_modifier_barrier_pulse",
    }
    assert_equal(#production, 24, "first guide includes nine weapons, six self modifiers, four supports, five support modifiers")
    for _, id in ipairs(production) do
        assert_true(Catalog.registry:get(id) ~= nil, "guide definition is registered: " .. id)
    end

    local high_ids = { "hakurei_sealing_needle", "hakurei_persuasion_needle", "marisa_magic_missile", "sanae_sky_serpent", "sanae_cobalt_spread" }
    local low_ids = { "hakurei_dream_sealing_needle", "marisa_earthlight_ray", "marisa_master_spark_weapon", "sanae_yasaka_divine_wind" }
    for _, id in ipairs(high_ids) do
        local definition = Catalog.registry:get(id)
        assert_true(definition.allowed_slots.HIGH_WEAPON == true and not definition.allowed_slots.LOW_WEAPON,
            id .. " is high-slot only")
        assert_true(definition.active_modes.HIGH == true and not definition.active_modes.LOW,
            id .. " is high-mode only")
    end
    for _, id in ipairs(low_ids) do
        local definition = Catalog.registry:get(id)
        assert_true(definition.allowed_slots.LOW_WEAPON == true and not definition.allowed_slots.HIGH_WEAPON,
            id .. " is low-slot only")
        assert_true(definition.active_modes.LOW == true and not definition.active_modes.HIGH,
            id .. " is low-mode only")
    end
    assert_equal(Catalog.registry:get("hakurei_dream_sealing_needle").penetration, 0,
        "Yokai-Sealing Needle uses the confirmed zero penetration")
    assert_equal(Catalog.registry:get("marisa_master_spark_weapon").metadata.transform_chance, 0.10,
        "Master Spark keeps the ten-percent hit-triggered transform chance")
    assert_equal(Catalog.registry:get("sanae_yasaka_divine_wind").metadata.max_active_fields, 6,
        "Divine Wind caps active wind fields at six")
    assert_true(Catalog.registry:get("support_modifier_high_phantom_charge") ~= Catalog.registry:get("support_modifier_low_phantom_edge"),
        "high and low Phantom support modifiers have distinct definitions")
    assert_equal(Catalog.registry:get("support_modifier_high_phantom_charge").metadata.active_mode, "HIGH",
        "Phantom Charge is high-only")
    assert_equal(Catalog.registry:get("support_modifier_low_phantom_edge").metadata.active_mode, "LOW",
        "Phantom Edge is low-only")

    local session = GameSession.new({ run_seed = 8142 })
    session:start_new()
    local player = session:get_player(1)
    local needle = EquipmentInstance.new(Catalog.registry:get("hakurei_sealing_needle"), 1)
    player.loadout:set_slot("high_weapons", 1, needle)
    local ok, reason = session.loadout_service:can_equip(needle, "low_weapons", 1, 1, true)
    assert_equal(ok, false, "the same non-dual weapon cannot occupy both weapon collections")
    assert_equal(reason, "ALREADY_EQUIPPED", "duplicate equipped weapon has an explicit reason")

    local spread_loadout = {
        high_weapons = { EquipmentInstance.new(Catalog.registry:get("sanae_cobalt_spread"), 1) },
        low_weapons = {}, supports = {}, self_modifiers = {}, support_modifiers = {},
    }
    local spread_shots = WeaponRuntimeManager.new(spread_loadout, Catalog.registry):update("HIGH", true,
        { x = 0, y = 0, angle = 90 })
    assert_equal(#spread_shots, 5, "Cobalt Spread creates five projectiles")
    assert_equal(spread_shots[1].angle, 70, "Cobalt Spread starts at -20 degrees")
    assert_equal(spread_shots[5].angle, 110, "Cobalt Spread ends at +20 degrees")
    assert_equal(spread_shots[1].projectile_type, "sanae_wind", "spread pattern keeps its authored projectile type")

    local beam_loadout = {
        high_weapons = {},
        low_weapons = { EquipmentInstance.new(Catalog.registry:get("marisa_earthlight_ray"), 1) },
        supports = {}, self_modifiers = {}, support_modifiers = {},
    }
    local beam_shots = WeaponRuntimeManager.new(beam_loadout, Catalog.registry):update("LOW", true,
        { x = 0, y = 0, angle = 90 })
    assert_equal(beam_shots[1].projectile_type, "MarisaLaser", "beam keeps its authored projectile type")
    assert_true(beam_shots[1].metadata.beam == true, "beam metadata is carried into the projectile descriptor")
    assert_equal(beam_shots[1].penetration, 999999, "Earthlight Ray has effectively infinite penetration")

    local homing_loadout = {
        high_weapons = { EquipmentInstance.new(Catalog.registry:get("sanae_sky_serpent"), 1) },
        low_weapons = {}, supports = {}, self_modifiers = {}, support_modifiers = {},
    }
    local homing_shots = WeaponRuntimeManager.new(homing_loadout, Catalog.registry):update("HIGH", true,
        { x = 0, y = 0, angle = 90 })
    assert_equal(homing_shots[1].projectile_type, "sanae_wind2", "homing weapon keeps its authored projectile type")
    assert_true(homing_shots[1].metadata.homing == true, "homing metadata is carried into the projectile descriptor")

    local support_loadout = {
        high_weapons = {}, low_weapons = {},
        supports = { EquipmentInstance.new(Catalog.registry:get("support_hakurei_yinyang_orb"), 1) },
        self_modifiers = {}, support_modifiers = {},
    }
    local support_manager = SupportRuntimeManager.new(support_loadout, Catalog.registry)
    local high_support_shots = support_manager:fire("HIGH", true, { x = 0, y = 0, angle = 90, player_id = 1 })
    local low_support_shots = SupportRuntimeManager.new(support_loadout, Catalog.registry):fire("LOW", true,
        { x = 0, y = 0, angle = 90, player_id = 1 })
    assert_equal(#high_support_shots, 4, "Yin-Yang Orb high mode fires one shot per orb")
    assert_equal(#low_support_shots, 8, "Yin-Yang Orb low mode fires a left/right pair per orb")
    assert_equal(high_support_shots[1].projectile_type, "reimu_bullet_blue", "high support uses blue orb bullets")
    assert_equal(low_support_shots[1].projectile_type, "reimu_bullet_orange", "low support uses orange orb bullets")

    local modifier_loadout = {
        high_weapons = { EquipmentInstance.new(Catalog.registry:get("hakurei_sealing_needle"), 1) },
        low_weapons = {}, supports = {},
        self_modifiers = { EquipmentInstance.new(Catalog.registry:get("self_duplex_barrier"), 1) },
        support_modifiers = {},
    }
    local modifier_runtime = ModifierRuntime.new(modifier_loadout, Catalog.registry)
    local modifier_shots = WeaponRuntimeManager.new(modifier_loadout, Catalog.registry, modifier_runtime):update("HIGH", true,
        { x = 0, y = 0, angle = 90 })
    assert_equal(#modifier_shots, 4, "Twin Barrier adds two side projectiles to a two-needle volley")
    assert_equal(modifier_shots[3].damage, 0.2, "Duplex Barrier side projectiles deal ten percent damage")
    assert_equal(modifier_shots[3].angle, 80, "Duplex Barrier adds the first left ten-degree shot")
    assert_equal(modifier_shots[4].angle, 100, "Duplex Barrier adds the first right ten-degree shot")

    local stacked_modifier_loadout = {
        high_weapons = { EquipmentInstance.new(Catalog.registry:get("hakurei_sealing_needle"), 1) },
        low_weapons = {}, supports = {}, self_modifiers = {
            EquipmentInstance.new(Catalog.registry:get("self_duplex_barrier"), 1),
            EquipmentInstance.new(Catalog.registry:get("self_duplex_barrier"), 1),
        }, support_modifiers = {},
    }
    local stacked_modifier_shots = WeaponRuntimeManager.new(stacked_modifier_loadout, Catalog.registry,
        ModifierRuntime.new(stacked_modifier_loadout, Catalog.registry)):update("HIGH", true,
        { x = 0, y = 0, angle = 90 })
    assert_equal(#stacked_modifier_shots, 6, "two Duplex Barriers add four projectiles")
    assert_equal(stacked_modifier_shots[5].angle, 70, "the second Duplex Barrier uses a twenty-degree left offset")
    assert_equal(stacked_modifier_shots[6].angle, 110, "the second Duplex Barrier uses a twenty-degree right offset")

    local tuned_loadout = {
        high_weapons = { EquipmentInstance.new(Catalog.registry:get("hakurei_persuasion_needle"), 1) },
        low_weapons = {}, supports = {},
        self_modifiers = {
            EquipmentInstance.new(Catalog.registry:get("self_high_speed_casting"), 1),
            EquipmentInstance.new(Catalog.registry:get("self_magic_penetration"), 1),
            EquipmentInstance.new(Catalog.registry:get("self_homing_formula"), 1),
        }, support_modifiers = {},
    }
    local tuned_manager = WeaponRuntimeManager.new(tuned_loadout, Catalog.registry,
        ModifierRuntime.new(tuned_loadout, Catalog.registry))
    local tuned_shots = tuned_manager:update("HIGH", true, { x = 0, y = 0, angle = 90 })
    assert_equal(tuned_shots[1].penetration, 2, "penetration modifier adds one layer")
    assert_true(tuned_shots[1].targeting == "NEAREST_ENEMY", "homing modifier supplies nearest-enemy targeting")
    assert_true(tuned_shots[1].damage < 2.6, "speed and penetration modifiers apply their damage tradeoffs")

    local giant_loadout = {
        high_weapons = { EquipmentInstance.new(Catalog.registry:get("hakurei_sealing_needle"), 1) },
        low_weapons = {}, supports = {},
        self_modifiers = { EquipmentInstance.new(Catalog.registry:get("self_giant_yinyang_projectile"), 1) },
        support_modifiers = {},
    }
    local giant_shot = WeaponRuntimeManager.new(giant_loadout, Catalog.registry,
        ModifierRuntime.new(giant_loadout, Catalog.registry)):update("HIGH", true,
        { x = 0, y = 0, angle = 90 })[1]
    assert_equal(giant_shot.scale, 1.3, "Unleashed Yin-Yang Orb scales projectile visuals by 1.3")
    assert_equal(giant_shot.hitbox_scale, 1.3, "Unleashed Yin-Yang Orb scales hitbox by 1.3")
    assert_equal(giant_shot.damage, 2.2, "Unleashed Yin-Yang Orb increases damage by 10%")
    assert_true(math.abs(giant_shot.speed - 16.8) < 0.001,
        "Unleashed Yin-Yang Orb slows projectile speed by 30%")

    local capped_giant_loadout = {
        high_weapons = { EquipmentInstance.new(Catalog.registry:get("hakurei_sealing_needle"), 1) },
        low_weapons = {}, supports = {}, self_modifiers = {}, support_modifiers = {},
    }
    for index = 1, 5 do
        capped_giant_loadout.self_modifiers[index] =
            EquipmentInstance.new(Catalog.registry:get("self_giant_yinyang_projectile"), 1)
    end
    local capped_giant_shot = WeaponRuntimeManager.new(capped_giant_loadout, Catalog.registry,
        ModifierRuntime.new(capped_giant_loadout, Catalog.registry)):update("HIGH", true,
        { x = 0, y = 0, angle = 90 })[1]
    assert_equal(capped_giant_shot.scale, 3, "Giant projectile visual scale is capped at three")
    assert_equal(capped_giant_shot.hitbox_scale, 2, "Giant projectile hitbox scale is capped at two")

    local afterglow_loadout = {
        high_weapons = { EquipmentInstance.new(Catalog.registry:get("hakurei_sealing_needle"), 1) },
        low_weapons = {}, supports = {},
        self_modifiers = { EquipmentInstance.new(Catalog.registry:get("self_afterglow"), 1) },
        support_modifiers = {},
    }
    local afterglow_manager = WeaponRuntimeManager.new(afterglow_loadout, Catalog.registry,
        ModifierRuntime.new(afterglow_loadout, Catalog.registry))
    local afterglow_total = 0
    local frame = 0
    while afterglow_manager.weapons[1].fire_count < 10 do
        frame = frame + 1
        afterglow_total = afterglow_total + #afterglow_manager:update("HIGH", true,
            { x = 0, y = 0, angle = 90, frame = frame })
    end
    assert_equal(afterglow_total, 20, "Short-Term Memory keeps the original ten volleys")
    assert_equal(afterglow_manager:invulnerability_frames(), 10,
        "Short-Term Memory grants the player ten invulnerable frames")
    local copied = 0
    for delayed_frame = 1, 10 do
        for _, shot in ipairs(afterglow_manager:update("HIGH", false,
                { x = 0, y = 0, angle = 90, frame = frame + delayed_frame })) do
            if shot.metadata and shot.metadata.afterglow_copy then copied = copied + 1 end
        end
    end
    assert_equal(copied, 2, "Short-Term Memory copies the complete tenth volley")

    local gated_afterglow = WeaponRuntimeManager.new(afterglow_loadout, Catalog.registry,
        ModifierRuntime.new(afterglow_loadout, Catalog.registry))
    local gated_frame = 0
    while gated_afterglow.weapons[1].fire_count < 10 do
        gated_frame = gated_frame + 1
        gated_afterglow:update("HIGH", true, { x = 0, y = 0, angle = 90, frame = gated_frame })
    end
    for _ = 1, 10 do
        gated_frame = gated_frame + 1
        assert_equal(#gated_afterglow:update("HIGH", false,
            { x = 0, y = 0, angle = 90, frame = gated_frame, attack_allowed = false }), 0,
            "Afterglow does not fire while attacks are disabled")
    end
    local gated_copies = 0
    for _ = 1, 10 do
        gated_frame = gated_frame + 1
        for _, shot in ipairs(gated_afterglow:update("HIGH", false,
                { x = 0, y = 0, angle = 90, frame = gated_frame, attack_allowed = true })) do
            if shot.metadata and shot.metadata.afterglow_copy then gated_copies = gated_copies + 1 end
        end
    end
    assert_equal(gated_copies, 2, "Afterglow delay resumes after the attack gate opens")

    local support_target_loadout = {
        high_weapons = {}, low_weapons = {},
        supports = { EquipmentInstance.new(Catalog.registry:get("support_hakurei_yinyang_orb"), 1) },
        self_modifiers = {}, support_modifiers = {
            EquipmentInstance.new(Catalog.registry:get("support_modifier_high_phantom_charge"), 1),
        },
    }
    local target_manager = SupportRuntimeManager.new(support_target_loadout, Catalog.registry,
        ModifierRuntime.new(support_target_loadout, Catalog.registry))
    local target_entities = target_manager:update(0, 0, "HIGH", nil,
        { { id = 99, x = 10, y = 100, hp = 10 }, { id = 100, x = 100, y = 100, hp = 10 } })
    assert_equal(target_entities[1].x, 10, "Phantom Charge moves supports below the nearest front enemy")
    assert_equal(target_entities[1].y, 76, "Phantom Charge offsets supports below the target")
    local numeric_protect_entities = target_manager:update(0, 0, "HIGH", nil,
        { { id = 101, x = 0, y = 80, hp = 10, protect = 0, invulnerable = 0 } })
    assert_true(numeric_protect_entities[1].auto_target_id == 101,
        "a numeric zero protection flag remains a valid support target")

    local spark_loadout = {
        high_weapons = {},
        low_weapons = { EquipmentInstance.new(Catalog.registry:get("marisa_master_spark_weapon"), 1) },
        supports = {}, self_modifiers = {}, support_modifiers = {},
    }
    local spark_manager = WeaponRuntimeManager.new(spark_loadout, Catalog.registry)
    local first_spark = spark_manager:update("LOW", true, { x = 0, y = 0, angle = 90, frame = 1 })[1]
    assert_true(first_spark.metadata.mini_master_spark ~= true,
        "Master Spark does not transform before a beam hit")
    local transformed = false
    local spark_frame = 1
    while not transformed and spark_frame < 600 do
        spark_frame = spark_frame + 1
        local fired = spark_manager:update("LOW", true, { x = 0, y = 0, angle = 90, frame = spark_frame })
        if #fired > 0 then
            local hit_roll = spark_manager:notify_projectile_hit(fired[1].instance_id, spark_frame)
            if hit_roll then
                for _ = 1, 6 do
                    spark_frame = spark_frame + 1
                    spark_manager:update("LOW", false, { x = 0, y = 0, angle = 90, frame = spark_frame })
                end
                local mini = spark_manager:update("LOW", true,
                    { x = 0, y = 0, angle = 90, frame = spark_frame + 1 })[1]
                transformed = mini and mini.metadata and mini.metadata.mini_master_spark == true
            end
        end
    end
    assert_true(transformed, "Master Spark transforms the next beam only after a successful-hit roll")

    local pulse_loadout = {
        high_weapons = {}, low_weapons = {}, supports = {
            EquipmentInstance.new(Catalog.registry:get("support_hakurei_yinyang_orb"), 1),
        }, self_modifiers = {}, support_modifiers = {
            EquipmentInstance.new(Catalog.registry:get("support_modifier_barrier_pulse"), 1),
        },
    }
    local pulse_manager = SupportRuntimeManager.new(pulse_loadout, Catalog.registry,
        ModifierRuntime.new(pulse_loadout, Catalog.registry))
    local pulse_count = 0
    for _ = 1, 240 do
        local entities = pulse_manager:update(0, 0, "HIGH", nil, {})
        if pulse_manager.last_modifier_context and pulse_manager.last_modifier_context.clear_pulses then
            pulse_count = pulse_count + #(pulse_manager.last_modifier_context.clear_pulses)
        end
    end
    assert_equal(pulse_count, 4, "Barrier Pulse staggers one local pulse per support entity per cycle")

    -- Exercise the fallback battle collision path as a playable-runtime
    -- smoke check: penetration reaches a second target and a beam remains
    -- alive long enough to deal its periodic damage.
    local battle_session = GameSession.new({ run_seed = 9917 }):start_new()
    local stage = StageAdapter.new(battle_session)
    stage:start_empty_room("guide_runtime_smoke")
    local runtime_player = stage.runtime.players[1]
    stage:_spawn_enemy("legacy_small_fairy", runtime_player.x, runtime_player.y + 20, { hp = 10, drop = 0 })
    stage:_spawn_enemy("legacy_small_fairy", runtime_player.x, runtime_player.y + 20, { hp = 10, drop = 0 })
    stage:_append_runtime_projectile({ x = runtime_player.x, y = runtime_player.y,
        angle = 90, speed = 24, damage = 3, radius = 4, penetration = 1,
        projectile_type = "reimu_bullet_red", metadata = {} }, runtime_player)
    stage:update({})
    assert_equal(stage.runtime.enemies[1].hp, 7, "penetrating shot damages the first enemy")
    assert_equal(stage.runtime.enemies[2].hp, 7, "penetrating shot reaches the second enemy")
    assert_equal(#stage.runtime.player_bullets, 0, "penetrating shot is removed after its final allowed hit")

    stage.runtime.enemies[1].hp = 10
    stage:_append_runtime_projectile({ x = runtime_player.x, y = runtime_player.y,
        angle = 90, speed = 0, damage = 2, radius = 4, penetration = 0,
        projectile_type = "MarisaLaser", metadata = {
            beam = true, beam_duration_frames = 4, tick_interval = 2,
        } }, runtime_player)
    stage:update({})
    assert_true(#stage.runtime.player_bullets == 1, "beam persists between damage ticks")
    stage:update({})
    assert_equal(stage.runtime.enemies[1].hp, 8, "persistent beam deals periodic damage")

    local control_stage = StageAdapter.new(GameSession.new({ run_seed = 9918 }):start_new())
    control_stage:start_empty_room("guide_control_smoke")
    local start_x = control_stage.runtime.players[1].x
    for _ = 1, 8 do
        control_stage:update({ [1] = { player_id = 1, move_x = 1, move_y = 0, shoot = true } })
    end
    assert_true(control_stage.runtime.players[1].x > start_x, "fallback player movement remains responsive")
    assert_true(control_stage.runtime_shot_calls > 0, "default loadout produces shots during a live update")
end
