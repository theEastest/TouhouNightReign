local load_error
local legacy_loaded = false
local native_stage
local native_boss_class
local native_card_list
-- Dialogue override bookkeeping. Each `boss.dialog.New` block in a boss class
-- is assigned an index so the JSON override for the matching block can be
-- applied when the card runs.
local native_dialog_block_index = setmetatable({}, { __mode = "k" })
local native_boss_key_for_class = setmetatable({}, { __mode = "k" })
local native_current_dialog_card = nil
local native_active_character

--- Which player character is active, used to pick the dialogue variant and
--- the native player class.
native_active_character = function()
    -- The room layer publishes the chosen character through the player state.
    local state = rawget(_G, "tnr_native_player_state")
    if type(state) == "table" and state.character_id then return tostring(state.character_id) end
    local current = rawget(_G, "player") or rawget(_G, "lstg") and lstg.player
    if current and current.character_id then return tostring(current.character_id) end
    return "reimu"
end

--- Assign a stable dialogue-block index to every dialog card of a boss class
--- and remember which data key the class belongs to.
local function native_index_dialog_blocks(boss_key, class)
    if not class or type(class.cards) ~= "table" then return end
    native_boss_key_for_class[class] = boss_key
    local block = 0
    for _, card in ipairs(class.cards) do
        if type(card) == "table" and card.is_dialog == true and not native_dialog_block_index[card] then
            local index = block
            native_dialog_block_index[card] = index
            block = block + 1
            -- Wrap the dialogue card's init so the override cursor is set to
            -- this block right before the author's script emits sentences.
            if type(card.init) == "function" then
                local native_init = card.init
                card.init = function(self, ...)
                    DialogOverride.begin(boss_key, index, native_active_character())
                    local ok, err = pcall(native_init, self, ...)
                    if not ok then
                        DialogOverride.end_dialogue()
                        error(err, 0)
                    end
                    return ok
                end
            end
        end
    end
end

local native_player
local native_render_func
local native_mode = "card"
local native_direct_card = false
local native_enemy_specs = nil
local native_enemy_training_only = false
local native_enemy_training_error = nil
local native_enemy_boss_error = nil
local native_enemy_training_seen_alive = false
local native_room_seed = 0
local native_room_floor = 1
local native_room_band = 1
local FloorBonus = require("tnr.battle.floor_bonus")
local DialogOverride = require("tnr.stages.dialog_override")
local native_room_music_hint
local native_room_generation = 0
-- Shared TNR encounter identity used on the wire. The native counter remains
-- local; this value prevents previous-room packets from being applied.
local native_external_room_generation = nil
local native_room_started = false
local native_enemy_boss_started = false
local native_virtual_keys = {}
local native_virtual_keys_previous = {}
local native_coop_enabled = false
local native_local_player_id = 1
local native_remote_player
local native_remote_generation = -1
local native_remote_input = {}
local native_remote_bomb_latched = false
local native_remote_bomb_tick = -1
local native_remote_bomb_charge_frames = 0
local native_remote_bomb_charge_fired = false
local native_physical_bomb_previous = false
local native_bomb_request_previous = false
local native_local_bomb_latched = false
local native_bomb_charge_frames = 0
local native_bomb_charge_max = 180
local native_bomb_charge_fired = false
local native_local_bomb_charged = false
local native_bomb_blocked = false
local native_bomb_hit_charge_timer = 0
local native_bomb_hit_charge_window = 0
local native_bomb_generation = 0
local native_last_applied_bomb_generation = 0
local native_last_bomb_owner = nil
local native_last_bomb_focus = false
local native_last_bomb_charged = false
local native_bomb_events = {}
local native_applied_bomb_events = {}
local native_local_bomb_sequences = {}
local native_local_bomb_ticks = {}
local native_enemy_kill_generation = 0
local native_enemy_kill_events = {}
local native_enemy_alive_cache = {}
local native_authoritative_enemy_states
local native_authoritative_enemy_initialized = {}
local native_last_applied_enemy_kill_generation = 0
local native_syncing_snapshot = false
local native_network_authority_host = true
local Aggro = require("tnr.multiplayer.aggro")
local native_aggro = Aggro.new(300)
local native_aggro_remote_report
local native_aggro_focus_player = 1
local native_aggro_focus_window = 0
local native_aggro_targeting = false
local native_aggro_hooks_installed = false
local native_original_new
local native_original_angle
local native_original_enemybase_colli
local native_original_object_colli
local native_original_enemy_kill
local native_original_reimu_spell
local native_original_reimu_shoot
-- Native legacy player classes per TNR character id. `reimu_player` etc. are
-- globals defined by the included THlib character scripts.
local native_player_class_by_character = {
    reimu = "reimu_player",
    marisa = "marisa_player",
    sanae = "sanae_player",
}

--- Resolve the native legacy player class for a character id.
local function native_player_class_for(character_id)
    local name = native_player_class_by_character[character_id]
    if not name then return nil end
    return rawget(_G, name)
end

-- Legacy sprite names for each character's support option and body. Used when
-- rendering the remote player and its options on the local screen.
local native_character_sprites = {
    reimu = { body = "reimu_player1", support = "reimu_support" },
    marisa = { body = "marisa_player1", support = "marisa_support" },
    sanae = { body = "sanae_player1", support = "sanae_support" },
}

local function native_character_sprites_for(character_id)
    return native_character_sprites[character_id] or native_character_sprites.reimu
end

-- Bomb/VFX classes created by each character's spell implementation. Used to
-- track stale bomb effects across room transitions per character.
local native_bomb_effect_classes = {}

--- Register the bomb-effect classes for a character so its spell VFX can be
--- tracked and cleaned across room transitions. Called after THlib is loaded.
local function native_register_bomb_classes(character_id, names)
    native_bomb_effect_classes[character_id] = native_bomb_effect_classes[character_id] or {}
    for _, name in ipairs(names) do
        local class = rawget(_G, name)
        if class then native_bomb_effect_classes[character_id][class] = true end
    end
end

local native_play_remote_bomb
local native_damage_owner_context
local native_bomb_effects = {}
local COOP_RESPAWN_FRAMES = 600
local native_respawn_frames = { [1] = 0, [2] = 0 }
-- Cumulative per-player counters for the whole encounter, used by the perfect
-- clear tracker. `native_miss_counts` counts respawns, `native_bomb_counts`
-- counts used bombs.
local native_miss_counts = { [1] = 0, [2] = 0 }
local native_bomb_counts = { [1] = 0, [2] = 0 }
local native_team_lives = 3
local native_party_state = nil
local native_player_state = nil
-- Immutable loadout descriptors supplied by the TNR session.  Native THlib
-- still owns the actual object simulation; these descriptors only select the
-- player profile parameters needed to construct the same local simulation on
-- both peers.
local native_local_loadout_descriptor = nil
local native_remote_loadout_descriptor = nil
-- Formal TNR combat runtime drivers.  The legacy Reimu methods remain
-- available for training/reference rooms, but are bypassed in a formal room
-- so equipment descriptors are the sole source of player firepower.
local native_runtime_active = false
local native_runtime_drivers = { [1] = nil, [2] = nil }
local native_runtime_shot_calls = 0
local native_legacy_shot_calls = 0
local native_runtime_last_projectile
local native_clear_enemy_bullets

local function native_reset_bomb_charge()
    native_bomb_charge_frames = 0
    native_bomb_charge_fired = false
    native_physical_bomb_previous = false
    native_bomb_request_previous = false
    native_local_bomb_latched = false
    native_local_bomb_charged = false
    native_bomb_blocked = false
    native_bomb_hit_charge_timer = 0
    native_bomb_hit_charge_window = 0
end

local function native_reset_remote_bomb_charge()
    native_remote_bomb_charge_frames = 0
    native_remote_bomb_charge_fired = false
    native_remote_bomb_latched = false
    native_remote_bomb_tick = -1
end

local function native_descriptor_support_count(descriptor)
    local total = 0
    for _, support in ipairs(descriptor and descriptor.supports or {}) do
        local definition = support.definition or support
        total = total + math.max(0, math.floor(tonumber(definition.entity_count) or 0))
    end
    return total
end

local function native_apply_loadout_descriptor(player_object, descriptor)
    if not player_object or type(descriptor) ~= "table" then return false end
    local speed = descriptor.speed or {}
    if tonumber(speed.high_speed) then player_object.hspeed = tonumber(speed.high_speed) end
    if tonumber(speed.low_speed) then player_object.lspeed = tonumber(speed.low_speed) end
    local support_count = native_descriptor_support_count(descriptor)
    -- Legacy Reimu's support formation has four visual slots.  Keep the
    -- original layout while honoring the descriptor's entity count, including
    -- an explicitly empty support loadout.
    player_object.support = math.min(5, support_count)
    -- THlib normally derives support count from `lstg.var.power` and slowly
    -- interpolates toward it every frame.  Formal loadouts own this value;
    -- keep the legacy driver on the same count or it will pull a three-unit
    -- support (for example Orrery) back to the default two-unit formation.
    if player_object == native_player and lstg and lstg.var then
        lstg.var.power = math.max(0, math.min(500, support_count * 100))
    end
    player_object.tnr_loadout_hash = descriptor.loadout_hash
    player_object.tnr_loadout_descriptor = descriptor
    return true
end

