#!/usr/bin/env python3
"""Generate the tvOS app icon and Top Shelf images.

Writes the brand asset catalog "App Icon & Top Shelf Image.brandassets" into
App/Resources/Assets.xcassets. The motif is a procedural emission nebula in
the Hubble palette; all randomness is seeded, so re-running the script only
changes files when the drawing code changes.

Layers (parallax on the Home Screen, front to back):
  Front  – a few bright stars with diffraction spikes, transparent background
  Middle – emission nebula with dust lanes, transparent background
  Back   – opaque deep-space background with faint stars

Requires Pillow and NumPy: python3 -m pip install Pillow numpy
"""

from __future__ import annotations

import json
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "App/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
INFO = {"author": "xcode", "version": 1}

SPACE = np.array([0.006, 0.008, 0.018])
GOLD = np.array([1.00, 0.66, 0.30])
TEAL = np.array([0.10, 0.62, 0.70])
BLUE = np.array([0.16, 0.26, 0.70])
STAR_COLOURS = np.array([
    [0.72, 0.82, 1.00],
    [0.90, 0.94, 1.00],
    [1.00, 1.00, 1.00],
    [1.00, 0.93, 0.80],
    [1.00, 0.80, 0.58],
])


@dataclass(frozen=True)
class Layout:
    """Positions as fractions of width/height; sizes as fractions of height."""

    nebula_centre: tuple[float, float]
    nebula_radius: tuple[float, float]
    bright_stars: tuple[tuple[float, float, float, int], ...]  # x, y, size, colour index
    seed: int


ICON = Layout(
    nebula_centre=(0.5, 0.52),
    nebula_radius=(0.42, 0.40),
    bright_stars=((0.34, 0.36, 1.0, 1), (0.70, 0.66, 0.55, 3), (0.80, 0.26, 0.35, 0)),
    seed=7,
)
TOP_SHELF = Layout(
    nebula_centre=(0.74, 0.5),
    nebula_radius=(0.30, 0.55),
    bright_stars=((0.62, 0.32, 0.8, 1), (0.88, 0.70, 0.45, 3), (0.30, 0.22, 0.3, 0), (0.12, 0.70, 0.25, 2)),
    seed=11,
)


# Noise ----------------------------------------------------------------------

def fbm(h: int, w: int, rng: np.random.Generator, octaves: int = 7, base: int = 3, gain: float = 0.5) -> np.ndarray:
    """Fractal value noise in [0, 1], isotropic in units of the image height."""
    total = np.zeros((h, w), np.float32)
    amplitude, norm = 1.0, 0.0
    for octave in range(octaves):
        cells_y = base * 2**octave
        cells_x = max(1, round(cells_y * w / h))
        grid = rng.random((cells_y + 3, cells_x + 3)).astype(np.float32)
        # Bicubic upsampling of a slightly larger grid, cropped to hide edge effects.
        scale_y, scale_x = h / cells_y, w / cells_x
        big = Image.fromarray(grid).resize((round((cells_x + 3) * scale_x), round((cells_y + 3) * scale_y)), Image.Resampling.BICUBIC)
        oy, ox = int(scale_y), int(scale_x)
        total += amplitude * np.asarray(big, np.float32)[oy:oy + h, ox:ox + w]
        norm += amplitude
        amplitude *= gain
    return total / norm


def stretch(field: np.ndarray) -> np.ndarray:
    lo, hi = np.percentile(field, [1, 99])
    return np.clip((field - lo) / (hi - lo), 0, 1)


def sample(field: np.ndarray, ys: np.ndarray, xs: np.ndarray) -> np.ndarray:
    """Bilinear lookup with clamped coordinates."""
    h, w = field.shape
    ys = np.clip(ys, 0, h - 1.001)
    xs = np.clip(xs, 0, w - 1.001)
    y0, x0 = ys.astype(np.int32), xs.astype(np.int32)
    fy, fx = ys - y0, xs - x0
    top = field[y0, x0] * (1 - fx) + field[y0, x0 + 1] * fx
    bottom = field[y0 + 1, x0] * (1 - fx) + field[y0 + 1, x0 + 1] * fx
    return top * (1 - fy) + bottom * fy


