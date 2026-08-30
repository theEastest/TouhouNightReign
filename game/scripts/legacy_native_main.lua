local load_error
local legacy_loaded = false
local native_stage
local native_boss_class
local native_card_list
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
local native_physical_bomb_previous = false
local native_bomb_request_previous = false
local native_local_bomb_latched = false
local native_bomb_generation = 0
local native_last_applied_bomb_generation = 0
local native_last_bomb_owner = nil
local native_last_bomb_focus = false
local native_bomb_events = {}
local native_applied_bomb_events = {}
local native_local_bomb_sequences = {}
local native_local_bomb_ticks = {}
local native_enemy_kill_generation = 0
local native_enemy_kill_events = {}
local native_enemy_alive_cache = {}
local native_authoritative_enemy_states
local native_authoritative_enemy_initialized = {}
local native_applied_enemy_drops = {}
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
local native_damage_owner_context
local native_bomb_effects = {}
local COOP_RESPAWN_FRAMES = 600
local native_respawn_frames = { [1] = 0, [2] = 0 }
local native_team_lives = 3
local native_party_state = nil
local native_player_state = nil
-- Immutable loadout descriptors supplied by the TNR session.  Native THlib
-- still owns the actual object simulation; these descriptors only select the
-- player profile parameters needed to construct the same local simulation on
-- both peers.
local native_local_loadout_descriptor = nil
local native_remote_loadout_descriptor = nil

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
    if support_count > 0 then
        -- Legacy Reimu's support formation has four visual slots.  Keep the
        -- original layout while honoring the descriptor's entity count.
        player_object.support = math.min(5, support_count)
    end
    player_object.tnr_loadout_hash = descriptor.loadout_hash
    player_object.tnr_loadout_descriptor = descriptor
    return true
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

local function native_is_valid_object(object)
    if object == nil or type(IsValid) ~= "function" then
        return false
    end
    local ok, valid = pcall(IsValid, object)
    return ok and valid == true
end

local function native_copy_support_layout(layout)
    if type(layout) ~= "table" then return nil end
    local result = {}
    for index = 1, 4 do
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

local function native_copy_drop(drop)
    if type(drop) ~= "table" then return nil end
    return {
        tonumber(drop[1]) or 0,
        tonumber(drop[2]) or 0,
        tonumber(drop[3]) or 0,
    }
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
            local object = native_original_new(class, ...)
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
            end
            return result
        end
    end
    -- Mark native enemy kills before the original callback runs. A client
    -- can then distinguish a locally killed enemy from one that must be
    -- removed by the host and have its original drop reproduced.
    if enemy and type(enemy.kill) == "function" then
        native_original_enemy_kill = enemy.kill
        enemy.kill = function(self, ...)
            if self then self._tnr_drop_spawned = true end
            return native_original_enemy_kill(self, ...)
        end
    end
    -- Track original Reimu Bomb objects so a stale effect cannot survive a
    -- room transition indefinitely. The original spell implementation and
    -- its damage are otherwise left untouched.
    if reimu_player and type(reimu_player.spell) == "function" then
        native_original_reimu_spell = reimu_player.spell
        reimu_player.spell = function(self, ...)
            local before = {}
            if ObjList and GROUP_PLAYER_BULLET then
                for _, object in ObjList(GROUP_PLAYER_BULLET) do before[object] = true end
            end
            local result = native_original_reimu_spell(self, ...)
            if ObjList and GROUP_PLAYER_BULLET then
                for _, object in ObjList(GROUP_PLAYER_BULLET) do
                    if not before[object]
                            and (object.class == reimu_kekkai or object.class == reimu_sp_ef1) then
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
    local bomb_pressed = bomb_down and not native_physical_bomb_previous
    local bomb_edge = (bomb_requested and not native_bomb_request_previous) or bomb_pressed
    -- Treat Bomb as a strict rising-edge action even if a stale input packet
    -- or the engine's key table reports X as held for several frames.
    if bomb_edge and not native_local_bomb_latched then
        input.bomb = true
        native_local_bomb_latched = true
    else
        input.bomb = false
    end
    if not bomb_requested and not bomb_down then
        native_local_bomb_latched = false
    end
    native_bomb_request_previous = bomb_requested
    native_physical_bomb_previous = bomb_down
    return input
end

