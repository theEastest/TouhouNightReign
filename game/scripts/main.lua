-- LuaSTG Sub entry point. Engine-specific rendering is kept in this thin adapter.
local lstg = require("lstg")

-- The playable runtime is backed by the reference THlib object model.  The
-- project adapter only selects rooms and forwards input; it does not replace
-- the original card/enemy scripts with fabricated compatibility patterns.
lstg.DoFile("legacy_native_main.lua")

local Bootstrap = require("tnr.bootstrap")
local LANTransport = require("tnr.multiplayer.lan_transport")

local function env_number(name, fallback)
    return tonumber(os.getenv(name)) or fallback
end

local network_mode = os.getenv("TNR_NETWORK_MODE")
local local_player_id = env_number("TNR_PLAYER_ID", network_mode == "client" and 2 or 1)
local bootstrap_options = {
    lstg = lstg,
    stage = rawget(_G, "stage"),
    run_seed = env_number("TNR_RUN_SEED", nil),
    player_count = env_number("TNR_PLAYER_COUNT", (network_mode == "host" or network_mode == "client") and 2 or 1),
    local_player_id = local_player_id,
    -- Equipment editing is optional. Selecting a map node should enter the
    -- room directly; the map's `i` button opens preparation on demand.
    preparation_required = false,
}
if network_mode == "host" or network_mode == "client" then
    bootstrap_options.network_role = network_mode
    bootstrap_options.player_count = 2
    bootstrap_options.transport = LANTransport.new({
        mode = network_mode,
        player_id = local_player_id,
        host = os.getenv("TNR_HOST") or (network_mode == "host" and "0.0.0.0" or "127.0.0.1"),
        port = env_number("TNR_PORT", 27123),
    })
end

local game = Bootstrap.create(bootstrap_options)
-- Native reference scripts route through the same coordinator as the project
-- UI. This must be attached before GameInit so the title BGM and every later
-- legacy PlayMusic call obey the single-track rule.
game.audio:attach_native()

