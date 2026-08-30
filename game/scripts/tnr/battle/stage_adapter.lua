local BattleManager = require("tnr.battle.battle_manager")
local StageDefinitions = require("tnr.stages.definitions")
local Content = require("tnr.stages.content_catalog")
local PlayerProfiles = require("tnr.player.player_profile")
local BattleTick = require("tnr.core.battle_tick")
local NativeResourcePreflight = require("tnr.stages.native_resource_preflight")
local CharacterRuntimeBridge = require("tnr.character.runtime.character_runtime_bridge")

local StageAdapter = {}
StageAdapter.__index = StageAdapter

local PI2 = math.pi * 2
local WORLD_LEFT, WORLD_RIGHT = 40, 1240
local WORLD_BOTTOM, WORLD_TOP = 40, 680

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function distance_squared(left, right)
    local dx = left.x - right.x
    local dy = left.y - right.y
    return dx * dx + dy * dy
end

local function aim_angle(from_x, from_y, to_x, to_y)
    return math.atan(to_y - from_y, to_x - from_x)
end

local function runtime_frame(runtime)
    return runtime.frame
end

local function numeric_waves(waves)
    if not waves then
        return {}
    end
    if type(waves[1]) == "table" then
        return waves
    end
    local result = {}
    for index, count in ipairs(waves) do
        result[#result + 1] = {
            delay = index == 1 and 0 or 45,
            enemy_id = "legacy_small_fairy",
            count = count,
            formation = "line",
            y = 610,
        }
    end
    return result
end

function StageAdapter.new(session, stage_api, lstg, audio)
    return setmetatable({
        session = session,
        stage_api = stage_api,
        lstg = lstg,
        audio = audio,
        battle = BattleManager.new(session),
        active_encounter = nil,
        runtime = nil,
        native_bridge = rawget(_G, "TNRNativeLegacy"),
        native_active = false,
    }, StageAdapter)
end

function StageAdapter:start(encounter)
    self.active_encounter = encounter
    local runtime_bridge = CharacterRuntimeBridge.new(self.session,
        self.session.local_player_id or 1, self.session.equipment_registry)
    local runtime_ok, runtime_value = pcall(runtime_bridge.create_runtime, runtime_bridge)
    self.character_runtime = runtime_ok and runtime_value or nil
    self.native_preflight = NativeResourcePreflight.run(".", { encounter and encounter.id })
    self.battle:begin(encounter)
    if self.audio then
        self.audio:play_music("stage")
    end
    if self.native_bridge and self.native_bridge.start_room and encounter.type ~= "TRAINING" then
        self.training_mode = false
        self.native_active = true
        local room_type = encounter.type == "BOSS" and "boss" or (encounter.type == "ELITE" and "elite" or "enemy")
        if self.native_bridge.set_room_generation then
            self.native_bridge.set_room_generation(encounter.room_generation)
        end
        if self.native_bridge.set_party_state then
            self.native_bridge.set_party_state(self.session.party)
        end
        if self.native_bridge.set_player_state then
            self.native_bridge.set_player_state(self.session:get_player(self.session.local_player_id or 1))
        end
        self.native_bridge.start_room(room_type, encounter.content_seed or self.session.run_seed or 1)
        if self.native_bridge.set_coop then
            self.native_bridge.set_coop((self.session.player_count or 1) > 1, self.session.local_player_id or 1)
        end
        -- Pass immutable runtime descriptors after the native player/proxy
        -- objects exist.  The bridge applies speed, weapon and support data
        -- locally while each peer still simulates projectiles independently.
        if self.native_bridge.set_loadout_descriptors then
            local local_id = self.session.local_player_id or 1
            local commits = self.session.loadout_commits or {}
            local local_commit = self.character_runtime and self.character_runtime.descriptor
                or commits[local_id] or self.session:build_loadout_commit(local_id)
            local remote_id = local_id == 1 and 2 or 1
            local remote_commit = commits[remote_id]
            self.native_bridge.set_loadout_descriptors(local_commit, remote_commit)
        end
        return true
    end
    if encounter.native_stage and self.stage_api and self.stage_api.Set then
        self.stage_api.Set(encounter.stage_id)
        return true
    end
    local definition = StageDefinitions[encounter.stage_id]
    assert(definition, "unknown stage definition: " .. tostring(encounter.stage_id))
    self.training_mode = false
    self.training_kind = nil
    self.training_card_id = nil
    self.training_target_id = nil
    self.training_display_name = nil
    self.runtime = self:_create_runtime(definition)
    self:_spawn_next_wave()
    return false
end

function StageAdapter:retry_encounter()
    local encounter = self.active_encounter or self.session.current_encounter
    if not encounter then
        return nil, "没有可重试的战斗"
    end
    -- A failed encounter consumes the party's remaining lives.  Retrying is
    -- a fresh attempt at the same node, so restore the normal starting pool
    -- before rebuilding the native or fallback stage.
    for _, player in ipairs(self.session.players:get_players()) do
        player.life = 3
        player.bomb = 3
        player.alive = true
        player.graze = 0
    end
    self.session.run_state = require("tnr.core.constants").run_states.ENCOUNTER
    self:start(encounter)
    return true
end

function StageAdapter:reset_for_new_run()
    if self.native_bridge and self.native_bridge.set_coop then
        self.native_bridge.set_coop(false, self.session.local_player_id or 1)
    end
    self.runtime = nil
    self.native_active = false
    self.active_encounter = nil
    self.training_mode = false
    self.training_kind = nil
    self.training_card_id = nil
    self.training_target_id = nil
    self.training_display_name = nil
    self.training_return_state = nil
    self.battle.active = nil
end

function StageAdapter:is_fallback_active()
    return self.runtime ~= nil
end

function StageAdapter:is_native_active()
    return self.native_active == true and self.native_bridge ~= nil
end

function StageAdapter:start_empty_room(encounter_id)
    local encounter = {
        id = encounter_id or "lan_empty_room",
        type = "EMPTY_ROOM",
        stage_id = "lan_empty_room",
    }
    self.active_encounter = encounter
    self.battle:begin(encounter)
    self.training_mode = false
    self.runtime = self:_create_runtime({ id = encounter.stage_id, kind = "empty", waves = {} })
    self.runtime.phase = "EMPTY_ROOM"
    return self.runtime
end

function StageAdapter:_create_runtime(definition)
    local runtime_players = {}
    local session_players = self.session.players:get_players()
    for index, session_player in ipairs(session_players) do
        local character_id = session_player.character_id or "reimu"
        local player_profile = PlayerProfiles[character_id] or PlayerProfiles.reimu
        local player_id = session_player.player_id
        runtime_players[player_id] = {
            player_id = player_id,
            x = index == 1 and 540 or 740,
            y = 100,
            speed = player_profile.normal_speed,
            focus = false,
            profile = player_profile,
            shoot_cooldown = 0,
            invulnerable = 0,
            bomb_timer = 0,
            bomb_damage_applied = false,
            graze_radius = 30,
        }
    end
    if not runtime_players[1] then
        local player_profile = PlayerProfiles.reimu
        runtime_players[1] = {
            player_id = 1, x = 640, y = 100, speed = player_profile.normal_speed,
            focus = false, profile = player_profile, shoot_cooldown = 0,
            invulnerable = 0, bomb_timer = 0, bomb_damage_applied = false, graze_radius = 30,
        }
    end
    return {
        frame = 0,
        battle_tick = BattleTick.new((self.session.run_seed or 1) + 101),
        pattern_id = nil,
        pattern_seed = nil,
        pattern_phase = nil,
        pattern_target_player_id = nil,
        pattern_start_tick = nil,
        last_world_hash = nil,
        definition = definition,
        phase = "WAVES",
        phase_wait = 0,
        wave_index = 0,
        wave_wait = 0,
        pending_wave = nil,
        enemies = {},
        bullets = {},
        player_bullets = {},
        players = runtime_players,
        player = runtime_players[1],
        kill_requested = false,
        bomb_flash = 0,
        bomb_timer = 0,
        bomb_damage_applied = false,
        current_card = nil,
        current_card_id = nil,
        current_card_index = 0,
        background_layers = {
            definition.background or "tnr-bg-night-road",
            "tnr-bg-night-road-2",
            "tnr-bg-night-road-3",
            "tnr-bg-night-road-4",
        },
        mid_boss_started = false,
        boss_started = false,
    }
