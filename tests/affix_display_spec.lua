local Catalog = require("tnr.equipment.affix_catalog")
local Equipment = require("tnr.equipment.phase1_catalog")
local Instance = require("tnr.equipment.equipment_instance")
local Info = require("tnr.ui.equipment_info")
local Renderer = require("tnr.ui.map_renderer")
local GameSession = require("tnr.core.game_session")

return function(eq, yes)
    local legendary = Equipment.registry:get("hakurei_dream_sealing_needle")
    local one, two
    for seed = 1, 300 do
        local rolled = Catalog.roll(legendary, seed)
        local again = Catalog.roll(legendary, seed)
        eq(#rolled, #again, "legendary affix count is deterministic")
        for index, affix in ipairs(rolled) do
            eq(affix.id, again[index].id, "legendary affix identity is deterministic")
            eq(affix.level, again[index].level, "legendary affix tier is deterministic")
        end
        if #rolled == 1 then one = rolled end
        if #rolled == 2 then two = rolled; yes(rolled[1].id ~= rolled[2].id, "random affixes are distinct") end
    end
    yes(one ~= nil and two ~= nil, "legendary offers can have one or two random affixes")
    local item = Instance.new(legendary, 1, {random_affixes = two})
    local restored = Instance.from_table(item:to_table())
    eq(#restored.random_affixes, 2, "both legendary random affixes survive serialization")
    local lines = Info.describe(legendary, item)
    local icons = 0
    for _, line in ipairs(lines) do
        yes(not tostring(line.text):find("词条：", 1, true), "description omits the affix prefix")
        if line.icon then icons = icons + 1 end
    end
    eq(icons, 3, "legendary detail contains two random icons and an exclusive icon")
    eq(Catalog.tier_color({id="capacity",level=3})[2], 255, "highest three-tier affix is yellow")
    eq(Catalog.tier_color({id="capacity",level=2})[2], 240, "middle tier is white")
    eq(Catalog.tier_color({id="capacity",level=1})[2], 155, "lowest three-tier affix is grey")
    eq(Catalog.tier_color({id="combo",level=1})[2], 255, "single-tier affix is yellow")
    Catalog.by_id.two_tier_test = {values = {1, 2}}
    eq(Catalog.tier_color({id="two_tier_test",level=2})[2], 255, "highest of two tiers is yellow")
    eq(Catalog.tier_color({id="two_tier_test",level=1})[2], 240, "lower of two tiers is white")
    Catalog.by_id.two_tier_test = nil
    yes(Catalog.label({id="frost",level=1}):find("15%%") ~= nil, "level one frost describes its actual bonus")
    yes(Catalog.label({id="capacity",level=3}):find("40%%") ~= nil, "affix description contains numeric value")

    local calls = {}
    local mock = { Color = function() return {} end, SetImageState = function() end, RenderRect = function() end,
        RenderTTF = function(_, text, x, _, y) calls[#calls + 1] = {text=text,x=x,y=y} end,
        BeginScene = function() end, EndScene = function() end, RenderClear = function() end,
        SetViewport = function() end, SetScissorRect = function() end, SetOrtho = function() end, Render = function() end }
    local renderer = Renderer.new(mock, 1280, 720); renderer.white = "white"
    local output = renderer:draw_info_lines(lines, 90, 276, {size=.66,line_height=23,width=1100,height=125,columns=2})
    yes(output >= #lines, "wrapping never removes detail lines")
    local text = ""
    for _, call in ipairs(calls) do
        text = text .. call.text
        yes(call.x >= 90 and call.x <= 1190, "detail remains within horizontal bounds")
        yes(call.y >= 151 and call.y <= 276, "detail remains within vertical bounds")
    end
    for _, line in ipairs(lines) do
        yes(text:find(line.text, 1, true) ~= nil, "all detail text remains visible: " .. line.text)
    end
    local session = GameSession.new({run_seed=14}):start_new()
    session.reward_choices = {{kind="EQUIPMENT",definition_id=legendary.weapon_id,random_affixes=two}}
    local reward_lines = Info.describe_reward(session,session.reward_choices[1])
    local reward_icons=0; for _, line in ipairs(reward_lines) do if line.icon then reward_icons=reward_icons+1 end end
    eq(reward_icons, 3, "reward preview includes all three affixes")
    eq(renderer:reward_hit_test(100, 400, 3), 1, "reward card remains clickable")

    local function elite_reward()
        local game = GameSession.new({run_seed=419,player_count=1}):start_new()
        local elite
        for _, node in pairs(game.map.nodes) do if node.type == "ELITE" then elite = node break end end
        yes(elite ~= nil, "generated map contains an elite")
        game:debug_goto(elite.id)
        game:complete_battle({clear_state=true,reward_eligible=true,player_id=1})
        return game
    end
    local elite_a, elite_b = elite_reward(), elite_reward()
    local guarantee_a = elite_a.reward_guaranteed_equipment[1]
    local guarantee_b = elite_b.reward_guaranteed_equipment[1]
    yes(guarantee_a ~= nil and guarantee_b ~= nil, "guaranteed item remains available for inspection")
    eq(#guarantee_a.random_affixes, #guarantee_b.random_affixes, "guaranteed count is deterministic between peers")
    for index, affix in ipairs(guarantee_a.random_affixes) do
        eq(affix.id, guarantee_b.random_affixes[index].id, "guaranteed affix matches across peers")
        eq(affix.level, guarantee_b.random_affixes[index].level, "guaranteed tier matches across peers")
    end
    local guarantee_index = #elite_a.reward_choices + 1
    eq(renderer:reward_hit_test(500, 485, #elite_a.reward_choices, guarantee_index), guarantee_index,
        "guaranteed reward can be inspected")
    calls = {}
    renderer:render_reward(elite_a, guarantee_index, nil, nil, false)
    local displayed = ""; for _, call in ipairs(calls) do displayed = displayed .. call.text end
    for _, line in ipairs(Info.describe(elite_a.equipment_registry:get(guarantee_a.definition_id), guarantee_a)) do
        yes(displayed:find(line.text, 1, true) ~= nil, "guaranteed detail is fully displayed: " .. line.text)
    end
end
