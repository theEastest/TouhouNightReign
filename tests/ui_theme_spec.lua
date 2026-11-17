local Renderer = require("tnr.ui.map_renderer")
local GameSession = require("tnr.core.game_session")
local MapScene = require("tnr.map.map_scene")

return function(eq, yes)
    local rects = {}
    local rendered_texts = {}
    local mock = { Color = function() return {} end, SetImageState = function() end,
        RenderRect = function(_, left, right, bottom, top)
            rects[#rects + 1] = { left, right, bottom, top }
        end,
        RenderTTF = function(_, text, left, _, bottom)
            rendered_texts[#rendered_texts + 1] = { text = tostring(text), x = left, y = bottom }
        end, BeginScene = function() end, EndScene = function() end,
        RenderClear = function() end, SetViewport = function() end, SetScissorRect = function() end,
        SetOrtho = function() end, Render = function() end }
    local renderer = Renderer.new(mock, 1280, 720); renderer.white = "white"
    local replay_picker = {
        network_lobby = false,
        stage_list = function() return { {}, {}, {}, {}, {}, {} } end,
        PLAYER_COUNTS = { {}, {} }, MODES = { {}, {} }, CHARACTERS = { {}, {}, {}, {} },
    }
    local replay_row = renderer:replay_select_hit_test(200, 499, replay_picker)
    eq(replay_row.field, "stage", "replay picker detects stage rows")
    eq(replay_row.index, 1, "replay picker detects the clicked stage")
    local replay_start = renderer:replay_select_hit_test(640, 100, replay_picker)
    eq(replay_start.action, "start", "replay picker detects its start button")
    local backgrounds = 0
    local draw_standard_backdrop = renderer.draw_standard_backdrop
    renderer.draw_standard_backdrop = function() backgrounds = backgrounds + 1 end
    local panels = {}
    local draw_panel = renderer.draw_panel
    renderer.draw_panel = function(self, l, r, b, t)
        panels[#panels + 1] = {l,r,b,t}; return draw_panel(self,l,r,b,t)
    end
    local session = GameSession.new({run_seed=128}):start_new()
    local flood_frames = {}
    local draw_flooded_layers = renderer.draw_flooded_layers
    renderer.draw_flooded_layers = function(self, view, positions, left, right, bottom, top)
        local before = #rects
        draw_flooded_layers(self, view, positions, left, right, bottom, top)
        flood_frames[#flood_frames + 1] = {
            rect_count = #rects - before,
            front_x = rects[before + 1] and rects[before + 1][2],
        }
    end
    renderer:render_map(MapScene.new(session):get_view(), session)
    eq(backgrounds, 1, "ordinary map uses themed backdrop")
    local map_category_text_counts = { ["战斗"] = 0, ["事件"] = 0, ["精英"] = 0 }
    for _, entry in ipairs(rendered_texts) do
        if map_category_text_counts[entry.text] ~= nil then
            map_category_text_counts[entry.text] = map_category_text_counts[entry.text] + 1
        end
    end
    for label, count in pairs(map_category_text_counts) do
        eq(count, 1, "map category label appears only in the legend, never beneath nodes: " .. label)
    end
    eq(flood_frames[1].rect_count, 0, "starting layer has no flooded rooms")
    local flood_next_id = session.map:get_forward_links()[1]
    yes(session.map:select_node(flood_next_id) ~= nil, "map can advance to trigger the flood")
    renderer.ui_time = 0.1
    renderer:render_map(MapScene.new(session):get_view(), session)
    renderer.ui_time = 0.8
    renderer:render_map(MapScene.new(session):get_view(), session)
    yes(flood_frames[2].rect_count >= 42, "leaving a layer draws the deep-blue flood")
    yes(flood_frames[3].rect_count >= 42, "flood is redrawn as an animated wave")
    yes(flood_frames[2].front_x ~= flood_frames[3].front_x, "flood wavefront moves between frames")
    renderer.draw_flooded_layers = draw_flooded_layers
    backgrounds = 1
    panels = {}; renderer:render_preparation(session, 1, "", nil, nil, false, false, false)
    eq(backgrounds, 2, "ordinary preparation uses themed backdrop")
    local ordinary_detail
    for _, panel in ipairs(panels) do if panel[3] == 350 and panel[4] == 628 then ordinary_detail = panel end end
    yes(ordinary_detail ~= nil, "ordinary equipment detail panel exists")
    eq(ordinary_detail[1], 678, "ordinary equipment detail is wider")
    yes(ordinary_detail[1] > 100 + 3 * (130 + 14) + 130, "wider panel leaves four weapon slots unobstructed")
    local marisa = GameSession.new({run_seed=129})
    marisa:set_local_character("marisa"); marisa:start_new()
    local loadout = marisa:get_player(1).loadout
    local Instance = require("tnr.equipment.equipment_instance")
    for _ = 1, 12 do loadout.inventory:add(Instance.new(marisa.equipment_registry:get("test_high_weapon"), 1)) end
    local app = require("tnr.bootstrap").create({run_seed=129})
    app.session = marisa
    local rows, twelfth = app:_preparation_rows()
    for index, row in ipairs(rows) do if row.kind == "inventory" and row.index == 12 then twelfth = index end end
    eq(renderer:preparation_hit_test(1050, 110, #rows, 1, loadout), twelfth,
        "twelfth inventory slot is hit correctly with Marisa's four weapon slots")
    local original_hit, received_loadout = renderer.preparation_hit_test
    renderer.preparation_hit_test = function(self, x, y, count, cursor, actual_loadout)
        received_loadout = actual_loadout
        return original_hit(self, x, y, count, cursor, actual_loadout)
    end
    renderer:render_preparation(marisa, 1, "", 1050, 110, false, false, false)
    eq(received_loadout, loadout, "hover detail uses actual character slot counts")
    renderer.preparation_hit_test = original_hit
    local before_replay = backgrounds
    renderer.replay = {equipment_session = session}
    panels = {}; renderer:render_preparation(session, 1, "", nil, nil, false, false, true)
    eq(backgrounds, before_replay, "legacy replay preparation does not use ordinary themed backdrop")
    local replay_detail
    for _, panel in ipairs(panels) do if panel[3] == 396 and panel[4] == 628 then replay_detail = panel end end
    eq(replay_detail[1], 846, "legacy replay keeps its earlier detail position")
    local relic = session.relic_catalog.reimu_initial_relic_plus
    eq(relic.display_name_zh, "灵梦角色遗物·改", "relic preserves its localized display name")
    eq(relic.description, "强化后的灵梦专属遗物。", "relic preserves its description")
    session.relic_choices[1] = { "reimu_initial_relic_plus", "test_relic", "test_relic_bonus" }
    eq(renderer:relic_hit_test(session, 500, 485, 1), 1, "upper half of first relic row is clickable")
    eq(renderer:relic_hit_test(session, 500, 445, 1), 1, "lower half of first relic row is clickable")
    eq(renderer:relic_hit_test(session, 500, 415, 1), nil, "gap between relic rows is not clickable")
    eq(renderer:relic_hit_test(session, 200, 465, 1), nil, "outside relic panel is not clickable")

    local labels = {}
    local api = {Color=function(...) return {...} end, SetImageState=function() end, RenderRect=function() end,
        RenderTTF=function(_, text, _, _, y) labels[text] = y end}
    local Gauge = require("tnr.character.runtime.p_gauge")
    local gauge = Gauge.new(); gauge.value = 61; gauge.progress = 35
    require("tnr.character.runtime.fallback_p_gauge").render({lstg=api, runtime={
        players={[1]={x=400,y=300,combat_runtime={p_gauge=gauge}}},p_pickups={}}})
    yes(labels["P1 61.0%"] > 542, "P label is above its meter")
    yes(labels["渴血兽 35%"] > 497, "thirst label is above its meter")

    renderer.draw_standard_backdrop = draw_standard_backdrop
    local before_animation = renderer.ui_time or 0
    renderer:draw_standard_backdrop()
    yes(renderer.ui_time > before_animation, "ordinary UI advances its ambient animation clock")
    rects = {}
    renderer.ui_time = 0.5
    renderer:draw_focus_frame(100, 400, 100, 180, 0)
    local first_glint_x = rects[#rects][1]
    rects = {}
    renderer.ui_time = 0.6
    renderer:draw_focus_frame(100, 400, 100, 180, 0)
    local second_glint_x = rects[#rects][1]
    yes(first_glint_x ~= second_glint_x, "selected-panel glint moves smoothly across frames")
end
