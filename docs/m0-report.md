# M0 Report – API feasibility

- Date: 2026-11-09
- Result: **Go for M1**, with the downgrades listed below
- Details: [API capability matrix](api-capability-matrix.md) · [ADR 0001](adr/0001-read-only-endpoint-allowlist.md) · [ADR 0002](adr/0002-tvos-local-networking.md)

## Environment

| Component | Version | Verified by |
|---|---|---|
| N.I.N.A. | 3.2 | `/version/nina` |
| Advanced API plugin | 2.2.15.3 | `/version`; source pinned at commit `353a853` |
| PHD2 | 2.6.14 | `Version` event |
| Equipment | ToupTek ATR2600C, GSServer mount, manual filter wheel, ZWO focuser, PHD2 guider, OpenWeatherMap | `/equipment/info` |
| Client | Mac on the same LAN as the telescope PC | ports 1888 and 4400 reachable |

Live captures: idle snapshot; ~140 manual 10 s snapshots incl. one camera-driver crash; ~30 min of PHD2 looping/calibration with failing calibration and star-lost events. No imaging sequence (overcast), no PHD2 guiding.

Throughout, the tooling sent only allowlisted `GET` requests, a WebSocket handshake, pongs and a close frame. Nothing was written to PHD2.

## Go / no-go

| Capability | Verdict | Evidence / limitation |
|---|---|---|
| Identify server read-only | ✅ **Go** | `/version`, `/version/nina` verified |
| Equipment state (camera, mount, filter, focuser, guider, weather, safety) | ✅ **Go** | All `info` endpoints verified. Camera setpoint fields ambiguous (`TargetTemp` vs `TemperatureSetPoint`) – not displayed until clarified |
| Completed-image events | ✅ **Go** | `IMAGE-PREPARED` + `IMAGE-SAVE` verified; payload has no `Index` |
| Preview image | ✅ **Go** | Thumbnail 0.1 s; full render 10.4 s server-side → thumbnail first, one full render at a time |
| Device fault events | ✅ **Go** | Camera disconnect/download-timeout/reconnect and guider disconnect/connect verified |
| Overdue exposure detection | ✅ **Go** | Observed: `IsExposing` true minutes after `ExposureEndTime` during a driver hang |
| Sequence progress | ⚠️ **Downgraded** | Only idle sequence JSON verified. Running-sequence schema must be captured before M2 progress UI is built |
| Filter change / dither / autofocus events | ⚠️ **Downgraded** | Not observed; names from the spec only |
| PHD2 event stream | ✅ **Go** (partial) | `Version`, `AppState`, looping, calibration, `CalibrationFailed`, `StarLost`, `Alert`, lock position verified |
| PHD2 guide steps, dither, settling | ⚠️ **Downgraded** | `GuideStep`, `GuidingDithered`, `Settle*` per wiki only; verify in M3 (PHD2 simulator or clear night) |
| Arcsecond guide units | ✅ **Go** (conditional) | `PixelScale` 0.773 ″/px present; which RMS definition N.I.N.A. shows is open (M3) |
| FOV rotation automatically | ❌ **No-go** | Manual optical profile; rotation flagged unknown |
| Plate-solve data without triggering a solve | ❌ **No-go** | Not available read-only |
| Apple TV network access | ⏳ **Deferred to M1** | Needs the app skeleton; requirements in ADR 0002 |
| Windows-side helper | **Not needed** | – |

## Security and privacy findings

1. **Control actions are HTTP `GET`, no authentication.** Read-only access is enforced by an explicit allowlist in code (ADR 0001).
2. **`/profile/show` returns third-party API keys in plain text** (astrometry, weather services). It was removed from all allowlists, and the sanitizer now redacts key, token, password, secret and URL fields.
3. The WebSocket must stay passive: inbound messages toggle global plugin state.

## Carry-over into later milestones

| Item | Milestone | Issue |
|---|---|---|
| Capture running-sequence JSON; build progress decoder from it | M2 | #4 |
| Clarify camera setpoint fields (`TargetTemp` vs `TemperatureSetPoint`) and 50 °C sensor reading with cooler off | M2 | #5 |
| Verify PHD2 `GuideStep`/dither/settle; decide RMS definition against N.I.N.A. | M3 | #6 |
| Verify filter-change, dither and autofocus WebSocket events | M2/M3 | #7 |
| Verify HTTP/WebSocket/TCP from Apple TV hardware; install tvOS 26 simulator runtime for Apple TV HD | M1 | #8 |

## Recommendation for M1

Start M1: Xcode project (tvOS 26), app shell, instance store with 0/1/many routing, manual add/test, a connection supervisor using the `PanGalacticCore` allowlisted request factory, reconnect/stale handling, ATS configuration per ADR 0002. First on-device check: plain HTTP to the telescope PC by IP and by hostname.
