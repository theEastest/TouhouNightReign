"""Generate the antialiased, text-free map node emblem atlas."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "game" / "assets" / "ui" / "map-node-icons.png"
TILE = 128
SCALE = 4
SIZE = TILE * SCALE

PALETTES = {
    "START": (222, 117, 124),
    "ENEMY": (226, 92, 112),
    "ELITE": (235, 185, 104),
    "BOSS": (243, 196, 119),
    "SHOP": (128, 201, 172),
    "EVENT": (148, 187, 224),
    "CURRENT": (248, 231, 197),
    "UNVISITED": (157, 170, 191),
}

PAPER = (250, 237, 211)
INK = (20, 24, 42)
DEEP = (10, 15, 31)


def p(value: float) -> int:
    return round(value * SCALE)


def ellipse(draw: ImageDraw.ImageDraw, box, fill, outline=None, width=1):
    box = tuple(p(value) for value in box)
    draw.ellipse(box, fill=fill, outline=outline, width=p(width))


def line(draw: ImageDraw.ImageDraw, points, fill, width=1, joint="curve"):
    draw.line([(p(x), p(y)) for x, y in points], fill=fill, width=p(width), joint=joint)


def polygon(draw: ImageDraw.ImageDraw, points, fill, outline=None, width=1):
    points = [(p(x), p(y)) for x, y in points]
    draw.polygon(points, fill=fill)
    if outline:
        draw.line(points + [points[0]], fill=outline, width=p(width), joint="curve")


def pill(draw: ImageDraw.ImageDraw, box, fill, outline=None, width=1, radius=6):
    draw.rounded_rectangle(tuple(p(value) for value in box), radius=p(radius), fill=fill,
                           outline=outline, width=p(width))


def petal_points(cx, cy, length, width, angle):
    points = []
    # Two rounded shoulders and a pointed base produce a compact ume petal.
    for index in range(9):
        t = index / 8
        local_x = width * math.sin(math.pi * t) * 0.88
        local_y = -length * 0.36 + length * 0.92 * t
        points.append((local_x, local_y))
    for index in range(8, -1, -1):
        t = index / 8
        local_x = -width * math.sin(math.pi * t) * 0.88
        local_y = -length * 0.36 + length * 0.92 * t
        points.append((local_x, local_y))
    cosine, sine = math.cos(angle), math.sin(angle)
    return [(cx + x * cosine - y * sine, cy + x * sine + y * cosine) for x, y in points]


def draw_blade(draw, start, end, half_width, accent):
    x1, y1 = start
    x2, y2 = end
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy)
    nx, ny = -dy / length * half_width, dx / length * half_width
    polygon(draw, [(x1 + nx, y1 + ny), (x2 + nx * 0.36, y2 + ny * 0.36),
                   end, (x2 - nx * 0.36, y2 - ny * 0.36), (x1 - nx, y1 - ny)], PAPER)
    line(draw, [start, ((x1 + x2) * 0.5, (y1 + y2) * 0.5)], accent, 0.7)


def draw_symbol(draw, kind, accent):
    if kind == "START":
        # Shrine gate: rising kasagi, suspended lintel and open pillars.
        polygon(draw, [(36, 48), (42, 40), (86, 40), (92, 48), (89, 51), (39, 51)], PAPER)
        line(draw, [(40, 43), (88, 43)], accent, 1.0)
        polygon(draw, [(43, 54), (85, 54), (83, 59), (45, 59)], PAPER)
        pill(draw, (47, 57, 53, 91), PAPER, radius=2)
        pill(draw, (75, 57, 81, 91), PAPER, radius=2)
        line(draw, [(49, 89), (51, 89)], accent, 1.2)
        line(draw, [(77, 89), (79, 89)], accent, 1.2)
    elif kind == "ENEMY":
        # Two slim spirit blades with wrapped hilts and guards.
        draw_blade(draw, (42, 84), (82, 44), 3.2, accent)
        draw_blade(draw, (46, 44), (86, 84), 3.2, accent)
        line(draw, [(38, 80), (49, 89)], accent, 3)
        line(draw, [(80, 89), (90, 80)], accent, 3)
        line(draw, [(41, 73), (50, 82)], PAPER, 1.1)
        line(draw, [(78, 82), (87, 73)], PAPER, 1.1)
        ellipse(draw, (61, 61, 67, 67), accent)
    elif kind == "ELITE":
        # Four layered ume petals around a faceted gold seal.
        for angle in (0, math.pi / 2, math.pi, math.pi * 1.5):
            polygon(draw, petal_points(64, 64, 28, 8.5, angle), PAPER, accent, 0.8)
        polygon(draw, [(64, 53), (75, 64), (64, 75), (53, 64)], accent)
        polygon(draw, [(64, 57), (71, 64), (64, 71), (57, 64)], PAPER)
    elif kind == "BOSS":
        # Moon crest: a three-point crown above a crescent.
        polygon(draw, [(40, 67), (44, 40), (58, 55), (64, 35), (71, 55),
                       (85, 40), (89, 67)], PAPER, accent, 1)
        line(draw, [(43, 70), (86, 70)], PAPER, 4)
        ellipse(draw, (53, 73, 75, 95), accent)
        ellipse(draw, (60, 70, 82, 92), INK)
        ellipse(draw, (61, 70, 65, 74), PAPER)
    elif kind == "SHOP":
        # Round paper lantern, framed in jade and finished with a tassel.
        line(draw, [(64, 36), (64, 41)], PAPER, 2)
        pill(draw, (47, 42, 81, 48), accent, PAPER, 0.9, 3)
        pill(draw, (43, 49, 85, 80), (52, 58, 70), PAPER, 2, 12)
        line(draw, [(50, 51), (50, 77)], accent, 1.2)
        line(draw, [(78, 51), (78, 77)], accent, 1.2)
        line(draw, [(48, 61), (80, 61)], PAPER, 1.3)
        line(draw, [(48, 70), (80, 70)], PAPER, 1.3)
        line(draw, [(64, 49), (64, 80)], accent, 1.2)
        pill(draw, (46, 81, 82, 86), accent, PAPER, 0.8, 2)
        line(draw, [(64, 86), (64, 96)], PAPER, 1.8)
        polygon(draw, [(64, 96), (68, 91), (64, 102), (60, 91)], accent)
    elif kind == "EVENT":
        # Five-petal cherry blossom with soft petal insets.
        for index in range(5):
            angle = index * math.tau / 5 - math.pi / 2
            polygon(draw, petal_points(64, 64, 28, 8.5, angle), PAPER, accent, 0.75)
            cx = 64 + math.cos(angle) * 12
            cy = 64 + math.sin(angle) * 12
            ellipse(draw, (cx - 1.4, cy - 1.4, cx + 1.4, cy + 1.4), accent)
        ellipse(draw, (58, 58, 70, 70), accent, PAPER, 0.8)
        ellipse(draw, (61, 61, 67, 67), PAPER)
    elif kind == "CURRENT":
        # Bright compass flower used only by the current-node legend.
        polygon(draw, [(64, 43), (69, 59), (85, 64), (69, 69), (64, 85),
                       (59, 69), (43, 64), (59, 59)], PAPER, accent, 1)
        polygon(draw, [(64, 53), (67, 64), (64, 75), (61, 64)], accent)
        ellipse(draw, (61, 61, 67, 67), PAPER)
    elif kind == "UNVISITED":
        # Quiet moon seal for nodes beyond the explored route.
        ellipse(draw, (47, 47, 81, 81), None, PAPER, 2.3)
        ellipse(draw, (57, 45, 87, 75), INK)
        polygon(draw, [(54, 77), (57, 73), (60, 77), (57, 81)], accent)
        ellipse(draw, (72, 46, 76, 50), accent)


def make_icon(kind, accent):
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    center = 64
    # Soft exterior shadow and lacquer disk.
    ellipse(draw, (8, 9, 120, 121), (0, 0, 0, 115))
    ellipse(draw, (8, 7, 120, 119), (9, 15, 31, 238), accent, 2.2)
    ellipse(draw, (13, 12, 115, 114), (17, 22, 39, 245), (177, 145, 123, 210), 0.8)
    ellipse(draw, (18, 17, 110, 109), (14, 20, 37, 248), (accent[0], accent[1], accent[2], 190), 0.65)

    # Four restrained seal petals and cardinal beads echo the title ornament.
    for angle in (0, math.pi / 2, math.pi, math.pi * 1.5):
        cx = center + math.cos(angle) * 46
        cy = center + math.sin(angle) * 46
        polygon(draw, petal_points(cx, cy, 5.5, 2.4, angle), (*accent, 235))
    for angle in (math.pi / 4, math.pi * 3 / 4, math.pi * 5 / 4, math.pi * 7 / 4):
        cx = center + math.cos(angle) * 43
        cy = center + math.sin(angle) * 43
        ellipse(draw, (cx - 1.25, cy - 1.25, cx + 1.25, cy + 1.25), (*PAPER, 215))

    draw_symbol(draw, kind, accent)
    return image.resize((TILE, TILE), Image.Resampling.LANCZOS)


def main():
    atlas = Image.new("RGBA", (TILE * len(PALETTES), TILE), (0, 0, 0, 0))
    for index, (kind, accent) in enumerate(PALETTES.items()):
        atlas.alpha_composite(make_icon(kind, accent), (index * TILE, 0))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUTPUT, optimize=True)
    print(f"Generated {OUTPUT} ({atlas.width}x{atlas.height}, {len(PALETTES)} emblems)")


if __name__ == "__main__":
    main()
