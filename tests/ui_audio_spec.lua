local Bootstrap = require("tnr.bootstrap")

return function(eq)
    local sounds = {}
    local app = Bootstrap.create({ run_seed = 713 })
    app.audio = {
        play = function(_, key) sounds[#sounds + 1] = key end,
        load = function() end,
    }
    app:init()
    app.session.run_state = require("tnr.core.constants").run_states.MENU

    local function step(input)
        app.input:set_pending(input)
        app:update()
    end

    step({ move_x = 1 })
    eq(app.menu_cursor, 2, "main menu cursor moves right")
    eq(sounds[1], "ui_move", "cursor movement plays the navigation sound")

    step({ move_y = 1 })
    eq(app.menu_cursor, 11, "bottom row clamps to its second live item")
    eq(sounds[2], nil, "rapid held movement is rate limited")
    step({ move_x = 1 })
    eq(app.menu_cursor, 10, "bottom-row horizontal movement wraps across live items")
    step({ move_x = 1 })
    eq(app.menu_cursor, 11, "bottom-row navigation never lands on the empty cell")

    step({ confirm = true })
    eq(sounds[#sounds], "ui_confirm", "confirm key plays the confirmation sound")

    step({ cancel = true })
    eq(sounds[#sounds], "ui_cancel", "cancel key plays the back sound")
end
