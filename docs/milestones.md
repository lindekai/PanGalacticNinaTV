# Milestones

Each milestone ends with a review; the next one starts only after approval.

| Milestone | Scope | Gate | Status |
|---|---|---|---|
| **M0** API feasibility | Pin plugin/PHD2 sources, capability matrix, read-only allowlist, probe tooling, live read-only fixtures from the owner's system, go/no-go | Data availability proven or explicitly downgraded; no UI work before | **Complete** – [report](m0-report.md) |
| M1 Skeleton & connections | Xcode project (tvOS 26), instance store, manual add/test, saved-host discovery, bounded subnet scan, routing 0/1/many, reconnect + stale state | Fresh app connects to real Advanced API; routing rules hold | **Complete** – Apple TV hardware check carried over in #8 |
| M2 Overview & imaging | Live session metrics, preview on completed image, full-screen viewer, offline fallback | No fake-live metrics; latency and memory measured | **In progress** – sequence progress waits for a running-sequence capture (#4) |
| M3 Guiding & alerts | Streaming chart, RMS with validated units, history, full screen, foreground-only alerts | Replays incl. pause, star lost, reconnect, dither, empty stream | Not started |
| M4 Astronomy | Compass, altitude plot, Sun/Moon/planets, time travel, star map, FOV overlay | Reference comparisons across sites/dates; usable on Apple TV HD | Not started |
| M5 Conditions, statistics, i18n, personality | Source-labelled conditions, verified metrics only, EN/DE, message engine | Freshness distinguishable; humor never replaces alarms | Not started |
| M6 Reliability & release readiness | Overnight soak, profiling, Wi-Fi dropouts, lifecycle, accessibility, docs, licenses | Overnight stability; no write requests in network log | Not started |

## M0 checklist

- [x] Locate authoritative Advanced API source and pin revision matching installed 2.2.15.3
- [x] Locate PHD2 event protocol documentation and pin revision
- [x] Draft capability matrix, risks, go/no-go ([api-capability-matrix.md](api-capability-matrix.md))
- [x] Draft read-only allowlist decision ([ADR 0001](adr/0001-read-only-endpoint-allowlist.md))
- [x] Read-only probe tooling with self-tests ([tools/m0](../tools/m0/README.md))
- [x] Owner test procedure ([m0-test-procedure.md](m0-test-procedure.md))
- [x] tvOS local networking research ([ADR 0002](adr/0002-tvos-local-networking.md))
- [x] `PanGalacticCore` protocol layer (no UI, no I/O): allowlisted request factory, envelope/event decoding, PHD2 framing/decoding/state, guide statistics – built from documentation, to be re-validated against live fixtures
- [x] CI for core package and M0 tooling
- [x] Record PHD2 version (2.6.14)
- [x] Live capture: Advanced API REST (idle and during snapshots; running sequence downgraded → M2)
- [x] Live capture: Advanced API WebSocket events incl. `IMAGE-SAVE`
- [x] Live capture: PHD2 events (`GuideStep` downgraded → M3)
- [x] Preview image timing (10.4 s full render, 0.1 s thumbnail)
- [x] LAN reachability from Mac (Apple TV deferred → M1)
- [x] Sanitize and commit fixtures; update matrix to *verified*
- [x] Live fixtures in `PanGalacticCore`; `IMAGE-SAVE` date format pinned (running-sequence schema → M2)
- [ ] RMS definition (about zero vs. standard deviation) → M3
- [x] Review and approval for M1

## M1 checklist ([#9](https://github.com/lindekai/PanGalacticNinaTV/issues/9))

- [x] Instance model, validation (host normalisation incl. IPv6), launch routing 0/1/many
- [x] Connection state machine: live / stale / offline, exponential backoff with jitter
- [x] `PanGalacticServices`: allowlisted HTTP client with byte cap, connection tester, instance store ([ADR 0003](adr/0003-instance-persistence.md)), polling connection, bounded opt-in subnet scan
- [x] Xcode project (tvOS 26.0) with shared scheme; SwiftUI shell: setup, add/edit with connection test, network search, picker, dashboard placeholder, settings
- [x] ATS `NSAllowsLocalNetworking` only ([ADR 0002](adr/0002-tvos-local-networking.md)); EN/DE string catalogs
- [x] CI builds the app for tvOS
- [x] Gate test in tvOS 26.5 simulator against a real N.I.N.A. (read-only): 0 → setup, 1 → live dashboard, many → picker, unreachable → offline with retry countdown
- [ ] Apple TV hardware check (#8)
- [x] Review and approval for M2

## M2 checklist

- [x] Camera: driver setpoint shown only while cooling; `TargetTemp`/`AtTargetTemp` not used (#5, source + live ramp)
- [x] Mount: RA/Dec (JNOW, as formatted by N.I.N.A.), altitude, pier side, parked/tracking/slewing
- [x] Newest frame: history polling, metadata, thumbnail with bounded retry ([ADR 0004](adr/0004-image-updates-by-polling.md))
- [x] Full-screen viewer: thumbnail first, single-flight server render, downsampled decode
- [x] Offline fallback: last known values dimmed and labelled "As of …"
- [x] Exposure countdown and overdue warning
- [x] Measured: thumbnail 0.1 s, full render 4.0 s, memory 35/42 MB (simulator)
- [ ] Sequence progress (target, exposure n/m) from a running-sequence capture (#4)
- [ ] Confirm `TargetTemp` as the ramp's final target after a completed cooldown (#5)
- [ ] Device measurement of latency and memory on Apple TV (#8)
- [ ] Review and approval for M3

## Proposed features (not yet scheduled)

- Surveillance camera view (RTSP / snapshot) – [proposal](features/surveillance-camera.md)
