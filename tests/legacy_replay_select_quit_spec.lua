-- The replay select screen must not quit the game when a stage is confirmed.
--
-- The main menu signals "quit" by returning true from its activation helper,
-- because that is how 退出游戏 asks the main loop to stop. The replay select
-- screen once forwarded the start result the same way, so confirming a stage
-- ended the run on the next frame instead of entering the stage. That is the
-- instant exit that was reported when 旧作重演 was opened.
--
-- These tests pin the two facts that matter: confirming starts the stage, and
-- confirming does not propagate a quit outward.

return function(assert_equal, assert_true, assert_false)
    local function load_bootstrap()
        package.loaded["tnr.bootstrap"] = nil
        package.loaded["tnr.ui.title_assets"] = nil
        return require("tnr.bootstrap")
    end

    local function fake_replay()
        local replay = {
            started = 0,
            data = true,
            stage_cursor = 1,
            mode_cursor = 1,
            character_cursor = 1,
            player_count_cursor = 1,
        }
        replay.ensure_data = function() return replay.data end
        replay.start_stage = function(self)
            self.started = self.started + 1
            return true
        end
        replay.stop = function() end
        replay.move_cursor = function() end
        replay.stage_list = function() return { { key = "st01" } } end
        replay.PLAYER_COUNTS = { { key = 1 } }
        replay.MODES = { { key = "modern" } }
        replay.CHARACTERS = { { key = "reimu" } }
        return replay
    end

    -- Confirming a stage enters the stage and reports "keep running".
    local Bootstrap = load_bootstrap()
    local Constants = require("tnr.core.constants")
    local instance = setmetatable({
        session = { run_state = Constants.run_states.REPLAY_SELECT },
        replay = fake_replay(),
        replay_field = "stage",
        start_replay_stage = Bootstrap.start_replay_stage,
        _update_replay_select = Bootstrap._update_replay_select,
    }, { __index = Bootstrap })
    local quit = instance:_update_replay_select({ confirm = true })
    assert_false(quit == true, "confirming a stage must not quit the game")
    assert_equal(instance.replay.started, 1, "confirming starts the stage once")
    assert_equal(instance.session.run_state, Constants.run_states.REPLAY_STAGE,
        "confirming moves into the stage")

    -- Cancelling leaves the select screen without starting a stage.
    local cancel_instance = setmetatable({
        session = { run_state = Constants.run_states.REPLAY_SELECT },
        replay = fake_replay(),
        replay_field = "stage",
        close_replay_select = function(self)
            self.closed = true
            self.session.run_state = Constants.run_states.MENU
        end,
        start_replay_stage = Bootstrap.start_replay_stage,
        _update_replay_select = Bootstrap._update_replay_select,
    }, { __index = Bootstrap })
    local cancel_quit = cancel_instance:_update_replay_select({ cancel = true })
    assert_false(cancel_quit == true, "cancelling must not quit the game")
    assert_equal(cancel_instance.replay.started, 0, "cancelling does not start a stage")
    assert_true(cancel_instance.closed, "cancelling closes the select screen")

    -- Moving the cursors must not start or end anything.
    local move_instance = setmetatable({
        session = { run_state = Constants.run_states.REPLAY_SELECT },
        replay = fake_replay(),
        replay_field = "stage",
        start_replay_stage = Bootstrap.start_replay_stage,
        _update_replay_select = Bootstrap._update_replay_select,
    }, { __index = Bootstrap })
    move_instance:_update_replay_select({ move_y = 1 })
    assert_equal(move_instance.replay.started, 0, "moving does not start a stage")

    -- The main menu still reports its own quit, so the fix did not disable it.
    local menu_instance = setmetatable({
        session = { run_state = Constants.run_states.MENU, player_count = 1, local_player_id = 1 },
        menu_cursor = 10,
        _update_replay_select = Bootstrap._update_replay_select,
        open_replay_select = function(self) self.opened = true end,
        _activate_main_menu = Bootstrap._activate_main_menu,
    }, { __index = Bootstrap })
    local menu_quit = menu_instance:_activate_main_menu(9)
    assert_true(menu_quit == true, "退出游戏 still reports a quit")
end
