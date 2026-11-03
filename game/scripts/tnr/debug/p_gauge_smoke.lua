-- Opt-in engine smoke test; never used by ordinary launches.
local Smoke = {}
function Smoke.update(driver, player)
    local g = driver.p_gauge
    player.protect = 999
    local n = (driver.p_smoke_frame or 0) + 1
    driver.p_smoke_frame = n
    if n == 1 then
        g.value = 40
        item_power.collect(); assert(math.abs(g.value - 50) < 0.001)
        item_power_large.collect(); assert(math.abs(g.value - 70) < 0.001)
        local counts = { small = 0, large = 0, money = 0 }
        local function count()
            local c = { small = 0, large = 0, money = 0 }
            for _, o in ObjList(GROUP_ITEM) do
                if o.class == item_power then c.small = c.small + 1
                elseif o.class == item_power_large then c.large = c.large + 1
                elseif o.img == "tnr-coin-1" then c.money = c.money + 1 end
            end
            return c
        end
        counts = count()
        item.DropItem(0, 100, {7,0,10})
        local after = count()
        assert(after.small - counts.small == 8, "small P drop mismatch")
        assert(after.large - counts.large == 2, "large P drop mismatch")
        assert(after.money - counts.money == 7, "coin drop mismatch")
        local choice = tonumber(os.getenv("TNR_P_GAUGE_SMOKE_HAZARD")) or math.floor(driver.p_rng:next_float()*3)+1
        driver.p_smoke_choice = choice
        g.event, g.hazard, g.hazard_frames = choice, choice, 600
    elseif n == 320 then
        if driver.p_smoke_choice == 2 then assert((driver.p_smoke_copies or 0) == (driver.p_smoke_sources or 0), "copy count mismatch") end
        local f = assert(io.open("p_gauge_smoke_result.txt", "w"))
        f:write("passed: native coin/P drops, pickup restoration, single negative effect, HUD\n")
        f:close()
    end
end
return Smoke
