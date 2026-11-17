local Immutable = require("tnr.core.immutable")
local Effects = {}
function Effects.update(adapter, player)
    local rt, combat = adapter.runtime, player.combat_runtime
    local g = combat.p_gauge
    if g.event then
        if rt.p_active_gauge and rt.p_active_gauge ~= g then rt.p_active_gauge.hazard_frames = 0 end
        rt.p_active_gauge = g
        rt.p_active_owner = player.player_id
        for i = #rt.bullets, 1, -1 do
            if rt.bullets[i].p_duplicate or rt.bullets[i].pattern == "p_rain" then table.remove(rt.bullets,i) end
        end
    end
    if rt.p_active_gauge == g and g.hazard_frames == 0 and g.hazard == 1 then
        for i=#rt.bullets,1,-1 do if rt.bullets[i].pattern == "p_rain" then table.remove(rt.bullets,i) end end
    end
    if g.event == 2 then
        local count = #rt.bullets
        for i = 1, count do
            local b = rt.bullets[i]
            if not b.p_duplicate then
                local copy = Immutable.copy(b)
                copy.vy = -copy.vy
                -- Curved trajectories must also be reflected about the horizontal axis.
                copy.curve = copy.curve and -copy.curve
                copy.p_duplicate, copy.grazed_by = true, {}
                rt.bullets[#rt.bullets + 1] = copy
            end
        end
    end
    if rt.p_active_gauge == g and g.hazard == 1 and g.hazard_frames > 0 and g.frame % 3 == 0 then
        for _ = 1, 4 do
            adapter:_emit_bullet(200 + combat.p_rng:next_float() * 880, 660, -math.pi/2,
                2 + combat.p_rng:next_float() * 2, 2, "p_rain")
            rt.bullets[#rt.bullets].render_scale = 0.18
        end
    end
end
function Effects.drop(rt, enemy)
    rt.p_pickups = rt.p_pickups or {}
    -- Fallback enemies have independent money and P fields; never derive one from the other.
    local count = enemy.drop_p or (enemy.boss and 5 or 1)
    for i = 1, count do
        rt.p_pickups[#rt.p_pickups + 1] = { x = enemy.x + (i - (count + 1)/2)*12,
            y = enemy.y, amount = i % 5 == 0 and 20 or 10 }
    end
end
function Effects.pickups(adapter)
    local rt = adapter.runtime
    for i = #(rt.p_pickups or {}), 1, -1 do
        local drop = rt.p_pickups[i]
        drop.y = drop.y - 1.5
        for _, player in ipairs(adapter:get_alive_players()) do
            if (player.x-drop.x)^2 + (player.y-drop.y)^2 < (24 * (player.combat_runtime.affixes and player.combat_runtime.affixes.pickup_multiplier or 1))^2 then
                player.combat_runtime.p_gauge:restore(drop.amount, "pickup")
                drop.collected = true
                break
            end
        end
        if drop.collected or drop.y < 0 then table.remove(rt.p_pickups, i) end
    end
end
function Effects.render(adapter)
    local rt, api = adapter.runtime, adapter.lstg
    local function rect(a,r,g,b,l,right,bottom,top)
        api.SetImageState("tnr-white", "", api.Color(a,r,g,b))
        api.RenderRect("tnr-white",l,right,bottom,top)
    end
    for _, drop in ipairs(rt.p_pickups or {}) do
        local radius = 5 * (drop.amount == 20 and math.sqrt(2) or 1)
        rect(255,255,60,90,drop.x-radius,drop.x+radius,drop.y-radius,drop.y+radius)
    end
    for id, player in pairs(rt.players) do
        local g = player.combat_runtime and player.combat_runtime.p_gauge
        if g then
            if g.resting then
                for i=1,24 do
                    local angle = math.rad(i*15 + g.frame*3)
                    local x,y = player.x+math.cos(angle)*32, player.y+math.sin(angle)*32
                    rect(220,255,50,70,x-2,x+2,y-2,y+2)
                end
            end
            if rt.p_active_gauge == g and g.hazard == 3 and g.hazard_frames > 0 then
                require("tnr.character.runtime.vision_mask").render(api, player.x, player.y, 1.5)
            end
            if player.combat_runtime.affixes and api.Render4V and rawget(_G,"lstg") then require("tnr.character.runtime.status_art").ring(player.combat_runtime.affixes,player) end
            local l, y = id==1 and 25 or 1090, 530
            -- Dark bands keep the red/white HUD legible over the playfield
            -- while retaining the existing status grid and resource positions.
            rect(165,12,16,29,l-2,l+152,y+21,y+40)
            rect(165,12,16,29,l-2,l+152,y-25,y-5)
            rect(220,30,25,40,l,l+150,y,y+12)
            rect(255,240,60,90,l,l+150*g.value/g.maximum,y,y+12)
            rect(255,255,240,220,l+150*30/g.maximum-1,l+150*30/g.maximum+1,y-2,y+14)
            rect(255,110,210,255,l+134,l+136,y-2,y+14)
            api.RenderTTF("Sans", string.format("P%d %.1f%%",id,g.value),l,l,y+36,y+36,0,api.Color(255,255,230,230),0.7)
            api.RenderTTF("Sans", string.format("渴血兽 %.0f%%",g.progress/g.progress_maximum*100),l,l,y-10,y-10,0,api.Color(255,255,160,175),0.65)
            rect(220,35,15,25,l,l+150,y-36,y-33)
            rect(255,210,35,65,l,l+150*math.min(1,g.progress/g.progress_maximum),y-36,y-33)
            local rows=player.combat_runtime.affixes and player.combat_runtime.affixes:statuses() or {}
            if api.Render and rawget(_G,"lstg") then
                require("tnr.character.runtime.status_art").grid(rows,l,y-60,150,player.combat_runtime.affixes,function(text,x,cy)
                    api.RenderTTF("Sans",text,x,x,cy,cy,2+4,api.Color(255,255,255,255),0.4)
                end,"ordinary")
            end
        end
    end
    api.SetImageState("tnr-white", "", api.Color(255,255,255,255))
end
return Effects