end

function StageAdapter:start_training(card_id)
    local card = Content.cards[card_id]
    assert(card, "unknown training card: " .. tostring(card_id))
    if self.native_bridge and not (card.legacy_boss and card.legacy_card_slot) then
        error("card is not backed by an original legacy class: " .. tostring(card_id))
    end
    for _, player in ipairs(self.session.players:get_players()) do
        player.life = 3
        player.bomb = 3
        player.alive = true
        player.graze = 0
    end
    self.training_mode = true
    self.training_kind = "card"
    self.training_return_state = require("tnr.core.constants").run_states.CARD_SELECT
    self.training_card_id = card_id
    self.training_target_id = card_id
    self.training_display_name = card.display_name
    if self.native_bridge and card.legacy_boss and card.legacy_card_slot then
        for _, player in ipairs(self.session.players:get_players()) do
            player.life = 3
            player.bomb = 3
            player.alive = true
            player.graze = 0
        end
        self.training_mode = true
        self.native_active = true
        self.active_encounter = {
            id = "native_training_" .. card_id,
            type = "TRAINING",
            stage_id = "native_training_" .. card_id,
        }
        self.battle:begin(self.active_encounter)
        local ok, err = self.native_bridge.start_card(
            card.legacy_boss, card.legacy_card_slot, false, nil,
            -- Every direct training entry is sourced from boss.card.New.
            -- Require a combat card even for dynamically imported entries;
            -- their generated slot metadata must never be allowed to select
            -- a dialogue or movement stage silently.
            true)
        if not ok then
            self.native_active = false
            error(err)
        end
        if self.native_bridge.set_coop then
            self.native_bridge.set_coop(false, self.session.local_player_id or 1)
        end
        self.session.run_state = require("tnr.core.constants").run_states.CARD_TRAINING
        return
    end
    self.active_encounter = {
        id = "training_" .. card_id,
        type = "TRAINING",
        stage_id = "training_" .. card_id,
    }
    self.battle:begin(self.active_encounter)
    self.runtime = self:_create_runtime({
        id = self.active_encounter.stage_id,
        kind = "boss",
        boss = { id = "training_boss", cards = { card_id } },
    })
    self.runtime.phase = "BOSS"
    self.runtime.boss_started = true
    self:_spawn_card_boss(self.runtime.definition.boss, card_id, 1)
    self.session.run_state = require("tnr.core.constants").run_states.CARD_TRAINING
end

function StageAdapter:start_enemy_training(enemy_id)
    local enemy_spec = (Content.enemy_waves and Content.enemy_waves[enemy_id]) or Content.enemies[enemy_id]
    assert(enemy_spec, "unknown training enemy: " .. tostring(enemy_id))
    for _, player in ipairs(self.session.players:get_players()) do
        player.life = 3
        player.bomb = 3
        player.alive = true
        player.graze = 0
    end
    self.training_mode = true
    self.training_kind = "enemy"
    self.training_return_state = require("tnr.core.constants").run_states.ENEMY_SELECT
    self.training_card_id = nil
    self.training_target_id = enemy_id
    self.training_display_name = enemy_spec.display_name
    if self.native_bridge and self.native_bridge.start_enemy_wave and enemy_spec.legacy_exact then
        self.native_active = true
        self.active_encounter = {
            id = "native_training_enemy_" .. enemy_id,
            type = "TRAINING",
            stage_id = "native_training_enemy_" .. enemy_id,
        }
        self.battle:begin(self.active_encounter)
        local ok, err = self.native_bridge.start_enemy_wave(enemy_id)
        if not ok then
            self.native_active = false
            error(err)
        end
        if self.native_bridge.set_coop then
            self.native_bridge.set_coop(false, self.session.local_player_id or 1)
        end
        self.session.run_state = require("tnr.core.constants").run_states.CARD_TRAINING
        return
    end
    self.active_encounter = {
        id = "training_enemy_" .. enemy_id,
        type = "TRAINING",
        stage_id = "training_enemy_" .. enemy_id,
    }
    self.battle:begin(self.active_encounter)
    self.runtime = self:_create_runtime({
        id = self.active_encounter.stage_id,
        kind = "training",
        waves = {},
    })
    self.runtime.phase = "WAVES"
    -- Headless tests and fallback builds do not have the native legacy object
    -- pool. Keep the real wave metadata in the selector, but use a known
    -- project enemy as the harmless fallback target in that environment.
    local fallback_id = Content.enemies[enemy_id] and enemy_id or "legacy_small_fairy"
    local fallback_spec = Content.enemies[fallback_id]
    self:_spawn_enemy(fallback_id, 640, 590, { hp = (fallback_spec.hp or 35) * 3, drop = 0 })
    self.session.run_state = require("tnr.core.constants").run_states.CARD_TRAINING
end

function StageAdapter:leave_training()
    local return_state = self.training_return_state
    self.runtime = nil
    self.native_active = false
    self.training_mode = false
    self.training_kind = nil
    self.training_card_id = nil
    self.training_target_id = nil
    self.training_display_name = nil
    self.training_return_state = nil
    self.battle.active = nil
    self.session.run_state = return_state or require("tnr.core.constants").run_states.CARD_SELECT
end

