#!/usr/bin/env python3
"""Generate the README banner from the app artwork.

Renders the Top Shelf nebula (same layers and seed as the app's Top Shelf image)
at banner size and letters it with the app name, tagline and description.
Writes docs/assets/banner.jpg.

Requires Pillow and NumPy: python3 -m pip install Pillow numpy
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import ImageDraw

from make_placeholder_icons import ROOT, TEXT, TEXT2, TOP_SHELF, flatten, font, render

OUTPUT = ROOT / "docs/assets/banner.jpg"
SIZE = (2560, 720)  # 1280 × 360 at 2x

TITLE = "Pan Galactic N.I.N.A. TV"
TAGLINE = "Don't Panic. Your Telescope Is Probably Fine."
DESCRIPTION = "Your observatory on the big screen · read-only monitor for N.I.N.A. and PHD2 on Apple TV"
GOLD = (255, 196, 110)


def main() -> int:
    w, h = SIZE
    image = flatten(render(w, h, TOP_SHELF))
    draw = ImageDraw.Draw(image)
    x = round(h * 0.16)
    title = font(round(h * 0.15), "Semibold")
    tagline = font(round(h * 0.062), "Medium")
    description = font(round(h * 0.040), "Regular")
    y = round(h * 0.25)
    draw.text((x, y), TITLE, font=title, fill=TEXT)
    y = draw.textbbox((x, y), TITLE, font=title)[3] + round(h * 0.07)
    draw.text((x, y), TAGLINE, font=tagline, fill=GOLD)
    y = draw.textbbox((x, y), TAGLINE, font=tagline)[3] + round(h * 0.06)
    draw.text((x, y), DESCRIPTION, font=description, fill=TEXT2)
    image.save(OUTPUT, quality=88, optimize=True, progressive=True)
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
