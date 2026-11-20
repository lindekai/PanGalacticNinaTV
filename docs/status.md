# Project status

Snapshot for picking up work on another machine. Last updated 2026-11-20 (M4.1 The Night).

## Resume here

- Branch `m4/night` (M4.1 The Night: night page, Object module with computed altitude, site cache, build 7). Earlier: branch `m3/tv-feedback` (sequence strip and page, build 6).
- Device check on the TV with build 7 is open: focus path image ⇄ Object module ⇄ sequence strip, and Menu back from the night page (could not be pressed in the simulator).
- Device check on the TV with build 6 is still open: focus path image ⇄ strip ⇄ header, Menu back from the sequence page, and the sequence page opening on the current step with a long real sequence.
- Earlier: branch `m3/guiding-overview`, **PR #18**, waiting for the owner's review.
- After approval: merge #18, start M4 ([ADR 0005](adr/0005-m4-before-m3-part-2.md)); check the guiding chart on the Apple TV during the next guided night.
- TestFlight build 5 is uploaded (2026-11-19; the first attempt on 2026-11-17 failed during an App Store Connect outage).
- Archiving lets Xcode rewrite `App/Resources/Localizable.xcstrings` (reformatted, many keys marked `stale`, `HFR`/`Live` dropped). Do not commit that: `git restore App/Resources/Localizable.xcstrings`.
- Decisions taken without explicit owner confirmation (change in #18 if wanted): RMS and colours only while the state is Guiding (curves dimmed otherwise); red LED and spelled-out state on LostLock; German tile text "bis Flip"; clock without AM/PM.
- Discord announcement draft (text and image): [docs/announcements/2026-11-17-discord.md](announcements/2026-11-17-discord.md).
- Capture night (#5, #6, #7 and the device check in one night): [checklist](m3-capture-night.md).
- Demo server for screenshots: `python3 tools/demo/demo_server.py [--guider-state Guiding|Stopped|LostLock]` ([tools/demo/README.md](../tools/demo/README.md)).

## Where things stand

| Item | State |
|---|---|
| M0 API feasibility | Done (PR #2, #3) |
| M1 Skeleton & connections | Done (PR #10) |
| M2 Overview & imaging | Done (PR #11, #13–#16): overview, viewer with zoom, ambient mode, devices and device details, sequence progress. Checked on Apple TV 4K with TestFlight build 4 |
| M3 Guiding & alerts | Paused: part 1 (overview guiding chart, meridian tile) in review; TV feedback (sequence strip and page, version, filter icon) on `m3/tv-feedback`, device check with build 6 open; part 2 waits for the capture night |
| M4 Astronomy | In progress: M4.1 The Night on `m4/night`, build 7 ([spec](superpowers/specs/2026-11-20-m4-night-design.md)) |
| TestFlight | Build 5 (guiding chart) uploaded 2026-11-19; build 6 (sequence strip and page) and build 7 (the night) are candidates |

Details: [milestones](milestones.md), [changelog](../CHANGELOG.md).

## Open items

| Issue | What is needed | Who |
|---|---|---|
| #5 | Confirm that the cooling ramp ends at `TargetTemp`; if so, show it as "target" next to the current setpoint | Owner lets a cooldown finish |
| #6 | PHD2 `GuideStep`, dither and settle from the PHD2 stream (N.I.N.A.'s RMS definition is settled by source review) | M3, needs a guided night with the M0 listeners |
| #7 | Filter-change, dither and autofocus WebSocket events | M3, same capture night |
| – | Surveillance camera view: owner answers the open questions in the [proposal](features/surveillance-camera.md) | Owner |

## Next steps

1. Device check of build 7 on the TV, then M4.2 (planets, time travel); M4.3 star map and FOV overlay last, after the catalogue licence is settled ([ADR 0005](adr/0005-m4-before-m3-part-2.md)).
2. M5 after M4: conditions, EN/DE and message engine first; statistics once verified metrics exist.
3. Whenever a clear night comes: device check of the guiding chart, then M3 part 2 (alerts, PHD2 stream, WebSocket events). Capture night: run `tools/m0` (passive WebSocket and PHD2 listeners) during guided imaging with dithering and an autofocus run, for #6 and #7; cooling snapshots for #5. Follow the [checklist](m3-capture-night.md).

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

### Signing, archive and TestFlight

The team ID is not in the repository. For device builds and archives:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # git-ignored; set DEVELOPMENT_TEAM
xcodebuild -project PanGalacticNinaTV.xcodeproj -scheme PanGalacticNinaTV \
  -destination 'generic/platform=tvOS' -configuration Release \
  -archivePath build/PanGalactic.xcarchive -allowProvisioningUpdates archive
```

Without a registered Apple TV in the team, automatic signing cannot archive (it first wants a development profile). Create a "tvOS App Store Connect" profile in the developer portal and enable the optional Release lines in `Local.xcconfig` (see the example file); Debug builds keep automatic signing.

Upload the archive from Xcode's Organizer (Distribute App → TestFlight & App Store). Raise `CURRENT_PROJECT_VERSION` for every upload. The placeholder icon is regenerated with `python3 tools/icons/make_placeholder_icons.py`.

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

### Screenshots and UI work without a telescope

`tools/demo/demo_server.py` serves a pretend N.I.N.A. on `127.0.0.1:1888` (see [its README](../tools/demo/README.md)). Seed an instance with host `127.0.0.1` as above; the Debug launch arguments `-debug.openViewer YES`, `-debug.zoom N` and `-debug.screen devices|Camera|Mount|…` (any `/equipment/info` key) open the other screens. Ambient mode after one minute: `xcrun simctl spawn <device-id> defaults write io.github.lindekai.PanGalacticNinaTV ambient.delayMinutes -int 1` (delete the key afterwards). Simulator screenshots of a 4K Apple TV are large PNGs; convert them right away (`sips -Z 1920 -s format jpeg`).

### Files that are not in the repository

- `captures/` (git-ignored): raw probe captures. They contain third-party API keys and the real host; copy them only if needed, never commit them.
- The plugin source used for reviews is the public `christian-photo/ninaAPI` repository at tag `2.2.15.3` (commit `353a853`); clone it locally for source reviews.