local function native_runtime_support_layout(player_object, entities)
    if not player_object or type(entities) ~= "table" then return end
    local layout = {}
    for index, entity in ipairs(entities) do
        if type(entity) == "table" then
            layout[index] = {
                (tonumber(entity.x) or tonumber(player_object.x) or 0) - (tonumber(player_object.x) or 0),
                (tonumber(entity.y) or tonumber(player_object.y) or 0) - (tonumber(player_object.y) or 0),
                1,
            }
        end
    end
    player_object.support = math.min(5, #layout)
    player_object.sp = layout
    player_object.supportx = tonumber(player_object.x) or 0
    player_object.supporty = tonumber(player_object.y) or 0
end

local NativeProjectile = require("tnr.character.runtime.native_projectile")
local native_runtime_enemy_targets

local function native_spawn_runtime_projectile(shot, player_object)
    local driver = native_runtime_drivers[shot.owner_player_id or native_local_player_id]
    local weapon = driver and driver.weapon_manager:find(shot.source_instance_id)
    local object = NativeProjectile.spawn(shot, weapon, native_runtime_enemy_targets)
    native_runtime_last_projectile = object
    if object then native_runtime_shot_calls = native_runtime_shot_calls + 1 end
    return object
end

local function native_has_local_bomb()
    local count = native_player_state and tonumber(native_player_state.bomb)
    if count == nil and lstg and lstg.var then
        count = tonumber(lstg.var.bomb)
    end
    -- A missing count occurs during native self-tests and before the player
    -- object is initialized. Do not reject those explicit test inputs; once
    -- a real count is available, zero is a hard input gate.
    return count == nil or count > 0
end

local native_is_valid_object

native_runtime_enemy_targets = function()
    local result = {}
    for _, group in ipairs({ GROUP_ENEMY, GROUP_NONTJT }) do
        for _, enemy in ObjList(group) do
            if native_is_valid_object(enemy) then
                result[#result + 1] = {
                    id = tostring(enemy), object = enemy,
                    x = enemy.x, y = enemy.y, hp = enemy.hp or 0,
                    radius = math.max(enemy.a or 0, enemy.b or 0),
                    protect = enemy.protect, colli = enemy.colli,
                }
            end
        end
    end
    return result
end

local function native_clear_enemy_bullets_near(pulses)
    if type(pulses) ~= "table" or #pulses == 0 or not ObjList or not GROUP_ENEMY_BULLET or not Del then
        return
    end
    for _, pulse in ipairs(pulses) do NativeProjectile.pulse(pulse) end
    for _, bullet in ObjList(GROUP_ENEMY_BULLET) do
        local bx, by = tonumber(bullet.x) or 0, tonumber(bullet.y) or 0
        for _, pulse in ipairs(pulses) do
            local dx, dy = bx - (tonumber(pulse.x) or 0), by - (tonumber(pulse.y) or 0)
            if dx * dx + dy * dy <= (tonumber(pulse.radius) or 0) ^ 2 then
                Del(bullet)
                break
            end
        end
    end
end

local function native_runtime_fire(driver, player_object, input, player_id)
    if not native_runtime_active or type(driver) ~= "table" or not driver.bridge then
        return 0
    end
    input = input or {}
    local mode = input.focus == true and "LOW" or "HIGH"
    local context = {
        player_id = tonumber(player_id) or native_local_player_id,
        x = player_object and tonumber(player_object.x) or 0,
        y = player_object and tonumber(player_object.y) or 0,
        angle = 90,
        frame = stage and stage.current_stage and tonumber(stage.current_stage.frame_count) or 0,
        focus = input.focus == true,
        room_generation = native_external_room_generation or native_room_seed,
        attack_allowed = player_object and not player_object.hide and not player_object.lock
            and (tonumber(player_object.death) or 0) == 0
            and not (lstg.player and lstg.player.dialog),
        enemies = native_runtime_enemy_targets(),
    }
    local ok, shots, support_state = pcall(driver.bridge.update, driver.bridge, driver,
        mode, input.shoot == true and not (player_object and player_object.hide == true), context)
    if not ok then error(shots) end
    driver._last_support_state = support_state
    native_runtime_support_layout(player_object, support_state)
    if driver.afterglow_invulnerability and driver.afterglow_invulnerability > 0 and player_object then
        player_object.protect = math.max(tonumber(player_object.protect) or 0,
            driver.afterglow_invulnerability)
        player_object.invuln = math.max(tonumber(player_object.invuln) or 0,
            driver.afterglow_invulnerability)
    end
    if driver.support_manager and driver.support_manager.last_modifier_context then
        native_clear_enemy_bullets_near(driver.support_manager.last_modifier_context.clear_pulses)
    end
    local created = 0
    for _, shot in ipairs(shots or {}) do
        if native_spawn_runtime_projectile(shot, player_object) then created = created + 1 end
    end
    if created > 0 and input.shoot == true and type(PlaySound) == "function" then
        -- The legacy Reimu shooter is suppressed while a formal loadout is
        -- active. Re-emit its one-per-volley plst00 cue so Z shots retain the
        -- reference timing without multiplying the sound for each projectile.
        pcall(PlaySound, "plst00", 0.3, (tonumber(player_object and player_object.x) or 0) / 1024, false)
    end
    return created
end

local function native_set_team_lives(value)
    native_team_lives = math.max(0, tonumber(value) or native_team_lives)
    if native_party_state then native_party_state.team_life = native_team_lives end
    if lstg and lstg.var then lstg.var.lifeleft = native_team_lives end
    return native_team_lives
end
local native_team_defeated = false
local native_team_wipe_generation = 0
local legacy_key_is_down
local legacy_key_is_pressed
local native_input_replay
local unpack_args = table.unpack or unpack

native_is_valid_object = function(object)
    if object == nil or type(IsValid) ~= "function" then
        return false
    end
    local ok, valid = pcall(IsValid, object)
    return ok and valid == true
end

local function native_copy_support_layout(layout)
    if type(layout) ~= "table" then return nil end
    local result = {}
    for index = 1, 8 do
        local entry = layout[index]
        if type(entry) == "table" then
            result[index] = {
                tonumber(entry[1]) or 0,
                tonumber(entry[2]) or 0,
                tonumber(entry[3]) or 0,
            }
        end
    end
    return result
end

local function native_capture_player_support(player_object)
    if type(player_object) ~= "table" then return nil end
    return {
        support = tonumber(player_object.support) or 0,
        lh = tonumber(player_object.lh) or 0,
        sp = native_copy_support_layout(player_object.sp),
    }
end

local function native_key_down(name)
    local input = lstg and lstg.Input
    local keyboard = input and input.Keyboard
    local code = keyboard and keyboard[name]
    if code == nil or type(keyboard.GetKeyState) ~= "function" then
        return false
    end
    local ok, state = pcall(keyboard.GetKeyState, code)
    return ok and not not state
end

local function native_player_position(player_id)
    player_id = tonumber(player_id)
    if player_id == native_local_player_id then
        if native_player then
            return tonumber(native_player.x) or 0, tonumber(native_player.y) or 0,
                (native_respawn_frames[player_id] or 0) <= 0
        end
    elseif native_remote_player then
        return tonumber(native_remote_player.x) or 0, tonumber(native_remote_player.y) or 0,
            (native_respawn_frames[player_id] or 0) <= 0
    end
    return 0, -176, false
end

local function native_aggro_target_position()
    return native_player_position(native_aggro_focus_player)
end

local function native_reset_aggro()
    native_aggro:reset()
    native_aggro_remote_report = nil
    native_aggro_focus_player = 1
    native_aggro_focus_window = 0
    native_aggro_targeting = false
end

local function native_pick_random_focus()
    if not native_coop_enabled then
        native_aggro_focus_player = native_local_player_id
        native_aggro_focus_window = tonumber(native_aggro.window_id) or 0
        return
    end
    -- Use the room seed and current window as a deterministic random source;
    -- both peers therefore pick the same player without another packet.
    local seed = math.floor(tonumber(native_room_seed) or 1)
    local salt = (tonumber(native_aggro.window_id) or 0) + 1
    -- Keep every intermediate product below Lua's exact-integer range. This
    -- matters when host and client run different LuaJIT/5.1 builds.
    local modulus = 2147483647
    local value = ((seed % modulus) * 1103515 + salt * 12345 + 6789) % modulus
    native_aggro_focus_player = (value % 2) + 1
    native_aggro_focus_window = tonumber(native_aggro.window_id) or 0
end

local function native_record_damage(player_id, amount)
    if native_coop_enabled then
        native_aggro:record(player_id, amount)
    end
end

local function native_notify_projectile_hit(projectile)
    if not projectile or projectile._tnr_hit_reported or projectile._tnr_managed_projectile then return end
    local owner = tonumber(projectile._tnr_owner_id or projectile.tnr_owner_id)
    local instance_id = projectile._tnr_source_instance_id or projectile.tnr_source_instance_id
    if not owner or not instance_id then return end
    local driver = native_runtime_drivers[owner]
    if driver and driver.weapon_manager then
        driver.weapon_manager:notify_projectile_hit(instance_id,
            stage and stage.current_stage and tonumber(stage.current_stage.frame_count) or 0)
        projectile._tnr_hit_reported = true
    end
end

local function native_update_aggro_window()
    if not native_coop_enabled then return end
    local report = native_aggro:advance(1)
    if not report then return end
    -- The host is the only authority allowed to compare reports and publish a
    -- focus. The client's local report is sent in peer_snapshot and retained
    -- until the corresponding host snapshot arrives.
    if native_network_authority_host and native_aggro_remote_report then
        local remote = native_aggro_remote_report
        if tonumber(remote.window_id) == tonumber(report.window_id) then
            local chosen = Aggro.compare(report, remote, native_aggro_focus_player)
            if chosen then
                native_aggro_focus_player = chosen
                native_aggro_focus_window = report.window_id
            end
            native_aggro_remote_report = nil
        end
    end
end

local function native_install_aggro_hooks()
    if native_aggro_hooks_installed then return end
    native_aggro_hooks_installed = true
    -- Tag every real player bullet at creation time. This includes Reimu's
    -- homing shots and bombs, while enemy bullets remain untouched.
    if type(New) == "function" then
        native_original_new = New
        New = function(class, ...)
            -- Exported activity scripts can create a short-lived effect at
            -- the same frame that its class is first referenced.  The native
            -- constructor requires a registered LuaSTG class, so register a
            -- valid class lazily and retry once before surfacing real errors.
            if type(class) ~= "table" or class.is_class ~= true then
                return nil
            end
            local ok, object_or_error = pcall(native_original_new, class, ...)
            if not ok and type(lstg.RegisterGameObjectClass) == "function" then
                pcall(lstg.RegisterGameObjectClass, class)
                ok, object_or_error = pcall(native_original_new, class, ...)
            end
            if not ok then
                -- Some imported activity helpers pass a legacy/plus class
                -- table that cannot be represented by the modern native
                -- object pool.  These are visual helpers (boss pointers,
                -- optional HUD effects, etc.); skipping just this object is
                -- safe and prevents an otherwise playable room from aborting
                -- its frame.  Do not hide unrelated constructor failures.
                if tostring(object_or_error):lower():match("object class required") then
                    return nil
                end
                error(object_or_error, 0)
            end
            local object = object_or_error
            if object and native_damage_owner_context
                    and GROUP_PLAYER_BULLET and object.group == GROUP_PLAYER_BULLET then
                object._tnr_owner_id = native_damage_owner_context
            end
            return object
        end
        _G.New = New
    end
    -- Record actual HP loss at the same collision point used by the imported
    -- enemy and boss classes. No synthetic damage is generated for misses.
    if enemybase and type(enemybase.colli) == "function" then
        native_original_enemybase_colli = enemybase.colli
        enemybase.colli = function(self, other)
            local before = tonumber(self.hp)
            local result = native_original_enemybase_colli(self, other)
            local after = tonumber(self.hp)
            local owner = other and tonumber(other._tnr_owner_id)
            if owner and before and after and after < before then
                native_record_damage(owner, before - after)
                native_notify_projectile_hit(other)
            end
            return result
        end
    end
    -- A few reference objects derive directly from object and provide their
    -- own collision callback. Cover that path without changing their logic.
    if _object and type(_object.colli) == "function" then
        native_original_object_colli = _object.colli
        _object.colli = function(self, other)
            local before = tonumber(self.hp)
            local result = native_original_object_colli(self, other)
            local after = tonumber(self.hp)
            local owner = other and tonumber(other._tnr_owner_id)
            if owner and before and after and after < before then
                native_record_damage(owner, before - after)
                native_notify_projectile_hit(other)
            end
            return result
        end
    end
    -- Mark native enemy kills before the original callback runs. A client
    -- can then distinguish a locally killed enemy from one that must be
    -- finalized locally after the peer reports the authoritative death.
    if enemy and type(enemy.kill) == "function" then
        native_original_enemy_kill = enemy.kill
        enemy.kill = function(self, ...)
            if self then self._tnr_drop_spawned = true end
            return native_original_enemy_kill(self, ...)
        end
    end
    native_register_bomb_classes("reimu", { "reimu_kekkai", "reimu_sp_ef1" })
    native_register_bomb_classes("marisa", { "marisa_sp_ef" })
    native_register_bomb_classes("sanae", { "sanae_bf", "sanae_dmg" })
    -- Track the original Bomb effects for every playable character so a stale
    -- effect cannot survive a room transition indefinitely. The original
    -- spell implementations and their damage are otherwise left untouched.
    for _, character_id in ipairs({ "reimu", "marisa", "sanae" }) do
        local player_class = native_player_class_for(character_id)
        if player_class and type(player_class.spell) == "function" then
            local native_original_spell = player_class.spell
            if character_id == "reimu" then native_original_reimu_spell = native_original_spell end
            player_class.spell = function(self, ...)
                local before = {}
                if ObjList and GROUP_PLAYER_BULLET then
                    for _, object in ObjList(GROUP_PLAYER_BULLET) do before[object] = true end
                end
                -- A full local charge uses the same finite charged path as the
                -- remote replay. Ordinary key-up Bombs retain the legacy spell
                -- implementation and its original high/low visuals.
                if native_local_bomb_charged then
                    local focus = self.slow == 1
                    native_play_remote_bomb(native_local_player_id, focus, true)
                    self.nextspell = focus and 360 or 420
                    self.protect = 480
                    return true
                end
                local result = native_original_spell(self, ...)
                local bomb_classes = native_bomb_effect_classes[character_id]
                if ObjList and GROUP_PLAYER_BULLET and bomb_classes then
                    for _, object in ObjList(GROUP_PLAYER_BULLET) do
                        if not before[object] and bomb_classes[object.class] then
                            object._tnr_bomb_effect = true
                            object._tnr_bomb_created_frame = stage and stage.current_stage
                                and tonumber(stage.current_stage.frame_count) or 0
                            native_bomb_effects[#native_bomb_effects + 1] = object
                        end
                    end
                end
                return result
            end
        end
        if player_class and type(player_class.shoot) == "function" then
            local native_original_shoot = player_class.shoot
            if character_id == "reimu" then native_original_reimu_shoot = native_original_shoot end
            player_class.shoot = function(self, ...)
                if native_runtime_active then
                    -- Formal TNR rooms create projectiles through the shared
                    -- descriptor runtime. Suppress the fixed legacy volley so
                    -- empty or modified loadouts cannot be bypassed by THlib.
                    return true
                end
                native_legacy_shot_calls = native_legacy_shot_calls + 1
                return native_original_shoot(self, ...)
            end
        end
    end
    -- Most reference aiming helpers ultimately call Angle(x1,y1,x2,y2).
    -- Redirect only calls whose target is the local player, preserving all
    -- original pattern math while making both peers aim at the selected focus.
    if type(Angle) == "function" then
        native_original_angle = Angle
        Angle = function(x1, y1, x2, y2, ...)
            -- LuaSTG also accepts Angle(object, target_object). Handle that
            -- overload explicitly because SetV2 and most imported cards use
            -- it instead of passing numeric coordinates.
            if native_aggro_targeting and x2 == nil and y2 == nil
                    and y1 == native_player then
                local tx, ty = native_aggro_target_position()
                local ok, value = pcall(native_original_angle, x1, { x = tx, y = ty }, ...)
                if ok then return value end
                return native_original_angle(tonumber(x1.x) or 0, tonumber(x1.y) or 0, tx, ty, ...)
            end
            if native_aggro_targeting and native_player and x2 ~= nil and y2 ~= nil then
                local px, py = tonumber(native_player.x), tonumber(native_player.y)
                if px and py and math.abs((tonumber(x2) or 0) - px) < 0.0001
                        and math.abs((tonumber(y2) or 0) - py) < 0.0001 then
                    local tx, ty = native_aggro_target_position()
                    x2, y2 = tx, ty
                end
            end
            return native_original_angle(x1, y1, x2, y2, ...)
        end
        _G.Angle = Angle
    end
end

local function native_merge_physical_input(input)
    input = input or {}
    local explicit_input = input._native_input_override == true
    local left = native_key_down("Left")
    local right = native_key_down("Right")
    local up = native_key_down("Up")
    local down = native_key_down("Down")
    local bomb_down = native_key_down("X")
    local keyboard_available = lstg and lstg.Input and lstg.Input.Keyboard
        and type(lstg.Input.Keyboard.GetKeyState) == "function"
    -- Direction and held actions are sampled every frame. This prevents a
    -- stale project input packet from pinning the player in one direction.
    if not explicit_input and keyboard_available then
        input.move_x = (right and 1 or 0) - (left and 1 or 0)
        input.move_y = (up and 1 or 0) - (down and 1 or 0)
        input.focus = native_key_down("LeftShift")
        input.shoot = native_key_down("Z")
    end
    local bomb_requested = input.bomb == true

    -- Bomb charge is an owner-local action. Never accumulate a charge, emit a
    -- release edge, or run the collision safety timer while the owner has no
    -- Bombs. If the key is held while the count is replenished, require a
    -- release before arming again; this prevents an old held key from firing
    -- immediately after a reward or room transition.
    if not native_has_local_bomb() then
        native_bomb_charge_frames = 0
        native_bomb_charge_fired = false
        native_local_bomb_latched = false
        native_local_bomb_charged = false
        native_bomb_hit_charge_timer = 0
        native_bomb_hit_charge_window = 0
        native_bomb_blocked = bomb_down
        input.bomb = false
        input.bomb_charged = false
        input.bomb_success = false
        native_physical_bomb_previous = bomb_down
        native_bomb_request_previous = false
        return input
    elseif native_bomb_blocked then
        if bomb_down then
            input.bomb = false
            input.bomb_charged = false
            input.bomb_success = false
            native_physical_bomb_previous = true
            native_bomb_request_previous = false
            return input
        end
        native_bomb_blocked = false
        native_physical_bomb_previous = false
    end

    if explicit_input then
        -- Deterministic self-tests and remote relays already provide a single
        -- Bomb edge. Do not turn those packets into a held-charge sequence.
        input.bomb = bomb_requested and not native_local_bomb_latched
        if input.bomb then
            native_local_bomb_latched = true
            native_local_bomb_charged = input.bomb_charged == true
        end
        if not bomb_requested then
            native_local_bomb_latched = false
            native_local_bomb_charged = false
        end
        native_bomb_charge_frames = 0
        native_bomb_charge_fired = false
    elseif bomb_down then
        if not native_physical_bomb_previous then
            native_bomb_charge_frames = 1
            native_bomb_charge_fired = false
        else
            native_bomb_charge_frames = math.min(native_bomb_charge_max, native_bomb_charge_frames + 1)
        end
        if native_bomb_charge_frames >= native_bomb_charge_max and not native_bomb_charge_fired then
            input.bomb = true
            input.bomb_charged = true
            native_bomb_charge_fired = true
            native_local_bomb_latched = true
            native_local_bomb_charged = true
        else
            input.bomb = false
        end
    else
        -- Releasing before the cap emits one normal Bomb. A full charge has
        -- already fired automatically and therefore emits no second edge.
        input.bomb = native_bomb_charge_frames > 0 and not native_bomb_charge_fired
            and not native_local_bomb_latched
        if input.bomb then
            native_local_bomb_latched = true
            input.bomb_charged = false
            native_local_bomb_charged = false
        end
        native_bomb_charge_frames = 0
        native_bomb_charge_fired = false
        native_local_bomb_latched = false
        native_local_bomb_charged = false
    end
    native_bomb_request_previous = bomb_requested
    local was_bomb_down = native_physical_bomb_previous
    -- A collision while charging is resolved locally.  The release edge in
    -- the next 18 frames upgrades the deferred safety Bomb; otherwise it is
    -- emitted automatically when the 30-frame timer expires.
    if not explicit_input and native_bomb_hit_charge_timer > 0 then
        local released_after_hit = not bomb_down and was_bomb_down
        if released_after_hit and native_bomb_hit_charge_window > 0 then
            input.bomb = true
            input.bomb_charged = true
            native_local_bomb_charged = true
            native_bomb_hit_charge_timer = 0
            native_bomb_hit_charge_window = 0
        elseif native_bomb_hit_charge_timer <= 1 then
            input.bomb = true
            input.bomb_charged = false
            native_local_bomb_charged = false
            native_local_bomb_latched = true
            native_bomb_charge_fired = true
            native_bomb_hit_charge_timer = 0
            native_bomb_hit_charge_window = 0
        else
            input.bomb = false
            native_bomb_hit_charge_timer = native_bomb_hit_charge_timer - 1
            native_bomb_hit_charge_window = math.max(0, native_bomb_hit_charge_window - 1)
        end
    end
    native_physical_bomb_previous = bomb_down
    return input
end

native_clear_enemy_bullets = function()
    if ObjList and GROUP_ENEMY_BULLET and Del then
        for _, bullet in ObjList(GROUP_ENEMY_BULLET) do
            Del(bullet)
        end
    end
end

-- Remove transient room objects before retrying a failed encounter.  The
-- native stage remains active while the failure menu is shown, so waiting for
-- stage.Change alone can leave the previous wave's enemies/projectiles in the
-- object pool.  Restrict this to combat groups; menu/UI objects are owned by
-- their own groups and must remain intact.
local function native_clear_room_objects()
    local groups = {
        rawget(_G, "GROUP_ENEMY"),
        rawget(_G, "GROUP_ENEMY_BULLET"),
        rawget(_G, "GROUP_PLAYER_BULLET"),
        rawget(_G, "GROUP_PLAYER"),
    }
    if type(ObjList) ~= "function" or type(Del) ~= "function" then return false end
    for _, group in ipairs(groups) do
        if group ~= nil then
            local ok, objects = pcall(ObjList, group)
            if ok and type(objects) == "table" then
                for _, object in ipairs(objects) do
                    pcall(Del, object)
                end
            end
        end
    end
    native_clear_enemy_bullets()
    native_player = nil
    native_remote_player = nil
    native_room_started = false
    native_enemy_boss_started = false
    native_bomb_effects = {}
    native_respawn_frames[1], native_respawn_frames[2] = 0, 0
    return true
end

local function native_capture_enemy_states(current)
    local result = {}
    if not current or type(current.enemy_objects) ~= "table" then
        return result
    end
    for enemy_id, enemy_object in pairs(current.enemy_objects) do
        local id = tonumber(enemy_id)
        if id then
            local alive = native_is_valid_object(enemy_object)
            local x, y, hp, hide = 0, 0, nil, false
            if alive then
                pcall(function()
                    x = tonumber(enemy_object.x) or 0
                    y = tonumber(enemy_object.y) or 0
                    hp = tonumber(enemy_object.hp)
                    hide = enemy_object.hide == true
                end)
            else
                -- A killed object may already have left the pool, but the
                -- bridge table still retains its final coordinates.
                pcall(function()
                    x = tonumber(enemy_object.x) or 0
                    y = tonumber(enemy_object.y) or 0
                end)
            end
            result[id] = {
                alive = alive,
                x = x,
                y = y,
                hp = hp,
                hide = hide,
            }
        end
    end
    return result
end

-- Reconcile a remote death through the local enemy's normal kill callback.
-- This preserves the local drop pool and keeps item ownership local; calling
-- Del directly would remove the enemy without producing its drops.
local function native_finalize_local_enemy_death(enemy_object)
    if not native_is_valid_object(enemy_object) then return end
    if enemy_object._tnr_drop_spawned == true then
        if type(Del) == "function" then pcall(Del, enemy_object) end
        return
    end
    if type(enemy_object.kill) == "function" then
        pcall(enemy_object.kill, enemy_object)
        enemy_object._tnr_drop_spawned = true
    elseif type(Kill) == "function" then
        pcall(Kill, enemy_object)
    elseif type(Del) == "function" then
        pcall(Del, enemy_object)
    end
end

local function native_cleanup_bomb_effects()
    local now = stage and stage.current_stage and tonumber(stage.current_stage.frame_count) or 0
    for index = #native_bomb_effects, 1, -1 do
        local effect = native_bomb_effects[index]
        local born
        pcall(function() born = tonumber(effect and effect._tnr_bomb_created_frame) end)
        local expired = not native_is_valid_object(effect)
            or (born and now - born > 300)
            or (not born and (tonumber(effect.timer) or 0) > 300)
        if expired then
            table.remove(native_bomb_effects, index)
        elseif ((born and now - born > 270)
                or (not born and (tonumber(effect.timer) or 0) > 270))
                and type(Del) == "function" then
            pcall(Del, effect)
            table.remove(native_bomb_effects, index)
        end
    end
end

local function native_apply_authoritative_enemy_states()
    if native_network_authority_host or type(native_authoritative_enemy_states) ~= "table" then
        return
    end
    local current = stage and stage.current_stage
    if not current or type(current.enemy_objects) ~= "table" then return end
    for enemy_id, enemy_state in pairs(native_authoritative_enemy_states) do
        local id = tonumber(enemy_id)
        local enemy_object = id and current.enemy_objects[id]
        if type(enemy_state) == "table" then
            if enemy_state.alive and native_is_valid_object(enemy_object) then
                pcall(function()
                    local host_x = tonumber(enemy_state.x)
                    local host_y = tonumber(enemy_state.y)
                    -- Correct only the first observed spawn position. Every
                    -- later frame is simulated by the local native enemy
                    -- logic; repeatedly applying network coordinates causes
                    -- visible stepping on the client.
                    if not native_authoritative_enemy_initialized[id] then
                        if host_x then enemy_object.x = host_x end
                        if host_y then enemy_object.y = host_y end
                        native_authoritative_enemy_initialized[id] = true
                    end
                    if tonumber(enemy_state.hp) then enemy_object.hp = tonumber(enemy_state.hp) end
                    enemy_object.hide = enemy_state.hide == true
                end)
            elseif not enemy_state.alive then
                native_authoritative_enemy_initialized[id] = nil
                native_finalize_local_enemy_death(enemy_object)
            end
        end
    end
end

local function native_disable_client_enemy_collisions()
    -- Both peers run the original enemy collision code. This compatibility
    -- hook intentionally does not suppress local damage or enemy contacts.
end

-- Bomb visuals are local presentation, while the Bomb edge itself is sent as
-- a tiny generation counter in the host snapshot.  The original Reimu spell
-- assumes the global `player` object, so replaying it for a proxy would attach
-- damage/effects to the wrong player.  Spawn the same native Kekkai object at
-- the remote coordinates instead; it remains a real GROUP_PLAYER_BULLET and
-- therefore damages the local Boss through the original collision system.
native_play_remote_bomb = function(owner_id, focus, charged)
    local owner = tonumber(owner_id) or 0
    local owner_object = owner == native_local_player_id and native_player or native_remote_player
    if not owner_object or type(New) ~= "function" or not reimu_kekkai then
        return
    end
    local x = tonumber(owner_object.x) or 0
    local y = tonumber(owner_object.y) or 0
    -- Focused Reimu Bomb uses the original small Kekkai damage.  The unfocused
    -- variant uses the same native object with the larger reference damage;
    -- both modes have a finite lifetime and are locally collidable.
    local damage = charged and (focus and 2.0 or 90) or (focus and 1.25 or 50)
    if type(PlaySound) == "function" then
        if focus then
            pcall(PlaySound, "power1", 0.8)
            pcall(PlaySound, "cat00", 0.8)
        else
            pcall(PlaySound, "nep00", 0.8)
            pcall(PlaySound, "slash", 0.8)
        end
    end
    local previous_owner = native_damage_owner_context
    native_damage_owner_context = tonumber(owner_id)
    local layers = charged and (focus and 30 or 12) or (focus and 20 or 6)
    local spacing = charged and 8 or 12
    local ok, effect = pcall(New, reimu_kekkai, x, y, damage, layers, 20, spacing)
    if ok and effect then
        effect._tnr_bomb_effect = true
        effect._tnr_bomb_created_frame = stage and stage.current_stage
            and tonumber(stage.current_stage.frame_count) or 0
        native_bomb_effects[#native_bomb_effects + 1] = effect
    end
    native_damage_owner_context = previous_owner
end

local function native_record_bomb(owner_id, focus, input_tick, charged)
    native_bomb_generation = native_bomb_generation + 1
    native_last_bomb_owner = owner_id
    native_last_bomb_focus = focus == true
    native_last_bomb_charged = charged == true
    -- Count used bombs per owner for the perfect clear tracker. A relayed
    -- remote bomb is the same logical bomb, so dedupe by owner/sequence via
    -- the local_event flag below.
    local bomb_owner = tonumber(owner_id)
    if bomb_owner then
        native_bomb_counts[bomb_owner] = (native_bomb_counts[bomb_owner] or 0) + 1
    end
    native_bomb_events[#native_bomb_events + 1] = {
        sequence = native_bomb_generation,
        owner = owner_id,
        focus = focus == true,
        charged = charged == true,
        origin = native_local_player_id,
        -- Marks which process executed the event. The host may relay a
        -- client's Bomb using the same owner/sequence pair that the client
        -- already recorded locally, so owner alone is not a safe dedupe key.
        local_event = tonumber(owner_id) == native_local_player_id,
        input_tick = tonumber(input_tick),
    }
    if tonumber(owner_id) == native_local_player_id then
        native_local_bomb_sequences[native_bomb_generation] = true
        if tonumber(input_tick) then
            native_local_bomb_ticks[tonumber(input_tick)] = true
        end
    end
    if #native_bomb_events > 32 then
        table.remove(native_bomb_events, 1)
    end
end

local function native_apply_remote_bomb_event(sequence, owner_id, focus, local_event, origin, input_tick, charged)
    sequence = tonumber(sequence) or 0
    owner_id = tonumber(owner_id) or 0
    if sequence <= 0 then return end
    -- A peer snapshot is retransmitted until the next sync tick. Deduplicate
    -- by sender and sequence rather than relying on a single global counter;
    -- this also remains correct when both players independently use Bomb.
    local key = tostring(owner_id) .. ":" .. tostring(sequence)
    if native_applied_bomb_events[key] then
        return
    end
    native_applied_bomb_events[key] = true
    -- The host relays the complete event history. A local event may therefore
    -- come back in that history on the client; it was already played by the
    -- local Reimu and must not be spawned a second time. Sequence numbers are
    -- scoped by owner, so this does not suppress the host's event.
    if tonumber(origin) == native_local_player_id and local_event == true
            and owner_id == native_local_player_id
            and native_local_bomb_sequences[sequence] then
        return
    end
    -- The host recreates a client's Bomb event in its own sequence space. An
    -- input tick lets the originating client recognize that retransmission
    -- and avoid spawning a second visual/damage object locally.
    if owner_id == native_local_player_id and tonumber(input_tick)
            and native_local_bomb_ticks[tonumber(input_tick)] then
        return
    end
    native_last_applied_bomb_generation = math.max(
        native_last_applied_bomb_generation, sequence)
    native_last_bomb_owner = owner_id
    native_last_bomb_focus = focus == true
    native_last_bomb_charged = charged == true
    native_clear_enemy_bullets()
    native_play_remote_bomb(owner_id, native_last_bomb_focus, charged == true)
end

local function native_set_player_alive()
    if not native_player then return end
    native_player.death = 0
    native_player.lock = false
    native_player.hide = false
    native_player.colli = true
    native_player.protect = 180
    native_player.x = native_local_player_id == 1 and -36 or 36
    native_player.y = -176
    native_player.key = {}
end

local function native_set_player_dead()
    if not native_player then return end
    native_player.death = 0
    native_player.lock = true
    native_player.hide = true
    native_player.colli = false
    native_player.key = {}
end

local function native_ensure_remote_player()
    if not native_coop_enabled or not native_player then
        return nil
    end
    if not native_remote_player or native_remote_generation ~= native_room_generation then
        native_remote_player = {
            x = native_local_player_id == 1 and 36 or -36,
            y = -176,
            invuln = 0,
            shoot_cooldown = 0,
            support = 0,
            lh = 0,
            sp = nil,
            character_id = "reimu",
            image = nil,
            hidden = false,
        }
        native_remote_generation = native_room_generation
    end
    local remote_sprites = native_character_sprites_for(native_remote_player.character_id)
    native_remote_player.image = native_remote_player.image or remote_sprites.body
    native_remote_player.shoot_cooldown = tonumber(native_remote_player.shoot_cooldown) or 0
    native_remote_player.support = tonumber(native_remote_player.support) or 0
    native_remote_player.lh = tonumber(native_remote_player.lh) or 0
    native_remote_player.hidden = native_remote_player.hidden == true
    return native_remote_player
end

local function native_render_remote_player()
    if not native_coop_enabled or not native_player then return end
    local remote = native_ensure_remote_player()
    local remote_id = native_local_player_id == 1 and 2 or 1
    if not remote or remote.hidden == true or (native_respawn_frames[remote_id] or 0) > 0 then return end
    pcall(function()
        SetViewMode("world")
        local world = lstg.world or {}
        local render_x = tonumber(remote.x) or 0
        local render_y = tonumber(remote.y) or 0
        local left = tonumber(world.pl) or -192
        local right = tonumber(world.pr) or 192
        local bottom = tonumber(world.pb) or -224
        local top = tonumber(world.pt) or 224
        render_x = math.max(left + 16, math.min(right - 16, render_x))
        render_y = math.max(bottom + 24, math.min(top - 24, render_y))
        local support = math.max(0, tonumber(remote.support) or 0)
        local layout = remote.sp
        if type(layout) ~= "table" then
            layout = {
                {-36, -12, 1},
                {-16, -32, 1},
                {16, -32, 1},
                {36, -12, 1},
            }
        end
        local support_count = native_runtime_active and 0 or math.min(4, math.floor(support + 0.999))
        local remote_sprites = native_character_sprites_for(remote.character_id)
        pcall(SetImageState, remote_sprites.support, "", Color(180, 255, 255, 255))
        local shown = 0
        for index = 1, 4 do
            local entry = layout[index]
            if shown < support_count and type(entry) == "table"
                    and (tonumber(entry[3]) or 0) > 0.5 then
                shown = shown + 1
                pcall(Render, remote_sprites.support, render_x + (tonumber(entry[1]) or 0),
                    render_y + (tonumber(entry[2]) or 0), 0)
            end
        end
        local image = remote.image or remote_sprites.body
        local rendered = pcall(function()
            SetImageState(image, "", Color(210, 255, 255, 255))
            Render(image, render_x, render_y, 0, 1)
        end)
        if not rendered and type(RenderRect) == "function" then
            SetImageState("tnr-white", "", Color(210, 255, 255, 220))
            RenderRect("tnr-white", render_x - 8, render_x + 8,
                render_y - 12, render_y + 12)
        end
        pcall(SetImageState, image, "", Color(255, 255, 255, 255))
        pcall(SetImageState, "reimu_support", "", Color(255, 255, 255, 255))
    end)
end

local function native_apply_local_respawn_state()
    if not native_coop_enabled then return end
    if (native_respawn_frames[native_local_player_id] or 0) > 0 then
        native_set_player_dead()
    end
end

local function native_start_respawn(player_id)
    if not native_coop_enabled or native_team_defeated then return end
    if (native_respawn_frames[player_id] or 0) <= 0 then
        native_respawn_frames[player_id] = COOP_RESPAWN_FRAMES
        -- Count the miss once per respawn, not once per frame.
        local id = tonumber(player_id) or 1
        native_miss_counts[id] = (native_miss_counts[id] or 0) + 1
    end
    if player_id == native_local_player_id then
        native_set_player_dead()
    elseif native_remote_player then
        native_remote_player.invuln = 0
        native_remote_player.hidden = true
    end
    -- A dead player cannot be an aiming target. Transfer aggro immediately;
    -- the host snapshot will make the same decision visible on the peer.
    local other_id = tonumber(player_id) == 1 and 2 or 1
    if (native_respawn_frames[other_id] or 0) <= 0 then
        native_aggro_focus_player = other_id
        native_aggro_focus_window = tonumber(native_aggro.window_id) or 0
    end
end

local function native_finish_respawn(player_id)
    native_respawn_frames[player_id] = 0
    if player_id == native_local_player_id then
        native_set_player_alive()
    elseif native_remote_player then
        native_remote_player.x = native_local_player_id == 1 and 36 or -36
        native_remote_player.y = -176
        native_remote_player.invuln = 180
        native_remote_player.hidden = false
    end
end

local function native_advance_respawns()
    if not native_coop_enabled or native_team_defeated then return end
    for player_id = 1, 2 do
        local frames = native_respawn_frames[player_id] or 0
        if frames > 0 then
            frames = frames - 1
            native_respawn_frames[player_id] = frames
            if frames == 0 then
                native_finish_respawn(player_id)
            end
        end
    end
end

local function native_resolve_team_wipe()
    if not native_coop_enabled or native_team_defeated then return end
    if (native_respawn_frames[1] or 0) > 0 and (native_respawn_frames[2] or 0) > 0 then
        -- A simultaneous wipe is one shared event. Clear the arena exactly
        -- once before either the life decrement or the synchronized revive.
        native_team_wipe_generation = native_team_wipe_generation + 1
        native_clear_enemy_bullets()
        native_set_team_lives(native_team_lives - 1)
        if native_team_lives <= 0 then
            native_team_defeated = true
            return
        end
        -- A shared life is consumed only by a simultaneous team wipe. Both
        -- players return together so the room continues as one encounter.
        native_finish_respawn(1)
        native_finish_respawn(2)
        native_pick_random_focus()
    end
end

local function native_render_coop_hud()
    if not RenderTTF or native_team_defeated then return end
    SetViewMode("ui")
    local right = (screen and screen.width or 640) - 14
    local y = (screen and screen.height or 480) - 72
    for player_id = 1, 2 do
        local frames = native_respawn_frames[player_id] or 0
        if frames > 0 then
            local seconds = frames / 60
            RenderTTF("Sans", string.format("P%d  RESPAWN  %0.1fs", player_id, seconds), right, right, y, y,
                Color(255, 255, 220, 150), "right", "vcenter", "noclip")
            y = y - 26
        end
    end
    local lives_label = native_coop_enabled and "TEAM LIVES" or "PLAYER LIVES"
    local lives_value = native_coop_enabled and native_team_lives
        or (native_player_state and tonumber(native_player_state.life))
        or (lstg and lstg.var and tonumber(lstg.var.lifeleft)) or native_team_lives
    RenderTTF("Sans", string.format("%s  %d", lives_label, lives_value), right, right, y, y,
        Color(255, 220, 240, 255), "right", "vcenter", "noclip")
    y = y - 26
    -- Bombs are player-owned resources.  Only show the local process's count;
    -- the peer has an independent count and never receives this value over
    -- the wire.
    local bombs = native_player_state and tonumber(native_player_state.bomb)
    if bombs == nil and lstg and lstg.var then
        bombs = tonumber(lstg.var.bomb)
    end
    local bomb_alert = (native_bomb_hit_charge_window or 0) > 0
    RenderTTF("Sans", string.format("BOMBS  %d", math.max(0, bombs or 0)), right, right, y, y,
        bomb_alert and Color(255, 80, 80, 255) or Color(255, 255, 220, 255), "right", "vcenter", "noclip")
    y = y - 26
    -- Current stage score and money collected this stage. Both reset at the
    -- room boundary, so this always reflects the stage being played.
    local stage_score = tonumber(lstg and lstg.var and lstg.var.score) or 0
    local stage_money = tonumber(lstg and lstg.var and lstg.var.tnr_stage_money) or 0
    RenderTTF("Sans", string.format("SCORE  %d", stage_score), right, right, y, y,
        Color(220, 235, 255, 255), "right", "vcenter", "noclip")
    y = y - 26
    RenderTTF("Sans", string.format("MONEY  %d", stage_money), right, right, y, y,
        Color(255, 225, 140, 255), "right", "vcenter", "noclip")
    -- The charge is local to this machine/player. Draw it beneath the Bomb
    -- counter so both peers can charge independently without synchronizing a
    -- continuous stream of frames.
    local width = (screen and screen.width or 640)
    local charge = math.max(0, math.min(native_bomb_charge_max, native_bomb_charge_frames or 0))
    local ratio = charge / math.max(1, native_bomb_charge_max)
    local bar_left, bar_right = width - 190, width - 14
    local bar_bottom, bar_top = math.max(18, y - 34), math.max(30, y - 20)
    SetImageState("tnr-white", "", bomb_alert and Color(255, 45, 45, 75) or Color(190, 15, 20, 35))
    RenderRect("tnr-white", bar_left, bar_right, bar_bottom, bar_top)
    SetImageState("tnr-white", "", bomb_alert and Color(255, 70, 70, 255) or Color(255, 120, 205, 255))
    if ratio > 0 then
        RenderRect("tnr-white", bar_left + 2, bar_left + 2 + (bar_right - bar_left - 4) * ratio,
            bar_bottom + 2, bar_top - 2)
    end
    RenderTTF("Sans", (charge > 0 and "BOMB CHARGE" or "BOMB READY"), bar_left, bar_right,
        bar_top + 4, bar_top + 4, Color(255, 235, 225, 240), "left", "vcenter", "noclip")
    SetViewMode("world")
end

local function native_render_aggro_marker()
    if not native_coop_enabled or type(Render4V) ~= "function"
            or not native_player or native_aggro_focus_player == nil then
        return
    end
    local x, y, alive = native_aggro_target_position()
    if not alive then return end
    -- A compact downward red triangle (roughly 1/5 of Reimu's sprite) follows
    -- the focused player's world position on both peers.
    SetViewMode("world")
    SetImageState("tnr-white", "", Color(255, 55, 55, 255))
    local tip_y = y + 30
    local half_width = 6
    local height = 8
    Render4V("tnr-white", x - half_width, tip_y + height, 0.45,
        x + half_width, tip_y + height, 0.45,
        x, tip_y, 0.45,
        x, tip_y, 0.45)
    SetImageState("tnr-white", "", Color(255, 255, 255, 255))
end

-- LuaSTG uses Lua 5.1/LuaJIT while catalog tests use Lua 5.4. Compile
-- original constructor expressions in either runtime without substituting
-- unresolved values.
local function compile_in_environment(source, chunk_name, environment)
    if type(loadstring) == "function" then
        local chunk, compile_error = loadstring(source, chunk_name)
        if chunk and type(setfenv) == "function" then
            setfenv(chunk, environment)
        end
        if chunk then
            return chunk
        end
    end
    local ok, chunk, compile_error = pcall(load, source, chunk_name, "t", environment)
    if ok and chunk then
        return chunk
    end
    return chunk, compile_error
end

local function seeded_value(seed, salt)
    -- Deterministic room composition keeps network peers in lockstep while
    -- making adjacent map nodes visibly different.
    return (math.floor(tonumber(seed) or 1) + salt * 1103515245 + 12345) % 2147483647
end

local legacy_enemy_wave_catalog = require("tnr.stages.legacy_enemy_waves")
local legacy_stage_music = require("tnr.stages.legacy_stage_music")

local function find_legacy_enemy_wave(wave_id)
    for _, stage in ipairs(legacy_enemy_wave_catalog) do
        for _, wave in ipairs(stage.waves or {}) do
            if wave.id == wave_id then
                return wave, stage
            end
        end
    end
    return nil
end

local function music_for_legacy_stage(stage_id)
    return legacy_stage_music[tostring(stage_id or "")]
end

local function normal_legacy_waves()
    local result = {}
    for _, stage in ipairs(legacy_enemy_wave_catalog) do
        if tostring(stage.source_stage):match("@Normal$") then
            for _, wave in ipairs(stage.waves or {}) do
                result[#result + 1] = wave
            end
        end
    end
    return result
end

local function build_native_enemy_specs(wave, seed)
    local specs = {}
    local members = wave and wave.members or {}
    for index, member in ipairs(members) do
        specs[#specs + 1] = {
            class_name = member.class_name,
            args = member.args,
            env = member.env,
            -- The catalog stores the original relative timeline. Keep it on
            -- the runtime spec so the native bridge can spawn formations at
            -- their source frame instead of collapsing the whole wave into
            -- frame zero.
            spawn_frame = tonumber(member.spawn_frame) or 0,
            index = index,
        }
    end
    return specs
end

local function substitute_captured_scalar(expression, name, replacement)
    -- Lua patterns have no look-behind.  Match the token together with its
    -- surrounding characters so object fields such as `player.x` remain
    -- fields instead of becoming the invalid `player.(220)`.  Keep table keys
    -- (`x=...`) intact for the same reason.
    local result = " " .. tostring(expression) .. " "
    local escaped_name = tostring(name):gsub("([%%%+%-%*%?%[%]%^%$%(%)%.])", "%%%1")
    result = result:gsub("([^%w_%.])(" .. escaped_name .. ")([^%w_])", function(prefix, token, suffix)
        if suffix == "=" then
            return prefix .. token .. suffix
        end
        return prefix .. "(" .. tostring(replacement) .. ")" .. suffix
    end)
    return result:sub(2, -2)
end

local function expand_captured_scalar(expression, expression_env)
    local result = tostring(expression)
    for _ = 1, 8 do
        local previous = result
        for name, value in pairs(expression_env) do
            if type(value) == "number" then
                result = substitute_captured_scalar(result, name, value)
            elseif type(value) == "string"
                    and not value:find("[{}:]")
                    and not value:find("%.new%s*%(") then
                result = substitute_captured_scalar(result, name, value)
            end
        end
        if result == previous then break end
    end
    return result
end

local function evaluate_native_enemy_args(spec, runtime_context, class_environment)
    local source_args = spec.args or {}
    local argument_count = #source_args
    local values = {}
    local expression_env = {
        math = math,
        sin = math.sin, cos = math.cos, tan = math.tan,
        pi = math.pi,
        ran = rawget(_G, "ran"),
        self = runtime_context,
    }
    -- Resolve source environment expressions against the enemy constructor's
    -- original DoFile environment first, then the global namespace. Imported
    -- activity files keep helpers such as karl_bullet_initializer in their
    -- per-file environment; looking only in _G turns those helpers into nil.
    setmetatable(expression_env, {
        __index = function(_, key)
            if class_environment and class_environment[key] ~= nil then
                return class_environment[key]
            end
            return _G[key]
        end,
    })
    local pending_env = {}
    for name, expression in pairs(spec.env or {}) do
        if type(expression) == "number" then
            expression_env[name] = expression
        elseif type(expression) == "string" then
            local literal = tonumber(expression)
            if literal ~= nil then
                expression_env[name] = literal
            else
                pending_env[#pending_env + 1] = { name = name, expression = expression }
            end
        end
    end
    -- Captured locals can depend on one another (for example `x=220*side`).
    -- Resolve them in passes so table iteration order cannot make a valid
    -- original expression disappear.
    local pending_names = {}
    for _, item in ipairs(pending_env) do
        pending_names[item.name] = true
    end
    local function expression_waits_for_pending_name(expression, current_name)
        expression = tostring(expression or "")
        for name in pairs(pending_names) do
            if name ~= current_name
                    and expression:match("%f[%a_]" .. name .. "%f[^%w_]") then
                return true
            end
        end
        return false
    end
    for _ = 1, #pending_env do
        if #pending_env == 0 then break end
        local unresolved = {}
        local progress = false
        for _, item in ipairs(pending_env) do
            if expression_waits_for_pending_name(item.expression, item.name) then
                unresolved[#unresolved + 1] = item
            else
                local chunk, compile_error = compile_in_environment("return " .. item.expression, "legacy_enemy_env", expression_env)
                -- Keep the pcall in its own statement.  `chunk and pcall(chunk)`
                -- is a non-final boolean expression in Lua and therefore
                -- discards pcall's return value, making every valid captured
                -- environment expression look unresolved.
                local ok, value
                if chunk then
                    ok, value = pcall(chunk)
                end
                if ok and value ~= nil then
                    expression_env[item.name] = value
                    pending_names[item.name] = nil
                    progress = true
                else
                    item.compile_error = compile_error or value
                    unresolved[#unresolved + 1] = item
                end
            end
        end
        pending_env = unresolved
        if not progress then break end
    end
    for _, item in ipairs(pending_env) do
        if item.expression ~= "nil" then
            print(string.format("TNR legacy env unresolved %s=%s (%s)", tostring(item.name), tostring(item.expression), tostring(item.compile_error)))
        end
    end
    for index, expression in ipairs(source_args) do
        -- The reference editor serializes an explicit nil argument as `_`.
        -- It is a valid positional argument and must not be treated as an
        -- unresolved expression (several enemy constructors depend on the
        -- following arguments retaining their original positions).
        local normalized_expression = type(expression) == "string"
            and expression:gsub("^%s+", ""):gsub("%s+$", "")
            or expression
        if normalized_expression == "_" or normalized_expression == "nil" then
            values[index] = nil
        else
        local resolved_expression = expand_captured_scalar(expression, expression_env)
        for name, value in pairs(expression_env) do
            if type(value) == "number" then
                resolved_expression = substitute_captured_scalar(resolved_expression, name, value)
            end
        end
        local direct_value = tonumber(resolved_expression)
        local chunk, compile_error
        if direct_value == nil then
            chunk, compile_error = compile_in_environment("return " .. resolved_expression, "legacy_enemy_arg", expression_env)
        end
        local ok, value = direct_value ~= nil, direct_value
        if not ok or value == nil then
            if chunk then ok, value = pcall(chunk) end
        end
        if not ok or value == nil then
            print(string.format("TNR legacy arg unresolved %d=%s -> %s (%s; d1=%s/%s ran=%s)", index, tostring(expression), tostring(resolved_expression), tostring(compile_error or value), tostring(expression_env.d1), type(expression_env.d1), type(expression_env.ran)))
            return nil
        end
        values[index] = value
        end
    end
    return values, argument_count
end

local function sorted_short_bosses()
    local result = {}
    for name, class in pairs(_editor_class or {}) do
        if type(name) == "string" and name:match(":Normal$") and type(class) == "table"
                and type(class.cards) == "table" and #class.cards > 0 and #class.cards < 3 then
            result[#result + 1] = name
        end
    end
    table.sort(result)
    return result
end

local function select_native_boss(seed, elite)
    local main = { "Reimu:Normal", "Marisa:Normal", "Sanae:Normal", "Mystia:Normal", "Larva:Normal", "Cirno:Normal", "Junko:Normal" }
    local pool = elite and sorted_short_bosses() or {}
    if not elite then
        for _, name in ipairs(main) do
            local class = _editor_class and _editor_class[name]
            if class and type(class.cards) == "table" and #class.cards > 0 then
                pool[#pool + 1] = name
            end
        end
    end
    if #pool == 0 then pool = main end
    local index = (math.floor(tonumber(seed) or 1) % #pool) + 1
    local name = pool[index]
    return _editor_class[name], name
end

local function valid_catalog_card(card, require_spell)
    if type(card) ~= "table" or card.legacy_exact ~= true then
        return false
    end
    if require_spell ~= nil and (card.is_spell == true) ~= require_spell then
        return false
    end
    local class = _editor_class and _editor_class[card.legacy_boss]
    local slot = tonumber(card.legacy_card_slot)
    local native_card = class and class.cards and slot and class.cards[slot]
    return class ~= nil and type(class.cards) == "table"
        and type(native_card) == "table" and native_card.is_combat == true
        and type(native_card.init) == "function"
end

local function catalog_cards(require_spell, elite_only, pool_filter)
    local module_name = require_spell and "tnr.training.card_training_catalog"
        or "tnr.training.nonspell_training_catalog"
    local source = require(module_name)
    local result = {}
    for _, card in ipairs(source) do
        local class = _editor_class and _editor_class[card.legacy_boss]
        if valid_catalog_card(card, require_spell)
                and (not elite_only or (class and #class.cards < 3))
                and (not pool_filter or pool_filter(card.legacy_boss)) then
            result[#result + 1] = card
        end
    end
    table.sort(result, function(left, right) return left.id < right.id end)
    return result
end

local function select_catalog_card(seed, require_spell, elite_only, salt, pool_filter)
    local pool = catalog_cards(require_spell, elite_only, pool_filter)
    if #pool == 0 and elite_only then
        pool = catalog_cards(require_spell, false, pool_filter)
    end
    if #pool == 0 and pool_filter then
        -- The floor pool may not contain a usable card for this room type;
        -- widen to the full catalog rather than failing the room.
        pool = catalog_cards(require_spell, elite_only)
    end
    if #pool == 0 and elite_only then
        pool = catalog_cards(require_spell, false)
    end
    if #pool == 0 then
        return nil, nil, nil
    end
    local index = (seeded_value(seed, salt or 0) % #pool) + 1
    local card = pool[index]
    local class = _editor_class[card.legacy_boss]
    return card, class, tonumber(card.legacy_card_slot)
end

-- Exported Boss classes usually begin at y=600 and may rely on a preceding
-- movement entry to enter the playfield. Preserve only that safe prefix when
-- a room starts at a selected card.
local function build_native_card_sequence(class, slot)
    if not class or type(class.cards) ~= "table" or not slot then
        return nil
    end
    local selected = class.cards[slot]
    if type(selected) ~= "table" then
        return nil
    end
    local cards = { selected }
    -- Walk backwards to recover the entrance movement that places the Boss on
    -- screen. Dialogues must never be included (they wait on UI input), but
    -- they must not stop the walk either: the reference stage order is often
    -- `move -> dialog -> card`, so skipping the dialog is the only way to find
    -- the entrance move. Without it the Boss stays off screen and the room
    -- shows no Boss at all (for example the Cirno non-spell).
    local pending_moves = {}
    for previous_index = slot - 1, 1, -1 do
        local previous = class.cards[previous_index]
        if not previous then
            break
        end
        if previous.is_combat == true then
            -- Another combat card precedes this one; keep the selection scoped.
            break
        end
        if previous.is_dialog then
            -- Skip the dialogue but keep looking for the entrance move.
        elseif previous.is_move then
            table.insert(pending_moves, 1, previous)
        else
            break
        end
    end
    for _, move in ipairs(pending_moves) do
        table.insert(cards, 1, move)
    end
    return cards
end

local function native_read_boss_status(boss)
    if not native_is_valid_object(boss) then
        return nil
    end
    local ok, status = pcall(function()
        local combat = boss.is_combat == true
        local maxhp = tonumber(boss.maxhp)
        local hp = tonumber(boss.hp)
        -- Legacy movement/dialogue cards use a 999999999 placeholder HP.
        -- Do not publish that transient state as a combat HP snapshot.
        if not combat or not maxhp or maxhp <= 0 or maxhp >= 100000000
                or not hp then
            return { combat = false }
        end
        return {
            combat = true,
            hp = math.max(0, math.min(hp, maxhp)),
            maxhp = maxhp,
            timer = tonumber(boss.timer),
            card_num = tonumber(boss.card_num),
        }
    end)
    if not ok or not status or not status.combat then
        return nil
    end
    return status
end

local function native_apply_boss_status(boss, snapshot, allow_dead)
    if not native_is_valid_object(boss) or type(snapshot) ~= "table" then
        return
    end
    -- Never apply a peer's transient entrance/movement placeholder. The
    -- combat card must have called setStatus locally before HP is shared.
    local combat = boss.is_combat == true
    if not combat then
        return
    end
    local maxhp = tonumber(snapshot.boss_maxhp)
    local hp = tonumber(snapshot.boss_hp)
    local incoming_card = tonumber(snapshot.boss_card_num)
    local local_card = tonumber(boss.card_num)
    -- Both peers execute the original card sequence locally. A delayed packet
    -- from the previous card must never overwrite the newly initialized
    -- card's HP bar; wait for a snapshot carrying the same card number.
    if incoming_card and local_card and incoming_card ~= local_card then
        return
    end
    if maxhp and maxhp > 0 and maxhp < 100000000 then
        boss.maxhp = maxhp
    end
    local effective_maxhp = tonumber(boss.maxhp)
    if effective_maxhp and effective_maxhp > 0 and effective_maxhp < 100000000 and hp then
        boss.hp = math.max(0, math.min(hp, effective_maxhp))
        -- boss_system normally refreshes this every frame; update immediately
        -- so a network correction can never render a stale/tiny bar.
        boss.hpbarlen = boss.hp / effective_maxhp
    end
    if snapshot.boss_timer ~= nil and (not incoming_card or not local_card or incoming_card == local_card) then
        local timer = tonumber(snapshot.boss_timer)
        if timer then boss.timer = timer end
    end
    if allow_dead and snapshot.boss_alive == false then
        boss.hp = 0
        boss.hpbarlen = 0
    end
end

local function select_catalog_wave(seed)
    local source = require("tnr.training.enemy_training_catalog")
    local pool = {}
    for _, wave in ipairs(source) do
        if wave.legacy_exact == true and (tonumber(wave.duration_seconds) or 0) >= 10
                and type(wave.members) == "table" and #wave.members > 0 then
            local has_loaded_class = false
            for _, member in ipairs(wave.members) do
                if type(member) == "table" and _editor_class[member.class_name] then
                    has_loaded_class = true
                    break
                end
            end
            if has_loaded_class then
                pool[#pool + 1] = wave
            end
        end
    end
    if #pool == 0 then return nil end
    table.sort(pool, function(left, right) return left.id < right.id end)
    return pool[(seeded_value(seed, 17) % #pool) + 1]
end

-- Ordinary rooms select a wave whose content-based difficulty tier matches the
-- node's six-band progression. Falls back to the nearest available band so a
-- thin band can never leave the room empty.
local WaveDifficulty = require("tnr.stages.wave_difficulty")
local function select_catalog_wave_for_band(seed, band)
    local source = require("tnr.training.enemy_training_catalog")
    local target = math.max(1, math.min(6, math.floor(tonumber(band) or 1)))
    local by_band = {}
    for _, wave in ipairs(source) do
        if wave.legacy_exact == true and (tonumber(wave.duration_seconds) or 0) >= 10
                and type(wave.members) == "table" and #wave.members > 0 then
            local has_loaded_class = false
            for _, member in ipairs(wave.members) do
                if type(member) == "table" and _editor_class[member.class_name] then
                    has_loaded_class = true
                    break
                end
            end
            if has_loaded_class then
                local tier = WaveDifficulty.tier_of(wave)
                by_band[tier] = by_band[tier] or {}
                by_band[tier][#by_band[tier] + 1] = wave
            end
        end
    end
    -- Prefer the exact band; otherwise widen outward until a tier is found.
    local chosen
    for offset = 0, 5 do
        for _, candidate in ipairs({ target - offset, target + offset }) do
            if not chosen and by_band[candidate] and #by_band[candidate] > 0 then
                chosen = by_band[candidate]
            end
        end
        if chosen then break end
    end
    if not chosen then return select_catalog_wave(seed) end
    table.sort(chosen, function(left, right) return left.id < right.id end)
    return chosen[(seeded_value(seed, 29 + target) % #chosen) + 1]
end

local function select_native_nonspell(class)
    if not class or type(class.cards) ~= "table" then
        return nil
    end
    for index, card in ipairs(class.cards) do
        if type(card) == "table" and card.is_combat == true and card.is_sc ~= true
                and type(card.init) == "function" then
            return card, index
        end
    end
    return nil
end

local function restore_project_ui_image()
    -- Native stage resource changes can evict project-global UI images. Keep
    -- the map renderer's primitive available in the active stage status.
    if lstg and lstg.LoadTexture and lstg.LoadImage then
        pcall(lstg.LoadTexture, "tnr-white-texture", "assets/texture/white.png", false)
        pcall(lstg.LoadImage, "tnr-white", "tnr-white-texture", 0, 0, 16, 16)
        if lstg.LoadTTF then
            pcall(lstg.LoadTTF, "Sans", "assets/font/SourceHanSansCN-Bold.otf", 48, 48)
        end
    end
end

-- THlib predates the current LuaSTG entry point and expects Include to be
-- available.  Map it to the engine's resource-aware DoFile implementation.
do
    local engine_include = rawget(_G, "Include")
    function Include(path)
        if type(path) == "string" then
            path = path:gsub("^THlib[/\\]", "LegacyTHlib/")
        end
        if type(engine_include) == "function" then
            return engine_include(path)
        end
        return lstg.DoFile(path)
    end
end

local function normalize_legacy_path(path)
    if type(path) ~= "string" then
        return path
    end
    return path:gsub("^THlib[/\\]", "Thlib/")
end

local function patch_loader(name)
    local original = lstg[name]
    if type(original) ~= "function" then
        return
    end

    local function file_exists(path)
        return lstg.FileManager
            and type(lstg.FileManager.FileExist) == "function"
            and lstg.FileManager.FileExist(path)
    end

    lstg[name] = function(resource, path, ...)
        local normalized = normalize_legacy_path(path)
        if name == "LoadFX" and resource == "er_desaturate" then
            -- The exported FX uses D3D9 effect syntax. This composite is
            -- required to present Tenka's scene, so load the D3D11 port and
            -- report any failure here instead of leaving an absent effect.
            return original(resource, "shader/er_desaturate.hlsl", ...)
        end
        if name == "LoadMusic" and type(normalized) == "string" then
            -- The exported scripts refer to music by its original basename
            -- (for example, `BGM-TKZ-1.ogg`). Resolve that basename to the
            -- imported original asset without silently substituting another BGM.
            local basename = normalized:match("[^/\\]+$")
            local imported = basename and ("assets/audio/music/" .. basename)
            if imported and file_exists(imported) then
                normalized = imported
            end
        elseif name == "LoadSound" and type(normalized) == "string" then
            -- Reference exports pass only a basename (for example
            -- `tan00.wav` or `one07.wav`). Resolve it against both imported
            -- sound roots before using the compatibility fallback; otherwise
            -- every missing path becomes the same tan00 click.
            local basename = normalized:match("[^/\\]+$")
            local imported_se = basename and ("assets/audio/se/" .. basename)
            local imported_music = basename and ("assets/audio/music/" .. basename)
            if imported_se and file_exists(imported_se) then
                normalized = imported_se
            elseif imported_music and file_exists(imported_music) then
                normalized = imported_music
            elseif not file_exists(normalized) then
                normalized = "assets/audio/se/se_tan00.wav"
            end
        end
        local ok, result = pcall(original, resource, normalized, ...)
        if ok then
            return result
        end
        -- The activity export does not ship every optional THlib HUD sheet.
        -- Reuse the canonical boss sheet for those UI-only resources so the
        -- actual card scripts can still run.
        if type(normalized) == "string" and normalized:match("^Thlib/enemy/") then
            return original(resource, "Thlib/enemy/boss.png", ...)
        end
        if type(normalized) == "string" and normalized:match("%.[Ww][Aa][Vv]$") then
            return original(resource, "assets/audio/se/se_tan00.wav", ...)
        end
        if name == "LoadFX" then
            -- A few reference scripts use paths relative to the original
            -- data root. Try the mounted project path variants before giving
            -- up, so optional effects such as fx_switch can be registered.
            local candidates = {
                normalized,
                type(normalized) == "string" and normalized:gsub("^shader[/\\]", "legacy/data/shader/") or nil,
                type(normalized) == "string" and normalized:gsub("^shader[/\\]", "data/shader/") or nil,
                type(normalized) == "string" and normalized:gsub("^shader[/\\]", "legacy/assets/data/shader/") or nil,
                type(normalized) == "string" and normalized:gsub("^shader[/\\]", "assets/data/shader/") or nil,
            }
            for _, candidate in ipairs(candidates) do
                if candidate and candidate ~= normalized then
                    local retry_ok, retry_result = pcall(original, resource, candidate, ...)
                    if retry_ok then return retry_result end
                end
            end
            return nil
        end
        if name == "LoadMusic" then
            error("original BGM resource not found: " .. tostring(normalized) .. "; copy the exact file into game/assets/audio/music")
        end
        error(result)
    end
    _G[name] = lstg[name]
end

for _, loader in ipairs({ "LoadTexture", "LoadSound", "LoadMusic", "LoadImageFromFile", "LoadAnimation", "LoadPS", "LoadFont", "LoadFX" }) do
    patch_loader(loader)
end

local function load_legacy_content()
    local ok, err = pcall(function()
        -- Bring up the same object/task/stage primitives used by the reference
        -- project without loading its launcher scene.
        require("gconfig")
        require("gconfig_auto")
        lstg.DoFile("lib/Lapi.lua")
        lstg.DoFile("lib/Lkeycode.lua")
        require("foundation.legacy.userdata")
        require("foundation.legacy.setting")
        -- Migrate the old THlib default (640x480) when it is still present in
        -- a local setting file. Custom user resolutions are left untouched.
        if setting and setting.resx == 640 and setting.resy == 480 then
            setting.resx, setting.resy = 1280, 720
        end
        require("foundation.legacy.scoredata")
        setting.mod = setting.mod or "TouHouNightReign"
        lstg.DoFile("lib/Llog.lua")
        lstg.DoFile("lib/Lglobal.lua")
        lstg.DoFile("lib/Lmath.lua")
        lstg.DoFile("plus/plus.lua")
        lstg.DoFile("lib/Lobject.lua")
        lstg.DoFile("lib/Lresources.lua")
        lstg.DoFile("lib/Lscreen.lua")
        lstg.DoFile("lib/Linput.lua")
        task = require("lib.Ltaskmove")
        lstg.DoFile("lib/Lstage.lua")
        lstg.DoFile("lib/Ltext.lua")
        lstg.DoFile("lib/Lplugin.lua")
        -- The exported Reimu frame function uses the legacy global
        -- KeyIsDown API directly. Bridge project-polled input into that API
        -- while preserving physical-key fallback for standalone THlib code.
        legacy_key_is_down = rawget(_G, "KeyIsDown")
        legacy_key_is_pressed = rawget(_G, "KeyIsPressed")
        KeyIsDown = function(key)
            if native_room_started and native_virtual_keys[key] ~= nil then
                return native_virtual_keys[key] == true
            end
            return legacy_key_is_down and legacy_key_is_down(key) or false
        end
        KeyIsPressed = function(key)
            if native_room_started and native_virtual_keys[key] ~= nil then
                return native_virtual_keys[key] == true and native_virtual_keys_previous[key] ~= true
            end
            return legacy_key_is_pressed and legacy_key_is_pressed(key) or false
        end
        KeyPress = KeyIsDown
        KeyTrigger = KeyIsPressed
        -- A few resource helpers are intentionally absent from the compact
        -- compatibility Lapi, but the reference THlib expects them globally.
        CopyImage = lstg.CopyImage
        local create_dispatcher = require("foundation.EventDispatcher")
        lstg.globalEventDispatcher = create_dispatcher()
        eventListener = create_dispatcher
        IntersectionDetectionManager = require("foundation.IntersectionDetectionManager")
        local engine_include = rawget(_G, "Include")
        local engine_dofile = rawget(_G, "DoFile")
        function DoFile(path)
            if type(path) == "string" then
                path = path:gsub("^THlib[/\\]", "LegacyTHlib/")
            end
            if type(engine_dofile) == "function" then
                return engine_dofile(path)
            end
            return lstg.DoFile(path)
        end
        function Include(path)
            if type(path) == "string" then
                path = path:gsub("^THlib[/\\]", "LegacyTHlib/")
            end
            if type(engine_include) == "function" then
                return engine_include(path)
            end
            return lstg.DoFile(path)
        end
        -- Missing optional post-effect resources should not abort an otherwise
        -- playable card. Keep the original call for valid effects and skip
        -- only the known legacy effect when its shader could not be compiled.
        local native_post_effect = rawget(lstg, "PostEffect") or rawget(_G, "PostEffect")
        if type(native_post_effect) == "function" then
            local function safe_post_effect(render_target, effect_name, ...)
                -- fx_switch is an optional transition effect in the exported
                -- activity.  Some installations do not compile the legacy
                -- shader; treat that transition as a no-op instead of
                -- aborting the whole frame.  Other effects retain native
                -- error behavior so genuine rendering bugs remain visible.
                if effect_name == "fx_switch" then
                    local ok_call, result = pcall(native_post_effect, render_target, effect_name, ...)
                    if ok_call then return result end
                    if tostring(result):lower():match("posteffect.*not found")
                            or tostring(result):lower():match("effect.*not found")
                            or tostring(result):lower():match("fx_switch.*not found") then
                        return nil
                    end
                    error(result, 0)
                end
                return native_post_effect(render_target, effect_name, ...)
            end
            -- Patch the namespace function as well as the global alias.  A
            -- later Lapi/THlib include can recreate the alias from lstg, but
            -- it cannot bypass this namespace-level wrapper.
            lstg.PostEffect = safe_post_effect
            PostEffect = safe_post_effect
        end
        -- The activity editor assumes these classic THlib sheets were loaded
        -- by the original project root. Load them before THlib's laser module,
        -- which creates its node image group from `bullet1` during Include.
        for index = 1, 6 do
            local path = "Thlib/bullet/bullet" .. index .. ".png"
            pcall(lstg.LoadTexture, "bullet" .. index, path, true)
        end
        Include("THlib.lua")
        -- Dialogue override hook. The reference export hard-codes its boss
        -- conversations; when the extracted JSON has a matching entry the text
        -- argument is replaced so the conversation can be edited without
        -- touching the compiled scripts. Missing entries keep the original.
        if boss and boss.dialog and type(boss.dialog.sentence) == "function" then
            local native_sentence = boss.dialog.sentence
            boss.dialog.sentence = function(self, image, position, text, ...)
                local override = DialogOverride.next_text and DialogOverride.next_text() or nil
                if override ~= nil and override ~= "" then text = override end
                return native_sentence(self, image, position, text, ...)
            end
        end
        -- Native rooms are driven by the same LegacyTHlib player system as
        -- the reference game. That system reads the replay action state for
        -- movement, so keep a direct handle for network-frame injection.
        native_input_replay = require("foundation.input.replay")
        spellcard_background = spellcard_background or default_spellcard_background or _spellcard_background
        -- Character scripts are separate from THlib.lua in the reference
        -- project; load each playable character explicitly so native rooms use
        -- the real shot, focus and bomb implementation for the selected
        -- character. A missing character script is skipped so the others still
        -- load.
        for _, character_path in ipairs({
            "Thlib/player/reimu/reimu.lua",
            "Thlib/player/marisa/marisa.lua",
            "Thlib/player/sanae/sanae.lua",
        }) do
            local ok_character, character_error = pcall(lstg.DoFile, character_path)
            if not ok_character then
                print("TNR legacy character load failed " .. character_path
                    .. ": " .. tostring(character_error))
            end
        end
        local classic_groups = {
            { "preimg", 80, 0, 32, 32, 1, 8 },
            { "arrow_big", 0, 0, 16, 16, 1, 16 },
            { "gun_bullet", 24, 0, 16, 16, 1, 16 },
            { "gun_bullet_void", 56, 0, 16, 16, 1, 16 },
            { "butterfly", 112, 0, 32, 32, 1, 8 },
            { "square", 152, 0, 16, 16, 1, 16 },
            { "ball_mid", 176, 0, 32, 32, 1, 8 },
            { "ellipse", 224, 0, 32, 32, 1, 8 },
            { "ball_big", 176, 0, 32, 32, 1, 8 },
            { "ball_light", 176, 0, 32, 32, 1, 8 },
            { "ball_small", 208, 0, 16, 16, 1, 16 },
            { "grain_a", 208, 0, 16, 16, 1, 16 },
            { "grain_b", 208, 0, 16, 16, 1, 16 },
            { "grain_c", 208, 0, 16, 16, 1, 16 },
            { "star_small", 224, 0, 32, 32, 1, 8 },
            { "star_big", 224, 0, 32, 32, 1, 8 },
            { "heart", 112, 0, 32, 32, 1, 8 },
            { "knife", 0, 0, 16, 16, 1, 16 },
            { "knife_b", 0, 0, 16, 16, 1, 16 },
            { "arrow_small", 0, 0, 16, 16, 1, 16 },
            { "arrow_mid", 0, 0, 16, 16, 1, 16 },
            { "water_drop", 176, 0, 32, 32, 1, 8 },
            { "music", 152, 0, 16, 16, 1, 16 },
            { "silence", 152, 0, 16, 16, 1, 16 },
            { "money", 152, 0, 16, 16, 1, 16 },
            { "mildew", 208, 0, 16, 16, 1, 16 },
            { "ball_huge", 176, 0, 32, 32, 1, 8 },
            { "ball_huge_dark", 176, 0, 32, 32, 1, 8 },
            { "ball_light_dark", 176, 0, 32, 32, 1, 8 },
        }
        for _, group in ipairs(classic_groups) do
            pcall(LoadImageGroup, group[1], "bullet1", group[2], group[3], group[4], group[5], group[6], group[7], 1, 1)
            pcall(LoadImageGroup, "fade_" .. group[1], "bullet1", group[2], group[3], group[4], group[5], group[6], group[7], 1, 1)
            for frame = 9, 16 do
                pcall(CopyImage, group[1] .. frame, group[1] .. "1")
                pcall(CopyImage, "fade_" .. group[1] .. frame, "fade_" .. group[1] .. "1")
            end
        end
        -- The editor uses colour-suffixed variants that are not present in
        -- the compact THlib atlas. Reuse the matching original frame; this
        -- preserves the class and timing logic while keeping every projectile
        -- constructible in the native object pool.
        for _, prefix in ipairs({ "ball_mid_b", "ball_mid_c", "ball_mid_d" }) do
            for frame = 1, 16 do
                local source = "ball_mid" .. frame
                local target = prefix .. frame
                pcall(CopyImage, target, source)
            end
        end
        -- Water-drop bullets are animated sprites, not frames in bullet1.
        -- The activity export uses both the normal and dark variants.
        pcall(LoadTexture, "bullet_water_drop", "Thlib/bullet/bullet_water_drop.png", true)
        -- Bullet frame indices span 1..16 (see LegacyTHlib/bullet/bullet.lua),
        -- but the water-drop sheet only carries 8 distinct frames. Load all
        -- 16 animation names, mapping 9..16 back onto frames 1..8, so a
        -- `water_drop_dark9..16` lookup can never fail at runtime.
        for index = 1, 16 do
            local source_index = ((index - 1) % 8) + 1
            local x = 48 * (source_index - 1)
            pcall(LoadAnimation, "water_drop" .. index, "bullet_water_drop", x, 0, 48, 32, 1, 4, 4, 4, 4)
            pcall(SetAnimationState, "water_drop" .. index, "mul+add")
            pcall(LoadAnimation, "water_drop_dark" .. index, "bullet_water_drop", x, 0, 48, 32, 1, 4, 4, 4, 4)
        end
        -- Older activity background scripts refer to this helper table while
        -- defining their concrete background class.
        starlight_background = { frame = function() end }
        Include("_editor_output.lua")
        -- The reference launcher invokes these resource registration helpers
        -- from each stage script.  Training and roguelike rooms jump directly
        -- to a card, so that launcher path is skipped.  Register the original
        -- helper assets once after the export has defined them; this keeps the
        -- card logic and resource names intact instead of substituting assets.
        for _, resource_loader_name in ipairs({
            "lico_dialog_res", "xy_dialog_res", "qxs_dialog_res",
            "karl_dialog_res", "kbz_dialog_res", "ae_dialog_res",
            "void_dialog_res", "wyj_dialog_res", "yyzy_dialog_res",
            "wuer_dialog_res", "yh_dialog_res", "staff_res",
        }) do
            local resource_loader = rawget(_G, resource_loader_name)
            if type(resource_loader) == "function" then
                local resource_ok, resource_error = pcall(resource_loader)
                if not resource_ok then
                    print("TNR legacy resource init failed " .. resource_loader_name
                        .. ": " .. tostring(resource_error))
                end
            end
        end
    end)
    if not ok then
        load_error = tostring(err)
        print("TNR native legacy load failed: " .. load_error)
        return false
    end
    legacy_loaded = true
    return true
end

local function setup_native_stage()
    if not legacy_loaded then
        return
    end
    -- Some imported cards adjust their BGM volume during the first task
    -- frame, before their normal entrance code calls LoadMusicRecord.  Keep
    -- the original resource name and recording parameters, but lazily load
    -- that record before the engine receives PlayMusic/SetBGMVolume.
    if not rawget(_G, "__tnr_music_guards") then
        local native_play_music = rawget(_G, "PlayMusic")
        local native_set_bgm_volume = rawget(_G, "SetBGMVolume")
        PlayMusic = function(name, ...)
            local audio = rawget(_G, "__tnr_audio_manager")
            if audio and type(audio.play_original) == "function" then
                return audio:play_original(name, ...)
            end
            if type(LoadMusicRecord) == "function" then
                pcall(LoadMusicRecord, name)
            end
            return native_play_music(name, ...)
        end
        SetBGMVolume = function(name, ...)
            local audio = rawget(_G, "__tnr_audio_manager")
            if audio and type(audio.set_original_volume) == "function" then
                return audio:set_original_volume(name, ...)
            end
            if type(LoadMusicRecord) == "function" then
                pcall(LoadMusicRecord, name)
            end
            return native_set_bgm_volume(name, ...)
        end
        _G.PlayMusic = PlayMusic
        _G.SetBGMVolume = SetBGMVolume
        _G.__tnr_music_guards = true
    end
    lstg.RegisterAllGameObjectClass()
    item.PlayerInit()
    InitScoreData()
    -- Drop substitution: half of the original power drops become money drops
    -- instead. The reference `item.DropItem` is wrapped rather than edited so
    -- the imported THlib source stays pristine and the change is reviewable.
    -- Money keeps the power drop's 1-unit value and counts toward the stage
    -- score exactly like the power it replaces.
    if item and type(item.DropItem) == "function" and not _G.__tnr_money_drop_installed then
        _G.__tnr_money_drop_installed = true
        local native_original_drop_item = item.DropItem
        -- Money substitution uses the shared legacy RNG so both LAN peers
        -- produce the same drop layout for the same room seed.
        local function native_random_money_drop()
            if ran and type(ran.Float) == "function" then
                return ran:Float(0, 1) < 0.5
            end
            return math.random() < 0.5
        end
        local function native_random_range(minimum, maximum)
            if ran and type(ran.Float) == "function" then
                return ran:Float(minimum, maximum)
            end
            return minimum + math.random() * (maximum - minimum)
        end
        -- Money pickup: subclasses the point item so it reuses the exact
        -- attraction, collection and render logic. Only `collect` changes, so
        -- it credits money (and the stage score) instead of points.
        local native_money_class = nil
        local function native_money_item_class()
            if native_money_class then return native_money_class end
            native_money_class = Class(item_point)
            function native_money_class:collect()
                local var = lstg.var
                var.tnr_stage_money = (tonumber(var.tnr_stage_money) or 0) + 1
                -- Money is worth the power unit it replaced and also counts
                -- toward the stage score.
                var.score = (tonumber(var.score) or 0) + 100
                New(float_text, 'item', 100, self.x, self.y + 6, 0.75, 90, 60, 0.5, 0.5,
                    Color(0x80FFE080), Color(0x00FFE080))
                var.itembar[3] = (var.itembar[3] or 0) + 1
            end
            if lstg.RegisterGameObjectClass then
                pcall(lstg.RegisterGameObjectClass, native_money_class)
            end
            return native_money_class
        end
        local function native_spawn_money(x, y)
            return New(native_money_item_class(), x, y)
        end
        item.DropItem = function(x, y, drop)
            -- Keep a pristine copy of the drop table: the reference mutates
            -- drop[1] and drop[4] in place.
            local power = tonumber(drop and drop[1]) or 0
            if power <= 0 then
                return native_original_drop_item(x, y, drop)
            end
            -- Split the power budget into "money or power" per unit so the
            -- total count is preserved while half become money.
            local money_units = 0
            local power_units = 0
            if power >= 400 then
                -- The full-power drop is a single large item; flip it whole.
                if native_random_money_drop() then money_units = 1 else power_units = power end
            else
                local large = math.floor(power / 100)
                local small = power % 100
                for _ = 1, large do
                    if native_random_money_drop() then money_units = money_units + 1 else power_units = power_units + 100 end
                end
                for _ = 1, small do
                    if native_random_money_drop() then money_units = money_units + 1 else power_units = power_units + 1 end
                end
            end
            -- Rebuild a drop table for the remaining power so the original
            -- spawn spread math is reused unchanged.
            if power_units > 0 then
                native_original_drop_item(x, y, { power_units, drop[2], drop[3] })
            end
            for _ = 1, money_units do
                local r2 = math.sqrt(native_random_range(1, 4)) * 5
                local angle = native_random_range(0, 360)
                native_spawn_money(x + r2 * math.cos(math.rad(angle)), y + r2 * math.sin(math.rad(angle)))
            end
            -- Faith and point drops still come from the reference path when
            -- there was no power to convert.
            if power_units <= 0 and (tonumber(drop[2]) or 0) + (tonumber(drop[3]) or 0) > 0 then
                native_original_drop_item(x, y, { 0, drop[2], drop[3] })
            end
        end
    end
    local boss_names = {
        reimu = "Reimu:Normal",
        marisa = "Marisa:Normal",
        sanae = "Sanae:Normal",
        mystia = "Mystia:Normal",
        larva = "Larva:Normal",
        cirno = "Cirno:Normal",
        junko = "Junko:Normal",
        yatsuhashi = "几缟雪嬢:Normal",
        azusa = "明津祢津:Normal",
    }
    local requested_boss = os.getenv("TNR_LEGACY_BOSS") or "reimu"
    local boss_key = boss_names[requested_boss:lower()] or requested_boss
    if not _editor_class[boss_key] then
        boss_key = "Reimu:Normal"
    end
    native_boss_class = _editor_class[boss_key]
    native_index_dialog_blocks(boss_key, native_boss_class)
    local boss_class = native_boss_class
    local card_index = tonumber(os.getenv("TNR_LEGACY_CARD_INDEX")) or 4
    local requested_name = os.getenv("TNR_LEGACY_CARD_NAME")
    if requested_name and boss_class and boss_class.cards then
        for index, candidate in ipairs(boss_class.cards) do
            if candidate.name == requested_name then
                card_index = index
                break
            end
        end
    end
    -- Start in an inert native stage.  Creating a full boss while the project
    -- is still on its menu leaves live legacy callbacks in the object pool;
    -- the first room transition would then fail inside ResetPool().
    native_boss_class = nil
    native_card_list = nil
    native_direct_card = false
    native_room_started = false
    native_stage = stage.New("TNRLegacyCard", true, false)
    -- ext_replay reads the previous stage group while switching stages.
    -- The standalone native stage has no group object, so provide the same
    -- minimal shape used by normal stage groups.
    native_stage.group = { name = "TNRLegacy" }
    function native_stage:init()
        -- Every process owns an independent item pool.  Item collision code
        -- uses this identity to reject the remote player proxy.
        _G.tnr_item_owner_player_id = native_local_player_id
        native_enemy_training_seen_alive = false
        native_bomb_effects = {}
        native_team_wipe_generation = 0
        native_respawn_frames[1], native_respawn_frames[2] = 0, 0
        self.frame_count = 0
        -- Each stage scores independently: reset the reference score and the
        -- money counter at the room boundary so the HUD and the clear payout
        -- only reflect the current stage.
        if lstg.var then
            lstg.var.score = 0
            lstg.var.tnr_stage_money = 0
        end
        native_miss_counts[1], native_miss_counts[2] = 0, 0
        native_bomb_counts[1], native_bomb_counts[2] = 0, 0
        -- Imported activities use the legacy 640x480 world.  A card or room
        -- can leave a camera offset behind when it is restarted, so restore
        -- the canonical world transform before constructing any objects.
        if ResetWorld then
            ResetWorld()
        end
        if ResetWorldOffset then
            ResetWorldOffset()
        end
        -- A number of original card tasks normalize their coordinates against
        -- the legacy world's center before assigning the value themselves.
        -- LuaSTG Sub's modern world table does not expose these two aliases by
        -- default, so create the exact reference defaults at the stage
        -- boundary for every native room.
        -- The exported cards use THlib's `ran` object for spread angles,
        -- timings and effect variants. Seed it from the room content seed so
        -- both LAN peers construct the same native pattern stream.
        local native_seed = math.floor(tonumber(native_room_seed) or 1)
        if native_seed <= 0 then
            native_seed = 1
        end
        if lstg.var then
            lstg.var.ran_seed = native_seed
        end
        if ran and type(ran.Seed) == "function" then
            pcall(ran.Seed, ran, native_seed)
        end
        if lstg.world then
            lstg.world.centerx = tonumber(lstg.world.centerx) or 0
            lstg.world.centery = tonumber(lstg.world.centery) or 0
        end
        -- `_G_shaker` is a legacy global and can retain a userdata from the
        -- previous stage after ResetPool.  ShakeScreen now validates this
        -- reference too, but clear it at the stage boundary so a new room
        -- always starts with a clean camera effect state.
        if lstg.tmpvar then
            lstg.tmpvar._G_shaker = nil
        end
        if SetViewMode then
            SetViewMode("world")
        end
        -- Create the target after stage.Change resets the previous object pool.
        -- Background classes from the reference project read the global
        -- `player` during their first frame, so the player must exist before
        -- the background is allocated.
        native_player = nil
        native_remote_player = nil
        player = nil
        lstg.player = nil
        -- Preserve the local player's independent bomb pool across room
        -- transitions. Respawn handling never writes this value, so a death
        -- or team wipe cannot replenish bombs.
        if native_room_started and lstg.var and native_player_state
                and tonumber(native_player_state.bomb) then
            lstg.var.bomb = math.max(0, tonumber(native_player_state.bomb))
        end
        if native_room_started then
            -- Spawn the native legacy player matching the character chosen on
            -- the select screen. Fall back to Reimu if the class is missing so
            -- a bad id can never leave the room without a player.
            local character_id = native_active_character()
            local player_class = native_player_class_for(character_id) or reimu_player
            native_active_player_class = player_class
            native_player = New(player_class)
            local start_x = native_coop_enabled and (native_local_player_id == 1 and -36 or 36) or 0
            native_player.x, native_player.y = start_x, -176
            native_player.group = GROUP_PLAYER
            native_player.nextspell, native_player.death, native_player.protect = 0, 0, 0
            native_player.colli = true
            native_player.key = native_player.key or {}
            native_player.no_shoot_time = native_player.no_shoot_time or 0
            -- The exported WalkImageSystem expects the frame table on the
            -- system object (the reference player stores it on the player
            -- instance).
            if native_player._wisys then
                native_player._wisys.imgs = native_player.imgs
            end
            native_player.img = native_player.imgs and native_player.imgs[1]
            native_apply_loadout_descriptor(native_player, native_local_loadout_descriptor)
            player = native_player
            lstg.player = native_player
        end
        -- The reference stage creates a scene background before the Boss.
        -- Spell-card scripts use lstg.tmpvar.bg for layer/hide transitions;
        -- allocate it only after `player` is available.
        if native_room_started then
            local background_class = native_boss_class and native_boss_class._bg
            -- Enemy-only waves do not have a Boss class background of their
            -- own. Keep them in an original THlib scene instead of rendering
            -- a black stage; the fallback is an imported reference
            -- background, never a synthetic compatibility image.
            if not background_class then
                background_class = rawget(_G, "XY_Midsummer_background")
                    or rawget(_G, "gzz_stg6bg_background")
                    or rawget(_G, "giantlibrary_background")
            end
            if background_class then
                local ok, scene_bg = pcall(New, background_class)
                if ok then
                    self.background = scene_bg
                end
            end
            if not (lstg.tmpvar and lstg.tmpvar.bg) and default_stage_background then
                local ok, scene_bg = pcall(New, default_stage_background)
                if ok then
                    self.background = scene_bg
                end
            end
        end
        native_enemy_boss_started = false
        if native_mode == "enemy" and native_enemy_specs then
            self.enemy_objects = {}
            self.enemy_schedule_index = 1
            self.enemy_spawned = false
        end
        -- Ordinary rooms begin with the original small-enemy waves. Their
        -- selected nonspell is constructed only after the wave is cleared so
        -- the native Boss entrance sequence cannot overlap the wave.
        if native_mode ~= "enemy" and native_boss_class and native_card_list then
            self.boss = New(native_boss_class, native_card_list)
            FloorBonus.apply(self.boss, native_room_floor, true)
        end
    end
    function native_stage:frame()
        self.frame_count = (self.frame_count or 0) + 1
        if native_mode == "enemy" and native_enemy_specs and self.enemy_objects then
            while self.enemy_schedule_index <= #native_enemy_specs do
                local spec = native_enemy_specs[self.enemy_schedule_index]
                if (spec.spawn_frame or 0) > self.frame_count then
                    break
                end
                local enemy_class = _editor_class[spec.class_name]
                if enemy_class then
                    local class_environment
                    if type(getfenv) == "function" and type(enemy_class.init) == "function" then
                        local env_ok, env = pcall(getfenv, enemy_class.init)
                        if env_ok and type(env) == "table" then
                            class_environment = env
                        end
                    end
                    local args, argument_count = evaluate_native_enemy_args(spec, self, class_environment)
                    local ok, object
                    if args then
                        ok, object = pcall(New, enemy_class, unpack_args(args, 1, argument_count))
                    else
                        print("TNR legacy wave skipped unresolved original arguments: " .. tostring(spec.class_name))
                        ok, object = false, nil
                    end
                    if ok and object then
                        -- Small enemies only receive the last-floor
                        -- amplification, never a floor-1 attenuation.
                        FloorBonus.apply(object, native_room_floor, false)
                        -- Preserve the source spawn index. The host can then
                        -- send a compact death/position state keyed by this
                        -- index, and the client can remove the exact enemy
                        -- without serializing its bullets.
                        self.enemy_objects[spec.index or (#self.enemy_objects + 1)] = object
                    end
                end
                self.enemy_schedule_index = self.enemy_schedule_index + 1
            end
            if self.enemy_schedule_index > #native_enemy_specs then
                self.enemy_spawned = true
                if #native_enemy_specs > 0 and #self.enemy_objects == 0 then
                    native_enemy_training_error = "no enemy object was created from the original constructor arguments"
                end
            end
        end
        -- Native ordinary rooms use the original enemy classes for the wave
        -- phase, then enter a real one-card nonspell with the same Boss
        -- system used by elite and boss rooms.  Stage:frame runs before the
        -- object pool frame, so the transition is observed on the first frame
        -- after the last enemy has actually been deleted.
        if native_mode == "enemy" and not self.boss and self.enemy_objects
                and self.enemy_spawned
                and not native_enemy_boss_started then
            local enemy_alive = false
            for _, enemy_object in pairs(self.enemy_objects) do
                if native_is_valid_object(enemy_object) then
                    enemy_alive = true
                    break
                end
            end
            if not enemy_alive then
                native_enemy_boss_started = true
                if not native_enemy_training_only and native_boss_class and native_card_list then
                    local ok, boss_object = pcall(New, native_boss_class, native_card_list)
                    if ok and boss_object then
                        FloorBonus.apply(boss_object, native_room_floor, true)
                        self.boss = boss_object
                        print("TNR ordinary room entered original nonspell after wave (setup cards="
                            .. tostring(#native_card_list) .. ")")
                    else
                        native_enemy_boss_error = "original nonspell could not be created: " .. tostring(boss_object)
                        print("TNR native ordinary nonspell failed: " .. tostring(boss_object))
                    end
                end
            end
        end
    end
    function native_stage:render()
        if self.boss and self.boss.bg and self.boss.bg.render then
            self.boss.bg:render()
        end
    end
    BeforeRender = BeforeRender or function() end
    AfterRender = AfterRender or function() end
    stage.Set("TNRLegacyCard")
    stage.Change()
    SetResourceStatus("stage")

    -- The native engine invokes these callbacks directly in this project.
    -- Reuse THlib's original update/render order so card tasks, collisions,
    -- spell effects and the boss UI are driven by the reference code.
    FrameFunc = function()
        return DoFrame()
    end
    RenderFunc = function()
        lstg.BeginScene()
        BeforeRender()
        if stage.current_stage and stage.current_stage.render then
            stage.current_stage:render()
        end
        -- Reimu's legacy render override draws support sprites before the
        -- base player renderer and does not check `hide`, so a dead/respawning
        -- player can leave support sprites at their last coordinates.  Hide
        -- the transient layout for this render pass and restore it after the
        -- object pool has been drawn for the next live frame.
        local hidden_player_layout
        if native_player and (native_player.hide or native_runtime_active) then
            hidden_player_layout = native_player.sp
            native_player.sp = {}
        end
        ObjRender()
        if hidden_player_layout and native_player then
            native_player.sp = hidden_player_layout
        end
        -- Draw the remote player after the legacy object pool so background
        -- and boss layers cannot clip it at the upper edge of the playfield.
        native_render_remote_player()
        if native_runtime_active then
            for owner, driver in pairs(native_runtime_drivers) do
                local player = owner == native_local_player_id and native_player or native_remote_player
                if driver and player and not player.hide and not player.hidden then
                    NativeProjectile.render_supports(driver._last_support_state, owner == native_local_player_id and 255 or 180)
                    NativeProjectile.render_streaks(driver, player)
                end
            end
        end
        native_render_aggro_marker()
        native_render_coop_hud()
        AfterRender()
        lstg.EndScene()
    end
    native_render_func = RenderFunc
end

-- `core.lua` installs its own empty GameInit/FrameFunc callbacks.  Perform
-- native setup while this entry script is being evaluated, then install the
-- project callback names afterwards so the engine cannot fall back to the
-- launcher scene.
load_legacy_content()

-- Install after the reference classes are loaded so inherited enemy/boss
-- collision callbacks and the native New/Angle functions are available.
native_install_aggro_hooks()

setup_native_stage()

-- Optional library surface used by the project-owned roguelike adapter. The
-- reference object model is initialized once, then cards can be rebound by
-- changing the Boss class/card list before stage.Change().
do
    local boss_aliases = {
        reimu = "Reimu:Normal", marisa = "Marisa:Normal", sanae = "Sanae:Normal",
        mystia = "Mystia:Normal", larva = "Larva:Normal", cirno = "Cirno:Normal",
        junko = "Junko:Normal",
    }
    local function bridge_boss_key(value)
        value = tostring(value or "reimu")
        return boss_aliases[value:lower()] or value
    end
    local function bridge_start_card(boss_key, card_index, all_cards, card_name, expected_combat)
        native_reset_aggro()
        native_room_generation = native_room_generation + 1
        native_room_started = true
        native_mode = "card"
        native_room_music_hint = nil
        native_direct_card = not all_cards
        native_enemy_training_only = false
        -- Direct card starts are training-room launches by definition. Keep
        -- the guard enabled for older callers that do not pass the optional
        -- argument introduced with the card-slot audit.
        if expected_combat == nil then
            expected_combat = not all_cards
        end
        native_enemy_specs = nil
        native_enemy_training_only = false
        native_enemy_training_error = nil
        native_enemy_boss_error = nil
        native_enemy_boss_started = false
        native_virtual_keys = {}
        native_virtual_keys_previous = {}
        native_reset_bomb_charge()
        native_bomb_generation = 0
        native_last_applied_bomb_generation = 0
        native_last_bomb_owner = nil
        native_last_bomb_focus = false
        native_last_bomb_charged = false
        native_bomb_events = {}
        native_applied_bomb_events = {}
        native_local_bomb_sequences = {}
        native_local_bomb_ticks = {}
        native_reset_remote_bomb_charge()
        native_enemy_kill_generation = 0
        native_enemy_kill_events = {}
        native_enemy_alive_cache = {}
        native_authoritative_enemy_states = nil
        native_authoritative_enemy_initialized = {}
        native_last_applied_enemy_kill_generation = 0
        local class = _editor_class[bridge_boss_key(boss_key)]
        if not class or not class.cards then
            return false, "unknown legacy boss: " .. tostring(boss_key)
        end
        local index = tonumber(card_index) or 4
        if card_name then
            for i, candidate in ipairs(class.cards) do
                if candidate.name == card_name then index = i break end
            end
        end
        local card = class.cards[index]
        if not card then return false, "unknown legacy card index: " .. tostring(index) end
        -- A direct training room must receive a real combat card.  The
        -- reference card arrays also contain dialogue and movement entries;
        -- accepting one here silently creates a room with no bullets and no
        -- HP bar, which is much harder to diagnose than a clear startup
        -- error. Full-room launches intentionally keep the complete list.
        if not all_cards and expected_combat
                and (card.is_combat ~= true or type(card.init) ~= "function") then
            local kind = card.is_move and "movement" or (card.is_dialog and "dialogue" or "non-combat")
            return false, string.format(
                "legacy card slot %d is %s, not a combat card (boss %s)",
                index, kind, tostring(boss_key))
        end
        native_boss_class = class
        native_index_dialog_blocks(boss_key, class)
        if type(class.bgm) == "string" and class.bgm ~= "" then
            native_room_music_hint = class.bgm
        end
        native_room_seed = index
        native_pick_random_focus()
        if all_cards then
            native_card_list = class.cards
        else
            -- Preserve the original entrance/movement segment immediately
            -- before a practiced card. Reference bosses often begin outside
            -- the playfield and rely on this movement card and its preceding
            -- dialogue/setup entries to enter it.  Omitting those entries
            -- leaves card-owned state (for example graze0) uninitialized.
            native_card_list = build_native_card_sequence(class, index)
        end
        scoredata = scoredata or {}
        scoredata.hiscore = scoredata.hiscore or {}
        stage.Set("TNRLegacyCard")
        stage.Change()
        restore_project_ui_image()
        return true, card, index
    end
    local function bridge_start_enemy_wave(wave_id)
        native_reset_aggro()
        native_room_generation = native_room_generation + 1
        local wave, source_stage = find_legacy_enemy_wave(wave_id)
        if not wave then
            return false, "unknown legacy enemy wave: " .. tostring(wave_id)
        end
        native_room_started = true
        native_mode = "enemy"
        native_room_music_hint = music_for_legacy_stage(source_stage and source_stage.source_stage)
        native_direct_card = false
        native_enemy_training_only = true
        native_enemy_training_error = nil
        native_enemy_boss_error = nil
        native_enemy_boss_started = false
        native_virtual_keys = {}
        native_virtual_keys_previous = {}
        native_reset_bomb_charge()
        native_bomb_generation = 0
        native_last_applied_bomb_generation = 0
        native_last_bomb_owner = nil
        native_last_bomb_focus = false
        native_last_bomb_charged = false
        native_bomb_events = {}
        native_applied_bomb_events = {}
        native_local_bomb_sequences = {}
        native_local_bomb_ticks = {}
        native_reset_remote_bomb_charge()
        native_enemy_kill_generation = 0
        native_enemy_kill_events = {}
        native_enemy_alive_cache = {}
        native_authoritative_enemy_states = nil
        native_authoritative_enemy_initialized = {}
        native_last_applied_enemy_kill_generation = 0
        native_boss_class = nil
        native_card_list = nil
        native_room_seed = 1
        native_pick_random_focus()
        native_enemy_specs = build_native_enemy_specs(wave, native_room_seed)
        scoredata = scoredata or {}
        scoredata.hiscore = scoredata.hiscore or {}
        stage.Set("TNRLegacyCard")
        stage.Change()
        restore_project_ui_image()
        return true, wave
    end

    local function bridge_start_room(room_type, seed, floor, band)
        native_reset_aggro()
        native_room_generation = native_room_generation + 1
        room_type = tostring(room_type or "enemy"):lower()
        native_room_seed = tonumber(seed) or 1
        native_room_floor = math.max(1, math.min(3, math.floor(tonumber(floor) or 1)))
        native_room_band = tonumber(band)
            or ((native_room_floor - 1) * 2 + 1)
        native_pick_random_focus()
        native_room_started = true
        native_mode = room_type
        native_room_music_hint = nil
        native_enemy_specs = nil
        native_enemy_training_only = false
        native_enemy_training_error = nil
        native_enemy_boss_started = false
        native_virtual_keys = {}
        native_virtual_keys_previous = {}
        native_reset_bomb_charge()
        native_bomb_generation = 0
        native_last_applied_bomb_generation = 0
        native_last_bomb_owner = nil
        native_last_bomb_focus = false
        native_last_bomb_charged = false
        native_bomb_events = {}
        native_applied_bomb_events = {}
        native_local_bomb_sequences = {}
        native_local_bomb_ticks = {}
        native_reset_remote_bomb_charge()
        native_enemy_kill_generation = 0
        native_enemy_kill_events = {}
        native_enemy_alive_cache = {}
        native_authoritative_enemy_states = nil
        native_authoritative_enemy_initialized = {}
        native_last_applied_enemy_kill_generation = 0
        if room_type == "boss" then
            native_direct_card = false
            -- Select a real imported spell from this floor's fixed boss pool.
            -- The selected class keeps its complete original card sequence.
            local BossPools = require("tnr.stages.boss_pools")
            local floor = native_room_floor
            local selected_card, selected_class = select_catalog_card(native_room_seed, true, false, 31,
                function(legacy_boss) return BossPools.is_floor_boss(legacy_boss, floor) end)
            native_boss_class = selected_class
            if selected_class then native_index_dialog_blocks(selected_card and selected_card.legacy_boss, selected_class) end
            native_card_list = native_boss_class and native_boss_class.cards or nil
            native_room_music_hint = native_boss_class and native_boss_class.bgm or nil
        elseif room_type == "elite" then
            native_direct_card = false
            local BossPools = require("tnr.stages.boss_pools")
            local floor = native_room_floor
            local selected_card, selected_class = select_catalog_card(native_room_seed, true, true, 47,
                function(legacy_boss) return BossPools.is_floor_elite(legacy_boss, floor) end)
            native_boss_class = selected_class
            if selected_class then native_index_dialog_blocks(selected_card and selected_card.legacy_boss, selected_class) end
            native_card_list = native_boss_class and native_boss_class.cards or nil
            native_room_music_hint = native_boss_class and native_boss_class.bgm or nil
            if not native_boss_class then
                local fallback_card, fallback_class, fallback_slot =
                    select_catalog_card(native_room_seed, true, false, 53,
                        function(legacy_boss) return BossPools.is_floor_elite(legacy_boss, floor) end)
                native_boss_class = fallback_class
                if fallback_class then native_index_dialog_blocks(fallback_card and fallback_card.legacy_boss, fallback_class) end
                native_card_list = fallback_class and fallback_class.cards or nil
                native_room_music_hint = native_boss_class and native_boss_class.bgm or nil
            end
        else
            native_mode = "enemy"
            native_direct_card = false
            native_enemy_training_only = false
            -- Ordinary rooms use the floor's weakest boss pool for the
            -- post-wave nonspell so the interlude matches the floor.
            local BossPools = require("tnr.stages.boss_pools")
            local floor = native_room_floor
            local nonspell, selected_class, nonspell_slot = select_catalog_card(native_room_seed, false, false, 61,
                function(legacy_boss) return BossPools.is_floor_boss(legacy_boss, floor) end)
            native_boss_class = selected_class
            if selected_class then native_index_dialog_blocks(nonspell and nonspell.legacy_boss, selected_class) end
            native_card_list = build_native_card_sequence(selected_class, nonspell_slot)
            if not native_boss_class or not native_card_list then
                native_enemy_boss_error = "no original nonspell with a valid entrance sequence was selected"
            end
            -- Pick a wave whose content tier matches the node's six-band
            -- difficulty progression. The wave retains original constructor
            -- arguments and spawn timing.
            local original_wave = select_catalog_wave_for_band(native_room_seed, native_room_band)
            native_enemy_specs = build_native_enemy_specs(original_wave, native_room_seed)
            native_room_music_hint = music_for_legacy_stage(original_wave
                and (original_wave.source_stage or original_wave.legacy_stage))
        end
        scoredata = scoredata or {}
        scoredata.hiscore = scoredata.hiscore or {}
        stage.Set("TNRLegacyCard")
        stage.Change()
        restore_project_ui_image()
        return true
    end

    -- Explicitly tear down the previous room before a retry.  Stage.Change
    -- normally resets the pool, but a failed battle can leave objects queued
    -- in the current stage until the next frame; clearing them here prevents
    -- old enemies, bullets, bomb effects and support afterimages from leaking
    -- into the fresh attempt.
    local function bridge_reset_room()
        native_room_started = false
        native_room_music_hint = nil
        native_enemy_specs = nil
        native_enemy_objects = nil
        native_bomb_effects = {}
        native_remote_player = nil
        native_player = nil
        player = nil
        if lstg then lstg.player = nil end
        local groups = {
            GROUP_ENEMY_BULLET, GROUP_PLAYER_BULLET, GROUP_ENEMY,
            GROUP_ITEM, GROUP_NONTJT, GROUP_GHOST, GROUP_PLAYER,
        }
        if ObjList and Del then
            for _, group in ipairs(groups) do
                if group ~= nil then
                    for _, object in ObjList(group) do
                        pcall(Del, object)
                    end
                end
            end
        end
        if type(ResetPool) == "function" then
            pcall(ResetPool)
        end
        native_virtual_keys = {}
        native_virtual_keys_previous = {}
        native_respawn_frames[1], native_respawn_frames[2] = 0, 0
        native_team_defeated = false
        native_bomb_events = {}
        native_applied_bomb_events = {}
        native_enemy_kill_events = {}
        native_authoritative_enemy_states = nil
        return true
    end
    TNRNativeLegacy = {
        clear_room_objects = native_clear_room_objects,
        set_authority = function(is_host)
            native_network_authority_host = is_host ~= false
            native_disable_client_enemy_collisions()
            return true
        end,
        set_room_generation = function(generation)
            native_external_room_generation = generation ~= nil and tostring(generation) or nil
            return native_external_room_generation
        end,
        set_party_state = function(party_state)
            native_party_state = party_state
            if party_state and party_state.team_life ~= nil then
                native_set_team_lives(party_state.team_life)
            end
            return true
        end,
        set_player_state = function(player_state)
            native_player_state = player_state
            -- Publish the character id so the native player class resolver and
            -- the dialogue override can pick the right variant.
            _G.tnr_native_player_state = player_state
            return true
        end,
        set_loadout_descriptors = function(local_descriptor, remote_descriptor)
            native_local_loadout_descriptor = local_descriptor
            native_remote_loadout_descriptor = remote_descriptor
            if native_player then
                native_apply_loadout_descriptor(native_player, native_local_loadout_descriptor)
            end
            if native_remote_player then
                native_remote_player.tnr_loadout_descriptor = native_remote_loadout_descriptor
                native_remote_player.tnr_loadout_hash = native_remote_loadout_descriptor
                    and native_remote_loadout_descriptor.loadout_hash or nil
                local speed = native_remote_loadout_descriptor
                    and native_remote_loadout_descriptor.speed or nil
                native_remote_player.hspeed = speed and tonumber(speed.high_speed) or 4.5
                native_remote_player.lspeed = speed and tonumber(speed.low_speed) or 2
                local count = native_descriptor_support_count(native_remote_loadout_descriptor)
                native_remote_player.support = math.min(5, math.max(0, count))
            end
            return true
        end,
        set_runtime_drivers = function(local_driver, remote_driver)
            native_runtime_drivers[1] = local_driver
            native_runtime_drivers[2] = remote_driver
            return true
        end,
        set_runtime_active = function(active)
            native_runtime_active = active == true
            native_runtime_shot_calls = 0
            native_legacy_shot_calls = 0
            native_runtime_last_projectile = nil
            return native_runtime_active
        end,
        start_card = bridge_start_card,
        start_enemy_wave = bridge_start_enemy_wave,
        start_room = bridge_start_room,
        get_music_hint = function()
            if type(native_room_music_hint) == "string" and native_room_music_hint ~= "" then
                return native_room_music_hint
            end
            return nil
        end,
        reset_room = bridge_reset_room,
        set_coop = function(enabled, local_player_id)
            local was_coop_enabled = native_coop_enabled
            native_coop_enabled = enabled == true
            native_local_player_id = tonumber(local_player_id) == 2 and 2 or 1
            NativeProjectile.set_local_player_id(native_local_player_id)
            _G.tnr_item_owner_player_id = native_local_player_id
            if native_coop_enabled ~= was_coop_enabled then
                native_reset_aggro()
            end
            native_remote_input = {}
            native_reset_remote_bomb_charge()
            native_authoritative_enemy_states = nil
            native_authoritative_enemy_initialized = {}
            native_reset_bomb_charge()
            native_respawn_frames[1], native_respawn_frames[2] = 0, 0
            if native_coop_enabled and (not was_coop_enabled or native_team_defeated) then
                native_set_team_lives(3)
                native_team_defeated = false
                native_pick_random_focus()
            end
            if native_coop_enabled and lstg and lstg.var then
                lstg.var.lifeleft = native_team_lives
            end
            if native_player and native_coop_enabled then
                native_player.x = native_local_player_id == 1 and -36 or 36
        native_remote_player = {
            x = native_local_player_id == 1 and 36 or -36,
            y = -176,
            invuln = 0,
            support = 0,
            lh = 0,
            sp = nil,
            image = "reimu_player1",
            hidden = false,
        }
        native_remote_player.support = math.min(5,
            math.max(0, native_descriptor_support_count(native_remote_loadout_descriptor)))
        native_remote_player.tnr_loadout_hash = native_remote_loadout_descriptor
            and native_remote_loadout_descriptor.loadout_hash or nil
        native_remote_player.tnr_loadout_descriptor = native_remote_loadout_descriptor
        local remote_speed = native_remote_loadout_descriptor
            and native_remote_loadout_descriptor.speed or nil
        native_remote_player.hspeed = remote_speed and tonumber(remote_speed.high_speed) or 4.5
        native_remote_player.lspeed = remote_speed and tonumber(remote_speed.low_speed) or 2
        native_remote_generation = native_room_generation
    elseif not native_coop_enabled then
        native_remote_player = nil
        native_remote_generation = -1
            end
            return true
        end,
        update_remote = function(input)
            native_remote_input = input or {}
            if not native_coop_enabled or not native_player then return end
            native_ensure_remote_player()
            native_cleanup_bomb_effects()
            local remote_id = native_local_player_id == 1 and 2 or 1
            if (native_respawn_frames[remote_id] or 0) > 0 then
                native_remote_player.invuln = 0
                native_remote_player.hidden = true
                if (native_respawn_frames[native_local_player_id] or 0) <= 0 then
                    native_aggro_focus_player = native_local_player_id
                    native_aggro_focus_window = tonumber(native_aggro.window_id) or 0
                end
                -- The local player may have entered respawn during the
                -- preceding DoFrame. Resolve the shared-life transition
                -- before returning from the remote-player path, otherwise a
                -- remote player already in cooldown prevents the check from
                -- ever running.
                if native_network_authority_host then
                    native_resolve_team_wipe()
                end
                return
            end
            if native_remote_player.shoot_cooldown > 0 then
                native_remote_player.shoot_cooldown = native_remote_player.shoot_cooldown - 1
            end
            local speed = native_remote_input.focus and (native_remote_player.lspeed or 2)
                or (native_remote_player.hspeed or 4)
            local dx = (native_remote_input.move_x or 0)
            local dy = (native_remote_input.move_y or 0)
            if dx ~= 0 and dy ~= 0 then speed = speed * 0.70710678 end
            native_remote_player.x = native_remote_player.x + dx * speed
            native_remote_player.y = native_remote_player.y + dy * speed
            local world = lstg.world or {}
            native_remote_player.x = math.max(world.pl or -192, math.min(world.pr or 192, native_remote_player.x))
            native_remote_player.y = math.max(world.pb or -224, math.min(world.pt or 224, native_remote_player.y))
            native_remote_player.supportx = native_remote_player.x
                + ((native_remote_player.supportx or native_remote_player.x) - native_remote_player.x) * 0.6875
            native_remote_player.supporty = native_remote_player.y
                + ((native_remote_player.supporty or native_remote_player.y) - native_remote_player.y) * 0.6875
            native_remote_player.invuln = math.max(0, (native_remote_player.invuln or 0) - 1)
            -- The remote player's collision is decided by the machine that
            -- owns that player. Never test the proxy against this process's
            -- local bullet pool: a pattern drift would otherwise hide the
            -- remote machine after a single local-only collision.
            -- Drive the original Reimu constructor for the proxy as well.
            -- Copying the local player's support layout is important: with a
            -- zero-support proxy only the two straight shots are produced,
            -- so Reimu's blue homing shots disappear on the other peer.
            if native_runtime_active and native_runtime_drivers[remote_id] then
                native_runtime_fire(native_runtime_drivers[remote_id], native_remote_player,
                    native_remote_input, remote_id)
                native_remote_player.shoot_cooldown = 1
            elseif native_remote_input.shoot and native_remote_player.shoot_cooldown <= 0 then
                -- Fire the remote character's own legacy shot so each peer
                -- renders the correct projectile pattern for the other player.
                local remote_class = native_player_class_for(native_remote_player.character_id)
                    or reimu_player
                if remote_class and type(remote_class.shoot) == "function" then
                    local support = math.max(0, tonumber(native_remote_player.support) or 4)
                    local support_layout = native_remote_player.sp
                    if type(support_layout) ~= "table" or not support_layout[1] then
                        support_layout = {
                            {-36, -12, 1}, {-16, -32, 1},
                            {16, -32, 1}, {36, -12, 1},
                        }
                    end
                    local current = stage and stage.current_stage
                    local angle_layout = native_player and native_player.anglelist
                    if type(angle_layout) ~= "table" then
                        angle_layout = {
                            {90, 90, 90, 90},
                            {90, 90, 90, 90},
                            {100, 80, 90, 90},
                            {110, 100, 80, 70},
                            {110, 100, 80, 70},
                        }
                    end
                    local shooter = {
                        x = native_remote_player.x,
                        y = native_remote_player.y,
                        support = support,
                        sp = support_layout,
                        anglelist = angle_layout,
                        imgs = remote_class.imgs,
                        A = 0.5, B = 0.5,
                        slow = native_remote_input.focus and 1 or 0,
                        supportx = native_remote_player.supportx or native_remote_player.x,
                        supporty = native_remote_player.supporty or native_remote_player.y,
                        nextshoot = 0,
                        timer = current and (tonumber(current.frame_count) or 0) or 0,
                        target = nil,
                    }
                    if type(remote_class.findtarget) == "function" then
                        pcall(remote_class.findtarget, shooter)
                    end
                    local previous_owner = native_damage_owner_context
                    native_damage_owner_context = remote_id
                    pcall(remote_class.shoot, shooter)
                    native_damage_owner_context = previous_owner
                    native_remote_player.shoot_cooldown = 4
                end
            end
            -- A packet carries a monotonically increasing input tick. Use it
            -- as the Bomb edge identity instead of a boolean latch: cached
            -- packets and reconnects can otherwise either repeat one Bomb or
            -- swallow the next one.
            -- The transport may coalesce a Bomb edge with a newer movement
            -- packet. Preserve the original action tick for dedupe so the
            -- host relay is recognized as the client's own Bomb on return.
            local function activate_remote_bomb()
                -- A bomb is a shared arena action. Use the same global
                -- destroyable-bullet group as the original PlayerSpell.
                native_clear_enemy_bullets()
                local remote_focus = native_remote_input.focus == true
                native_record_bomb(remote_id, remote_focus,
                    native_remote_input.bomb_tick or native_remote_input.tick,
                    native_remote_input.bomb_charged == true)
                native_play_remote_bomb(remote_id, remote_focus, native_remote_input.bomb_charged == true)
            end
            -- Only the final Bomb release edge is sent over the wire. Charge
            -- duration and hit judgment stay local to the owning simulation.
            local remote_bomb_tick = tonumber(native_remote_input.bomb_tick
                or native_remote_input.tick)
            local bomb_edge = native_remote_input.bomb == true
                and ((remote_bomb_tick and remote_bomb_tick ~= native_remote_bomb_tick)
                    or (not remote_bomb_tick and not native_remote_bomb_latched))
            if bomb_edge then
                native_remote_bomb_latched = true
                if remote_bomb_tick then native_remote_bomb_tick = remote_bomb_tick end
                activate_remote_bomb()
            elseif not native_remote_input.bomb then
                native_remote_bomb_latched = false
            end
            if native_network_authority_host then
                native_resolve_team_wipe()
            end
        end,
        update = function(input)
            input = native_merge_physical_input(input)
            native_cleanup_bomb_effects()
            native_apply_local_respawn_state()
            native_advance_respawns()
            native_apply_local_respawn_state()
            if native_coop_enabled and native_team_defeated then
                input = {}
            end
            for key, value in pairs(native_virtual_keys) do
                native_virtual_keys_previous[key] = value
            end
            native_virtual_keys.up = input.move_y == 1
            native_virtual_keys.down = input.move_y == -1
            native_virtual_keys.left = input.move_x == -1
            native_virtual_keys.right = input.move_x == 1
            native_virtual_keys.slow = input.focus == true
            native_virtual_keys.shoot = input.shoot == true
            native_virtual_keys.spell = input.bomb == true
            native_virtual_keys.special = false
            if native_player then
                local key_state = {
                    up = input.move_y == 1, down = input.move_y == -1,
                    left = input.move_x == -1, right = input.move_x == 1,
                    slow = input.focus == true, shoot = input.shoot == true,
                    spell = input.bomb == true, special = false,
                }
                native_player.key = key_state
                -- Keep the player-system flags in sync as well.  The
                -- reference system normally derives them from key events;
                -- assigning them here makes the native bridge resilient to a
                -- stage that replaces the player's virtual-key table.
                local player_system = native_player._playersys
                if player_system then
                    player_system.__up_flag = key_state.up
                    player_system.__down_flag = key_state.down
                    player_system.__left_flag = key_state.left
                    player_system.__right_flag = key_state.right
                    player_system.__slow_flag = key_state.slow
                    player_system.__shoot_flag = key_state.shoot
                    player_system.__spell_flag = key_state.spell
                    player_system.__special_flag = key_state.special
                end
            end
            if native_runtime_active and native_runtime_drivers[native_local_player_id]
                    and native_player then
                -- Advance the formal weapon/support runtimes every frame;
                -- their own cooldowns decide whether a volley is emitted.
                -- This keeps held fire deterministic without relying on the
                -- legacy player's power-driven `nextshoot` state.
                native_runtime_fire(native_runtime_drivers[native_local_player_id],
                    native_player, input, native_local_player_id)
            end
            if native_input_replay and native_input_replay.setExternalInput then
                native_input_replay.setExternalInput({
                    move_x = tonumber(input.move_x) or 0,
                    move_y = tonumber(input.move_y) or 0,
                    slow = input.focus == true,
                    shoot = input.shoot == true,
                    spell = input.bomb == true,
                    special = false,
                })
            end
            native_disable_client_enemy_collisions()
            local bomb_before = lstg and lstg.var and tonumber(lstg.var.bomb)
            local nextspell_before = native_player and tonumber(native_player.nextspell) or 0
            local previous_owner = native_damage_owner_context
            native_damage_owner_context = native_local_player_id
            -- Keep the original native frame logic intact; the temporary
            -- context tags only bullets created during this frame.
            native_aggro_targeting = native_coop_enabled
            local result = DoFrame()
            native_aggro_targeting = false
            native_damage_owner_context = previous_owner
            if native_runtime_active and native_player then
                native_apply_loadout_descriptor(native_player, native_local_loadout_descriptor)
                local local_driver = native_runtime_drivers[native_local_player_id]
                if local_driver then
                    native_runtime_support_layout(native_player, local_driver._last_support_state)
                end
            end
            native_update_aggro_window()
            if native_input_replay and native_input_replay.clearExternalInput then
                native_input_replay.clearExternalInput()
            end
            -- Reconcile enemy HP/death state after the native update. The
            -- helper applies a coordinate only when an object is first seen;
            -- all subsequent movement remains local and smooth.
            native_apply_authoritative_enemy_states()
            -- THlib marks a player as dying after a bullet collision.  While
            -- the local Bomb key is being charged, convert that death marker
            -- into the same deferred safety Bomb used by the fallback room.
            if native_player and (native_player.death or 0) > 0
                    and native_bomb_charge_frames > 0
                    and (native_bomb_hit_charge_timer or 0) <= 0 then
                native_player.death = 0
                native_player.protect = math.max(tonumber(native_player.protect) or 0, 90)
                native_bomb_hit_charge_timer = 30
                native_bomb_hit_charge_window = 18
                native_bomb_charge_frames = 0
                native_bomb_charge_fired = false
                native_local_bomb_charged = false
            end
            -- The original player class consumes Bomb only when its cooldown
            -- and global Bomb count allow it. Publish exactly that edge to the
            -- peer; held X/input packets can never retrigger the effect.
            local bomb_after = lstg and lstg.var and tonumber(lstg.var.bomb)
            if native_player_state and bomb_after ~= nil then
                native_player_state.bomb = math.max(0, bomb_after)
            end
            if native_player_state and not native_coop_enabled and lstg and lstg.var
                    and tonumber(lstg.var.lifeleft) then
                native_player_state.life = math.max(0, tonumber(lstg.var.lifeleft))
            end
            if native_coop_enabled and input.bomb == true
                    and bomb_before and bomb_after and bomb_after < bomb_before
                    and nextspell_before <= 0 then
                native_record_bomb(native_local_player_id, input.focus == true, input.tick,
                    input.bomb_charged == true or native_local_bomb_charged == true)
            end
            if native_coop_enabled and native_player and not native_team_defeated
                    and (native_respawn_frames[native_local_player_id] or 0) <= 0
                    and (native_player.death or 0) > 0 then
                -- THlib normally consumes a life at death==90. Intercept the
                -- original death timer immediately and replace it with the
                -- shared ten-second respawn state.
                native_start_respawn(native_local_player_id)
            end
            return result
        end,
        render = function()
            if native_render_func then return native_render_func() end
        end,
        state = function()
            local current = stage and stage.current_stage
            local boss = current and current.boss
            if not native_is_valid_object(boss) then
                boss = nil
            end
            local boss_hp, boss_maxhp, boss_timer, boss_card_num
            local boss_status = native_read_boss_status(boss)
            if boss_status then
                boss_hp = boss_status.hp
                boss_maxhp = boss_status.maxhp
                boss_timer = boss_status.timer
                boss_card_num = boss_status.card_num
            end
            local alive = boss ~= nil
            local enemy_count = 0
            if native_mode == "enemy" then
                -- Before the transition this tracks wave enemies; after the
                -- transition it tracks the newly spawned nonspell Boss.
                if not alive then
                    for _, enemy_object in pairs(current and current.enemy_objects or {}) do
                        if native_is_valid_object(enemy_object) then
                            enemy_count = enemy_count + 1
                            alive = true
                        end
                    end
                end
                if enemy_count > 0 then
                    native_enemy_training_seen_alive = true
                elseif native_enemy_training_only and current and current.enemy_spawned
                        and (current.frame_count or 0) > 2
                        and not native_enemy_training_seen_alive
                        and not native_enemy_training_error then
                    native_enemy_training_error = "original enemy objects became invalid immediately after creation"
                end
            end
            return {
                active = native_player ~= nil and native_room_started,
                player = native_player,
                boss = boss,
                -- The adapter uses this common field for encounter lifetime;
                -- in an ordinary room it means "at least one wave enemy is
                -- alive", not that a Boss object exists.
                boss_alive = alive,
                enemy_spawned = current and current.enemy_spawned == true,
                enemy_count = enemy_count,
                enemy_training_active = native_enemy_training_only == true,
                enemy_training_error = native_enemy_training_error,
                enemy_boss_error = native_enemy_boss_error,
                enemy_training_seen_alive = native_enemy_training_seen_alive,
                enemy_boss_started = native_enemy_boss_started == true,
                room_type = native_mode,
                frame_count = current and tonumber(current.frame_count) or 0,
                player_dead = native_player ~= nil and native_player.death and native_player.death > 0,
                coop_enabled = native_coop_enabled,
                respawn_frames = { [1] = native_respawn_frames[1] or 0, [2] = native_respawn_frames[2] or 0 },
                team_lives = native_team_lives,
                team_defeated = native_team_defeated,
                team_wipe_generation = native_team_wipe_generation,
                remote_player = native_remote_player,
                boss_hp = boss_hp,
                boss_maxhp = boss_maxhp,
                boss_timer = boss_timer,
                boss_card_num = boss_card_num,
                aggro_focus_player = native_aggro_focus_player,
                aggro_focus_window = native_aggro_focus_window,
                runtime_active = native_runtime_active,
                runtime_shot_calls = native_runtime_shot_calls,
                legacy_shot_calls = native_legacy_shot_calls,
                runtime_last_projectile = native_runtime_last_projectile,
                -- Reference-project stage score and the money collected this
                -- stage. The score follows the original THlib scoring (hits,
                -- faith, point items, spell-card bonus and money pickups).
                stage_score = tonumber(lstg.var and lstg.var.score) or 0,
                stage_money = tonumber(lstg.var and lstg.var.tnr_stage_money) or 0,
                -- Cumulative per-player counters for perfect clear detection.
                player_miss_counts = { [1] = native_miss_counts[1] or 0, [2] = native_miss_counts[2] or 0 },
                player_bomb_counts = { [1] = native_bomb_counts[1] or 0, [2] = native_bomb_counts[2] or 0 },
            }
        end,
        snapshot = function()
            local state = TNRNativeLegacy.state()
            local current = stage and stage.current_stage
            local players = {}
            if state.player then
                players[native_local_player_id] = {
                    x = tonumber(state.player.x) or 0,
                    y = tonumber(state.player.y) or 0,
                    hidden = state.player.hide == true,
                    dead = (tonumber(state.player.death) or 0) > 0,
                    support = tonumber(state.player.support) or 0,
                    lh = tonumber(state.player.lh) or 0,
                    sp = native_copy_support_layout(state.player.sp),
                }
            end
            if state.remote_player then
                local remote_id = native_local_player_id == 1 and 2 or 1
                players[remote_id] = {
                    x = tonumber(state.remote_player.x) or 0,
                    y = tonumber(state.remote_player.y) or 0,
                    hidden = (native_respawn_frames[remote_id] or 0) > 0,
                    dead = (native_respawn_frames[remote_id] or 0) > 0,
                    support = tonumber(state.remote_player.support) or 0,
                    lh = tonumber(state.remote_player.lh) or 0,
                    sp = native_copy_support_layout(state.remote_player.sp),
                }
            end
            return {
                room_seed = native_room_seed,
                room_type = native_mode,
                room_generation = native_external_room_generation or native_room_generation,
                boss_hp = state.boss_hp,
                boss_maxhp = state.boss_maxhp,
                boss_timer = state.boss_timer,
                boss_card_num = state.boss_card_num,
                boss_alive = state.boss_alive == true,
                coop_enabled = state.coop_enabled == true,
                respawn_frames = state.respawn_frames,
                team_lives = state.team_lives,
                team_defeated = state.team_defeated == true,
                team_wipe_generation = native_team_wipe_generation,
                frame = stage and stage.current_stage and stage.current_stage.frame_count or 0,
                players = players,
                -- Host publishes enemy HP/death for reconciliation. Drops
                -- are deliberately excluded from network ownership: each
                -- endpoint runs its own enemy kill callback and local item
                -- pool, so the remote player can never collect them.
                enemies = native_capture_enemy_states(current),
                enemy_spawned = current and current.enemy_spawned == true,
                bomb_generation = native_bomb_generation,
                bomb_owner = native_last_bomb_owner,
                bomb_focus = native_last_bomb_focus == true,
                bomb_charged = native_last_bomb_charged == true,
                bomb_events = native_bomb_events,
                aggro_focus_player = native_aggro_focus_player,
                aggro_focus_window = native_aggro_focus_window,
            }
        end,
        peer_snapshot = function()
            local current = stage and stage.current_stage
            local boss = current and current.boss
            local boss_valid = native_is_valid_object(boss)
            local boss_hp, boss_maxhp, boss_timer, boss_card_num
            local boss_status = native_read_boss_status(boss)
            if boss_status then
                boss_hp = boss_status.hp
                boss_maxhp = boss_status.maxhp
                boss_timer = boss_status.timer
                boss_card_num = boss_status.card_num
            else
                boss_valid = false
            end
            local enemies = {}
            for enemy_id, enemy_object in pairs(current and current.enemy_objects or {}) do
                if type(enemy_id) == "number" then
                    local alive = native_is_valid_object(enemy_object)
                    local x, y, hp, hide = 0, 0, nil, false
                    if alive then
                        local ok = pcall(function()
                            x = tonumber(enemy_object.x) or 0
                            y = tonumber(enemy_object.y) or 0
                            hp = tonumber(enemy_object.hp)
                            hide = enemy_object.hide == true
                        end)
                        if not ok then
                            alive = false
                            x, y, hp, hide = 0, 0, nil, false
                        end
                    end
                    enemies[enemy_id] = {
                        alive = alive,
                        x = x,
                        y = y,
                        hp = hp,
                        hide = hide,
                    }
                end
            end
            local players = {}
            if native_is_valid_object(native_player) then
                local ok = pcall(function()
                    players[native_local_player_id] = {
                        x = tonumber(native_player.x) or 0,
                        y = tonumber(native_player.y) or 0,
                        hidden = native_player.hide == true,
                        dead = (tonumber(native_player.death) or 0) > 0,
                        support = tonumber(native_player.support) or 0,
                        lh = tonumber(native_player.lh) or 0,
                        sp = native_copy_support_layout(native_player.sp),
                    }
                end)
                if not ok then players[native_local_player_id] = nil end
            end
            return {
                room_seed = native_room_seed,
                room_type = native_mode,
                room_generation = native_external_room_generation or native_room_generation,
                frame = current and tonumber(current.frame_count) or 0,
                players = players,
                respawn_frames = {
                    [1] = native_respawn_frames[1] or 0,
                    [2] = native_respawn_frames[2] or 0,
                },
                team_lives = native_team_lives,
                team_defeated = native_team_defeated == true,
                team_wipe_generation = native_team_wipe_generation,
                enemies = enemies,
                boss_hp = boss_status and boss_hp or nil,
                boss_maxhp = boss_status and boss_maxhp or nil,
                boss_timer = boss_status and boss_timer or nil,
                boss_card_num = boss_status and boss_card_num or nil,
                aggro_report = native_aggro.last_report,
            }
        end,
        apply_peer_snapshot = function(snapshot)
            if type(snapshot) ~= "table" then return end
            if snapshot.room_seed ~= nil and tonumber(snapshot.room_seed) ~= tonumber(native_room_seed) then
                return
            end
            if snapshot.room_type ~= nil and tostring(snapshot.room_type) ~= tostring(native_mode) then
                return
            end
            if snapshot.room_generation ~= nil
                    and tostring(snapshot.room_generation) ~= tostring(native_external_room_generation or native_room_generation) then
                return
            end
            local current = stage and stage.current_stage
            if not current then return end
            local remote_id = native_local_player_id == 1 and 2 or 1
            if native_network_authority_host and type(snapshot.aggro_report) == "table" then
                local report = snapshot.aggro_report
                if tonumber(report.window_id) then
                    native_aggro_remote_report = {
                        window_id = tonumber(report.window_id),
                        damage = {
                            [2] = tonumber(report.damage and report.damage[2]) or 0,
                        },
                    }
                    local local_report = native_aggro.last_report
                    if local_report and tonumber(local_report.window_id) == tonumber(report.window_id) then
                        local chosen = Aggro.compare(
                            local_report, native_aggro_remote_report, native_aggro_focus_player)
                        if chosen then
                            native_aggro_focus_player = chosen
                            native_aggro_focus_window = local_report.window_id
                        end
                        native_aggro_remote_report = nil
                    end
                end
            end
            -- The remote endpoint is authoritative for the life/death state
            -- of its own player.  Apply only that side's respawn timer; never
            -- let a peer packet revive or protect our locally owned player.
            if type(snapshot.respawn_frames) == "table" then
                local remote_frames = math.max(0, tonumber(snapshot.respawn_frames[remote_id]) or 0)
                local previous_frames = native_respawn_frames[remote_id] or 0
                native_respawn_frames[remote_id] = remote_frames
                if remote_frames > 0 and previous_frames <= 0 then
                    if native_remote_player then native_remote_player.invuln = 0 end
                    if (native_respawn_frames[native_local_player_id] or 0) <= 0 then
                        native_aggro_focus_player = native_local_player_id
                        native_aggro_focus_window = tonumber(native_aggro.window_id) or 0
                    end
                elseif remote_frames == 0 and previous_frames > 0 then
                    native_finish_respawn(remote_id)
                end
            end
            if not native_network_authority_host and snapshot.team_lives ~= nil then
                native_set_team_lives(math.min(native_team_lives,
                    math.max(0, tonumber(snapshot.team_lives) or native_team_lives)))
            end
            if not native_network_authority_host and snapshot.team_defeated == true then
                native_team_defeated = true
            end
            local remote_state = type(snapshot.players) == "table" and snapshot.players[remote_id]
            if remote_state and native_remote_player then
                pcall(function()
                    if tonumber(remote_state.x) then native_remote_player.x = tonumber(remote_state.x) end
                    if tonumber(remote_state.y) then native_remote_player.y = tonumber(remote_state.y) end
                    if tonumber(remote_state.support) then native_remote_player.support = tonumber(remote_state.support) end
                    if tonumber(remote_state.lh) then native_remote_player.lh = tonumber(remote_state.lh) end
                    if type(remote_state.sp) == "table" then native_remote_player.sp = native_copy_support_layout(remote_state.sp) end
                    native_remote_player.hidden = remote_state.hidden == true
                end)
            end
            local enemies = snapshot.enemies
            -- Both peers run the native wave locally. The client keeps this
            -- peer state as a lightweight reconciliation stream: HP and
            -- death/removal are synchronized, while movement is corrected
            -- only for the first spawn by native_apply_authoritative_enemy_states.
            if not native_network_authority_host and type(enemies) == "table" and current.enemy_objects then
                native_authoritative_enemy_states = enemies
                -- The actual coordinate application is repeated after
                -- DoFrame; retain this immediate pass for death/removal
                -- visibility before the next frame's stage transition.
                for enemy_id, enemy_state in pairs(enemies) do
                    local id = tonumber(enemy_id)
                    local enemy_object = id and current.enemy_objects[id]
                    if type(enemy_state) == "table" then
                        if enemy_state.alive and native_is_valid_object(enemy_object) then
                            pcall(function()
                                if tonumber(enemy_state.hp) then enemy_object.hp = tonumber(enemy_state.hp) end
                                enemy_object.hide = enemy_state.hide == true
                            end)
                        elseif not enemy_state.alive then
                            native_authoritative_enemy_initialized[id] = nil
                            native_finalize_local_enemy_death(enemy_object)
                        end
                    end
                end
            end
            local boss = current.boss
            if not native_network_authority_host and native_is_valid_object(boss) then
                pcall(native_apply_boss_status, boss, snapshot, false)
            end
        end,
        apply_snapshot = function(snapshot)
            if type(snapshot) ~= "table" then return end
            if snapshot.room_seed ~= nil and tonumber(snapshot.room_seed) ~= tonumber(native_room_seed) then
                return
            end
            if snapshot.room_type ~= nil and tostring(snapshot.room_type) ~= tostring(native_mode) then
                return
            end
            if snapshot.room_generation ~= nil
                    and tostring(snapshot.room_generation) ~= tostring(native_external_room_generation or native_room_generation) then
                return
            end
            local incoming_events = snapshot.bomb_events
            if type(incoming_events) == "table" then
                for _, event in ipairs(incoming_events) do
                    local sequence = tonumber(event.sequence) or 0
                    native_apply_remote_bomb_event(sequence, event.owner, event.focus,
                        event.local_event, event.origin, event.input_tick, event.charged)
                end
            else
                local incoming_bomb_generation = tonumber(snapshot.bomb_generation) or 0
                native_apply_remote_bomb_event(incoming_bomb_generation,
                    snapshot.bomb_owner, snapshot.bomb_focus, false, nil, nil,
                    snapshot.bomb_charged == true)
            end
            local local_id = native_local_player_id
            local remote_id = local_id == 1 and 2 or 1
            local incoming_wipe = tonumber(snapshot.team_wipe_generation) or 0
            local wipe_advanced = incoming_wipe > native_team_wipe_generation
            local incoming_frames
            if snapshot.respawn_frames then
                incoming_frames = {
                    [1] = math.max(0, tonumber(snapshot.respawn_frames[1]) or 0),
                    [2] = math.max(0, tonumber(snapshot.respawn_frames[2]) or 0),
                }
                -- A client may detect its own collision one frame before the
                -- host receives the corresponding input. Never let an older
                -- host snapshot erase that local death timer, otherwise the
                -- local player is revived early (with protection) and the
                -- two peers disagree about who is dead.
                local previous_remote_frames = native_respawn_frames[remote_id] or 0
                for player_id = 1, 2 do
                    if player_id == local_id and native_respawn_frames[player_id] > 0
                            and not wipe_advanced then
                        native_respawn_frames[player_id] = math.max(
                            native_respawn_frames[player_id], incoming_frames[player_id])
                    else
                        native_respawn_frames[player_id] = incoming_frames[player_id]
                    end
                end
                if incoming_frames[remote_id] > 0 and previous_remote_frames <= 0
                        and incoming_frames[local_id] <= 0 then
                    native_aggro_focus_player = local_id
                    native_aggro_focus_window = tonumber(native_aggro.window_id) or 0
                end
            end
            if snapshot.team_lives ~= nil then
                native_set_team_lives(math.max(0, tonumber(snapshot.team_lives) or native_team_lives))
            end
            if snapshot.team_defeated ~= nil then
                native_team_defeated = snapshot.team_defeated == true
            end
            if wipe_advanced then
                native_team_wipe_generation = incoming_wipe
                native_clear_enemy_bullets()
                -- A wipe snapshot supersedes the local timer guard.  The
                -- host sends zero timers for a successful shared revive; run
                -- the same transition locally so hidden/dead proxies become
                -- visible immediately.  A zero-life wipe remains defeated.
                if not native_team_defeated then
                    for player_id = 1, 2 do
                        if (incoming_frames and incoming_frames[player_id] or 0) <= 0 then
                            native_finish_respawn(player_id)
                        end
                    end
                end
            end
            if not native_network_authority_host and snapshot.aggro_focus_player ~= nil then
                local focus = tonumber(snapshot.aggro_focus_player)
                if focus == 1 or focus == 2 then
                    native_aggro_focus_player = focus
                    native_aggro_focus_window = tonumber(snapshot.aggro_focus_window)
                        or native_aggro_focus_window
                end
            end
            local remote_state = snapshot.players and snapshot.players[remote_id]
            if remote_state and native_remote_player then
                if tonumber(remote_state.x) then native_remote_player.x = tonumber(remote_state.x) end
                if tonumber(remote_state.y) then native_remote_player.y = tonumber(remote_state.y) end
                if tonumber(remote_state.support) then native_remote_player.support = tonumber(remote_state.support) end
                if tonumber(remote_state.lh) then native_remote_player.lh = tonumber(remote_state.lh) end
                if type(remote_state.sp) == "table" then native_remote_player.sp = native_copy_support_layout(remote_state.sp) end
                native_remote_player.hidden = remote_state.hidden == true
            end
            local enemies = snapshot.enemies
            local current = stage and stage.current_stage
            if not native_network_authority_host and type(enemies) == "table"
                    and current.enemy_objects then
                native_authoritative_enemy_states = enemies
            end
            native_apply_local_respawn_state()
            current = stage and stage.current_stage
            local boss = current and current.boss
            if not native_is_valid_object(boss) then return end
            pcall(native_apply_boss_status, boss, snapshot, true)
        end,
    }
end

function GameInit()
end

function GameFrame()
end

function GameRender()
    if not legacy_loaded then
        return
    end
end

function GameExit()
end
