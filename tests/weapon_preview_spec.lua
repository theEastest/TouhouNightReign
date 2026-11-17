local Catalog = require("tnr.equipment.phase1_catalog")
local Preview = require("tnr.ui.weapon_preview")
local Renderer = require("tnr.ui.map_renderer")

return function(eq, yes)
    eq(Preview.FRAME_COUNT, 8, "weapon preview uses an eight-frame loop")

    local weapons = 0
    for _, definition in pairs(Catalog.registry:all()) do
        if definition.equipment_type == "WEAPON" and not definition.test_only then
            weapons = weapons + 1
            for frame = 0, Preview.FRAME_COUNT - 1 do
                local projectiles = Preview.sample(definition, frame, 100, 50)
                yes(#projectiles > 0, "weapon preview is populated: " .. tostring(definition.weapon_id))
                for _, projectile in ipairs(projectiles) do
                    yes(projectile.x >= 20 and projectile.x <= 180, "preview projectile remains in its panel")
                    yes(projectile.y >= 50 and projectile.y <= 150, "preview projectile remains above its firing point")
                end
            end
        end
    end
    yes(weapons > 0, "equipment catalog contains weapons")

    local spread = Catalog.registry:get("sanae_cobalt_spread")
    local spread_shots = Preview.sample(spread, 0, 100, 50)
    eq(#spread_shots, 5, "spread preview shows all five projectiles on its first volley")
    yes(spread_shots[1].angle < spread_shots[3].angle
        and spread_shots[3].angle < spread_shots[5].angle,
        "spread preview angles are ordered across the fan")

    local laser = Catalog.registry:get("marisa_earthlight_ray")
    local beam = Preview.sample(laser, 0, 100, 50)[1]
    yes(beam.beam and beam.beam_length > 0, "beam preview grows a visible laser")

    local effects = { rendered = 0, labels = {} }
    local fake = {
        CheckRes = function() return true end,
        Color = function(...) return { ... } end,
        SetImageState = function() end,
        Render = function() effects.rendered = effects.rendered + 1 end,
        Render4V = function() effects.rendered = effects.rendered + 1 end,
        RenderRect = function() end,
        RenderTTF = function(_, text) effects.labels[#effects.labels + 1] = tostring(text) end,
        BeginScene = function() end,
        EndScene = function() end,
        RenderClear = function() end,
        SetViewport = function() end,
        SetScissorRect = function() end,
        SetOrtho = function() end,
    }
    for _, definition in pairs(Catalog.registry:all()) do
        if definition.equipment_type == "WEAPON" and not definition.test_only then
            for frame = 0, Preview.FRAME_COUNT - 1 do
                yes(Preview.draw(fake, definition, frame, 100, 50, 0.45) > 0,
                    "each weapon frame reaches the native projectile renderer: " .. tostring(definition.weapon_id))
            end
        end
    end
    yes(effects.rendered > 0, "preview uses the native projectile art renderer")

    local renderer = Renderer.new(fake, 1280, 720)
    renderer.white = "white"
    for _ = 1, Preview.FRAME_COUNT do
        renderer:render_equipment_catalog({ { id = spread.weapon_id, definition = spread } }, 1)
    end
    eq(renderer.catalog_preview_frame, 0, "equipment catalog advances and wraps the eight-frame preview")
    local preview_label = false
    for _, label in ipairs(effects.labels) do
        if label == "外观预览 · 8 帧循环" then preview_label = true end
    end
    yes(preview_label, "equipment catalog labels the weapon animation preview")
end
