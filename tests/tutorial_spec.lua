local Bootstrap = require("tnr.bootstrap")
local Constants = require("tnr.core.constants")
local Renderer = require("tnr.ui.map_renderer")
local Pages = require("tnr.ui.tutorial_pages")

return function(eq, yes)
    local calls = {}
    local mock = { Color = function() return {} end, SetImageState = function() end, RenderRect = function() end,
        RenderTTF = function(_, text, x, _, y) calls[#calls + 1] = {text=text,x=x,y=y} end,
        BeginScene = function() end, EndScene = function() end, RenderClear = function() end,
        SetViewport = function() end, SetScissorRect = function() end, SetOrtho = function() end, Render = function() end }
    local renderer = Renderer.new(mock, 1280, 720); renderer.white = "white"
    eq(renderer:menu_hit_test(160, 80), 11, "tutorial occupies the eleventh menu cell")
    eq(renderer:tutorial_hit_test(120, 90), "prev", "previous button hit test")
    eq(renderer:tutorial_hit_test(1100, 90), "next", "next button hit test")
    eq(renderer:tutorial_hit_test(1100, 610), "exit", "exit button hit test")
    calls = {}; renderer:render_menu(11)
    local menu_label = false
    for _, call in ipairs(calls) do if call.text == "新手教程" then menu_label = true end end
    yes(menu_label, "main menu visibly labels the tutorial entry")
    for i, page in ipairs(Pages) do
        calls = {}; renderer:render_tutorial(i, nil, nil)
        local rendered = {}; for _, call in ipairs(calls) do
            rendered[call.text] = true
            yes(call.x >= 0 and call.x <= 1280 and call.y >= 0 and call.y <= 720, "tutorial text anchor stays on screen")
        end
        yes(rendered[page.title], "tutorial page title is drawn")
        for _, text in ipairs(page.lines) do yes(rendered[text], "tutorial page text is drawn") end
    end
    local app = Bootstrap.create({run_seed=88})
    app.renderer = renderer; app:init(); app.menu_cursor = 11
    local function step(input) app.input:set_pending(input); app:update() end
    step({confirm=true})
    eq(app.session.run_state, Constants.run_states.TUTORIAL, "menu enters tutorial")
    eq(app.tutorial_page, 1, "tutorial opens on first page")
    step({move_x=1}); eq(app.tutorial_page, 2, "right moves forward")
    step({move_x=1}); eq(app.tutorial_page, 2, "held direction does not skip pages")
    step({move_x=0}); step({move_x=-1}); eq(app.tutorial_page, 1, "left returns to previous page")
    step({move_x=0}); step({move_x=-1}); eq(app.tutorial_page, 1, "previous does not leave first page")
    for _ = 2, #Pages do step({confirm=true}) end
    eq(app.tutorial_page, #Pages, "confirm advances to final page")
    step({confirm=true}); eq(app.session.run_state, Constants.run_states.MENU, "completing tutorial returns to menu")
    app:_activate_main_menu(11)
    eq(app.tutorial_page, 1, "reopening resets the tutorial")
    local mouse_x, mouse_y = 1100, 90
    app.input.get_mouse_position = function() return mouse_x, mouse_y end
    step({mouse_primary_pressed=true}); eq(app.tutorial_page, 2, "mouse advances a page")
    mouse_x = 120; step({mouse_primary_pressed=true}); eq(app.tutorial_page, 1, "mouse returns a page")
    mouse_x, mouse_y = 1100, 610; step({mouse_primary_pressed=true})
    eq(app.session.run_state, Constants.run_states.MENU, "mouse exit returns to menu")
    app:_activate_main_menu(11); step({cancel=true})
    eq(app.session.run_state, Constants.run_states.MENU, "escape returns to menu")
end
