"""Build the title-screen assets from the user's source art.

Produces:
  game/assets/title/bg.png        1280x720 background
  game/assets/title/logo.png      logo sprite (cropped, transparent)
  game/assets/title/icon_1..9.png nine menu icons, one per cell

Run from the game directory:
  python tools/build_title_assets.py
"""
import io
import os
from PIL import Image

SRC = "resource"
OUT = "game/assets/title"

# Source art --------------------------------------------------------------
BG_SRC = os.path.join(SRC, "title_BG.png")
LOGO_SRC = os.path.join(SRC, "title.png")
ICONS_SRC = os.path.join(SRC, "ICONS.png")

SCREEN_W, SCREEN_H = 1280, 720

# Icons are drawn inside a 104px menu cell, so storing them far above the
# displayed size only bloats the package. Downscale to the display resolution
# with a small margin for the selection lift.
ICON_MAX = 128
# The logo is displayed 420px wide.
LOGO_MAX_W = 640

os.makedirs(OUT, exist_ok=True)


def trim_alpha(image, threshold=8):
    """Tight crop to the non-transparent content."""
    bbox = image.getchannel("A").point(lambda a: 255 if a > threshold else 0).getbbox()
    if bbox:
        return image.crop(bbox)
    return image


# --- Background ----------------------------------------------------------
bg = Image.open(BG_SRC).convert("RGB")
# Cover the screen while preserving aspect ratio, then center-crop.
scale = max(SCREEN_W / bg.width, SCREEN_H / bg.height)
new_size = (max(1, round(bg.width * scale)), max(1, round(bg.height * scale)))
bg = bg.resize(new_size, Image.LANCZOS)
left = (bg.width - SCREEN_W) // 2
top = (bg.height - SCREEN_H) // 2
bg = bg.crop((left, top, left + SCREEN_W, top + SCREEN_H))
bg.save(os.path.join(OUT, "bg.png"), optimize=True)
print("bg.png", bg.size)

# --- Logo ----------------------------------------------------------------
logo = trim_alpha(Image.open(LOGO_SRC).convert("RGBA"))
# Scale the logo to a comfortable header width, keeping its aspect ratio.
if logo.width > LOGO_MAX_W:
    logo = logo.resize((LOGO_MAX_W, max(1, round(logo.height * LOGO_MAX_W / logo.width))), Image.LANCZOS)
logo.save(os.path.join(OUT, "logo.png"), optimize=True)
print("logo.png", logo.size)

# --- Icons ---------------------------------------------------------------
# The sheet is a 3x3 grid; split at the midpoints of the detected gaps.
ROW_EDGES = [0, 441, 812, 1254]
COL_EDGES = [0, 433, 833, 1254]
sheet = Image.open(ICONS_SRC).convert("RGBA")
index = 0
for r in range(3):
    for c in range(3):
        index += 1
        cell = sheet.crop((COL_EDGES[c], ROW_EDGES[r], COL_EDGES[c + 1], ROW_EDGES[r + 1]))
        cell = trim_alpha(cell)
        # Downscale to the menu display size.
        if max(cell.width, cell.height) > ICON_MAX:
            scale = ICON_MAX / max(cell.width, cell.height)
            cell = cell.resize((max(1, round(cell.width * scale)), max(1, round(cell.height * scale))), Image.LANCZOS)
        cell.save(os.path.join(OUT, "icon_%d.png" % index), optimize=True)
        print("icon_%d.png" % index, cell.size)
