-- Reference bullet and effect colour palette.
--
-- The games index a fixed 28 entry colour table by a small integer to tint a
-- bullet sprite. The table comes from the original bullet manager, which holds
-- two variants: one for sprites drawn with texture blending and one for the
-- additive effect sprites. Using it is what makes a bullet sheet of white
-- shapes render as the coloured bullets the originals show.

local Palette = {}

-- Index 0 is transparent black through 27 white. The order is the reference's,
-- so a bullet whose colour index is 11 is its blue and index 17 its green.
Palette.WITH_TEXTURE_BLENDING = {
    0xff000000, 0xff303030, 0xff606060, 0xff500000, 0xff900000, 0xffff2020, 0xff400040,
    0xff800080, 0xffff30ff, 0xff000050, 0xff000090, 0xff2020ff, 0xff203060, 0xff304090,
    0xff3080ff, 0xff005000, 0xff009000, 0xff20ff20, 0xff206000, 0xff409010, 0xff80ff20,
    0xff505000, 0xff909000, 0xffffff20, 0xff603000, 0xff904010, 0xfff08020, 0xffffffff,
}

Palette.WITHOUT_TEXTURE_BLENDING = {
    0xfff0f0f0, 0xfff0f0f0, 0xffffffff, 0xffffe0e0, 0xffffe0e0, 0xffffe0e0, 0xffffe0ff,
    0xffffe0ff, 0xffffe0ff, 0xffe0e0ff, 0xffe0e0ff, 0xffe0e0ff, 0xffe0ffff, 0xffe0ffff,
    0xffe0ffff, 0xffe0ffe0, 0xffe0ffe0, 0xffe0ffe0, 0xffe0ffe0, 0xffe0ffe0, 0xffe0ffe0,
    0xffffffe0, 0xffffffe0, 0xffffffe0, 0xffffe0e0, 0xffffe0e0, 0xffffe0e0, 0xffffffff,
}

-- Sprite offsets within a coloured bullet group: a bullet family cycles through
-- a few sprite variants per colour. Sixteen pixel families use one table and
-- thirty two pixel families the other.
Palette.SPRITE_OFFSET_16 = { 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 0 }
Palette.SPRITE_OFFSET_32 = { 0, 1, 1, 2, 2, 3, 4, 0 }

--- Split a packed 0xAARRGGBB value into the channels the renderer wants.
function Palette.unpack(value)
    value = tonumber(value) or 0xffffffff
    return {
        a = math.floor(value / 0x1000000) % 256,
        r = math.floor(value / 0x10000) % 256,
        g = math.floor(value / 0x100) % 256,
        b = value % 256,
    }
end

--- The tint for a colour index, clamped to the table.
function Palette.tint(index, blending)
    local table_ = blending and Palette.WITH_TEXTURE_BLENDING or Palette.WITHOUT_TEXTURE_BLENDING
    local i = math.floor(tonumber(index) or 27)
    if i < 0 then i = 0 end
    if i >= #table_ then i = #table_ - 1 end
    return table_[i + 1]
end

return Palette
