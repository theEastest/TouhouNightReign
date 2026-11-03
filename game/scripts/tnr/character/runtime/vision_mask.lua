-- Circular feathered aperture. Vertex alpha interpolation avoids a tiled or hard edge.
local Mask = {}
function Mask.alpha(radius, inner, outer)
    local t = math.max(0, math.min(1, (radius - inner) / (outer - inner)))
    return math.floor(255 * t * t * (3 - 2 * t) + 0.5)
end
function Mask.render(api, x, y, scale)
    scale = scale or 1
    local inner, outer = 48 * scale, 156 * scale
    local segments, bands = 96, 8
    for band = 0, bands do
        local r1 = inner + (outer - inner) * band / bands
        local r2 = band == bands and 3000 or inner + (outer - inner) * (band + 1) / bands
        local c1, c2 = api.Color(Mask.alpha(r1,inner,outer),0,0,0), api.Color(Mask.alpha(r2,inner,outer),0,0,0)
        api.SetImageState("tnr-white", "", c1, c1, c2, c2)
        for i=0,segments-1 do
            local a, b = i * math.pi * 2 / segments, (i+1) * math.pi * 2 / segments
            api.Render4V("tnr-white",
                x + math.cos(a)*r1,y + math.sin(a)*r1,0.5,
                x + math.cos(b)*r1,y + math.sin(b)*r1,0.5,
                x + math.cos(b)*r2,y + math.sin(b)*r2,0.5,
                x + math.cos(a)*r2,y + math.sin(a)*r2,0.5)
        end
    end
    api.SetImageState("tnr-white", "", api.Color(255,255,255,255))
end
return Mask