local function native_clear_enemy_bullets()
    if ObjList and GROUP_ENEMY_BULLET and Del then
        for _, bullet in ObjList(GROUP_ENEMY_BULLET) do
            Del(bullet)
        end
    end
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
            local drop, drop_spawned
            if alive then
                pcall(function()
                    x = tonumber(enemy_object.x) or 0
                    y = tonumber(enemy_object.y) or 0
                    hp = tonumber(enemy_object.hp)
                    hide = enemy_object.hide == true
                    drop = native_copy_drop(enemy_object.drop or enemy_object._tnr_drop_spec)
                    drop_spawned = enemy_object._tnr_drop_spawned == true
                end)
            else
                -- A killed object may already have left the pool, but the
                -- bridge table still retains its final coordinates/drop spec.
                pcall(function()
                    x = tonumber(enemy_object.x) or 0
                    y = tonumber(enemy_object.y) or 0
                    drop = native_copy_drop(enemy_object.drop or enemy_object._tnr_drop_spec)
                    drop_spawned = enemy_object._tnr_drop_spawned == true
                end)
            end
            result[id] = {
                alive = alive,
                x = x,
                y = y,
                hp = hp,
                hide = hide,
                drop = drop,
                drop_spawned = drop_spawned,
            }
        end
    end
    return result
end

