-- Modern (TH10+) interpolation modes, shared by ECL, ANM and STD.
-- Reference: https://exphp.github.io/thpages/#/anm/interpolation
local function fraction(mode, t)
    t = math.max(0, math.min(1, t))
    if mode >= 1 and mode <= 3 then return t ^ (mode + 1) end
    if mode >= 4 and mode <= 6 then return 1 - (1 - t) ^ (mode - 2) end
    if mode == 8 then return t * t * (3 - 2 * t) end
    if mode >= 9 and mode <= 11 then
        local power = mode - 7
        return t < 0.5 and (2 * t)^power / 2 or 1 - (2 - 2 * t)^power / 2
    end
    if mode >= 12 and mode <= 14 then
        local power = mode - 10
        return t < 0.5 and (1 - (1 - 2 * t)^power) / 2 or (1 + (2 * t - 1)^power) / 2
    end
    if mode == 15 then return t == 1 and 1 or 0 end
    if mode == 16 then return t > 0 and 1 or 0 end
    if mode == 18 then return math.sin(t * math.pi / 2) end
    if mode == 19 then return 1 - math.cos(t * math.pi / 2) end
    if mode == 20 then return t < 0.5 and fraction(18, t * 2) / 2 or 0.5 + fraction(19, t * 2 - 1) / 2 end
    if mode == 21 then return (1 - math.cos(t * math.pi)) / 2 end
    return t
end
return fraction
