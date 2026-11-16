#!/usr/bin/env python3
"""A pretend N.I.N.A. for screenshots and UI work without a telescope.

Serves the read-only routes the app polls (Advanced API 2.2.15.3 shapes) on
127.0.0.1 from the sanitized test fixtures, dressed up as a clear night:
camera cooled and exposing, mount tracking M 31, guiding, a time-bound
sequence loop with a few hours left, and a history of frames. The frames are a
procedural galaxy (seeded, so every run draws the same picture); nothing comes
from a real observatory.

    python3 -m pip install Pillow numpy
    python3 tools/demo/demo_server.py            # http://127.0.0.1:1888/v2/api

Point an instance at host 127.0.0.1 (the tvOS Simulator shares the Mac's
network). Rendered frames are cached in tools/demo/.cache (git-ignored).
"""

from __future__ import annotations

import argparse
import io
import json
import math
import re
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "Packages/PanGalacticCore/Tests/PanGalacticCoreTests/Fixtures/nina"
CACHE = Path(__file__).resolve().parent / ".cache"

SENSOR = (6224, 4168)  # IMX571, as in the fixtures
EXPOSURE = 300  # seconds per light frame
FRAMES = 23  # frames already in the history when the server starts
TARGET = "M 31"
# A public landmark instead of a real site: the Royal Observatory, Greenwich.
SITE = {"SiteLatitude": 51.4769, "SiteLongitude": -0.0005, "SiteElevation": 46}

START = datetime.now(timezone.utc).astimezone()


def fixture(name: str):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def envelope(response):
    return {"Response": response, "Error": "", "StatusCode": 200, "Success": True, "Type": "API"}


def iso(moment: datetime) -> str:
    return moment.isoformat(timespec="microseconds")


