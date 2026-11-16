# Demo server

A pretend N.I.N.A. for screenshots and UI work without a telescope. It answers the read-only routes the app polls, in the shapes of Advanced API 2.2.15.3, on `127.0.0.1` only.

| Route | Served |
|---|---|
| `/version`, `/version/nina` | Fixture versions (plugin 2.2.15.3, N.I.N.A. 3.2) |
| `/equipment/info` | The idle fixture dressed up as a clear night: camera cooled to −10 °C and exposing, mount tracking M 31 with a meridian flip in about two hours, PHD2 guiding, dome not connected |
| `/sequence/state`, `/sequence/json` | The running-sequence fixtures, aimed at M 31, with a time-bound loop ending about three hours after start |
| `/image-history` | 23 frames at start, one more every 300 s, with plausible HFR and star counts |
| `/image/thumbnail/{i}`, `/image/{i}` | A procedural galaxy, rendered once at sensor size (6224 × 4168) and cached in `.cache/` |

Everything else returns 404. Nothing comes from a real observatory: the equipment data is the sanitized test fixture and the site is the Royal Observatory, Greenwich.

```sh
python3 -m pip install Pillow numpy
python3 tools/demo/demo_server.py [--port 1888]
```

In the app, add an instance with host `127.0.0.1`. The tvOS Simulator shares the Mac's network. For seeding the instance and opening particular screens through Debug launch arguments, see [docs/status.md](../../docs/status.md#screenshots-and-ui-work-without-a-telescope).
