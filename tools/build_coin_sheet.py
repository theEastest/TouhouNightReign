#!/usr/bin/env python3
"""Downsample the high-resolution coin animation into the game's item sheet.

The source is resource/金币动画.png: a 5-keyframe gold-coin spin at roughly
355x377 per frame. The game draws items from a 32x32 cell, so each keyframe is
area-downscaled into its own 32x32 cell and laid out as a horizontal strip of
five frames.

Output: game/assets/items/coin_sheet.png (160x32, 5 frames of 32x32).

Usage:
    python tools/build_coin_sheet.py
"""
import os
import sys

try:
    from PIL import Image
except ImportError:
    raise SystemExit("Pillow is required: pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "resource", "金币动画.png")
OUTPUT = os.path.join(ROOT, "game", "assets", "items", "coin_sheet.png")

CELL = 32
VISIBLE = 30  # coin occupies this many pixels inside each 32x32 cell

# Tight bounding boxes of each keyframe in the source sheet, measured from the
# non-background pixels. Order is the sampled spin: face, narrow, edge, narrow,
# face.
FRAMES = [
    (96, 451, 103, 455),
    (705, 962, 91, 468),
    (1358, 1459, 91, 468),
    (1840, 2097, 91, 468),
    (2353, 2709, 103, 455),
]


def main():
    if not os.path.isfile(SOURCE):
        raise SystemExit("source not found: %s" % SOURCE)
    source = Image.open(SOURCE).convert("RGBA")
    # The source is a flat RGB render on a solid black background. Build an
    # alpha channel from luminance so the black backdrop becomes transparent
    # while the bright coin stays opaque; a soft ramp keeps the anti-aliased
    # glow around the coin.
    pixels = source.load()
    width, height = source.size
    for y in range(height):
        for x in range(width):
            r, g, b, _ = pixels[x, y]
            # Perceptual luminance; the coin is far brighter than the backdrop.
            luminance = (r * 299 + g * 587 + b * 114) // 1000
            if luminance <= 12:
                alpha = 0
            elif luminance >= 48:
                alpha = 255
            else:
                alpha = int((luminance - 12) * 255 / (48 - 12))
            pixels[x, y] = (r, g, b, alpha)
    sheet = Image.new("RGBA", (CELL * len(FRAMES), CELL), (0, 0, 0, 0))
    for index, (x0, x1, y0, y1) in enumerate(FRAMES):
        crop = source.crop((x0, y0, x1, y1))
        crop_width, crop_height = crop.size
        scale = VISIBLE / max(crop_width, crop_height)
        target = (max(1, round(crop_width * scale)), max(1, round(crop_height * scale)))
        small = crop.resize(target, Image.LANCZOS)
        offset_x = (CELL - target[0]) // 2
        offset_y = (CELL - target[1]) // 2
        sheet.alpha_composite(small, (index * CELL + offset_x, offset_y))
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    sheet.save(OUTPUT)
    print("wrote %s (%dx%d, %d frames)" % (OUTPUT, sheet.width, sheet.height, len(FRAMES)))


if __name__ == "__main__":
    main()
