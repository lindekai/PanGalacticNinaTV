# Changelog

All notable changes to this project are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added (M3)
- Guiding chart on the overview: RA and Dec of N.I.N.A.'s last guide steps (`/equipment/guider/graph`) with dither markers and ±1″/±2″ lines; the y range grows with large errors (up to ±8″). Total, RA and Dec RMS in the header, the total coloured green below 1″, yellow up to 2″ and red above (owner's thresholds). RMS is shown only while guiding; after a stop the old curves are dimmed. The light turns red when the guide star is lost.
- Meridian tile: time to the meridian flip as N.I.N.A. computes it, with the approximate clock time; "—" when not tracking.
- Source review: N.I.N.A.'s guide RMS is the population standard deviation about the mean; `RMSError` in `/equipment/info` comes from the same history as the graph.
- Demo server: live guide graph and `--guider-state`.
- Capture night checklist for the open M3 captures (#5, #6, #7) and the device check of the guiding chart.
- README: credits with author and community, as in the NINA Pocket Companion.
- ADR 0005: M4 starts while M3 part 2 waits for live data; M5 follows M4.
- Sequence strip on the overview: last step (✓, or ✕ when it failed), current step with its container, and the next step, from the existing `/sequence/json` poll. A click opens the sequence page.
- Sequence page: the whole Advanced Sequence as a tree with status per step; the running branch is expanded and centred, containers expand and collapse with a click; loop end, iterations, dither interval and exposure settings under each step.
- Settings: app version and build.
- Filter wheel icon for the Filter tile and the device list, in outline style: housing ring, five filter cells and a hub.
- TestFlight build 6 is the candidate for this feedback round.

### Changed (M3)
- The Guiding tile is replaced by the Meridian tile; guiding lives in the chart.
- Overview margins 56 px left/right and 36 px top/bottom (were Apple's 80/60 safe area), so the strip fits without shrinking the image.

### Added (M2)
- Overview: newest frame with target, type, filter, exposure, HFR and stars; camera with sensor temperature, active setpoint, cooler power, gain and exposure countdown; mount with RA/Dec, altitude, pier side and state; filter and guider.
- Full-screen image viewer: shows the thumbnail at once, then a 1920×1080 render from N.I.N.A. (one request at a time, cached).
- "As of" label and dimming when data is not live.
- Custom telescope-on-mount icon.
- ADR 0004 (image updates by polling); proposal for a surveillance camera view.
- Redesigned overview ("precision instrument"): slate/teal design system, header with sequence/exposure/live pills and settings button, newest frame with caption and HFR trend of recent frames, modules Camera (gain first), Object (altitude only while tracking), Mount, Guiding and Filter with status LEDs.
- Equatorial mount icon; Top Shelf lettering.
- Connection keeps the last 50 image-history entries (backfilled four per poll).
- Sequence pill: target, frames of this run or loop "n/m", and time left of a time-bound loop, from `/sequence/state` and `/sequence/json` (at most every 15 s); "Not running" when idle, "—" while unknown (#4).

- Ambient mode: after 5 minutes without remote input (1–30 min or off in Settings) the newest frame fills the screen with a glass strip (target · sequence · LIVE and time) that moves every 3 minutes against burn-in; new frames cross-fade. Any input or an alarm (offline, overdue exposure) returns to the overview. While it is enabled, the screensaver does not start on the overview.
- Device page (button next to Settings): all eleven device types from `/equipment/info` with name and "Connected", "Not connected" or "Unknown"; no new endpoint.
- Device details: a click on a device opens everything N.I.N.A. reports about it in groups (e.g. camera cooling, exposure, sensor; mount position, motion, meridian, site incl. coordinates; switch readings and outputs; weather; filter list with the active filter), from the same `/equipment/info` poll and read-only. Only connected devices show values; `"NaN"` readings are left out or shown as "—"; enum fields are localized in the app, N.I.N.A.'s own localized labels are not used.
- Viewer zoom in steps: a click zooms one step closer (whole frame, then 50/75/100/150/200/300/400 %, skipping steps too close to fitting), Menu one step back, Play/Pause to the whole frame. Swipes drag the picture continuously, arrow clicks move a quarter screen. Each change shows the step with one dot per step and a map of the visible part for two seconds; from 100 % on, pixels are drawn as squares. The full-resolution render (`/image/{index}` without `resize`) is requested once, on the first zoom.
- Demo server (`tools/demo/demo_server.py`): a pretend N.I.N.A. on 127.0.0.1 with sanitized fixtures and a procedural galaxy, for screenshots and UI work without a telescope.
- README with screenshots of every screen, the app artwork and a tour of the features.
- TestFlight preparation: layered app icon and Top Shelf images with a procedural nebula (`tools/icons/make_placeholder_icons.py`), `ITSAppUsesNonExemptEncryption = NO`, signing team from a git-ignored `Config/Local.xcconfig`.

### Changed (M2)
- Camera setpoint: the driver's `TemperatureSetPoint` is shown only while the cooler is on; `TargetTemp` and `AtTargetTemp` are ignored (#5).
- Guider state is localized (e.g. "Stopped" → "Gestoppt"); unknown states are shown as received.
- Header pills use one font and size on one baseline ("Sequence · Not running", like "LIVE · 17:21"); the exposure pill keeps its width while counting down.
- The newest frame takes the image's aspect ratio (no black bars).
- Focus: swiping down from the settings button reaches the image, and up returns; the image gets the focus once the first frame is known.
- README banner drawn from the app artwork (`tools/icons/make_banner.py`) instead of the earlier SVG.
- Dashboard redesign phase 2 (tab bar) dropped: the device page with per-device details covers it.
- Ambient strip no longer repeats the target when the running sequence already names it ("M 31 · 5 frames", not "M 31 · M 31 · 5 frames").

### Added (M1)
- tvOS app (`PanGalacticNinaTV.xcodeproj`, tvOS 26.0): setup, add/edit instance with read-only connection test, opt-in local network search, instance picker, dashboard placeholder with live/stale/offline badge and equipment overview, settings.
- English and German string catalogs, including the local network usage description.
- `PanGalacticServices` package target: allowlisted HTTP client, connection tester, instance store, polling instance connection, bounded subnet scan.
- Instance model, host validation, launch routing and connection state machine in `PanGalacticCore`.
- ADR 0003 (instance persistence); ADR 0002 accepted with simulator findings.
- CI builds the tvOS app.

### Changed (M1)
- Common network failures are reported as short, localizable messages.

### Changed
- `IMAGE-SAVE` statistics: placeholder values (`Stars` −1, `HFR` 0, `"NaN"`) become unavailable; `ImageType` decoded; `Date` parsed.
- PHD2 state tracker: `CalibrationFailed` sets the state to unknown.
- Sanitizer redacts API keys, tokens, passwords, secrets and URLs; only LAN-style IP addresses are redacted.

### Security
- `/profile/show` removed from all allowlists: it returns third-party API keys in plain text.

### Added
- M0 report with go/no-go and carry-over items.
- Live fixtures from a real N.I.N.A. 3.2 / Advanced API 2.2.15.3 / PHD2 2.6.14 system (sanitized) with decoding tests.
- `NINADate` parser for N.I.N.A. timestamps; `NINAGuiderInfo` decoder.
- M0 API capability matrix for N.I.N.A. Advanced API 2.2.15.3 and PHD2 event monitoring, with read-only endpoint allowlist, risks and go/no-go table.
- ADR 0001 (read-only endpoint allowlist) and ADR 0002 (tvOS local networking).
- M0 probe tooling (`tools/m0`): allowlisted REST capture, passive WebSocket and PHD2 listeners, sanitizer, self-tests.
- `PanGalacticCore` Swift package: allowlisted N.I.N.A. request factory and guard, response envelope and WebSocket event decoding, PHD2 line framer, event decoder and state tracker, guide statistics with explicit units.
- CI for the Swift package and the M0 tooling.
- MIT license.
- Repository presentation: README with banner and roadmap, CONTRIBUTING, SECURITY policy, issue and pull request templates.