def frame_count(now: datetime) -> int:
    return FRAMES + int((now - START).total_seconds() // EXPOSURE)


# MARK: Equipment


def equipment(now: datetime) -> dict:
    info = fixture("equipment-info-idle.json")["Response"]
    elapsed = (now - START).total_seconds() % EXPOSURE
    exposure_end = now + timedelta(seconds=EXPOSURE - elapsed)

    info["Camera"].update(
        Temperature=-10.0, TargetTemp=-10, TemperatureSetPoint=-10, AtTargetTemp=True, CoolerOn=True,
        CoolerPower=38.5, IsExposing=True, CameraState="Exposing", ExposureEndTime=iso(exposure_end),
        Gain=100, Offset=50, DewHeaterOn=True, LastDownloadTime=1.82,
    )
    info["Mount"].update(
        TrackingEnabled=True, TrackingMode="Sidereal", AtPark=False, AtHome=False, Slewing=False,
        RightAscension=0.7122, Declination=41.269, RightAscensionString="00:42:44",
        DeclinationString="41° 16' 09\"", Altitude=62.24, AltitudeString="62° 14' 30\"",
        Azimuth=118.04, AzimuthString="118° 02' 11\"", SideOfPier="pierWest",
        TimeToMeridianFlip=2.35, TimeToMeridianFlipString="02:21:00", HoursToMeridianString="02:06:00",
        SiderealTime=22.61, SiderealTimeString="22:36:44", **SITE,
    )
    info["Mount"].pop("Coordinates", None)
    info["Guider"].update(
        State="Guiding", PixelScale=3.87,
        RMSError={
            "RA": {"Pixel": 0.111, "Arcseconds": 0.43}, "Dec": {"Pixel": 0.090, "Arcseconds": 0.35},
            "Total": {"Pixel": 0.143, "Arcseconds": 0.55}, "PeakRA": {"Pixel": 0.41, "Arcseconds": 1.59},
            "PeakDec": {"Pixel": 0.33, "Arcseconds": 1.28},
        },
    )
    info["Focuser"] = {
        "Position": 30126, "StepSize": 0, "Temperature": 8.4, "IsMoving": False, "IsSettling": False,
        "TempComp": False, "TempCompAvailable": False, "Connected": True, "Name": "ZWO EAF",
        "DisplayName": "ZWO EAF (ASCOM)", "Description": "ZWO Focuser (1)",
        "DriverInfo": "ZWO Focuser ASCOM Driver", "DriverVersion": "6.0", "SupportedActions": [],
    }
    info["FlatDevice"].update(CoverState="Open", LightOn=False, Brightness=0)
    info["WeatherData"].update(
        Temperature=6.8, DewPoint=1.9, Humidity=71, Pressure=1018, CloudCover=4, WindSpeed=1.6,
        WindGust=3.1, WindDirection=245, RainRate=0,
    )
    info["SafetyMonitor"].update(IsSafe=True)
    return info


# MARK: Sequence


def sequence(name: str, now: datetime):
    """The running fixture, aimed at M 31 and ending a few hours from now."""
    text = (FIXTURES / name).read_text(encoding="utf-8").replace("Coma Cluster", TARGET)
    loop_end = iso(now.replace(microsecond=0) + timedelta(hours=3, minutes=12))
    text = re.sub(r'"TargetTime": "2026-11-16T05:00:[^"]*"', f'"TargetTime": "{loop_end}"', text)
    return json.loads(text)


# MARK: Images


def entry(index: int) -> dict:
    """Plausible statistics for frame `index`, wobbling a little from frame to frame."""
    date = START - timedelta(seconds=(FRAMES - index) * EXPOSURE)
    wobble = math.sin(index * 1.3) * 0.5 + math.sin(index * 0.37) * 0.5
    template = fixture("image-history-entry.json")["Response"][0]
    template.update(
        ExposureTime=EXPOSURE, ImageType="LIGHT", Filter="UV/IR", TargetName=TARGET, Temperature=-10.0,
        Gain=100, Offset=50, Date=iso(date), HFR=round(2.15 + 0.12 * wobble, 2),
        HFRStDev=round(0.41 + 0.03 * wobble, 2), Stars=int(1840 - 140 * wobble),
        RmsText='Tot: 0.14 (0.55")', Mean=1210.4, Median=1182, StDev=233.6, Min=212, Max=65535,
    )
    return template


def galaxy():
    """The full-resolution frame: an Andromeda-like spiral, two companions and a star field."""
    import numpy as np
    from PIL import Image

    path = CACHE / "full.jpg"
    if path.exists():
        return Image.open(path)
    CACHE.mkdir(exist_ok=True)
    width, height = SENSOR
    rng = np.random.default_rng(31)
    y, x = np.mgrid[0:height, 0:width].astype(np.float32)

    def ellipse(cx, cy, a, b, angle):
        c, s = math.cos(angle), math.sin(angle)
        u = ((x - cx) * c + (y - cy) * s) / a
        v = (-(x - cx) * s + (y - cy) * c) / b
        return u, v

    u, v = ellipse(width * 0.5, height * 0.5, 1500, 430, math.radians(-35))
    r = np.sqrt(u**2 + v**2)
    disc = np.exp(-r * 3.1)
    core = np.exp(-(r / 0.05) ** 2) * 2.5 + np.exp(-r * 14) * 1.2
    theta = np.arctan2(v, u)
    arms = 0.5 + 0.5 * np.sin(2 * theta - 9 * np.log(r + 0.05))
    dust = 1 - 0.4 * np.exp(-((np.abs(v) - 0.3) / 0.11) ** 2) * np.exp(-(r / 0.8) ** 4) * (0.5 + 0.5 * arms)
    light = (disc * (0.55 + 0.45 * arms) * dust + core).astype(np.float32)

    for cx, cy, a, b, angle, level in [(0.62, 0.36, 160, 110, -20, 0.9), (0.33, 0.72, 90, 90, 0, 1.1)]:
        cu, cv = ellipse(width * cx, height * cy, a, b, math.radians(angle))
        light += level * np.exp(-np.sqrt(cu**2 + cv**2) * 3)

    rgb = np.stack([light * 1.0, light * 0.86, light * 0.74], axis=-1)
    rgb[..., 2] += (disc * arms * (r > 0.35)).astype(np.float32) * 0.18  # blue young stars in the arms
    rgb[..., 0] += (core * 0.08).astype(np.float32)

    stars = Image.new("RGB", (width, height))
    from PIL import ImageDraw, ImageFilter
    draw = ImageDraw.Draw(stars)
    for _ in range(7000):
        sx, sy = rng.uniform(0, width), rng.uniform(0, height)
        size = 0.9 + min(rng.pareto(3.2) * 1.2, 9)
        tint = rng.choice([(255, 236, 214), (255, 250, 245), (214, 228, 255), (255, 214, 180)])
        level = min(1.0, 0.18 + rng.pareto(2.0) * 0.22)
        color = tuple(int(c * level) for c in tint)
        draw.ellipse([sx - size, sy - size, sx + size, sy + size], fill=color)
    stars = stars.filter(ImageFilter.GaussianBlur(2.2))
    star_layer = np.asarray(stars, dtype=np.float32) / 255 * 2.2

    sky = 0.035 + rng.normal(0, 0.012, (height, width, 1)).astype(np.float32)
    image = sky + rgb * 0.55 + star_layer
    image = np.arcsinh(image * 9) / np.arcsinh(9)  # stretch like N.I.N.A.'s auto stretch
    pixels = (np.clip(image, 0, 1) * 255).astype(np.uint8)
    picture = Image.fromarray(pixels)
    picture.save(path, quality=92)
    return picture


def jpeg(image, max_width: int | None) -> bytes:
    from PIL import Image

    if max_width and image.width > max_width:
        image = image.resize((max_width, round(image.height * max_width / image.width)), Image.LANCZOS)
    out = io.BytesIO()
    image.save(out, format="JPEG", quality=88)
    return out.getvalue()


RENDERS: dict[str, bytes] = {}


def render(kind: str, max_width: int | None) -> bytes:
    if kind not in RENDERS:
        RENDERS[kind] = jpeg(galaxy(), max_width)
    return RENDERS[kind]


# MARK: Server


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 (http.server API)
        url = urlparse(self.path)
        query = {k: v[-1] for k, v in parse_qs(url.query).items()}
        path = url.path.removeprefix("/v2/api")
        now = datetime.now(timezone.utc).astimezone()

        if path == "/version":
            return self.json(fixture("version.json"))
        if path == "/version/nina":
            return self.json(fixture("version-nina-friendly.json"))
        if path == "/equipment/info":
            return self.json(envelope(equipment(now)))
        if path == "/sequence/state":
            return self.json(sequence("sequence-state-running-2.json", now))
        if path == "/sequence/json":
            return self.json(sequence("sequence-json-running-2.json", now))
        if path == "/image-history":
            if query.get("count") == "true":
                return self.json(envelope(frame_count(now)))
            index = int(query.get("index", "0"))
            return self.json(envelope([entry(index)]))
        if match := re.fullmatch(r"/image/thumbnail/(\d+)", path):
            return self.bytes(render("thumbnail", 960), "image/jpeg")
        if match := re.fullmatch(r"/image/(\d+)", path):
            full = "size" not in query and "scale" not in query
            return self.bytes(render("full" if full else "screen", None if full else 1920), "image/jpeg")
        self.send_error(404, "Not part of the demo")

    def json(self, payload):
        self.bytes(json.dumps(payload).encode(), "application/json")

    def bytes(self, body: bytes, content_type: str):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=1888)
    args = parser.parse_args()
    print("Drawing the demo frame (first run takes a moment)…")
    galaxy()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Demo N.I.N.A. on http://127.0.0.1:{args.port}/v2/api – Ctrl-C to stop")
    server.serve_forever()


if __name__ == "__main__":
    main()
