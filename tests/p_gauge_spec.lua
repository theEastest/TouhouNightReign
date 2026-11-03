local Gauge = require("tnr.character.runtime.p_gauge")
local Bridge = require("tnr.character.runtime.character_runtime_bridge")
local Session = require("tnr.core.game_session")
local Service = require("tnr.equipment.loadout_service")
local function near(actual, expected) assert(math.abs(actual - expected) < 0.00001, tostring(actual) .. " ~= " .. expected) end
return function(eq, yes)
    local g = Gauge.new()
    eq(g.value, 100, "battle starts full")
    g.value = 40
    for _ = 1, 60 do g:step({ supports = 1, moving = true }) end
    near(g.value, 40 + 100/30)
    g.value = 10
    for _ = 1, 60 do g:step({ supports = 1, moving = true }) end
    near(g.value, 10 + 200/30)
    g = Gauge.new(); g.value = 50
    for _ = 1, 60 do g:step({ firing = true, cost = 3.33 }) end
    near(g.value, 46.67)
    g = Gauge.new(); g.value = 40
    for _ = 1, 60 do g:step({}) end
    near(g.value, 40)
    for _ = 1, 60 do g:step({}) end
    near(g.value, 73)
    yes(g.resting, "rest ring enabled")
    g:step({ firing = true }); eq(g.resting, false, "shoot interrupts rest")
    eq(g.idle_frames, 0, "rest timer resets")
    g:restore(10, "pickup"); near(g.value, 83)
    g:restore(20, "pickup"); near(g.value, 100)
    g.value = 0.9; g:step({ supports = 4 })
    eq(g.hot_frames, 300, "exhaustion wins over regen")
    for _ = 1, 299 do g:step({}) end
    eq(g.hot_frames, 1, "locked for full five seconds")
    g:step({}); eq(g.value, 100, "hot expiry refills")
    eq(g.hot_frames, 0, "hot ends")
    g = Gauge.new(); g.value = 20
    for _ = 1, 999 do g:step({moving = true}) end
    eq(g.triggers, 0, "not before 1000 low frames")
    g:step({moving = true, choose_hazard = function() return 2 end})
    eq(g.triggers, 1, "100 percent triggers")
    eq(g.event, 2, "selected effect emitted once")
    near(g:damage_multiplier(), 1.1)
    g:step({moving = true}); eq(g.event, nil, "one-shot event")
    for _ = 1, 999 do g:step({moving = true}) end
    near(g:damage_multiplier(), 1.2)
    g.value = 50
    for _ = 1, 299 do g:step({moving = true}) end
    g.progress = 5
    g:step({moving = true}); eq(g.progress, 0, "five-second absence clears buildup")
    for _ = 1, 300 do g:step({moving = true}) end
    near(g:damage_multiplier(), 1)
    eq(Gauge.new().triggers, 0, "new stage clears multiplier history")
    g:on("restore", function(data) if data.source == "pickup" then data.percent = data.percent * 2 end end)
    g.value = 40; g:restore(10, "pickup"); near(g.value, 60)
    local frame = g.frame; g:step({paused = true}); eq(g.frame, frame, "pause freezes state")

    local Mask = require("tnr.character.runtime.vision_mask")
    eq(Mask.alpha(48,48,156),0,"clear center")
    eq(Mask.alpha(156,48,156),255,"black exterior")
    yes(Mask.alpha(70,48,156) > 0 and Mask.alpha(140,48,156) < 255,"feathered boundary")
    local vertices = {}
    local api = { Color = function(...) return {...} end, SetImageState = function() end,
        Render4V = function(_, ...) vertices[#vertices+1] = {...} end }
    Mask.render(api, 100, 200)
    local first_x,first_y = vertices[1][1],vertices[1][2]
    vertices = {}; Mask.render(api, 130, 240)
    near(vertices[1][1]-first_x,30); near(vertices[1][2]-first_y,40)
    local Effects = require("tnr.character.runtime.fallback_p_gauge")
    local combat = { p_gauge = Gauge.new(), p_rng = require("tnr.core.rng").new(55) }
    local adapter = {runtime={bullets={{x=2,y=3,vx=4,vy=-5,radius=6,curve=0.2,custom={value=7}}}}}
    combat.p_gauge.event = 2
    Effects.update(adapter,{combat_runtime=combat})
    eq(#adapter.runtime.bullets,2,"one copy per source")
    local copy = adapter.runtime.bullets[2]
    eq(copy.vx,4,"copy preserves horizontal velocity"); eq(copy.vy,5,"copy reverses vertical velocity")
    eq(copy.custom.value,7,"copy preserves custom properties")
    yes(copy.custom ~= adapter.runtime.bullets[1].custom,"copies do not share mutable state")
    combat.p_gauge.event=nil; Effects.update(adapter,{combat_runtime=combat})
    eq(#adapter.runtime.bullets,2,"effect does not repeat next frame")
    combat.p_gauge.event, combat.p_gauge.hazard, combat.p_gauge.hazard_frames = 3,3,600
    Effects.update(adapter,{combat_runtime=combat})
    eq(#adapter.runtime.bullets,1,"new penalty clears earlier copies")
    local other = {p_gauge=Gauge.new(),p_rng=require("tnr.core.rng").new(88)}
    other.p_gauge.event, other.p_gauge.hazard, other.p_gauge.hazard_frames = 1,1,600
    adapter._emit_bullet = function(self,x,y,angle,speed,radius,pattern)
        self.runtime.bullets[#self.runtime.bullets+1]={x=x,y=y,radius=radius,pattern=pattern}
    end
    Effects.update(adapter,{combat_runtime=other})
    eq(combat.p_gauge.hazard_frames,0,"co-op trigger replaces prior negative effect")
    eq(#adapter.runtime.bullets,5,"dense rain emits four small bullets")
    eq(adapter.runtime.bullets[2].radius,2,"rain uses small hitboxes")
    other.p_gauge.event=nil; other.p_gauge.hazard_frames=0
    Effects.update(adapter,{combat_runtime=other})
    eq(#adapter.runtime.bullets,1,"rain clears on expiry")
    local session = Session.new({run_seed = 120})
    session:start_new()
    local p = session:get_player(1)
    local service = Service.new(session, session.equipment_registry)
    local ok, enabled = service:toggle_weapon(1, "high_weapons", 1)
    yes(ok, "toggle accepted on map"); eq(enabled, false, "first click disables")
    local bridge = Bridge.new(session, 1)
    local descriptor = bridge:build_descriptor()
    local remote = bridge:create_runtime_from_descriptor(descriptor)
    eq(remote.weapon_manager.weapons[1].enabled, false, "descriptor preserves switch")
    local instance = p.loadout.high_weapons[1]
    local restored = require("tnr.equipment.equipment_instance").from_table(instance:to_table())
    eq(restored.runtime_data.enabled, false, "save preserves switch")
    local shots = bridge:update(remote, "HIGH", true, {x=0,y=0})
    for _, shot in ipairs(shots) do yes(shot.source_instance_id ~= instance.instance_id, "disabled weapon cannot fire") end
    remote.p_gauge.value = 0
    shots = bridge:update(remote, "HIGH", true, {x=0,y=0})
    eq(#shots, 0, "hot blocks weapons AND supports")
end
