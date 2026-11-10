# Project status

Snapshot for picking up work on another machine. Last updated 2026-11-10.

## Where things stand

| Item | State |
|---|---|
| M0 API feasibility | Done (PR #2, #3) |
| M1 Skeleton & connections | Done (PR #10); Apple TV hardware check open in #8 |
| M2 Overview & imaging | Part 1 in PR #11 (`m2/overview`), CI green, **awaiting review and merge** |
| Tests | 74 (`swift test`: 52 core, 22 services) |

Details: [milestones](milestones.md), [changelog](../CHANGELOG.md).

## Open items

| Issue | What is needed | Who |
|---|---|---|
| #4 | Capture `/sequence/json` and `/sequence/state` while a real sequence runs (e.g. 3 × 30 s lights), then implement "exposure n of m" | Owner starts a sequence; then capture with `tools/m0/m0probe.py rest --label running` |
| #5 | Confirm that the cooling ramp ends at `TargetTemp`; if so, show it as "target" next to the current setpoint | Owner lets a cooldown finish |
| #6 | PHD2 `GuideStep`, dither, settle and RMS definition | M3 |
| #7 | Filter-change, dither and autofocus WebSocket events | M3 |
| #8 | Run the app on Apple TV: bare Windows hostname, Wi-Fi vs. Ethernet, idle timer, latency and memory on device | Owner (needs signing team) |
| – | Surveillance camera view: owner answers the open questions in the [proposal](features/surveillance-camera.md) | Owner |

## Next steps

1. Review and merge PR #11.
2. Sequence capture (#4) → sequence progress on the Overview; this completes M2.
3. M3: guiding chart, RMS, read-only WebSocket listener, foreground alerts.

## Setting up a new machine

Requirements: macOS with Xcode 26 or newer (tvOS 26 SDK), Python 3 for the M0 tooling, GitHub CLI.

```sh
git clone https://github.com/lindekai/PanGalacticNinaTV.git
cd PanGalacticNinaTV
git config user.email "<your GitHub noreply address>"   # push protection rejects private addresses

# Tests and build
(cd Packages/PanGalacticCore && swift test)
python3 tools/m0/tests/test_m0probe.py
xcodebuild -project PanGalacticNinaTV.xcodeproj -scheme PanGalacticNinaTV \
  -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build
```

A tvOS 26.x simulator runtime is needed to run the app (Xcode → Settings → Components).

### Running in the simulator against a real N.I.N.A.

The app reads its instance list from `UserDefaults` (ADR 0003), so a test instance can be passed as a launch argument without touching the UI:

```sh
HEX=$(python3 -c 'import json;print(json.dumps({"version":1,"instances":[{"id":"6F1C2D7E-0000-4000-8000-000000000001","name":"Observatory","host":"<N.I.N.A. host>","apiPort":1888}]}).encode().hex())')
xcrun simctl launch <device-id> io.github.lindekai.PanGalacticNinaTV -instances.v1 "<$HEX>"
# Debug builds only: open the full-screen viewer as soon as an image is known
xcrun simctl launch <device-id> io.github.lindekai.PanGalacticNinaTV -instances.v1 "<$HEX>" -debug.openViewer YES
```

Never commit the real host, captures or screenshots that show it.

### Files that are not in the repository

- `captures/` (git-ignored): raw probe captures. They contain third-party API keys and the real host; copy them only if needed, never commit them.
- The plugin source used for reviews is the public `christian-photo/ninaAPI` repository at tag `2.2.15.3` (commit `353a853`); clone it locally for source reviews.