function GameInit()
    lstg.LoadTexture("tnr-white-texture", "assets/texture/white.png", false)
    lstg.LoadImage("tnr-white", "tnr-white-texture", 0, 0, 16, 16)
    -- Playable character sprite sheets. Each is loaded independently and a
    -- missing sheet is skipped so one absent character cannot break the boot.
    local character_sheets = {
        reimu = "assets/players/reimu/reimu.png",
        marisa = "assets/players/marisa/marisa.png",
        sanae = "assets/players/sanae/sanae.png",
    }
    for character_id, path in pairs(character_sheets) do
        local key = "tnr-" .. character_id .. "-texture"
        local image_group = "tnr-" .. character_id
        local ok_texture = pcall(lstg.LoadTexture, key, path, false)
        if ok_texture then
            if lstg.LoadImageGroup then
                pcall(lstg.LoadImageGroup, image_group, key, 0, 0, 32, 48, 8, 3, 0.5, 0.5)
            else
                for row = 0, 2 do
                    for column = 0, 7 do
                        local frame = row * 8 + column + 1
                        pcall(lstg.LoadImage, image_group .. frame, key, column * 32, row * 48, 32, 48, 16, 24)
                    end
                end
            end
            -- Straight shots reuse the top row of the sheet.
            pcall(lstg.LoadImage, image_group .. "-red", key, 192, 160, 64, 16, 16, 16)
            pcall(lstg.LoadImage, image_group .. "-blue", key, 0, 160, 16, 16, 16, 16)
        end
    end
    -- Compatibility aliases: the fallback renderer and older code refer to the
    -- Reimu-named images directly.
    lstg.LoadTexture("tnr-reimu-texture", "assets/players/reimu/reimu.png", false)
    if lstg.LoadImageGroup then
        lstg.LoadImageGroup("tnr-reimu", "tnr-reimu-texture", 0, 0, 32, 48, 8, 3, 0.5, 0.5)
    else
        for row = 0, 2 do
            for column = 0, 7 do
                local frame = row * 8 + column + 1
                lstg.LoadImage("tnr-reimu" .. frame, "tnr-reimu-texture", column * 32, row * 48, 32, 48, 16, 24)
            end
        end
    end
    lstg.LoadImage("tnr-reimu-red", "tnr-reimu-texture", 192, 160, 64, 16, 16, 16)
    lstg.LoadImage("tnr-reimu-blue", "tnr-reimu-texture", 0, 160, 16, 16, 16, 16)
    lstg.LoadTexture("tnr-night-road-texture", "assets/backgrounds/night_road/gzz6bg1.png", false)
    lstg.LoadImage("tnr-bg-night-road", "tnr-night-road-texture", 0, 0, 512, 512, 256, 256)
    for index = 2, 5 do
        local key = "tnr-night-road-texture-" .. index
        local image = "tnr-bg-night-road-" .. index
        lstg.LoadTexture(key, "assets/backgrounds/night_road/gzz6bg" .. index .. ".png", false)
        local size = index == 5 and 256 or 512
        lstg.LoadImage(image, key, 0, 0, size, size, size * 0.5, size * 0.5)
    end
    lstg.LoadTexture("tnr-reimu-boss-texture", "assets/bosses/reimu/reimu_boss.png", false)
    lstg.LoadImage("tnr-reimu-boss", "tnr-reimu-boss-texture", 0, 0, 200, 390, 100, 195)
    lstg.LoadTexture("tnr-sanae-boss-texture", "assets/bosses/sanae/sanae_boss.png", false)
    lstg.LoadImage("tnr-sanae-boss", "tnr-sanae-boss-texture", 0, 0, 241, 387, 120, 193)
    lstg.LoadTexture("tnr-sanae-sc-bg1-texture", "assets/bosses/spellcard/sf_sanae_bg1.png", false)
    lstg.LoadImage("tnr-sanae-sc-bg1", "tnr-sanae-sc-bg1-texture", 0, 0, 384, 448, 192, 224)
    lstg.LoadTexture("tnr-sanae-sc-bg2-texture", "assets/bosses/spellcard/sf_sanae_bg2.png", false)
    lstg.LoadImage("tnr-sanae-sc-bg2", "tnr-sanae-sc-bg2-texture", 0, 0, 256, 256, 128, 128)
    -- Imported THlib sheets remain available to project UI and native content
    -- fallback paths, while native rooms use the original registrations.
    -- `legacy-data` is already mounted at legacy/assets/data/ by config.json.
    -- Resource paths therefore start at Thlib/, not legacy/assets/data/Thlib/.
    lstg.LoadTexture("tnr-thlib-bullet-texture", "Thlib/bullet/bullet1.png", false)
    -- The source image groups use the original THlib world-size multipliers:
    -- 2.5 for 16px bullets, 4 for 32px bullets, and 4.5 for ellipses.
    lstg.LoadImage("tnr-thlib-bullet-arrow", "tnr-thlib-bullet-texture", 0, 0, 16, 16, 8, 8)
    lstg.LoadImage("tnr-thlib-bullet-gun", "tnr-thlib-bullet-texture", 24, 0, 16, 16, 8, 8)
    lstg.LoadImage("tnr-thlib-bullet-void", "tnr-thlib-bullet-texture", 56, 0, 16, 16, 8, 8)
    lstg.LoadImage("tnr-thlib-bullet-butterfly", "tnr-thlib-bullet-texture", 112, 0, 32, 32, 16, 16)
    lstg.LoadImage("tnr-thlib-bullet-square", "tnr-thlib-bullet-texture", 152, 0, 16, 16, 8, 8)
    lstg.LoadImage("tnr-thlib-bullet-ball", "tnr-thlib-bullet-texture", 176, 0, 32, 32, 16, 16)
    lstg.LoadImage("tnr-thlib-bullet-mildew", "tnr-thlib-bullet-texture", 208, 0, 16, 16, 8, 8)
    lstg.LoadImage("tnr-thlib-bullet-ellipse", "tnr-thlib-bullet-texture", 224, 0, 32, 32, 16, 16)
    lstg.LoadTexture("tnr-thlib-bullet2-texture", "Thlib/bullet/bullet2.png", false)
    lstg.LoadImage("tnr-thlib-bullet-star", "tnr-thlib-bullet2-texture", 224, 0, 32, 32, 16, 16)
    lstg.LoadTexture("tnr-thlib-enemy-texture", "Thlib/enemy/enemy1.png", false)
    -- Match the coordinates used by THlib's enemy.lua, rather than the
    -- unrelated top-left cells of the sheet.
    lstg.LoadImage("tnr-thlib-enemy1", "tnr-thlib-enemy-texture", 0, 384, 32, 32, 16, 16)
    lstg.LoadImage("tnr-thlib-enemy25", "tnr-thlib-enemy-texture", 0, 192, 64, 64, 32, 32)
    local enemy1_frames = {
        { 0, 384, 32, 32 }, { 0, 416, 32, 32 }, { 0, 448, 32, 32 }, { 0, 480, 32, 32 },
        { 0, 0, 48, 32 }, { 0, 96, 48, 32 }, { 320, 0, 48, 48 }, { 320, 144, 48, 48 },
        { 0, 192, 64, 64 },
    }
    for index, frame in ipairs(enemy1_frames) do
        lstg.LoadImage("tnr-thlib-enemy-style-" .. index, "tnr-thlib-enemy-texture", frame[1], frame[2], frame[3], frame[4], frame[3] * 0.5, frame[4] * 0.5)
    end
    lstg.LoadTexture("tnr-thlib-enemy2-texture", "Thlib/enemy/enemy2.png", false)
    lstg.LoadImage("tnr-thlib-enemy13", "tnr-thlib-enemy2-texture", 0, 96, 32, 32, 16, 16)
    local enemy2_frames = {
        { 0, 0, 32, 32 }, { 0, 32, 32, 32 }, { 0, 64, 32, 32 }, { 0, 96, 32, 32 },
        { 0, 128, 64, 64 }, { 0, 288, 32, 32 }, { 0, 352, 32, 32 }, { 0, 416, 32, 32 }, { 0, 480, 32, 32 },
    }
    for offset, frame in ipairs(enemy2_frames) do
        local index = offset + 9
        lstg.LoadImage("tnr-thlib-enemy-style-" .. index, "tnr-thlib-enemy2-texture", frame[1], frame[2], frame[3], frame[4], frame[3] * 0.5, frame[4] * 0.5)
    end
    lstg.LoadTexture("tnr-thlib-boss-ui-texture", "Thlib/enemy/boss.png", false)
    lstg.LoadImage("tnr-boss-hpbar", "tnr-thlib-boss-ui-texture", 116, 0, 8, 128, 4, 64)
    lstg.LoadImage("tnr-boss-spell-effect", "tnr-thlib-boss-ui-texture", 96, 0, 16, 128, 8, 64)
    -- Activity boss animation and arena layers. These are kept as project
    -- aliases so the active runtime never has to load legacy globals.
    lstg.LoadTexture("tnr-legacy-void-boss-texture", "void_boss1.png", false)
    local void_boss_frames = {}
    for row = 0, 2 do
        for column = 0, 3 do
            local index = row * 4 + column + 1
            local image = "tnr-legacy-void-boss-" .. index
            lstg.LoadImage(image, "tnr-legacy-void-boss-texture", column * 64, row * 64, 64, 64, 32, 32)
            void_boss_frames[index] = image
        end
    end
    lstg.LoadTexture("tnr-legacy-void-bg-texture", "void_boss1bg.png", false)
    lstg.LoadImage("tnr-legacy-void-bg", "tnr-legacy-void-bg-texture", 0, 0, 1024, 1024, 512, 512)
    lstg.LoadTexture("tnr-legacy-buduc-bg-texture", "buducdbga.png", false)
    lstg.LoadImage("tnr-legacy-buduc-bg", "tnr-legacy-buduc-bg-texture", 0, 0, 960, 640, 480, 320)
    lstg.LoadTexture("tnr-legacy-void-fx-texture", "void_boss1bgb.png", false)
    lstg.LoadImage("tnr-legacy-void-fx", "tnr-legacy-void-fx-texture", 0, 0, 512, 512, 256, 256)
    lstg.LoadTexture("tnr-legacy-sf-effect-texture", "sf_bossheet.png", false)
    lstg.LoadImage("tnr-legacy-sf-effect", "tnr-legacy-sf-effect-texture", 0, 0, 1356, 631, 678, 315)
    lstg.LoadTexture("tnr-legacy-charge-texture", "charge_circie.png", false)
    lstg.LoadImage("tnr-legacy-charge", "tnr-legacy-charge-texture", 0, 0, 256, 256, 128, 128)
    lstg.LoadTexture("tnr-legacy-qxs-boss-texture", "qxs_Boss.png", false)
    lstg.LoadImage("tnr-legacy-qxs-boss", "tnr-legacy-qxs-boss-texture", 0, 0, 256, 341, 128, 170)
    lstg.LoadTexture("tnr-legacy-stupid-boss-texture", "stupid_boss.png", false)
    lstg.LoadImage("tnr-legacy-stupid-boss", "tnr-legacy-stupid-boss-texture", 0, 0, 360, 309, 180, 154)
    game.audio:load()
    game.audio:play_music("menu")
    lstg.LoadTTF("Sans", "assets/font/SourceHanSansCN-Bold.otf", 48, 48)
    game:init()
    if os.getenv("TNR_NATIVE_INPUT_SELFTEST") == "1" then
        local test_ok, test_error = pcall(function()
            assert(TNRNativeLegacy and TNRNativeLegacy.start_room, "native bridge is unavailable")
            assert(TNRNativeLegacy.start_room("enemy", 20260826), "native test room could not start")
            TNRNativeLegacy.set_coop(false, 1)
            local bridge = TNRNativeLegacy
            local GameSession = require("tnr.core.game_session")
            local CharacterRuntimeBridge = require("tnr.character.runtime.character_runtime_bridge")
            local runtime_session = GameSession.new({ run_seed = 20260826, player_count = 1 })
            runtime_session:start_new(20260826)
            local runtime_bridge = CharacterRuntimeBridge.new(
                runtime_session, 1, runtime_session.equipment_registry)
            local runtime_driver = runtime_bridge:create_runtime()
            bridge.set_runtime_drivers(runtime_driver, nil)
            bridge.set_loadout_descriptors(runtime_driver.descriptor, nil)
            bridge.set_runtime_active(true)
            local before = assert(bridge.state().player, "native test player was not created")
            local before_x = before.x
            local function managed_bullet_state()
                local count = 0
                local found_default_sprite = false
                if ObjList and GROUP_PLAYER_BULLET then
                    for _, bullet in ObjList(GROUP_PLAYER_BULLET) do
                        if bullet._tnr_managed_projectile then
                            count = count + 1
                            if bullet.tnr_projectile_type == "reimu_normal"
                                    and bullet.img == "reimu_bullet_red" then
                                found_default_sprite = true
                            end
                        end
                    end
                end
                return count, found_default_sprite
            end
            local bullets_before = managed_bullet_state()
            bridge.update({ _native_input_override = true, player_id = 1, move_x = 1, move_y = 0, shoot = true })
            local after = assert(bridge.state().player, "native test player disappeared after movement")
            assert(after.x > before_x, "native input self-test: movement did not change player x")
            -- Native objects created immediately before DoFrame enter the
            -- enumerable object pool on the following frame.
            bridge.update({ _native_input_override = true, player_id = 1, move_x = 0, move_y = 0, shoot = false })
            local bullets_after, found_default_sprite = managed_bullet_state()
            local runtime_state = bridge.state()
            local last_projectile = runtime_state.runtime_last_projectile
            assert(runtime_state.runtime_active == true and runtime_state.runtime_shot_calls > 0,
                "native input self-test: formal runtime emitted no shots"
                    .. " (hide=" .. tostring(after.hide)
                    .. ", lock=" .. tostring(after.lock)
                    .. ", death=" .. tostring(after.death)
                    .. ", weapons=" .. tostring(#runtime_driver.weapon_manager.weapons)
                    .. ", projectile=" .. tostring(last_projectile) .. ")")
            assert(bullets_after > bullets_before,
                "native input self-test: emitted shots did not remain in the player bullet pool"
                    .. " (before=" .. tostring(bullets_before)
                    .. ", after=" .. tostring(bullets_after)
                    .. ", valid=" .. tostring(last_projectile and IsValid(last_projectile))
                    .. ", group=" .. tostring(last_projectile and last_projectile.group)
                    .. ", status=" .. tostring(last_projectile and last_projectile.status)
                    .. ", img=" .. tostring(last_projectile and last_projectile.img) .. ")")
            assert(found_default_sprite,
                "native input self-test: default Reimu shot did not use its visible sprite")
            assert(runtime_state.legacy_shot_calls == 0,
                "native input self-test: legacy Reimu volley was not suppressed")
            local bomb_before = tonumber(lstg.var.bomb) or 0
            bridge.update({ _native_input_override = true, player_id = 1, move_x = 0, move_y = 0, bomb = true })
            assert((tonumber(lstg.var.bomb) or bomb_before) < bomb_before,
                "native input self-test: bomb input did not consume a bomb")
            local bomb_after_first = tonumber(lstg.var.bomb) or bomb_before
            bridge.update({ _native_input_override = true, player_id = 1, move_x = 0, move_y = 0, bomb = true })
            assert((tonumber(lstg.var.bomb) or bomb_after_first) == bomb_after_first,
                "native input self-test: held bomb input repeated")
            bridge.update({ _native_input_override = true, player_id = 1, bomb = false })
            bridge.set_coop(true, 1)
            local remote_before = assert(bridge.state().remote_player, "native test remote player was not created")
            local remote_x = remote_before.x
            bridge.update_remote({ player_id = 2, move_x = 1, move_y = 0 })
            assert(bridge.state().remote_player.x > remote_x,
                "native input self-test: remote movement did not change remote player x")
        end)
        local result_file = io.open("native_input_selftest.result", "w")
        if result_file then
            result_file:write(test_ok and "passed\n" or ("failed: " .. tostring(test_error) .. "\n"))
            result_file:close()
        end
        if not test_ok then error(test_error) end
        print("TNR native input self-test passed")
    end
    if os.getenv("TNR_NATIVE_AUTO_ROOM") then
        -- Development smoke path for room adapters: generate a seeded map and
        -- jump to the first requested native room without menu automation.
        local requested_room = os.getenv("TNR_NATIVE_AUTO_ROOM"):upper()
        game:start_game(env_number("TNR_RUN_SEED", nil))
        for node_id, node in pairs(game.session.map.nodes) do
            if node.type == requested_room then
                game.session:debug_goto(node_id)
                break
            end
        end
    end
    if os.getenv("TNR_NATIVE_AUTO_CARD") == "1" then
        -- Development smoke path: enter the first generated legacy card so
        -- the native object pool can be verified without menu automation.
        local training_catalog = require("tnr.training.card_training_catalog")
        for index, card in ipairs(training_catalog) do
            if card.legacy_boss and card.legacy_card_slot then
                game.selection_kind = "card"
                game.selection_catalog = training_catalog
                game:start_selected_training(index)
                break
            end
        end
    end
    local auto_enemy_wave = os.getenv("TNR_NATIVE_AUTO_ENEMY_WAVE")
    if auto_enemy_wave and auto_enemy_wave ~= "" then
        local enemy_training_catalog = require("tnr.training.enemy_training_catalog")
        game:start_game(env_number("TNR_RUN_SEED", nil))
        game.selection_kind = "enemy"
        game.selection_catalog = enemy_training_catalog
        game:start_selected_training(auto_enemy_wave)
    end
    if game.battle_sync:is_networked() then
        local connected, connect_error = game.transport:connect()
        if not connected then
            game.stage_adapter.network_status = "NETWORK ERROR: " .. tostring(connect_error)
            if game._network_trace then
                game:_network_trace("network_initial_connect_failed", {
                    error = connect_error or game.transport.last_error or "unknown",
                })
            end
        end
    end
    if os.getenv("TNR_EMPTY_ROOM") == "1" then
        game:start_game(bootstrap_options.run_seed)
        game.session.run_state = "ENCOUNTER"
        game.stage_adapter:start_empty_room()
    end
end

function GameExit()
    if game.transport.disconnect then
        game.transport:disconnect()
    end
    game:shutdown()
end

function FrameFunc()
    return game:update()
end

function RenderFunc()
    game:render()
end