local function native_spawn_authoritative_drop(enemy_id, enemy_object, enemy_state)
    if type(enemy_state) ~= "table" or type(enemy_state.drop) ~= "table"
            or type(item) ~= "table" or type(item.DropItem) ~= "function" then
        return
    end
    if enemy_id and native_applied_enemy_drops[enemy_id] then
        return
    end
    if enemy_object and enemy_object._tnr_drop_spawned == true then
        if enemy_id then native_applied_enemy_drops[enemy_id] = true end
        return
    end
    local x = tonumber(enemy_state.x) or (enemy_object and tonumber(enemy_object.x)) or 0
    local y = tonumber(enemy_state.y) or (enemy_object and tonumber(enemy_object.y)) or 0
    local drop = native_copy_drop(enemy_state.drop)
    if drop then
        pcall(item.DropItem, x, y, drop)
        if enemy_object then enemy_object._tnr_drop_spawned = true end
        if enemy_id then native_applied_enemy_drops[enemy_id] = true end
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
                native_spawn_authoritative_drop(id, enemy_object, enemy_state)
                if native_is_valid_object(enemy_object) then
                    pcall(Del, enemy_object)
                end
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
local function native_play_remote_bomb(owner_id, focus)
    if not native_coop_enabled
            or not native_player or not native_remote_player
            or type(New) ~= "function" or not reimu_kekkai then
        return
    end
    local x = tonumber(native_remote_player.x) or 0
    local y = tonumber(native_remote_player.y) or 0
    -- Focused Reimu Bomb uses the original small Kekkai damage.  The unfocused
    -- variant uses the same native object with the larger reference damage;
    -- both modes have a finite lifetime and are locally collidable.
    local damage = focus and 1.25 or 50
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
    local ok, effect = pcall(New, reimu_kekkai, x, y, damage, focus and 3 or 6, 20, 12)
    if ok and effect then
        effect._tnr_bomb_effect = true
        effect._tnr_bomb_created_frame = stage and stage.current_stage
            and tonumber(stage.current_stage.frame_count) or 0
        native_bomb_effects[#native_bomb_effects + 1] = effect
    end
    native_damage_owner_context = previous_owner
end

local function native_record_bomb(owner_id, focus, input_tick)
    native_bomb_generation = native_bomb_generation + 1
    native_last_bomb_owner = owner_id
    native_last_bomb_focus = focus == true
    native_bomb_events[#native_bomb_events + 1] = {
        sequence = native_bomb_generation,
        owner = owner_id,
        focus = focus == true,
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

local function native_apply_remote_bomb_event(sequence, owner_id, focus, local_event, origin, input_tick)
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
    native_clear_enemy_bullets()
    native_play_remote_bomb(owner_id, native_last_bomb_focus)
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
            support = 4,
            lh = 0,
            sp = nil,
            image = "reimu_player1",
            hidden = false,
        }
        native_remote_generation = native_room_generation
    end
    native_remote_player.image = native_remote_player.image or "reimu_player1"
    native_remote_player.shoot_cooldown = tonumber(native_remote_player.shoot_cooldown) or 0
    native_remote_player.support = tonumber(native_remote_player.support) or 4
    native_remote_player.lh = tonumber(native_remote_player.lh) or 0
    native_remote_player.hidden = native_remote_player.hidden == true
    return native_remote_player
end

local function native_render_remote_player()
    if not native_coop_enabled or not native_player then return end
    local remote = native_ensure_remote_player()
    local remote_id = native_local_player_id == 1 and 2 or 1
    if not remote or (native_respawn_frames[remote_id] or 0) > 0 then return end
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
        local support_count = math.min(4, math.floor(support + 0.999))
        pcall(SetImageState, "reimu_support", "", Color(180, 255, 255, 255))
        local shown = 0
        for index = 1, 4 do
            local entry = layout[index]
            if shown < support_count and type(entry) == "table"
                    and (tonumber(entry[3]) or 0) > 0.5 then
                shown = shown + 1
                pcall(Render, "reimu_support", render_x + (tonumber(entry[1]) or 0),
                    render_y + (tonumber(entry[2]) or 0), 0)
            end
        end
        local image = remote.image or "reimu_player1"
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
    if not native_coop_enabled or not RenderTTF then return end
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
    RenderTTF("Sans", string.format("TEAM LIVES  %d", native_team_lives), right, right, y, y,
        Color(255, 220, 240, 255), "right", "vcenter", "noclip")
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

local function expand_captured_scalar(expression, expression_env)
    local result = tostring(expression)
    for _ = 1, 8 do
        local previous = result
        for name, value in pairs(expression_env) do
            if type(value) == "number" then
                result = result:gsub("(%f[%a_])" .. name .. "(%f[^%w_])", "%1(" .. tostring(value) .. ")%2")
            elseif type(value) == "string"
                    and not value:find("[{}:]")
                    and not value:find("%.new%s*%(") then
                result = result:gsub("(%f[%a_])" .. name .. "(%f[^%w_])", "%1(" .. value .. ")%2")
            end
        end
        if result == previous then break end
    end
    return result
end

local function evaluate_native_enemy_args(spec, runtime_context)
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
    -- Resolve source environment expressions against the complete legacy
    -- global namespace as well as values captured in the catalog. Some enemy
    -- constructors intentionally reference shared tables such as `bi` or
    -- `listb`; treating those as nil makes an otherwise valid enemy vanish.
    setmetatable(expression_env, { __index = _G })
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
    for _ = 1, #pending_env do
        if #pending_env == 0 then break end
        local unresolved = {}
        local progress = false
        for _, item in ipairs(pending_env) do
            local chunk, compile_error = compile_in_environment("return " .. item.expression, "legacy_enemy_env", expression_env)
            local ok, value = chunk and pcall(chunk)
            if ok and value ~= nil then
                expression_env[item.name] = value
                progress = true
            else
                item.compile_error = compile_error or value
                unresolved[#unresolved + 1] = item
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
                resolved_expression = resolved_expression:gsub("(%f[%a_])" .. name .. "(%f[^%w_])", "%1" .. tostring(value) .. "%2")
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

local function catalog_cards(require_spell, elite_only)
    local module_name = require_spell and "tnr.training.card_training_catalog"
        or "tnr.training.nonspell_training_catalog"
    local source = require(module_name)
    local result = {}
    for _, card in ipairs(source) do
        local class = _editor_class and _editor_class[card.legacy_boss]
        if valid_catalog_card(card, require_spell)
                and (not elite_only or (class and #class.cards < 3)) then
            result[#result + 1] = card
        end
    end
    table.sort(result, function(left, right) return left.id < right.id end)
    return result
end

local function select_catalog_card(seed, require_spell, elite_only, salt)
    local pool = catalog_cards(require_spell, elite_only)
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
    for previous_index = slot - 1, 1, -1 do
        local previous = class.cards[previous_index]
        if not previous then
            break
        end
        if previous.is_combat == true then
            break
        end
        -- Dialogues belong to the full-stage flow and can wait on UI input
        -- forever in a room that starts after an enemy wave. Preserve only
        -- movement setup needed to bring the Boss on screen.
        if previous.is_dialog then
            break
        elseif previous.is_move then
            table.insert(cards, 1, previous)
        else
            break
        end
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
            pcall(lstg.LoadTTF, "Sans", "C:/Windows/Fonts/msyh.ttc", 48, 48)
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
            if not file_exists(normalized) then
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
        -- The activity editor assumes these classic THlib sheets were loaded
        -- by the original project root. Load them before THlib's laser module,
        -- which creates its node image group from `bullet1` during Include.
        for index = 1, 6 do
            local path = "Thlib/bullet/bullet" .. index .. ".png"
            pcall(lstg.LoadTexture, "bullet" .. index, path, true)
        end
        Include("THlib.lua")
        -- Native rooms are driven by the same LegacyTHlib player system as
        -- the reference game. That system reads the replay action state for
        -- movement, so keep a direct handle for network-frame injection.
        native_input_replay = require("foundation.input.replay")
        spellcard_background = spellcard_background or default_spellcard_background or _spellcard_background
        -- Character scripts are separate from THlib.lua in the reference
        -- project; load Reimu explicitly so native rooms use her real shot,
        -- focus and bomb implementation.
        lstg.DoFile("Thlib/player/reimu/reimu.lua")
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
        for index = 1, 8 do
            local x = 48 * (index - 1)
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
            if type(LoadMusicRecord) == "function" then
                pcall(LoadMusicRecord, name)
            end
            return native_play_music(name, ...)
        end
        SetBGMVolume = function(name, ...)
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
        native_enemy_training_seen_alive = false
        native_bomb_effects = {}
        native_applied_enemy_drops = {}
        native_team_wipe_generation = 0
        native_respawn_frames[1], native_respawn_frames[2] = 0, 0
        self.frame_count = 0
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
        if native_room_started then
            native_player = New(reimu_player)
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
                    local args, argument_count = evaluate_native_enemy_args(spec, self)
                    local ok, object
                    if args then
                        ok, object = pcall(New, enemy_class, unpack_args(args, 1, argument_count))
                    else
                        print("TNR legacy wave skipped unresolved original arguments: " .. tostring(spec.class_name))
                        ok, object = false, nil
                    end
                    if ok and object then
                        -- Preserve the source spawn index. The host can then
                        -- send a compact death/position state keyed by this
                        -- index, and the client can remove the exact enemy
                        -- without serializing its bullets.
                        object._tnr_drop_spec = native_copy_drop(object.drop)
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
        ObjRender()
        -- Draw the remote player after the legacy object pool so background
        -- and boss layers cannot clip it at the upper edge of the playfield.
        native_render_remote_player()
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
        native_physical_bomb_previous = false
        native_bomb_request_previous = false
        native_local_bomb_latched = false
        native_bomb_generation = 0
        native_last_applied_bomb_generation = 0
        native_last_bomb_owner = nil
        native_last_bomb_focus = false
        native_bomb_events = {}
        native_applied_bomb_events = {}
        native_local_bomb_sequences = {}
        native_local_bomb_ticks = {}
        native_remote_bomb_tick = -1
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
        local wave = find_legacy_enemy_wave(wave_id)
        if not wave then
            return false, "unknown legacy enemy wave: " .. tostring(wave_id)
        end
        native_room_started = true
        native_mode = "enemy"
        native_direct_card = false
        native_enemy_training_only = true
        native_enemy_training_error = nil
        native_enemy_boss_error = nil
        native_enemy_boss_started = false
        native_virtual_keys = {}
        native_virtual_keys_previous = {}
        native_physical_bomb_previous = false
        native_bomb_request_previous = false
        native_local_bomb_latched = false
        native_bomb_generation = 0
        native_last_applied_bomb_generation = 0
        native_last_bomb_owner = nil
        native_last_bomb_focus = false
        native_bomb_events = {}
        native_applied_bomb_events = {}
        native_local_bomb_sequences = {}
        native_local_bomb_ticks = {}
        native_remote_bomb_tick = -1
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

    local function bridge_start_room(room_type, seed)
        native_reset_aggro()
        native_room_generation = native_room_generation + 1
        room_type = tostring(room_type or "enemy"):lower()
        native_room_seed = tonumber(seed) or 1
        native_pick_random_focus()
        native_room_started = true
        native_mode = room_type
        native_enemy_specs = nil
        native_enemy_training_only = false
        native_enemy_training_error = nil
        native_enemy_boss_started = false
        native_virtual_keys = {}
        native_virtual_keys_previous = {}
        native_physical_bomb_previous = false
        native_bomb_request_previous = false
        native_local_bomb_latched = false
        native_bomb_generation = 0
        native_last_applied_bomb_generation = 0
        native_last_bomb_owner = nil
        native_last_bomb_focus = false
        native_bomb_events = {}
        native_applied_bomb_events = {}
        native_local_bomb_sequences = {}
        native_local_bomb_ticks = {}
        native_remote_bomb_tick = -1
        native_enemy_kill_generation = 0
        native_enemy_kill_events = {}
        native_enemy_alive_cache = {}
        native_authoritative_enemy_states = nil
        native_authoritative_enemy_initialized = {}
        native_last_applied_enemy_kill_generation = 0
        if room_type == "boss" then
            native_direct_card = false
            -- Select a real imported spell from the same pool exposed by
            -- Spellcard Practice.  The selected class keeps its complete
            -- original card sequence for a boss room.
            local selected_card, selected_class = select_catalog_card(native_room_seed, true, false, 31)
            native_boss_class = selected_class
            native_card_list = native_boss_class and native_boss_class.cards or nil
        elseif room_type == "elite" then
            native_direct_card = false
            local selected_card, selected_class = select_catalog_card(native_room_seed, true, true, 47)
            native_boss_class = selected_class
            native_card_list = native_boss_class and native_boss_class.cards or nil
            if not native_boss_class then
                local fallback_card, fallback_class, fallback_slot =
                    select_catalog_card(native_room_seed, true, false, 53)
                native_boss_class = fallback_class
                native_card_list = fallback_class and fallback_class.cards or nil
            end
        else
            native_mode = "enemy"
            native_direct_card = false
            native_enemy_training_only = false
            -- The first phase is the original small-enemy composition.  Keep
            -- a seeded original Boss class/card ready for the post-wave
            -- nonspell instead of treating the room as enemy-only.
            local nonspell, selected_class, nonspell_slot = select_catalog_card(native_room_seed, false, false, 61)
            native_boss_class = selected_class
            native_card_list = build_native_card_sequence(selected_class, nonspell_slot)
            if not native_boss_class or not native_card_list then
                native_enemy_boss_error = "no original nonspell with a valid entrance sequence was selected"
            end
            -- Pick from the exact same wave list used by Enemy Practice.  The
            -- wave retains original constructor arguments and spawn timing.
            local original_wave = select_catalog_wave(native_room_seed)
            native_enemy_specs = build_native_enemy_specs(original_wave, native_room_seed)
        end
        scoredata = scoredata or {}
        scoredata.hiscore = scoredata.hiscore or {}
        stage.Set("TNRLegacyCard")
        stage.Change()
        restore_project_ui_image()
        return true
    end
    TNRNativeLegacy = {
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
                native_remote_player.support = math.min(5, math.max(4, count))
            end
            return true
        end,
        start_card = bridge_start_card,
        start_enemy_wave = bridge_start_enemy_wave,
        start_room = bridge_start_room,
        set_coop = function(enabled, local_player_id)
            local was_coop_enabled = native_coop_enabled
            native_coop_enabled = enabled == true
            native_local_player_id = tonumber(local_player_id) == 2 and 2 or 1
            if native_coop_enabled ~= was_coop_enabled then
                native_reset_aggro()
            end
            native_remote_input = {}
            native_remote_bomb_latched = false
            native_remote_bomb_tick = -1
            native_authoritative_enemy_states = nil
            native_authoritative_enemy_initialized = {}
            native_physical_bomb_previous = false
            native_bomb_request_previous = false
            native_local_bomb_latched = false
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
            support = 4,
            lh = 0,
            sp = nil,
            image = "reimu_player1",
            hidden = false,
        }
        native_remote_player.support = math.min(5,
            math.max(4, native_descriptor_support_count(native_remote_loadout_descriptor)))
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
            if native_remote_input.shoot and native_remote_player.shoot_cooldown <= 0
                    and reimu_player and type(reimu_player.shoot) == "function" then
                local support = math.max(0, tonumber(native_remote_player.support) or 4)
                local support_layout = native_remote_player.sp
                if type(support_layout) ~= "table" or not support_layout[1] then
                    support_layout = {
                        {-36, -12, 1}, {-16, -32, 1},
                        {16, -32, 1}, {36, -12, 1},
                    }
                end
                local current = stage and stage.current_stage
                local angle_layout = native_player.anglelist
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
                    slow = native_remote_input.focus and 1 or 0,
                    supportx = native_remote_player.supportx or native_remote_player.x,
                    supporty = native_remote_player.supporty or native_remote_player.y,
                    nextshoot = 0,
                    timer = current and (tonumber(current.frame_count) or 0) or 0,
                    target = nil,
                }
                if player_class and type(player_class.findtarget) == "function" then
                    pcall(player_class.findtarget, shooter)
                end
                local previous_owner = native_damage_owner_context
                native_damage_owner_context = remote_id
                pcall(reimu_player.shoot, shooter)
                native_damage_owner_context = previous_owner
                native_remote_player.shoot_cooldown = 4
            end
            -- A packet carries a monotonically increasing input tick. Use it
            -- as the Bomb edge identity instead of a boolean latch: cached
            -- packets and reconnects can otherwise either repeat one Bomb or
            -- swallow the next one.
            -- The transport may coalesce a Bomb edge with a newer movement
            -- packet. Preserve the original action tick for dedupe so the
            -- host relay is recognized as the client's own Bomb on return.
            local remote_bomb_tick = tonumber(native_remote_input.bomb_tick
                or native_remote_input.tick)
            local bomb_edge = native_remote_input.bomb == true
                and ((remote_bomb_tick and remote_bomb_tick ~= native_remote_bomb_tick)
                    or (not remote_bomb_tick and not native_remote_bomb_latched))
            if bomb_edge then
                native_remote_bomb_latched = true
                if remote_bomb_tick then native_remote_bomb_tick = remote_bomb_tick end
                -- A bomb is a shared arena action.  Use the same global
                -- destroyable-bullet group as the original PlayerSpell.
                native_clear_enemy_bullets()
                local remote_focus = native_remote_input.focus == true
                native_record_bomb(remote_id, remote_focus,
                    native_remote_input.bomb_tick or native_remote_input.tick)
                native_play_remote_bomb(remote_id, remote_focus)
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
            native_update_aggro_window()
            if native_input_replay and native_input_replay.clearExternalInput then
                native_input_replay.clearExternalInput()
            end
            -- Reconcile enemy HP/death state after the native update. The
            -- helper applies a coordinate only when an object is first seen;
            -- all subsequent movement remains local and smooth.
            native_apply_authoritative_enemy_states()
            -- The original player class consumes Bomb only when its cooldown
            -- and global Bomb count allow it. Publish exactly that edge to the
            -- peer; held X/input packets can never retrigger the effect.
            local bomb_after = lstg and lstg.var and tonumber(lstg.var.bomb)
            if native_player_state and bomb_after ~= nil then
                native_player_state.bomb = math.max(0, bomb_after)
            end
            if native_coop_enabled and input.bomb == true
                    and bomb_before and bomb_after and bomb_after < bomb_before
                    and nextspell_before <= 0 then
                native_record_bomb(native_local_player_id, input.focus == true, input.tick)
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
                -- Host publishes enemy HP/death and drop specifications. The
                -- client still simulates movement and creates its own local
                -- item objects, but uses this stream to keep counts equal.
                enemies = native_capture_enemy_states(current),
                enemy_spawned = current and current.enemy_spawned == true,
                bomb_generation = native_bomb_generation,
                bomb_owner = native_last_bomb_owner,
                bomb_focus = native_last_bomb_focus == true,
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
                            if native_is_valid_object(enemy_object) then
                                pcall(Del, enemy_object)
                            end
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
                        event.local_event, event.origin, event.input_tick)
                end
            else
                local incoming_bomb_generation = tonumber(snapshot.bomb_generation) or 0
                native_apply_remote_bomb_event(incoming_bomb_generation,
                    snapshot.bomb_owner, snapshot.bomb_focus)
            end
            local local_id = native_local_player_id
            local remote_id = local_id == 1 and 2 or 1
            if snapshot.respawn_frames then
                local incoming_frames = {
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
                    if player_id == local_id and native_respawn_frames[player_id] > 0 then
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
            local incoming_wipe = tonumber(snapshot.team_wipe_generation) or 0
            if incoming_wipe > native_team_wipe_generation then
                native_team_wipe_generation = incoming_wipe
                native_clear_enemy_bullets()
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
