-- Reference HUD font renderer.
--
-- The game's HUD numbers and Latin labels are drawn from the ascii sheet rather
-- than a vector font. The sheet is a 14x14 grid of glyphs laid out from ASCII
-- code 33 upward, eighteen per row, so a character's sprite index is simply its
-- code minus 32.
--
-- This module turns a string into the list of sprite rectangles to draw, with
-- the per-character advance from the reference so numbers line up the same way.

local HudFont = {}

HudFont.__index = HudFont

-- The sheet's glyph metrics.
local GLYPH_SIZE = 14
local GLYPHS_PER_ROW = 18

-- Codepoint to sprite index. The sheet has blank slots inserted where a glyph
-- was unused, so a plain arithmetic rule drifts; the table is derived from the
-- image by tools/compile_ascii_font.py.
local GLYPH_MAP = require("tnr.legacy_replay.data.th15_ascii_font")

HudFont.GLYPH_MAP = GLYPH_MAP

--- Sprite index for a character, or nil when the character has no glyph (a
-- space, a control character, or a codepoint the sheet does not cover).
function HudFont.sprite_for(character)
    local code = string.byte(character)
    if not code then return nil end
    return GLYPH_MAP[code]
end

--- Lay a string out into glyph draws.
-- Returns a list of { sprite = n, x = offset }. The caller adds the origin and
-- scales to canvas units.
function HudFont.layout(text, options)
    options = options or {}
    local advance = options.advance or GLYPH_SIZE
    local tracking = options.tracking or 0
    local draws = {}
    local pen = 0
    for index = 1, #text do
        local character = text:sub(index, index)
        local sprite = HudFont.sprite_for(character)
        if sprite then
            draws[#draws + 1] = { sprite = sprite, x = pen }
        end
        pen = pen + advance + tracking
    end
    return draws, pen
end

--- Width of a string in glyph units.
function HudFont.measure(text, options)
    options = options or {}
    local advance = options.advance or GLYPH_SIZE
    local tracking = options.tracking or 0
    return math.max(0, #text * (advance + tracking) - tracking)
end

HudFont.GLYPH_SIZE = GLYPH_SIZE

return HudFont
