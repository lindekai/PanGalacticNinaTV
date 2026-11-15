#!/usr/bin/env python3
"""Generate the placeholder tvOS app icon and Top Shelf images.

Writes the brand asset catalog "App Icon & Top Shelf Image.brandassets" into
App/Resources/Assets.xcassets. The output is deterministic (fixed star seed),
so re-running the script only changes files when the drawing code changes.

Layers (parallax on the Home Screen, front to back):
  Front  – telescope silhouette, transparent background
  Middle – moon with soft glow, transparent background
  Back   – opaque night-sky gradient with stars

Requires Pillow: python3 -m pip install Pillow
"""

from __future__ import annotations

import json
import random
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "App/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
INFO = {"author": "xcode", "version": 1}
SUPERSAMPLE = 4

SKY_TOP = (8, 12, 38)
SKY_BOTTOM = (46, 26, 84)
MOON = (236, 232, 214)
TELESCOPE = (226, 232, 246)

# Telescope silhouette from TelescopeMount.imageset/telescope-mount.svg (64 × 64 view box).
TELESCOPE_POLYGONS = [
    [(10.4, 25.0), (49.2, 6.6), (54.3, 17.4), (15.5, 35.8)],
    [(46.6, 3.9), (55.0, 0.0), (60.6, 11.8), (52.2, 15.8)],
    [(5.5, 26.8), (11.0, 24.2), (13.6, 29.6), (8.1, 32.2)],
    [(30.2, 32.8), (33.8, 36.4), (24.6, 45.6), (21.0, 42.0)],
    [(16.6, 41.4), (23.6, 48.4), (19.4, 52.6), (12.4, 45.6)],
    [(29.5, 35.0), (34.5, 35.0), (34.5, 61.0), (29.5, 61.0)],
    [(30.4, 37.6), (34.2, 40.0), (20.6, 63.0), (16.8, 60.6)],
    [(33.6, 37.6), (29.8, 40.0), (43.4, 63.0), (47.2, 60.6)],
]
TELESCOPE_HEAD = (32.0, 31.0, 7.0)  # cx, cy, r


def write_json(path: Path, payload: dict) -> None:
    path.mkdir(parents=True, exist_ok=True)
    (path / "Contents.json").write_text(json.dumps(payload, indent=2) + "\n")


def finish(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.resize(size, Image.Resampling.LANCZOS)


def back_layer(size: tuple[int, int]) -> Image.Image:
    w, h = size[0] * SUPERSAMPLE, size[1] * SUPERSAMPLE
    image = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(image)
    for y in range(h):
        t = y / max(h - 1, 1)
        colour = tuple(round(a + (b - a) * t) for a, b in zip(SKY_TOP, SKY_BOTTOM))
        draw.line([(0, y), (w, y)], fill=colour)
    rng = random.Random(42)
    unit = min(w, h)
    for _ in range(int(w * h / unit**2 * 90)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = unit * rng.choice([0.0025, 0.0035, 0.005, 0.008])
        level = rng.randint(150, 255)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(level, level, min(255, level + 20)))
    return finish(image, size).convert("RGB")


def middle_layer(size: tuple[int, int], centre: tuple[float, float], radius: float) -> Image.Image:
    w, h = size[0] * SUPERSAMPLE, size[1] * SUPERSAMPLE
    cx, cy, r = centre[0] * w, centre[1] * h, radius * min(w, h)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([cx - 1.6 * r, cy - 1.6 * r, cx + 1.6 * r, cy + 1.6 * r], fill=MOON + (70,))
    glow = glow.filter(ImageFilter.GaussianBlur(r * 0.5))
    moon = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(moon)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=MOON + (255,))
    for dx, dy, cr in [(-0.35, -0.2, 0.22), (0.3, 0.25, 0.16), (0.05, -0.45, 0.1), (-0.1, 0.45, 0.12)]:
        draw.ellipse(
            [cx + dx * r - cr * r, cy + dy * r - cr * r, cx + dx * r + cr * r, cy + dy * r + cr * r],
            fill=(212, 206, 186, 255),
        )
    return finish(Image.alpha_composite(glow, moon), size)


