"""Build the looping, text-free pixel icons used beside weapon names."""

from __future__ import annotations

import math
import re
import zlib
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "game" / "scripts" / "tnr" / "equipment"
OUTPUT = ROOT / "game" / "assets" / "ui" / "weapon-icons.png"
CELL = 24
FRAME_COUNT = 8
GRID = CELL // 2

WEAPON_ID = re.compile(r'weapon_id\s*=\s*"([^"]+)"')
PALETTES = (
    ((248, 225, 177, 255), (233, 103, 123, 255), (120, 37, 67, 255)),
    ((197, 231, 247, 255), (102, 179, 227, 255), (39, 83, 143, 255)),
    ((231, 212, 255, 255), (173, 126, 223, 255), (81, 56, 137, 255)),
    ((212, 243, 208, 255), (113, 203, 151, 255), (45, 111, 100, 255)),
    ((255, 219, 182, 255), (241, 148, 89, 255), (138, 66, 53, 255)),
    ((246, 209, 225, 255), (215, 111, 169, 255), (119, 53, 115, 255)),
)
INK = (21, 25, 44, 255)
PAPER = (255, 245, 220, 255)


def weapon_ids() -> list[str]:
    found: set[str] = set()
    for path in SOURCE.glob("*.lua"):
        found.update(WEAPON_ID.findall(path.read_text(encoding="utf-8")))
    return sorted(found)


def put(draw: ImageDraw.ImageDraw, x: int, y: int, color, dx: int = 0, dy: int = 0) -> None:
    x += dx
    y += dy
    if 0 <= x < GRID and 0 <= y < GRID:
        draw.point((x, y), fill=color)


def sprite(weapon_id: str, frame: int) -> Image.Image:
    seed = zlib.crc32(weapon_id.encode("utf-8"))
    bright, accent, shade = PALETTES[seed % len(PALETTES)]
    style = (seed >> 4) % 6
    canvas = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    bob = round(math.sin(frame * math.tau / FRAME_COUNT) * 0.45)
    dx = round(math.cos(frame * math.tau / FRAME_COUNT) * 0.35)
    center = 5 + dx

    # Small lacquered shadow gives the weapon silhouette contrast at 24px.
    draw.rectangle((center - 2, 2 + bob, center + 2, 9 + bob), fill=INK)
    if style == 0:  # needle / blade
        for y, width in ((1, 0), (2, 1), (3, 1), (4, 1), (5, 1)):
            for x in range(center - width, center + width + 1):
                put(draw, x, y, bright if y < 3 else accent, dy=bob)
        draw.rectangle((center - 2, 6 + bob, center + 2, 6 + bob), fill=accent)
        draw.rectangle((center - 1, 7 + bob, center + 1, 9 + bob), fill=bright)
        put(draw, center, 10, shade, dy=bob)
    elif style == 1:  # talisman / orb
        draw.rectangle((center - 3, 3 + bob, center + 3, 8 + bob), fill=shade)
        draw.rectangle((center - 2, 2 + bob, center + 2, 9 + bob), fill=accent)
        draw.rectangle((center - 1, 3 + bob, center + 1, 8 + bob), fill=bright)
        put(draw, center, 5, PAPER, dy=bob)
        angle = frame * math.tau / FRAME_COUNT
        put(draw, center + round(4 * math.cos(angle)), 5 + round(4 * math.sin(angle)), PAPER)
    elif style == 2:  # staff / beam
        draw.rectangle((center - 1, 2 + bob, center + 1, 10 + bob), fill=accent)
        draw.rectangle((center, 3 + bob, center, 9 + bob), fill=bright)
        draw.rectangle((center - 2, 1 + bob, center + 2, 3 + bob), fill=shade)
        draw.rectangle((center - 1, 1 + bob, center + 1, 2 + bob), fill=bright)
        put(draw, center, 0, PAPER, dy=bob)
    elif style == 3:  # paired spread shots
        for offset in (-2, 0, 2):
            top_shift = 1 if offset else 0
            for y in range(2 + top_shift, 8):
                put(draw, center + offset, y + bob, bright if y < 5 else accent)
        draw.rectangle((center - 3, 8 + bob, center + 3, 9 + bob), fill=shade)
        put(draw, center, 10, bright, dy=bob)
    elif style == 4:  # bow / crescent
        for y, width in ((1, 1), (2, 2), (3, 2), (4, 1), (5, 0), (6, 1), (7, 2), (8, 2), (9, 1)):
            put(draw, center - width, y + bob, accent)
            put(draw, center + width, y + bob, bright)
        draw.rectangle((center, 2 + bob, center, 9 + bob), fill=PAPER)
    else:  # compact magic launcher
        draw.rectangle((center - 2, 3 + bob, center + 2, 7 + bob), fill=shade)
        draw.rectangle((center - 1, 2 + bob, center + 1, 8 + bob), fill=accent)
        draw.rectangle((center, 2 + bob, center, 7 + bob), fill=bright)
        draw.rectangle((center - 1, 8 + bob, center + 1, 9 + bob), fill=shade)

    # Eight distinct glints create a seamless pulse without changing the weapon
    # silhouette or adding letters to the art.
    glints = ((2, 1), (8, 2), (9, 5), (8, 9), (2, 10), (0, 6), (1, 3), (5, 0))
    gx, gy = glints[frame % FRAME_COUNT]
    put(draw, gx, gy, PAPER)
    if frame % 2 == 0:
        put(draw, gx - 1, gy, accent)
    return canvas.resize((CELL, CELL), Image.Resampling.NEAREST)


def main() -> None:
    ids = weapon_ids() + ["default"]
    atlas = Image.new("RGBA", (CELL * FRAME_COUNT, CELL * len(ids)), (0, 0, 0, 0))
    for row, weapon_id in enumerate(ids):
        for frame in range(FRAME_COUNT):
            atlas.alpha_composite(sprite(weapon_id, frame), (frame * CELL, row * CELL))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUTPUT, optimize=True)
    print(f"Generated {OUTPUT} ({atlas.width}x{atlas.height}; {len(ids)} weapon rows)")


if __name__ == "__main__":
    main()
