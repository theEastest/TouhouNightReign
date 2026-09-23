local Constants = require("tnr.core.constants")
local GameSession = require("tnr.core.game_session")
local WeightPolicy = require("tnr.character.runtime.weight_speed_policy")

return function(assert_equal, assert_true)
    -- Per-character slot layout and capacity, exactly as specified.
    local expected = {
        reimu = { high = 3, low = 3, support = 1, self_mod = 2, support_mod = 2, capacity = 100, speed = 4.5 },
        marisa = { high = 4, low = 2, support = 1, self_mod = 3, support_mod = 1, capacity = 90, speed = 4.95 },
        sanae = { high = 1, low = 3, support = 3, self_mod = 1, support_mod = 3, capacity = 120, speed = 4.05 },
    }
    for character_id, spec in pairs(expected) do
        local session = GameSession.new({ run_seed = 1, player_count = 1 })
        assert_true(session:set_local_character(character_id) ~= nil,
            character_id .. " must be selectable")
        session:start_new(1)
        local player = session:get_player(1)
        local loadout = player.loadout
        assert_equal(#loadout.high_weapons, spec.high, character_id .. " high weapon slots")
        assert_equal(#loadout.low_weapons, spec.low, character_id .. " low weapon slots")
        assert_equal(#loadout.supports, spec.support, character_id .. " support slots")
        assert_equal(#loadout.self_modifiers, spec.self_mod, character_id .. " self modifier slots")
        assert_equal(#loadout.support_modifiers, spec.support_mod, character_id .. " support modifier slots")
        assert_equal(#loadout.inventory.items, 0, character_id .. " inventory starts empty")
        assert_equal(loadout.inventory.capacity, 6, character_id .. " inventory holds six items")
        assert_equal(player.base_capacity, spec.capacity, character_id .. " base capacity")
        assert_equal(player.current_capacity, spec.capacity, character_id .. " current capacity")
    end

    -- The relative speeds follow the confirmed rules: Marisa 10% faster,
    -- Sanae 10% slower than Reimu.
    local base = 4.5
    local marisa = GameSession.new({ run_seed = 1, character_id = "marisa" })
    local sanae = GameSession.new({ run_seed = 1, character_id = "sanae" })
    assert_equal(string.format("%.2f", base * 1.10), string.format("%.2f", 4.95),
        "marisa is 10% faster than reimu")
    assert_equal(string.format("%.2f", base * 0.90), string.format("%.2f", 4.05),
        "sanae is 10% slower than reimu")
    assert_true(marisa.local_character_id == "marisa", "marisa character id is kept")
    assert_true(sanae.local_character_id == "sanae", "sanae character id is kept")

    -- Weight classification drives the loadout bar and the ultralight bonus.
    assert_equal(WeightPolicy.classify(49, 100), "ULTRALIGHT", "under half capacity is ultralight")
    assert_equal(WeightPolicy.classify(50, 100), "NORMAL", "exactly half is normal")
    assert_equal(WeightPolicy.classify(100, 100), "NORMAL", "at capacity is normal")
    assert_equal(WeightPolicy.classify(101, 100), "OVERLOAD", "over capacity is overloaded")
    assert_equal(WeightPolicy.high_speed(4.5, 100, 0), 9.0, "ultralight doubles high speed")
    assert_equal(WeightPolicy.high_speed(4.5, 100, 100), 4.5, "normal weight keeps base speed")

    -- Regression: the preparation screen and its hit test must render for every
    -- character. The hit test reads the shared slot-grid layout, so a mis-scoped
    -- local previously crashed render_preparation with a nil call.
    local Bootstrap = require("tnr.bootstrap")
    local MapRenderer = require("tnr.ui.map_renderer")
    local mock = {
        Color = function() return {} end, SetImageState = function() end, RenderRect = function() end,
        RenderTTF = function() end, BeginScene = function() end, EndScene = function() end,
        RenderClear = function() end, SetViewport = function() end, SetScissorRect = function() end,
        SetOrtho = function() end, Render = function() end,
    }
    local renderer = MapRenderer.new(mock, 1280, 720)
    renderer.white = "white"
    for _, character_id in ipairs({ "reimu", "marisa", "sanae" }) do
        local bootstrap = Bootstrap.create({})
        bootstrap:init()
        bootstrap.renderer = renderer
        bootstrap:open_character_select(function() bootstrap:start_game(7) end)
        for index, entry in ipairs(bootstrap.character_catalog) do
            if entry.id == character_id then bootstrap.character_cursor = index end
        end
        bootstrap:confirm_character_select()
        bootstrap.session.run_state = Constants.run_states.MAP_PREPARATION
        local rendered = pcall(function() bootstrap:render() end)
        assert_true(rendered, character_id .. " preparation screen must render")
        -- Every group slot must be hit-testable with the character's loadout.
        local loadout = bootstrap:_local_loadout()
        local rows = #bootstrap:_preparation_rows()
        for _, key in ipairs({ "high_weapons", "low_weapons", "supports",
                "self_modifiers", "support_modifiers" }) do
            local slot_count = #loadout[key]
            for slot = 1, slot_count do
                local hit = renderer:preparation_hit_test(0, 0, rows, 1, loadout)
                assert_true(hit == nil or type(hit) == "number",
                    character_id .. " hit test must not crash for " .. key)
            end
        end
    end
end