def front_layer(size: tuple[int, int], origin: tuple[float, float], height: float) -> Image.Image:
    """Draw the telescope; origin is the top-left corner and height the drawing height, both as fractions."""
    w, h = size[0] * SUPERSAMPLE, size[1] * SUPERSAMPLE
    scale = height * h / 64
    ox, oy = origin[0] * w, origin[1] * h
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    fill = TELESCOPE + (255,)
    for polygon in TELESCOPE_POLYGONS:
        draw.polygon([(ox + x * scale, oy + y * scale) for x, y in polygon], fill=fill)
    cx, cy, r = TELESCOPE_HEAD
    draw.ellipse([ox + (cx - r) * scale, oy + (cy - r) * scale, ox + (cx + r) * scale, oy + (cy + r) * scale], fill=fill)
    return finish(image, size)


def icon_layers(size: tuple[int, int]) -> dict[str, Image.Image]:
    # Keep the motif inside the central safe zone; tvOS crops and scales the edges during parallax.
    return {
        "Front": front_layer(size, origin=(0.5 - 0.62 * size[1] / size[0] / 2, 0.2), height=0.62),
        "Middle": middle_layer(size, centre=(0.7, 0.3), radius=0.12),
        "Back": back_layer(size),
    }


def write_stack(name: str, base_size: tuple[int, int], scales: list[int]) -> None:
    stack = CATALOG / f"{name}.imagestack"
    layer_names = ["Front", "Middle", "Back"]
    write_json(stack, {"info": INFO, "layers": [{"filename": f"{layer}.imagestacklayer"} for layer in layer_names]})
    rendered = {scale: icon_layers((base_size[0] * scale, base_size[1] * scale)) for scale in scales}
    for layer in layer_names:
        layer_dir = stack / f"{layer}.imagestacklayer"
        write_json(layer_dir, {"info": INFO})
        content = layer_dir / "Content.imageset"
        images = []
        for scale in scales:
            filename = f"{layer.lower()}@{scale}x.png"
            content.mkdir(parents=True, exist_ok=True)
            rendered[scale][layer].save(content / filename, optimize=True)
            images.append({"filename": filename, "idiom": "tv", "scale": f"{scale}x"})
        write_json(content, {"images": images, "info": INFO})


def write_top_shelf(name: str, base_size: tuple[int, int]) -> None:
    imageset = CATALOG / f"{name}.imageset"
    images = []
    for scale in (1, 2):
        size = (base_size[0] * scale, base_size[1] * scale)
        image = back_layer(size).convert("RGBA")
        aspect = size[1] / size[0]
        image = Image.alpha_composite(image, middle_layer(size, centre=(1 - 1.15 * aspect, 0.3), radius=0.13))
        image = Image.alpha_composite(image, front_layer(size, origin=(1 - 0.9 * aspect, 0.18), height=0.7))
        filename = f"top-shelf@{scale}x.png"
        imageset.mkdir(parents=True, exist_ok=True)
        image.convert("RGB").save(imageset / filename, optimize=True)
        images.append({"filename": filename, "idiom": "tv", "scale": f"{scale}x"})
    write_json(imageset, {"images": images, "info": INFO})


def main() -> int:
    if CATALOG.exists():
        shutil.rmtree(CATALOG)
    write_stack("App Icon", (400, 240), [1, 2])
    write_stack("App Icon - App Store", (1280, 768), [1])
    write_top_shelf("Top Shelf Image", (1920, 720))
    write_top_shelf("Top Shelf Image Wide", (2320, 720))
    write_json(
        CATALOG,
        {
            "assets": [
                {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
                {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
                {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
                {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
            ],
            "info": INFO,
        },
    )
    print(f"Wrote {CATALOG.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