def warped(h: int, w: int, rng: np.random.Generator, strength: float) -> np.ndarray:
    """Domain-warped noise: wispy, filament-like structure."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    qx = stretch(fbm(h, w, rng, octaves=5)) - 0.5
    qy = stretch(fbm(h, w, rng, octaves=5)) - 0.5
    return stretch(sample(fbm(h, w, rng), ys + strength * h * qy, xs + strength * h * qx))


def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def blur(image: np.ndarray, sigma: float) -> np.ndarray:
    radius = max(1, int(3 * sigma))
    kernel = np.exp(-0.5 * (np.arange(-radius, radius + 1) / sigma) ** 2)
    kernel /= kernel.sum()
    out = image
    for axis in (0, 1):
        out = np.apply_along_axis(lambda line: np.convolve(line, kernel, mode="same"), axis, out)
    return out


# Layers ---------------------------------------------------------------------

def nebula(h: int, w: int, layout: Layout) -> np.ndarray:
    rng = np.random.default_rng(layout.seed)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = (xs / w - layout.nebula_centre[0]) * w / h / layout.nebula_radius[0]
    dy = (ys / h - layout.nebula_centre[1]) / layout.nebula_radius[1]
    falloff = np.exp(-1.6 * (dx**2 + dy**2))

    gas = warped(h, w, rng, strength=0.35)
    core_gas = warped(h, w, rng, strength=0.25)
    detail = stretch(fbm(h, w, rng, octaves=8, base=6, gain=0.6))
    dust = warped(h, w, rng, strength=0.3)

    outer = smoothstep(0.25, 0.9, gas) * falloff * (0.65 + 0.35 * detail)
    core = smoothstep(0.45, 1.0, core_gas) * falloff**2.2 * (0.55 + 0.45 * detail)
    rim = smoothstep(0.2, 0.7, gas) * falloff**0.5 * 0.35
    lanes = 1 - 0.95 * smoothstep(0.55, 0.8, dust) * smoothstep(0.1, 0.5, falloff)

    rgb = (TEAL * outer[..., None] * 1.3 + GOLD * core[..., None] * 1.8 + BLUE * rim[..., None]) * lanes[..., None]
    return 1 - np.exp(-1.6 * rgb)  # soft tone mapping


def stars(h: int, w: int, rng: np.random.Generator, density: float, sigma: float, brightness: float) -> np.ndarray:
    count = int(density * w * h / 1e4)
    canvas = np.zeros((h, w, 3), np.float32)
    ys, xs = rng.integers(0, h, count), rng.integers(0, w, count)
    level = np.minimum(rng.pareto(2.2, count) * 0.25 + 0.05, 1.0) * brightness
    colours = STAR_COLOURS[rng.integers(0, len(STAR_COLOURS), count)]
    np.add.at(canvas, (ys, xs), colours * level[:, None])
    return blur(canvas, sigma) * (2 * np.pi * sigma**2)


def back(h: int, w: int, layout: Layout) -> np.ndarray:
    rng = np.random.default_rng(layout.seed + 100)
    unit = h / 768
    glow = stretch(fbm(h, w, rng, octaves=4, base=2))[..., None] * np.array([0.02, 0.025, 0.05])
    field = stars(h, w, rng, density=9, sigma=0.55 * unit, brightness=0.9)
    field += stars(h, w, rng, density=0.6, sigma=1.1 * unit, brightness=1.2)
    return np.clip(SPACE + glow + field, 0, 1)


def front(h: int, w: int, layout: Layout) -> np.ndarray:
    canvas = np.zeros((h, w, 3), np.float32)
    for fx, fy, size, colour in layout.bright_stars:
        cx, cy, s = fx * w, fy * h, size * h / 768
        reach = int(120 * s)
        y0, y1 = max(0, int(cy) - reach), min(h, int(cy) + reach)
        x0, x1 = max(0, int(cx) - reach), min(w, int(cx) + reach)
        ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        dy, dx = ys - cy, xs - cx
        r2 = dx**2 + dy**2
        core = np.exp(-r2 / (2 * (3.0 * s) ** 2))
        halo = 0.35 * np.exp(-r2 / (2 * (14 * s) ** 2)) + 0.12 * np.exp(-np.sqrt(r2) / (40 * s))
        # Spikes taper: short exponential reach, width shrinking with distance.
        def spike(along: np.ndarray, across: np.ndarray) -> np.ndarray:
            width = 1.4 * s * np.exp(-np.abs(along) / (60 * s)) + 0.3
            return np.exp(-np.abs(along) / (28 * s)) * np.exp(-across**2 / (2 * width**2))

        light = np.clip(core * 1.4 + halo + 0.55 * (spike(dx, dy) + spike(dy, dx)), 0, None)
        canvas[y0:y1, x0:x1] += light[..., None] * STAR_COLOURS[colour]
    return 1 - np.exp(-1.8 * canvas)


def to_rgba(rgb: np.ndarray) -> Image.Image:
    """Light on transparent: alpha from brightness, colour un-premultiplied."""
    alpha = np.clip(rgb.max(axis=2), 0, 1)
    colour = np.where(alpha[..., None] > 1e-4, rgb / np.maximum(alpha[..., None], 1e-4), 0)
    data = np.dstack([colour, alpha])
    return Image.fromarray((np.clip(data, 0, 1) * 255 + 0.5).astype(np.uint8))


def to_rgb(rgb: np.ndarray) -> Image.Image:
    return Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8))


def render(w: int, h: int, layout: Layout) -> dict[str, Image.Image]:
    return {
        "Front": to_rgba(front(h, w, layout)),
        "Middle": to_rgba(nebula(h, w, layout)),
        "Back": to_rgb(back(h, w, layout)),
    }


def flatten(layers: dict[str, Image.Image]) -> Image.Image:
    image = layers["Back"].convert("RGBA")
    for name in ("Middle", "Front"):
        image = Image.alpha_composite(image, layers[name])
    return image.convert("RGB")


# Catalog --------------------------------------------------------------------

def write_json(path: Path, payload: dict) -> None:
    path.mkdir(parents=True, exist_ok=True)
    (path / "Contents.json").write_text(json.dumps(payload, indent=2) + "\n")


def write_stack(name: str, layers: dict[str, Image.Image], sizes: dict[int, tuple[int, int]]) -> None:
    stack = CATALOG / f"{name}.imagestack"
    write_json(stack, {"info": INFO, "layers": [{"filename": f"{layer}.imagestacklayer"} for layer in layers]})
    for layer, image in layers.items():
        layer_dir = stack / f"{layer}.imagestacklayer"
        write_json(layer_dir, {"info": INFO})
        content = layer_dir / "Content.imageset"
        content.mkdir(parents=True, exist_ok=True)
        images = []
        for scale, size in sizes.items():
            filename = f"{layer.lower()}@{scale}x.png"
            image.resize(size, Image.Resampling.LANCZOS).save(content / filename, optimize=True)
            images.append({"filename": filename, "idiom": "tv", "scale": f"{scale}x"})
        write_json(content, {"images": images, "info": INFO})


TITLE = "Pan Galactic"
SUBTITLE = "N.I.N.A. Observatory Monitor"
TEXT = (220, 227, 230)      # Theme.text
TEXT2 = (140, 154, 162)     # Theme.text2


def font(size: int, weight: str) -> ImageFont.FreeTypeFont:
    """SF Pro from the system (variable font); Helvetica Neue as fallback."""
    try:
        f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
        f.set_variation_by_name(weight)
        return f
    except (OSError, ValueError):
        return ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", size)


def letter(image: Image.Image) -> Image.Image:
    """Name and subtitle on the star field, left of the nebula, inside the safe area.

    tvOS 26 shows the Top Shelf full screen behind the dock, scaled up and centre-cropped:
    of a 720 pt high image only the middle 1760 pt are visible (measured in the tvOS 26.5
    simulator), so the text starts at the 80 pt screen margin of that crop.
    """
    w, h = image.size
    draw = ImageDraw.Draw(image)
    visible = h * 1760 / 720
    x = round((w - visible) / 2 + visible * 80 / 1920)
    title = font(round(h * 0.15), "Semibold")
    subtitle = font(round(h * 0.055), "Regular")
    title_box = draw.textbbox((0, 0), TITLE, font=title)
    y = round(h * 0.40) - (title_box[3] - title_box[1])
    draw.text((x, y), TITLE, font=title, fill=TEXT)
    draw.text((x + round(h * 0.006), y + (title_box[3] - title_box[1]) + round(h * 0.07)), SUBTITLE, font=subtitle, fill=TEXT2)
    return image


def write_top_shelf(name: str, base_size: tuple[int, int]) -> None:
    imageset = CATALOG / f"{name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    full = letter(flatten(render(base_size[0] * 2, base_size[1] * 2, TOP_SHELF)))
    images = []
    for scale in (1, 2):
        filename = f"top-shelf@{scale}x.png"
        full.resize((base_size[0] * scale, base_size[1] * scale), Image.Resampling.LANCZOS).save(imageset / filename, optimize=True)
        images.append({"filename": filename, "idiom": "tv", "scale": f"{scale}x"})
    write_json(imageset, {"images": images, "info": INFO})


def main() -> int:
    if CATALOG.exists():
        shutil.rmtree(CATALOG)
    # Render once at App Store size and downsample, so all icon sizes look identical.
    icon = render(1280, 768, ICON)
    write_stack("App Icon", icon, {1: (400, 240), 2: (800, 480)})
    write_stack("App Icon - App Store", icon, {1: (1280, 768)})
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
