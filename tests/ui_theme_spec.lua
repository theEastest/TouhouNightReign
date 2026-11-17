local Renderer = require("tnr.ui.map_renderer")
local GameSession = require("tnr.core.game_session")
local MapScene = require("tnr.map.map_scene")

return function(eq, yes)
    local mock = { Color = function() return {} end, SetImageState = function() end, RenderRect = function() end,
        RenderTTF = function() end, BeginScene = function() end, EndScene = function() end,
        RenderClear = function() end, SetViewport = function() end, SetScissorRect = function() end,
        SetOrtho = function() end, Render = function() end }
    local renderer = Renderer.new(mock, 1280, 720); renderer.white = "white"
    local backgrounds = 0
    renderer.draw_standard_backdrop = function() backgrounds = backgrounds + 1 end
    local panels = {}
    local draw_panel = renderer.draw_panel
    renderer.draw_panel = function(self, l, r, b, t)
        panels[#panels + 1] = {l,r,b,t}; return draw_panel(self,l,r,b,t)
    end
    local session = GameSession.new({run_seed=128}):start_new()
    renderer:render_map(MapScene.new(session):get_view(), session)
    eq(backgrounds, 1, "ordinary map uses themed backdrop")
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
end