function StageAdapter:_spawn_enemy(enemy_id, x, y, overrides)
    local spec = Content.enemies[enemy_id]
    assert(spec, "unknown enemy content: " .. tostring(enemy_id))
    overrides = overrides or {}
    local hp = overrides.hp or spec.hp
    local enemy = {
        id = enemy_id,
        x = x,
        y = y,
        home_x = x,
        home_y = y,
        hp = hp,
        max_hp = hp,
        radius = overrides.radius or spec.radius,
        fire_timer = overrides.fire_interval or spec.fire_interval or 60,
        fire_interval = overrides.fire_interval or spec.fire_interval or 60,
        speed = overrides.speed ~= nil and overrides.speed or spec.speed or spec.bullet_speed or 3,
        bullet_speed = overrides.bullet_speed or spec.bullet_speed or spec.speed or 3,
        pattern = overrides.pattern or spec.pattern or spec.fire_pattern or "aimed",
        drop = overrides.drop or spec.drop or spec.drop_money or 2,
        boss = overrides.boss or false,
        boss_image = overrides.boss_image,
        boss_frames = overrides.boss_frames,
        effect_image = overrides.effect_image,
        phase_label = overrides.phase_label,
        sprite = overrides.sprite or spec.sprite,
        bullet_sprite = overrides.bullet_sprite or spec.bullet_sprite,
        bullet_render_scale = overrides.bullet_render_scale or spec.bullet_render_scale or 0.4,
    }
    self.runtime.enemies[#self.runtime.enemies + 1] = enemy
    return enemy
end

function StageAdapter:_formation_x(index, count, formation)
    if formation == "sides" then
        return index % 2 == 0 and 240 or 1040
    end
    if formation == "pair" then
        return index % 2 == 0 and 520 or 760
    end
    if formation == "center" then
        return 640 + (index - (count + 1) / 2) * 52
    end
    return 160 + index * (960 / (count + 1))
end

function StageAdapter:_spawn_wave(wave)
    local count = wave.count or 1
    local y = wave.y or 650
    for index = 1, count do
        self:_spawn_enemy(wave.enemy_id or wave.enemy or "legacy_small_fairy", self:_formation_x(index, count, wave.formation), y)
    end
end

function StageAdapter:_spawn_next_wave()
    local runtime = self.runtime
    if not runtime or runtime.phase ~= "WAVES" then
        return
    end
    local waves = numeric_waves(runtime.definition.waves)
    runtime.wave_index = runtime.wave_index + 1
    local wave = waves[runtime.wave_index]
    if wave then
        runtime.wave_wait = wave.delay or 0
        if runtime.wave_wait == 0 then
            self:_spawn_wave(wave)
        else
            runtime.pending_wave = wave
        end
    elseif runtime.definition.kind == "ordinary" then
        self:_begin_mid_boss()
    elseif runtime.definition.kind == "boss" then
        self:_begin_boss()
    else
        self:_finish(true, { reward_eligible = true })
    end
end

function StageAdapter:_spawn_card_boss(boss_spec, card_id, card_index)
    local runtime = self.runtime
    local card = Content.cards[card_id]
    assert(card, "unknown card content: " .. tostring(card_id))
    runtime.current_card = card
    runtime.current_card_id = card_id
    runtime.current_card_index = card_index
    runtime.pattern_id = card_id
    local pattern_rng = runtime.battle_tick:get_rng("pattern")
    runtime.pattern_seed = pattern_rng.state
    runtime.pattern_phase = pattern_rng:next_float() * PI2
    runtime.pattern_target_player_id = nil
    runtime.pattern_start_tick = runtime.battle_tick.tick
    runtime.phase_wait = 0
    runtime.background_overlay = card.background_asset
    runtime.card_time_limit = (card.duration or card.duration_seconds or 60) * 60
    runtime.card_time_remaining = runtime.card_time_limit
    runtime.card_time_spell = card.time_spell == true
    if self.audio then self.audio:play("card") end
    self:_spawn_enemy("legacy_butterfly", 640, 590, {
        hp = card.hp,
        radius = 44,
        fire_interval = card.fire_interval or 24,
        pattern = card.pattern,
        speed = 0,
        bullet_speed = card.bullet_speed or 2.8,
        drop = 25,
        boss = true,
        phase_label = card.display_name,
        boss_image = boss_spec.id == "sanae_mid" and "tnr-sanae-boss" or "tnr-reimu-boss",
        boss_frames = card.boss_frames,
        effect_image = card.effect_asset,
        sprite = boss_spec.sprite,
        bullet_sprite = card.bullet_sprite,
        bullet_render_scale = card.bullet_render_scale,
    })
end

function StageAdapter:_begin_mid_boss()
    local runtime = self.runtime
    if runtime.mid_boss_started then
        return
    end
    runtime.mid_boss_started = true
    runtime.phase = "MID_BOSS"
    runtime.phase_wait = 0
    local boss = runtime.definition.mid_boss
    if not boss or not boss.cards or #boss.cards == 0 then
        self:_finish(true, { reward_eligible = true })
        return
    end
    self:_spawn_card_boss(boss, boss.cards[1], 1)
end

function StageAdapter:_begin_boss()
    local runtime = self.runtime
    if runtime.boss_started then
        return
    end
    runtime.boss_started = true
    runtime.phase = "BOSS"
    runtime.phase_wait = 0
    local boss = runtime.definition.boss
    if not boss or not boss.cards or #boss.cards == 0 then
        self:_finish(true, { reward_eligible = true })
        return
    end
    self:_spawn_card_boss(boss, boss.cards[1], 1)
end

function StageAdapter:_emit_bullet(x, y, angle, speed, radius, pattern, curve)
    self.runtime.bullets[#self.runtime.bullets + 1] = {
        x = x, y = y, vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
        radius = radius or 5, pattern = pattern, curve = curve, grazed_by = {},
    }
end

function StageAdapter:get_alive_players()
    local result = {}
    for player_id, runtime_player in pairs(self.runtime and self.runtime.players or {}) do
        local player = self.session:get_player(player_id)
        if player and player.alive and player.life > 0 then
            result[#result + 1] = runtime_player
        end
    end
    table.sort(result, function(left, right) return left.player_id < right.player_id end)
    return result
end

function StageAdapter:get_player_by_id(player_id)
    return self.runtime and self.runtime.players and self.runtime.players[player_id] or nil
end

function StageAdapter:get_nearest_player(x, y)
    local nearest
    local nearest_distance
    for _, player in ipairs(self:get_alive_players()) do
        local distance = (player.x - x) ^ 2 + (player.y - y) ^ 2
        if not nearest_distance or distance < nearest_distance then
            nearest = player
            nearest_distance = distance
        end
    end
    return nearest
end

function StageAdapter:get_random_alive_player()
    local players = self:get_alive_players()
    if #players == 0 then
        return nil
    end
    if #players == 1 then
        return players[1]
    end
    local index = self.runtime.battle_tick:get_rng("boss"):next_int(1, #players)
    return players[index]
end

function StageAdapter:_spawn_player_shots(player)
    local runtime = self.runtime
    local shots = player.focus and player.profile.focused_shot or player.profile.normal_shot
    for _, shot in ipairs(shots) do
        local angle = math.rad(shot.angle or 90)
        runtime.player_bullets[#runtime.player_bullets + 1] = {
            x = player.x + (shot.offset_x or 0),
            y = player.y + (shot.offset_y or 0),
            vx = math.cos(angle) * (shot.speed or 24),
            vy = math.sin(angle) * (shot.speed or 24),
            speed = shot.speed or 24,
            damage = shot.damage or 1,
            radius = shot.radius or 4,
            focused = player.focus,
            owner_id = player.player_id,
        }
    end
end

function StageAdapter:_emit_pattern(enemy)
    local player
    if enemy.boss then
        player = self:get_random_alive_player()
    else
        player = self:get_nearest_player(enemy.x, enemy.y)
    end
    player = player or self.runtime.player
    if enemy.boss then
        self.runtime.pattern_target_player_id = player and player.player_id or nil
    end
    local base = aim_angle(enemy.x, enemy.y, player.x, player.y)
    local pattern = enemy.pattern or "aimed"
    local pattern_phase = self.runtime.pattern_phase or 0
    local function emit(angle, speed, radius, curve)
        self:_emit_bullet(enemy.x, enemy.y, angle, speed, radius, pattern, curve)
        self.runtime.bullets[#self.runtime.bullets].sprite = enemy.bullet_sprite or "tnr-thlib-bullet-gun"
        self.runtime.bullets[#self.runtime.bullets].render_scale = enemy.bullet_render_scale or 0.4
    end
    if pattern == "fan" or pattern == "aimed_fan" then
        local count = pattern == "aimed_fan" and 5 or 7
        local spread = pattern == "aimed_fan" and 0.12 or 0.2
        for offset = -(count - 1) / 2, (count - 1) / 2 do
            emit(base + offset * spread, enemy.bullet_speed, pattern == "aimed_fan" and 5 or 6)
        end
    elseif pattern == "ritual" then
        -- Two staggered rings: the alternating speeds make safe lanes move
        -- instead of producing the same static radial burst every card.
        for index = 0, 7 do
            local angle = pattern_phase + runtime_frame(self.runtime) * 0.018 + index * PI2 / 8
            local speed = enemy.bullet_speed * (index % 2 == 0 and 0.72 or 1.25)
            emit(angle, speed, 5)
        end
    elseif pattern == "seal" then
        -- A square seal: four slow anchors and four faster diagonals create
        -- a rotating cage rather than a radial ring.
        local rotation = pattern_phase + runtime_frame(self.runtime) * 0.025
        for index = 0, 3 do
            emit(rotation + index * math.pi / 2, enemy.bullet_speed * 0.75, 6)
            emit(rotation + math.pi / 4 + index * math.pi / 2, enemy.bullet_speed * 1.25, 4)
        end
    elseif pattern == "spiral" then
        -- Two counter-rotating arms with a phase offset.
        local rotation = pattern_phase + runtime_frame(self.runtime) * 0.055
        for arm = 0, 1 do
            for index = 0, 4 do
                local angle = rotation + arm * math.pi + index * 0.24
                emit(angle, enemy.bullet_speed + index * 0.18, 5)
            end
        end
    elseif pattern == "wind" then
        local swing = math.sin(self.runtime.frame * 0.045) * 0.55
        for offset = -3, 3 do
            local curve = offset == 0 and 0 or (offset > 0 and 0.004 or -0.004)
            emit(base + swing + offset * 0.11, enemy.bullet_speed, 5, curve)
        end
    elseif pattern == "cross" then
        for index = 0, 3 do
            emit(pattern_phase + index * math.pi / 2 + self.runtime.frame * 0.015, enemy.bullet_speed, 7)
        end
        if self.runtime.frame % 2 == 0 then
            for index = 0, 3 do
                emit(pattern_phase + math.pi / 4 + index * math.pi / 2, enemy.bullet_speed * 0.7, 4)
            end
        end
    elseif pattern == "laser" then
        local sweep = math.sin(runtime_frame(self.runtime) * 0.018) * 0.7
        for index = -2, 2 do
            emit(base + sweep + index * 0.035, enemy.bullet_speed * 1.15, 9, index * 0.0015)
        end
    elseif pattern == "radial" then
        -- A dense rotating ring with a slowly changing gap.
        local rotation = pattern_phase + runtime_frame(self.runtime) * 0.02
        local count = 16
        local gap = math.floor(runtime_frame(self.runtime) / 36) % count
        for index = 0, count - 1 do
            if index ~= gap and index ~= (gap + 1) % count then
                emit(rotation + index * PI2 / count, enemy.bullet_speed * 0.82, 5)
            end
        end
    elseif pattern == "orbit" then
        -- Three orbiting arms produce the long-lived wheel used by several
        -- legacy cards, with alternating speeds on each arm.
        local rotation = pattern_phase + runtime_frame(self.runtime) * 0.045
        for arm = 0, 2 do
            for index = 0, 2 do
                local angle = rotation + arm * PI2 / 3 + index * 0.16
                emit(angle, enemy.bullet_speed * (0.75 + index * 0.22), 5)
            end
        end
    elseif pattern == "curtain" then
        -- A sweeping curtain changes direction every few beats instead of
        -- repeatedly aiming at the same player position.
        local sweep = math.sin(runtime_frame(self.runtime) * 0.035) * 0.9
        for index = -5, 5 do
            local angle = math.pi * 1.5 + sweep + index * 0.085
            emit(angle, enemy.bullet_speed * (0.9 + (index + 5) % 3 * 0.12), 4)
        end
    elseif pattern == "rain" then
        local drift = math.sin(runtime_frame(self.runtime) * 0.025) * 0.5
        for index = 0, 7 do
            emit(base + drift + (index - 3.5) * 0.18, enemy.bullet_speed * (0.7 + index * 0.1), 4)
        end
    elseif pattern == "burst" then
        local phase = runtime_frame(self.runtime) % 90
        if phase < 18 then
            for index = 0, 11 do
                emit(pattern_phase + index * PI2 / 12, enemy.bullet_speed * (1.2 + phase * 0.015), 6)
            end
        end
    elseif pattern == "vortex" then
        local rotation = pattern_phase + runtime_frame(self.runtime) * 0.04
        for arm = 0, 1 do
            for index = 0, 5 do
                local angle = rotation + arm * math.pi + index * 0.18
                emit(angle, enemy.bullet_speed * (0.65 + index * 0.16), 5, arm == 0 and 0.004 or -0.004)
            end
        end
    elseif pattern == "windmill" then
        local rotation = pattern_phase - runtime_frame(self.runtime) * 0.035
        for spoke = 0, 3 do
            for index = 0, 2 do
                emit(rotation + spoke * math.pi / 2 + index * 0.08, enemy.bullet_speed * (0.8 + index * 0.25), 5)
            end
        end
    elseif pattern == "light_seal" then
        local rotation = pattern_phase + runtime_frame(self.runtime) * 0.018
        for index = 0, 7 do
            emit(rotation + index * PI2 / 8, enemy.bullet_speed * (index % 2 == 0 and 0.7 or 1.15), 6)
        end
    elseif pattern == "barrier" then
        local rotation = pattern_phase + math.sin(runtime_frame(self.runtime) * 0.02) * 0.45
        for index = -4, 4 do
            emit(rotation + index * 0.13, enemy.bullet_speed * 0.9, 6)
            emit(rotation + math.pi + index * 0.13, enemy.bullet_speed * 0.65, 4)
        end
    elseif pattern == "starburst" then
        local rotation = pattern_phase + runtime_frame(self.runtime) * 0.025
        for index = 0, 7 do
            emit(rotation + index * PI2 / 8, enemy.bullet_speed * 1.3, 7)
            emit(rotation + math.pi / 8 + index * PI2 / 8, enemy.bullet_speed * 0.55, 4)
        end
    elseif pattern == "formation" then
        -- Four timed lanes reproduce the reference card's orthogonal seal:
        -- each lane starts offset from the boss and slowly contracts.
        local rotation = pattern_phase + math.floor(runtime_frame(self.runtime) / 120) * 0.04
        local contraction = math.max(0.55, 1 - (runtime_frame(self.runtime) % 120) / 420)
        for side = 0, 3 do
            local angle = rotation + side * math.pi / 2
            for index = -4, 4 do
                emit(angle + index * 0.035, enemy.bullet_speed * contraction, 6)
            end
        end
    else
        emit(base, enemy.bullet_speed, enemy.boss and 7 or 5)
    end
end

function StageAdapter:_advance_after_phase()
    local runtime = self.runtime
    local boss_spec = runtime.phase == "MID_BOSS" and runtime.definition.mid_boss or runtime.definition.boss
    if boss_spec and runtime.current_card_index < #boss_spec.cards then
        local next_index = runtime.current_card_index + 1
        self:_spawn_card_boss(boss_spec, boss_spec.cards[next_index], next_index)
        return
    end
    if runtime.phase == "MID_BOSS" and not runtime.definition.clear_after_mid_boss then
        runtime.phase = "WAVES"
        runtime.phase_wait = 0
        runtime.wave_wait = 45
        return
    end
    self:_finish(true, { reward_eligible = true })
end

function StageAdapter:_finish(clear_state, options)
    if not self.runtime then
        return
    end
    if self.training_mode then
        self.runtime = nil
        self.training_result = { clear_state = clear_state == true, kind = self.training_kind, target_id = self.training_target_id }
        self.battle.active = nil
        if clear_state then
            self.session.run_state = self.training_return_state or require("tnr.core.constants").run_states.CARD_SELECT
        else
            self.session.run_state = require("tnr.core.constants").run_states.CARD_TRAINING_FAILED
        end
        return
    end
    self.runtime = nil
    self:complete(clear_state, options)
end

function StageAdapter:update(input)
    if self.native_active and self.native_bridge then
        local values = input or {}
        local by_player = {}
        local has_player_map = false
        -- Accept both the project map form (`[id] = input`) and a single
        -- PlayerInput object received directly from older callers. Always use
        -- the embedded player_id when it is available; positional fallbacks
        -- could let a P1 packet drive the P2 local player.
        for key, candidate in pairs(values) do
            if type(candidate) == "table" and candidate.player_id ~= nil then
                local player_id = tonumber(candidate.player_id)
                if player_id then
                    by_player[player_id] = candidate
                    has_player_map = true
                end
            elseif key == "player_id" then
                local player_id = tonumber(values.player_id)
                if player_id then
                    by_player[player_id] = values
                    has_player_map = true
                end
            end
        end
        local local_id = self.session.local_player_id or 1
        if has_player_map then
            local local_input = by_player[local_id] or { player_id = local_id }
            self.native_bridge.update(local_input)
            if self.native_bridge.update_remote then
                local remote_id = local_id == 1 and 2 or 1
                self.native_bridge.update_remote(by_player[remote_id] or { player_id = remote_id })
            end
        else
            self.native_bridge.update(values)
        end
        local state = self.native_bridge.state and self.native_bridge.state() or {}
        -- Pull only the native lifecycle fields into the formal model. Score,
        -- graze and bombs are updated as owner-local deltas elsewhere.
        local adapter = self.session.legacy_state_adapter
        if adapter then
            if state.team_lives ~= nil and self.session.party then
                adapter:set_team_life(state.team_lives)
            end
            local local_id = self.session.local_player_id or 1
            local local_snapshot = state.player and {
                alive = (tonumber(state.player.death) or 0) <= 0 and state.player.hide ~= true,
                respawning = (state.respawn_frames and (state.respawn_frames[local_id] or 0) or 0) > 0,
                respawn_timer = state.respawn_frames and state.respawn_frames[local_id] or 0,
            }
            if local_snapshot and self.session:get_player(local_id) then
                adapter:apply_player_snapshot(local_id, local_snapshot)
            end
            if state.remote_player and self.session.player_count > 1 then
                local remote_id = local_id == 1 and 2 or 1
                adapter:apply_player_snapshot(remote_id, {
                    alive = state.remote_player.hidden ~= true,
                    respawning = state.respawn_frames and (state.respawn_frames[remote_id] or 0) > 0,
                    respawn_timer = state.respawn_frames and state.respawn_frames[remote_id] or 0,
                })
            end
        end
        -- Native co-op owns death timing: an individual player is hidden for
        -- ten seconds and returns while the other player continues. Only the
        -- shared team wipe is allowed to end the encounter. Single-player
        -- rooms retain THlib's original death/life behavior.
        if state.coop_enabled and state.team_defeated then
            self.native_active = false
            if self.training_mode then
                self.battle.active = nil
                self.training_result = { clear_state = false, kind = self.training_kind, target_id = self.training_target_id }
                self.session.run_state = require("tnr.core.constants").run_states.CARD_TRAINING_FAILED
            else
                self:complete(false, { reward_eligible = false })
            end
        elseif not state.coop_enabled and state.player_dead and state.player and state.player.death > 90 then
            self.native_active = false
            if self.training_mode then
                self.battle.active = nil
                self.training_result = { clear_state = false, kind = self.training_kind, target_id = self.training_target_id }
                self.session.run_state = require("tnr.core.constants").run_states.CARD_TRAINING_FAILED
            else
                self:complete(false, { reward_eligible = false })
            end
        elseif self.training_mode and self.training_kind == "enemy"
                and state.enemy_training_active and not state.enemy_spawned then
            -- Wait for the native stage boundary to finish constructing the
            -- selected wave before interpreting an empty object list as a
            -- completed practice target.
            return
        elseif self.training_mode and self.training_kind == "enemy"
                and state.enemy_training_active and state.enemy_training_error then
            -- A native wave must never be replaced by a synthetic enemy. Keep
            -- the failure in the normal training flow so the player can retry
            -- or return to the wave selector with a visible result screen.
            self.native_active = false
            self.battle.active = nil
            self.training_result = {
                clear_state = false,
                kind = self.training_kind,
                target_id = self.training_target_id,
                error = state.enemy_training_error,
            }
            self.session.run_state = require("tnr.core.constants").run_states.CARD_TRAINING_FAILED
        elseif self.training_mode and self.training_kind == "enemy"
                and state.enemy_training_active and state.enemy_count == 0
                and state.enemy_training_seen_alive then
            self.native_active = false
            self.battle.active = nil
            self.training_result = { clear_state = true, kind = self.training_kind, target_id = self.training_target_id }
            self.session.run_state = self.training_return_state or require("tnr.core.constants").run_states.ENEMY_SELECT
        elseif state.enemy_boss_error then
            -- A roguelike enemy room must not silently clear when its
            -- original nonspell failed to instantiate. Keep the failure in
            -- the normal retry/menu flow with the native error visible.
            self.native_active = false
            self.battle.active = nil
            self:complete(false, { reward_eligible = false, error = state.enemy_boss_error })
        elseif (state.frame_count or 0) > 3 and not state.boss_alive
                and (state.room_type ~= "enemy"
                    or (state.enemy_spawned and state.enemy_boss_started)) then
            self.native_active = false
            if self.training_mode then
                self.battle.active = nil
                self.training_result = { clear_state = true, kind = self.training_kind, target_id = self.training_target_id }
                self.session.run_state = self.training_return_state or require("tnr.core.constants").run_states.CARD_SELECT
            else
                self:complete(true, { reward_eligible = true })
            end
        end
        return
    end
    local runtime = self.runtime
    if not runtime then
        return
    end
    runtime.frame = runtime.frame + 1
    runtime.battle_tick:advance()
    local inputs = input or {}
    if inputs.player_id then
        inputs = { [inputs.player_id] = inputs }
    elseif inputs.move_x ~= nil then
        inputs = { [1] = inputs }
    end

    local max_bomb_flash = 0
    for player_id, player in pairs(runtime.players) do
        local input_state = inputs[player_id] or {}
        local session_player = self.session:get_player(player_id)
        if session_player and session_player.alive then
            player.focus = input_state.focus == true
            player.speed = player.focus and player.profile.focused_speed or player.profile.normal_speed
            local move_x = input_state.move_x or 0
            local move_y = input_state.move_y or 0
            local move_scale = move_x ~= 0 and move_y ~= 0 and 0.70710678 or 1
            player.x = clamp(player.x + move_x * player.speed * move_scale, WORLD_LEFT, WORLD_RIGHT)
            player.y = clamp(player.y + move_y * player.speed * move_scale, WORLD_BOTTOM, WORLD_TOP)
            player.invulnerable = math.max(0, player.invulnerable - 1)

            if input_state.bomb and session_player.bomb > 0 and player.bomb_timer <= 0 then
                self.battle:use_bomb(player_id)
                if self.audio then self.audio:play("bomb") end
                player.bomb_timer = player.profile.bomb.duration
                player.bomb_damage_applied = false
                player.invulnerable = player.profile.bomb.invulnerability
                runtime.bullets = {}
            end
            if player.bomb_timer > 0 then
                player.bomb_timer = player.bomb_timer - 1
                max_bomb_flash = math.max(max_bomb_flash, player.bomb_timer)
                runtime.bullets = {}
                if not player.bomb_damage_applied then
                    for _, enemy in ipairs(runtime.enemies) do
                        enemy.hp = enemy.hp - player.profile.bomb.damage
                        enemy.last_hit_player_id = player_id
                    end
                    player.bomb_damage_applied = true
                end
            else
                player.bomb_damage_applied = false
            end

            if input_state.shoot and player.shoot_cooldown <= 0 then
                self:_spawn_player_shots(player)
                if self.audio then self.audio:play("shot") end
                player.shoot_cooldown = player.profile.shot_interval
            end
            player.shoot_cooldown = math.max(0, player.shoot_cooldown - 1)
        end
    end
    runtime.bomb_flash = max_bomb_flash

    if runtime.kill_requested then
        for _, enemy in ipairs(runtime.enemies) do
            enemy.hp = 0
        end
        runtime.kill_requested = false
    end

    if runtime.pending_wave and runtime.wave_wait > 0 then
        runtime.wave_wait = runtime.wave_wait - 1
        if runtime.wave_wait <= 0 then
            local pending = runtime.pending_wave
            runtime.pending_wave = nil
            self:_spawn_wave(pending)
        end
    end

    for index = #runtime.player_bullets, 1, -1 do
        local bullet = runtime.player_bullets[index]
        bullet.x = bullet.x + bullet.vx
        bullet.y = bullet.y + bullet.vy
        local hit = false
        for _, enemy in ipairs(runtime.enemies) do
            if enemy.hp > 0 and distance_squared(bullet, enemy) <= (enemy.radius + bullet.radius) ^ 2 then
                enemy.hp = enemy.hp - bullet.damage
                enemy.last_hit_player_id = bullet.owner_id or 1
                self.battle:add_score(100, bullet.owner_id or 1, "shot")
                hit = true
                break
            end
        end
        if hit or bullet.y > 740 or bullet.x < -30 or bullet.x > 1310 then
            table.remove(runtime.player_bullets, index)
        end
    end

    for _, enemy in ipairs(runtime.enemies) do
        if enemy.hp > 0 then
            if enemy.boss then
                enemy.x = 640 + math.sin(runtime.frame * 0.012) * 250
                enemy.y = 560 + math.sin(runtime.frame * 0.021) * 35
                runtime.phase_wait = runtime.phase_wait + 1
                local duration = (runtime.current_card and (runtime.current_card.duration or runtime.current_card.duration_seconds) or 60) * 60
                runtime.card_time_remaining = math.max(0, (runtime.card_time_limit or duration) - runtime.phase_wait)
                if runtime.card_time_spell and runtime.card_time_remaining <= 0 then
                    enemy.hp = 0
                end
            else
                enemy.y = enemy.home_y - math.min(runtime.frame, 120) * 0.35
                enemy.x = enemy.home_x + math.sin((runtime.frame + enemy.home_x) * 0.02) * 18
            end
            enemy.fire_timer = enemy.fire_timer - 1
            if enemy.fire_timer <= 0 then
                self:_emit_pattern(enemy)
                enemy.fire_timer = enemy.fire_interval
            end
        end
    end

    for index = #runtime.bullets, 1, -1 do
        local bullet = runtime.bullets[index]
        if bullet.curve and bullet.curve ~= 0 then
            local angle = math.atan(bullet.vy, bullet.vx) + bullet.curve
            local speed = math.sqrt(bullet.vx * bullet.vx + bullet.vy * bullet.vy)
            bullet.vx = math.cos(angle) * speed
            bullet.vy = math.sin(angle) * speed
        end
        bullet.x = bullet.x + bullet.vx
        bullet.y = bullet.y + bullet.vy
        local consumed = false
        for player_id, player in pairs(runtime.players) do
            local session_player = self.session:get_player(player_id)
            if session_player and session_player.alive then
                local collision_distance = (bullet.radius + player.profile.hitbox_radius + 2) ^ 2
                local graze_distance = (bullet.radius + player.graze_radius) ^ 2
                local distance = distance_squared(bullet, player)
                if distance <= collision_distance and player.invulnerable == 0 then
                    player.invulnerable = 90
                    self.battle:record_player_life_lost(player_id, 1)
                    self.session:add_life(player_id, -1, "hit")
                    if self.audio then self.audio:play("hit") end
                    consumed = true
                    break
                elseif distance <= graze_distance and distance > collision_distance and not bullet.grazed_by[player_id] then
                    bullet.grazed_by[player_id] = true
                    self.battle:record_graze(player_id, 1)
                    self.battle:add_score(10, player_id, "graze")
                end
            end
        end
        if consumed or bullet.x < -30 or bullet.x > 1310 or bullet.y < -30 or bullet.y > 750 then
            table.remove(runtime.bullets, index)
        end
    end

    for _, enemy in ipairs(runtime.enemies) do
        if enemy.hp > 0 and not enemy.boss then
            for player_id, player in pairs(runtime.players) do
                local session_player = self.session:get_player(player_id)
                if session_player and session_player.alive and player.invulnerable == 0 and distance_squared(enemy, player) <= (enemy.radius + player.profile.hitbox_radius) ^ 2 then
                    player.invulnerable = 90
                    self.battle:record_player_life_lost(player_id, 1)
                    self.session:add_life(player_id, -1, "enemy_contact")
                    if self.audio then self.audio:play("hit") end
                end
            end
        end
    end

    local alive_players = self:get_alive_players()
    if #alive_players == 0 then
        self:_finish(false, { reward_eligible = false })
        return
    end

    for index = #runtime.enemies, 1, -1 do
        if runtime.enemies[index].hp <= 0 then
            local defeated = runtime.enemies[index]
            self.battle:collect_money(defeated.drop or 2, defeated.last_hit_player_id or 1, "enemy_drop")
            table.remove(runtime.enemies, index)
        end
    end

    if #runtime.enemies == 0 and not runtime.pending_wave then
        if runtime.phase == "WAVES" then
            local waves = numeric_waves(runtime.definition.waves)
            if runtime.wave_index < #waves then
                runtime.wave_wait = runtime.wave_wait + 1
                if runtime.wave_wait >= 45 then
                    runtime.wave_wait = 0
                    self:_spawn_next_wave()
                end
            elseif runtime.definition.kind == "ordinary" then
                self:_begin_mid_boss()
            elseif runtime.definition.kind == "boss" then
                self:_begin_boss()
            else
                self:_finish(true, { reward_eligible = true })
            end
        elseif runtime.phase == "MID_BOSS" or runtime.phase == "BOSS" then
            runtime.phase_wait = runtime.phase_wait + 1
            if runtime.phase_wait >= 30 then
                self:_advance_after_phase()
            end
        end
    end
    runtime.last_world_hash = self:world_hash()
end

function StageAdapter:get_world_snapshot()
    local runtime = self.runtime
    if not runtime then
        return nil
    end
    local players = {}
    for player_id, player in pairs(runtime.players) do
        local state = self.session:get_player(player_id)
        players[#players + 1] = {
            id = player_id, x = player.x, y = player.y, invulnerable = player.invulnerable,
            focus = player.focus, shoot_cooldown = player.shoot_cooldown,
            bomb_timer = player.bomb_timer, bomb_damage_applied = player.bomb_damage_applied,
            life = state and state.life or 0, alive = state and state.alive or false,
            bomb = state and state.bomb or 0, score = state and state.score or 0,
            graze = state and state.graze or 0, money = state and state.money or 0,
        }
    end
    table.sort(players, function(left, right) return left.id < right.id end)
    local enemies = {}
    for _, enemy in ipairs(runtime.enemies) do
        enemies[#enemies + 1] = {
            id = enemy.id, x = enemy.x, y = enemy.y, home_x = enemy.home_x, home_y = enemy.home_y,
            hp = enemy.hp, max_hp = enemy.max_hp, radius = enemy.radius,
            fire_timer = enemy.fire_timer, fire_interval = enemy.fire_interval,
            speed = enemy.speed, bullet_speed = enemy.bullet_speed, pattern = enemy.pattern,
            drop = enemy.drop, boss = enemy.boss, boss_image = enemy.boss_image,
            boss_frames = enemy.boss_frames, effect_image = enemy.effect_image,
            sprite = enemy.sprite, bullet_sprite = enemy.bullet_sprite,
            bullet_render_scale = enemy.bullet_render_scale,
            phase_label = enemy.phase_label, last_hit_player_id = enemy.last_hit_player_id,
        }
    end
    local bullets = {}
    for _, bullet in ipairs(runtime.bullets) do
        bullets[#bullets + 1] = {
            x = bullet.x, y = bullet.y, vx = bullet.vx, vy = bullet.vy,
            radius = bullet.radius, pattern = bullet.pattern, curve = bullet.curve,
            sprite = bullet.sprite,
            render_scale = bullet.render_scale,
            grazed_by = bullet.grazed_by,
        }
    end
    local player_bullets = {}
    for _, bullet in ipairs(runtime.player_bullets) do
        player_bullets[#player_bullets + 1] = {
            x = bullet.x, y = bullet.y, vx = bullet.vx, vy = bullet.vy,
            speed = bullet.speed, damage = bullet.damage, radius = bullet.radius,
            focused = bullet.focused, owner_id = bullet.owner_id,
        }
    end
    return {
        tick = runtime.battle_tick.tick,
        phase = runtime.phase,
        phase_wait = runtime.phase_wait,
        wave_index = runtime.wave_index,
        wave_wait = runtime.wave_wait,
        pending_wave = runtime.pending_wave,
        mid_boss_started = runtime.mid_boss_started,
        boss_started = runtime.boss_started,
        current_card_id = runtime.current_card_id,
        current_card_index = runtime.current_card_index,
        pattern_id = runtime.pattern_id,
        pattern_seed = runtime.pattern_seed,
        pattern_phase = runtime.pattern_phase,
        pattern_target_player_id = runtime.pattern_target_player_id,
        pattern_start_tick = runtime.pattern_start_tick,
        card_time_limit = runtime.card_time_limit,
        card_time_remaining = runtime.card_time_remaining,
        card_time_spell = runtime.card_time_spell,
        players = players,
        enemies = enemies,
        bullets = bullets,
        player_bullets = player_bullets,
        session_money = self.session.money,
        total_score = self.session.total_score,
        battle = self.battle.active and {
            encounter_id = self.battle.active.encounter_id,
            battle_score = self.battle.active.battle_score,
            money_collected = self.battle.active.money_collected,
            life_lost = self.battle.active.life_lost,
            bomb_used = self.battle.active.bomb_used,
            per_player = self.battle.active.per_player,
        } or nil,
        rng = runtime.battle_tick:snapshot(),
    }
end

function StageAdapter:make_network_snapshot()
    local snapshot = self:get_world_snapshot()
    if snapshot then
        snapshot.battle_score = self.battle.active and self.battle.active.battle_score or 0
        snapshot.money_collected = self.battle.active and self.battle.active.money_collected or 0
    end
    return snapshot
end

function StageAdapter:apply_snapshot(snapshot)
    local runtime = self.runtime
    if not runtime or not snapshot then
        return false
    end
    if snapshot.rng then
        runtime.battle_tick:restore(snapshot.rng)
    else
        runtime.battle_tick.tick = snapshot.tick or runtime.battle_tick.tick
    end
    runtime.frame = snapshot.tick or runtime.frame
    runtime.phase = snapshot.phase or runtime.phase
    runtime.phase_wait = snapshot.phase_wait or runtime.phase_wait
    runtime.wave_index = snapshot.wave_index or runtime.wave_index
    runtime.wave_wait = snapshot.wave_wait or 0
    runtime.pending_wave = snapshot.pending_wave
    runtime.mid_boss_started = snapshot.mid_boss_started == true
    runtime.boss_started = snapshot.boss_started == true
    runtime.current_card_id = snapshot.current_card_id
    runtime.current_card_index = snapshot.current_card_index or 0
    runtime.current_card = snapshot.current_card_id and Content.cards[snapshot.current_card_id] or nil
    runtime.pattern_id = snapshot.pattern_id
    runtime.pattern_seed = snapshot.pattern_seed
    runtime.pattern_phase = snapshot.pattern_phase
    runtime.pattern_target_player_id = snapshot.pattern_target_player_id
    runtime.pattern_start_tick = snapshot.pattern_start_tick
    runtime.card_time_limit = snapshot.card_time_limit
    runtime.card_time_remaining = snapshot.card_time_remaining
    -- Preserve nil for encounters without a spell card; converting it to
    -- false changes the serialized world shape and creates a false desync.
    runtime.card_time_spell = snapshot.card_time_spell
    self.session.money = snapshot.session_money or self.session.money
    self.session.total_score = snapshot.total_score or self.session.total_score
    if snapshot.battle and self.battle.active then
        self.battle.active.encounter_id = snapshot.battle.encounter_id or self.battle.active.encounter_id
        self.battle.active.battle_score = snapshot.battle.battle_score or 0
        self.battle.active.money_collected = snapshot.battle.money_collected or 0
        self.battle.active.life_lost = snapshot.battle.life_lost or 0
        self.battle.active.bomb_used = snapshot.battle.bomb_used or 0
        self.battle.active.per_player = snapshot.battle.per_player or {}
    end
    for _, player_snapshot in ipairs(snapshot.players or {}) do
        local player = runtime.players[player_snapshot.id]
        local state = self.session:get_player(player_snapshot.id)
        if player then
            player.x = player_snapshot.x
            player.y = player_snapshot.y
            player.invulnerable = player_snapshot.invulnerable or 0
            player.focus = player_snapshot.focus == true
            player.speed = player.focus and player.profile.focused_speed or player.profile.normal_speed
            player.shoot_cooldown = player_snapshot.shoot_cooldown or 0
            player.bomb_timer = player_snapshot.bomb_timer or 0
            player.bomb_damage_applied = player_snapshot.bomb_damage_applied == true
        end
        if state then
            state.life = player_snapshot.life or state.life
            state.alive = player_snapshot.alive ~= false and state.life > 0
            state.bomb = player_snapshot.bomb or state.bomb
            state.score = player_snapshot.score or state.score
            state.graze = player_snapshot.graze or state.graze
            state.money = player_snapshot.money or state.money
        end
    end
    runtime.enemies = {}
    for _, enemy_snapshot in ipairs(snapshot.enemies or {}) do
        runtime.enemies[#runtime.enemies + 1] = {
            id = enemy_snapshot.id, x = enemy_snapshot.x, y = enemy_snapshot.y,
            home_x = enemy_snapshot.home_x or enemy_snapshot.x, home_y = enemy_snapshot.home_y or enemy_snapshot.y,
            hp = enemy_snapshot.hp, max_hp = enemy_snapshot.max_hp or enemy_snapshot.hp,
            radius = enemy_snapshot.radius or (enemy_snapshot.boss and 44 or 18),
            fire_timer = enemy_snapshot.fire_timer or 1, fire_interval = enemy_snapshot.fire_interval or 60,
            speed = enemy_snapshot.speed or 0, bullet_speed = enemy_snapshot.bullet_speed or 3,
            pattern = enemy_snapshot.pattern, drop = enemy_snapshot.drop or 0,
            boss = enemy_snapshot.boss == true,
            boss_image = enemy_snapshot.boss_image or (enemy_snapshot.boss and "tnr-reimu-boss" or nil),
            boss_frames = enemy_snapshot.boss_frames,
            effect_image = enemy_snapshot.effect_image,
            phase_label = enemy_snapshot.phase_label,
            sprite = enemy_snapshot.sprite,
            bullet_sprite = enemy_snapshot.bullet_sprite,
            bullet_render_scale = enemy_snapshot.bullet_render_scale or 0.4,
            last_hit_player_id = enemy_snapshot.last_hit_player_id,
        }
    end
    runtime.bullets = {}
    for _, bullet_snapshot in ipairs(snapshot.bullets or {}) do
        runtime.bullets[#runtime.bullets + 1] = {
            x = bullet_snapshot.x, y = bullet_snapshot.y, vx = bullet_snapshot.vx, vy = bullet_snapshot.vy,
            radius = bullet_snapshot.radius or 5, pattern = bullet_snapshot.pattern,
            curve = bullet_snapshot.curve, grazed_by = bullet_snapshot.grazed_by or {},
            sprite = bullet_snapshot.sprite,
            render_scale = bullet_snapshot.render_scale or 0.4,
        }
    end
    runtime.player_bullets = {}
    for _, bullet_snapshot in ipairs(snapshot.player_bullets or {}) do
        runtime.player_bullets[#runtime.player_bullets + 1] = {
            x = bullet_snapshot.x, y = bullet_snapshot.y,
            vx = bullet_snapshot.vx, vy = bullet_snapshot.vy,
            speed = bullet_snapshot.speed, damage = bullet_snapshot.damage,
            radius = bullet_snapshot.radius, focused = bullet_snapshot.focused == true,
            owner_id = bullet_snapshot.owner_id,
        }
    end
    runtime.last_world_hash = self:world_hash()
    return true
end

function StageAdapter:world_hash()
    local runtime = self.runtime
    if not runtime then
        return nil
    end
    return runtime.battle_tick:hash(self:get_world_snapshot())
end

function StageAdapter:render()
    local runtime = self.runtime
    local lstg = self.lstg
    if not runtime or not lstg then
        return
    end
    lstg.BeginScene()
    lstg.RenderClear(lstg.Color(255, 9, 12, 28))
    lstg.SetViewport(0, 1280, 0, 720)
    lstg.SetScissorRect(0, 1280, 0, 720)
    lstg.SetOrtho(0, 1280, 0, 720)
    if lstg.Render then
        for index, background in ipairs(runtime.background_layers or {}) do
            local alpha = index == 1 and 205 or 100
            lstg.SetImageState(background, "", lstg.Color(alpha, 255, 255, 255))
            lstg.Render(background, 640, 360, 0, 2.5, 1.4)
        end
        if runtime.background_overlay then
            lstg.SetImageState(runtime.background_overlay, "", lstg.Color(150, 255, 255, 255))
            lstg.Render(runtime.background_overlay, 640, 360, 0, 2.8, 1.6)
        end
    end
    local image = "tnr-white"
    local frame = math.floor(runtime.frame / 4) % 8 + 1
    for player_id, runtime_player in pairs(runtime.players) do
        local player_state = self.session:get_player(player_id)
        if player_state and player_state.alive and runtime_player.invulnerable % 6 < 3 then
            local player_color = player_id == 1 and lstg.Color(255, 120, 180, 255) or lstg.Color(255, 120, 220, 150)
            lstg.SetImageState(image, "", player_color)
            if lstg.Render then
                lstg.Render("tnr-reimu" .. frame, runtime_player.x, runtime_player.y, 0, 1, 1)
            else
                local hitbox = runtime_player.profile.hitbox_radius
                lstg.RenderRect(image, runtime_player.x - hitbox * 2, runtime_player.x + hitbox * 2, runtime_player.y - hitbox * 2, runtime_player.y + hitbox * 2)
            end
        end
    end
    for _, bullet in ipairs(runtime.player_bullets) do
        if lstg.Render then
            lstg.Render(bullet.focused and "tnr-reimu-blue" or "tnr-reimu-red", bullet.x, bullet.y, 90, 1, 1)
        else
            lstg.SetImageState(image, "", lstg.Color(255, 120, 255, 160))
            lstg.RenderRect(image, bullet.x - bullet.radius, bullet.x + bullet.radius, bullet.y - bullet.radius * 2, bullet.y + bullet.radius * 2)
        end
    end
    for _, bullet in ipairs(runtime.bullets) do
        local bullet_color = {
            ritual = { 255, 255, 170, 80 },
            seal = { 255, 90, 180, 255 },
            spiral = { 255, 190, 90, 255 },
            wind = { 255, 90, 210, 255 },
            cross = { 255, 100, 220, 150 },
            aimed_fan = { 255, 255, 90, 110 },
        }
        local values = bullet_color[bullet.pattern] or { 255, 255, 80, 90 }
        lstg.SetImageState(image, "", lstg.Color(values[1], values[2], values[3], values[4]))
        local bullet_image = bullet.sprite or "tnr-bullet-red"
        if lstg.Render and bullet_image then
            local scale = bullet.render_scale or 0.4
            lstg.Render(bullet_image, bullet.x, bullet.y, math.deg(math.atan(bullet.vy, bullet.vx)), scale, scale)
        else
            lstg.RenderRect(image, bullet.x - bullet.radius, bullet.x + bullet.radius, bullet.y - bullet.radius, bullet.y + bullet.radius)
        end
    end
    for _, enemy in ipairs(runtime.enemies) do
        lstg.SetImageState(image, "", enemy.boss and lstg.Color(255, 220, 80, 100) or lstg.Color(255, 255, 170, 80))
        if enemy.boss and lstg.Render and enemy.boss_image then
            local boss_image = enemy.boss_image
            if enemy.boss_frames and #enemy.boss_frames > 0 then
                local frame_index = math.floor(runtime.frame / 8) % #enemy.boss_frames + 1
                boss_image = enemy.boss_frames[frame_index]
            end
            lstg.Render(boss_image, enemy.x, enemy.y, 0, 0.72, 0.72)
            if runtime.current_card and runtime.current_card.is_spell and enemy.effect_image then
                local effect_alpha = 90 + math.floor((math.sin(runtime.frame * 0.08) + 1) * 45)
                lstg.SetImageState(enemy.effect_image, "mul+add", lstg.Color(effect_alpha, 255, 255, 255))
                lstg.Render(enemy.effect_image, enemy.x, enemy.y, runtime.frame * 1.5, 1.3, 1.3)
            end
        elseif lstg.Render and enemy.sprite then
            lstg.Render(enemy.sprite, enemy.x, enemy.y, 0, 1, 1)
        else
            lstg.RenderRect(image, enemy.x - enemy.radius, enemy.x + enemy.radius, enemy.y - enemy.radius, enemy.y + enemy.radius)
        end
    end
    local phase_text = runtime.current_card and runtime.current_card.display_name or runtime.phase
    local hud_parts = {}
    for player_id = 1, self.session.player_count or 1 do
        local player_state = self.session:get_player(player_id)
        local runtime_player = runtime.players[player_id]
        if player_state and runtime_player then
            hud_parts[#hud_parts + 1] = string.format("P%d Score %d  Life %d  Bomb %d  Graze %d", player_id, player_state.score, player_state.life, player_state.bomb, player_state.graze)
        end
    end
    lstg.RenderTTF("Sans", table.concat(hud_parts, "     "), 40, 40, 680, 680, 0, lstg.Color(255, 240, 240, 240), 2)
    lstg.RenderTTF("Sans", phase_text, 40, 40, 640, 640, 0, lstg.Color(255, 220, 220, 220), 1.5)
    if runtime.current_card and runtime.current_card.is_spell then
        local hp_ratio = 0
        for _, enemy in ipairs(runtime.enemies) do
            if enemy.boss then
                hp_ratio = math.max(0, math.min(1, enemy.hp / math.max(1, enemy.max_hp)))
                break
            end
        end
        local bar_left, bar_right, bar_bottom, bar_top = 260, 1020, 625, 641
        lstg.SetImageState(image, "", lstg.Color(190, 20, 20, 30))
        lstg.RenderRect(image, bar_left, bar_right, bar_bottom, bar_top)
        lstg.SetImageState(image, "", lstg.Color(255, 225, 55, 75))
        lstg.RenderRect(image, bar_left, bar_left + (bar_right - bar_left) * hp_ratio, bar_bottom + 2, bar_top - 2)
        local remaining = runtime.card_time_remaining or 0
        local seconds = math.ceil(remaining / 60)
        lstg.RenderTTF("Sans", string.format("%02d", seconds), bar_right + 20, bar_right + 90, bar_bottom - 2, bar_bottom - 2, 0, lstg.Color(255, 245, 230, 200), 1.1)
    end
    local mode_label = (self.session.player_count or 1) > 1 and "P1/P2 LOCAL CO-OP" or "P1 SINGLE PLAYER"
    lstg.RenderTTF("Sans", mode_label, 40, 40, 560, 560, 0, lstg.Color(255, 220, 220, 220), 1.5)
    if self.network_status then
        local color = self.network_status:sub(1, 6) == "DESYNC" and lstg.Color(255, 255, 100, 100) or lstg.Color(255, 120, 255, 160)
        lstg.RenderTTF("Sans", self.network_status, 40, 40, 520, 520, 0, color, 1.25)
    end
    if runtime.bomb_flash > 0 then
        lstg.RenderTTF("Sans", "BOMB", 640, 640, 360, 360, 1 + 4, lstg.Color(255, 255, 255, 255), 4)
    end
    lstg.EndScene()
end

function StageAdapter:get_battle_manager()
    return self.battle
end

function StageAdapter:complete(clear_state, options)
    return self.battle:complete(clear_state, options)
end

function StageAdapter:kill_all()
    if self.runtime then
        self.runtime.kill_requested = true
        return true
    end
    if self.stage_api and self.stage_api.kill_all then
        return self.stage_api.kill_all()
    end
    return false
end

return StageAdapter
