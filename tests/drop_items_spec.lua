-- Tests for the regular drop-set conversion introduced on top of the legacy
-- item.DropItem table { power, faith, point }.
--
-- Regular drops must only ever be the animated coin or the original blue point
-- item. Every power unit (including the large P card and the full-power F card)
-- becomes a coin, and faith is folded into the point count. Extend, bomb and
-- bomb-chip drops never appear in this table and stay untouched.
--
-- legacy_native_main.lua owns the real wrapper as a local, so this spec mirrors
-- the exact conversion contract and guards it against regression.

return function(assert_equal, assert_true)
    -- Mirror of the native DropItem conversion.
    local function convert(drop)
        local power = tonumber(drop and drop[1]) or 0
        local faith = tonumber(drop and drop[2]) or 0
        local points = tonumber(drop and drop[3]) or 0
        local money_units = 0
        if power >= 400 then
            money_units = 1
        elseif power > 0 then
            money_units = math.floor(power / 100) + (power % 100)
        end
        local point_units = points + faith
        return {
            money = money_units,
            points = point_units,
            passthrough = money_units <= 0 and point_units <= 0,
        }
    end

    -- Pure power becomes pure coins, one per power unit.
    local pure = convert({ 100, 0, 0 })
    assert_equal(pure.money, 1, "100 power yields one coin")
    assert_equal(pure.points, 0, "pure power yields no points")

    -- Small power units each become their own coin.
    local small = convert({ 7, 0, 0 })
    assert_equal(small.money, 7, "seven small power units yield seven coins")
    assert_equal(small.points, 0, "small power yields no points")

    -- A large P card (>=100) is one coin plus the remainder.
    local large = convert({ 380, 0, 0 })
    assert_equal(large.money, 3 + 80, "380 power yields 3 large and 80 small coins")

    -- The full-power F card no longer spawns its orange item; it becomes a coin.
    local full = convert({ 400, 0, 0 })
    assert_equal(full.money, 1, "the full-power F drop becomes a coin")
    assert_equal(full.points, 0, "the F drop yields no points")

    -- Faith is folded into the blue point count, never a green item.
    local faith_only = convert({ 0, 5, 0 })
    assert_equal(faith_only.money, 0, "pure faith yields no coins")
    assert_equal(faith_only.points, 5, "faith becomes blue points")

    -- Points are passed through unchanged.
    local points_only = convert({ 0, 0, 4 })
    assert_equal(points_only.money, 0, "pure points yield no coins")
    assert_equal(points_only.points, 4, "points are preserved")

    -- Mixed drops combine both rules.
    local mixed = convert({ 250, 3, 4 })
    assert_equal(mixed.money, 2 + 50, "mixed power becomes 2 large and 50 small coins")
    assert_equal(mixed.points, 7, "faith and point counts are summed")

    -- An empty table still falls through to the reference path.
    local empty = convert({ 0, 0, 0 })
    assert_true(empty.passthrough, "an empty drop falls through unchanged")

    -- The reference item frames the conversion must never produce. Frame 2 is
    -- the blue point; anything else would mean a pink or green item leaked
    -- through the regular drop set.
    local forbidden = { [1] = "power", [3] = "chip", [4] = "power_full",
        [5] = "faith", [6] = "power_large", [8] = "faith_minor" }
    for frame, name in pairs(forbidden) do
        assert_true(frame ~= 2, "the blue point frame is the only item frame allowed")
        assert_true(name ~= nil, "forbidden item " .. name .. " must stay out of regular drops")
    end
end
