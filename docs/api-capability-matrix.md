# API Capability Matrix

Status: **M0 – desk research complete; live verification in progress** (idle snapshot 2026-11-09, see §7).
Every row below is derived from published specs and plugin source at a pinned revision. Nothing is marked *verified* until a sanitized live fixture from the owner's system exists in `Tests/Fixtures/`.

## 1. Pinned sources

| Component | Installed (owner) | Source of truth | Pin |
|---|---|---|---|
| N.I.N.A. | 3.2 (live: `"3.2 "`) | — | — |
| Advanced API plugin | 2.2.15.3 | [christian-photo/ninaAPI](https://github.com/christian-photo/ninaAPI) (MPL-2.0) | tag `2.2.15.3` → commit `353a853fb598cfa358900340396806c945a0de36` |
| ↳ REST spec | | `ninaAPI/api_spec.yaml` (OpenAPI 3.0, `info.version: 2.2.15`) | same commit |
| ↳ WebSocket spec | | `ninaAPI/websocket_spec.yaml` (AsyncAPI 2.0, `info.version: 2.2.13.0` – **stale header**, see risks) | same commit |
| ↳ Server wiring | | `ninaAPI/WebService/API.cs`, `WebService/V2/**/*.cs` | same commit |
| PHD2 | 2.6.14 (live `Version` event) | [PHD2 wiki: EventMonitoring](https://github.com/OpenPHDGuiding/phd2/wiki/EventMonitoring) | wiki commit `e3ec52c9694f03a452be826bdb71d2e3d853d4c8` (2025-08-13) |

Server layout at the pinned commit (`API.cs`):

| Path | Purpose | Phase 1 use |
|---|---|---|
| `http://<host>:1888/v2/api/...` | REST controller | **Allowlisted GETs only** (§3) |
| `ws://<host>:1888/v2/socket` | Event stream | **Passive subscribe only, never send application messages** |
| `ws://<host>:1888/v2/tppa` | Three-point polar alignment control | Never open |
| `ws://<host>:1888/v2/mount` | Manual mount axis movement | Never open |
| `ws://<host>:1888/v2/filterwheel`, `/v2/rotator` | Networked device drivers | Never open |

## 2. Key findings

1. **HTTP verb is not a safety signal.** At 2.2.15.3, all hardware/sequence actions are `GET` routes (e.g. `/equipment/mount/park`, `/equipment/camera/capture`, `/sequence/start`, `/equipment/dome/open`). Only `POST /sequence/load` uses another verb. A "GET-only" rule is therefore **insufficient**; the client must enforce an explicit **path allowlist** (see [ADR 0001](adr/0001-read-only-endpoint-allowlist.md)).
2. **No authentication.** No API key or auth middleware exists in the pinned source. Anyone on the LAN can issue control requests. Our app must never become a relay, and docs must warn against exposing port 1888 beyond the LAN.
3. **Undocumented routes exist** in source but not in the spec: `/time`, `/`, `/image/{index}/prefix`, `/application/windows`, `/application/windows/close` (mutating), `/equipment/focuser/pins/reverse` (mutating). Only `/time` (returns `DateTime.Now`, source-reviewed) is a candidate for the allowlist.
4. **WebSocket inbound messages change global server state.** `WebSocketV2.OnMessageReceivedAsync` toggles a *static* `sendConsumerEvents` flag on `enable-consumer-events` / `disable-consumer-events`; it affects all clients (e.g. Touch 'N' Stars). At this revision the consumer-event sender returns early, but the client must still **send nothing** on `/v2/socket`.
5. **Stretched preview is available server-side.** `GET /image/{index}` and `GET /prepared-image` render, optionally debayer, stretch (profile defaults with `autoPrepare=true`), resize and stream JPEG/PNG. tvOS therefore does not need to parse FITS. Cost: full-resolution decode + debayer + stretch runs **on the telescope PC** for every request (§5 R3).
6. **Thumbnails** (`/image/thumbnail/{index}`) are pre-rendered 256 px JPEGs; require "Create Thumbnails" = ON (it is ON on the owner's system).
7. **Guiding data has two sources**: N.I.N.A. (`/equipment/guider/info`, `/equipment/guider/graph` with `PixelScale`, RMS and dither flags) and PHD2's TCP event stream (per-frame `GuideStep` in pixels). PHD2 events carry **no pixel scale**; arcsec conversion needs `PixelScale` from N.I.N.A. or a user-entered value.

## 3. Read-only endpoint allowlist (candidate)

"Source reviewed" = handler body inspected at the pinned commit; it only reads mediator state, profile values or files and writes the response. "Live" = HTTP 200 with plausible content from the owner's system (idle state unless noted).

### Tier A – cheap state, suitable for polling

| Endpoint | Data | Source reviewed | Live verified |
|---|---|---|---|
| `GET /version` | plugin version string | ✅ spec | ✅ idle |
| `GET /version/nina?friendly=true` | N.I.N.A. version | ✅ | ✅ idle |
| `GET /time` *(undocumented)* | server local time (clock-skew check) | ✅ | ✅ idle |
| `GET /application-start` | N.I.N.A. start time | ✅ | ✅ idle |
| `GET /equipment/info` | bundled camera/dome/filterwheel/flat/focuser/guider/mount/rotator/safety/switch/weather info | ✅ | ✅ idle |
| `GET /equipment/camera/info` | temperature, setpoint, cooler power, `IsExposing`, `ExposureEndTime`, sensor size, pixel size | ✅ | ✅ idle |
| `GET /equipment/mount/info` | RA/Dec (+epoch), alt/az, tracking, park, side of pier, time to meridian flip, site lat/long/elevation | ✅ | ✅ idle |
| `GET /equipment/filterwheel/info` | selected filter, filter list | ✅ | ✅ idle |
| `GET /equipment/focuser/info` | position, temperature, moving | ✅ | ✅ idle |
| `GET /equipment/guider/info` | state, RMS RA/Dec/Total/peaks, `PixelScale`, last guide step | ✅ | ✅ idle |
| `GET /equipment/guider/graph` | guide step history (`RADistanceRaw`, `DECDistanceRaw`, `Dither`), RMS, scale | ✅ (reads `GuideStepsHistory` via reflection – fragile) | ✅ idle |
| `GET /equipment/{rotator,safetymonitor,weather,dome,switch,flatdevice}/info` | device state | ✅ | ✅ idle |
| `GET /sequence/json` | sequence tree with item status (author: "more reliable") | ✅ | ✅ idle |
| `GET /sequence/state` | richer sequence tree incl. plugin items | ✅ | ✅ idle |
| `GET /image-history?count=true` / `?index=<n>` | image count / one history entry | ✅ | ✅ idle |
| `GET /event-history` | all WebSocket events since plugin start (unbounded list – see R5) | ✅ | ✅ idle |
| `GET /application/plugins` | installed plugin folder names | ✅ | ✅ idle |
| `GET /framing/info` | framing assistant state | ✅ | ✅ idle |
| `GET /profile/horizon` | custom horizon of active profile | ✅ | ✅ idle |

### Tier B – heavy or sensitive, on demand and rate-limited

| Endpoint | Why tier B | Source reviewed | Live verified |
|---|---|---|---|
| `GET /image/thumbnail/{index}` | file read; cheap but binary | ✅ | ✅ 0.1 s, 622×417 JPEG |
| `GET /image/{index}?resize=true&size=WxH&quality=Q&stream=true&autoPrepare=true` | full decode/debayer/stretch on telescope PC | ✅ | ✅ **10.4 s** for 26 MP → 1920×1286 JPEG (q 85, 637 KB) |
| `GET /prepared-image?resize=true&size=WxH&quality=Q&autoPrepare=true` | as above, last prepared image | ✅ | ⬜ |
| `GET /equipment/focuser/last-af` | reads newest AF JSON from disk | ✅ | ✅ idle |
| `GET /astro-util/moon-separation?ra=&dec=` | server-side calc using profile site | ✅ | ⬜ |

### Explicitly excluded (non-exhaustive)

Everything not listed above. Notably: all `connect`/`disconnect`/`rescan`/`list-devices`, every mount/dome/focuser/rotator/filterwheel/flat/switch action, `camera/capture*` (incl. `capture/statistics`, which runs star detection), `cool`/`warm`, `sequence/*` actions, `profile/change-value`/`switch`, `framing/set-*`/`slew`, `image/{index}/solve`, `prepared-image/solve`, `livestack/*`, `flats/*`, `application/switch-tab`, `application/screenshot` and `application/logs` (privacy), `profile/show` (**returns third-party API keys in plain text**, e.g. astrometry and weather services – verified live 2026-11-09), `application/windows*`, `POST /sequence/load`.

## 4. Desired data → provider

| Desired data | Provider | Candidate endpoint / event | Status | Notes |
|---|---|---|---|---|
| Plugin identity / version | Advanced API | `/version`, `/version/nina` | spec + source | Envelope `{Response, Error, StatusCode, Success, Type}` |
| Sequence state & progress | Advanced API | `/sequence/json`, WS `SEQUENCE-STARTING`, `SEQUENCE-FINISHED`, `SEQUENCE-ENTITY-FAILED` | spec + source | Exposure count/progress must be derived from tree; schema is free-form (`Response` untyped in spec) → **fixture required** |
| Current exposure | Advanced API | `camera/info` `IsExposing`, `ExposureEndTime`, `LastDownloadTime` | spec | Remaining time only if `ExposureEndTime` is reliable |
| Completed image event | Advanced API WS | `IMAGE-SAVE` with `ImageStatistics` (live: **no `Index`**, plus `ImageType`; ExposureTime, Filter, Temperature, Gain, Offset, Date, HFR, HFRStDev, Stars, Mean, Median, StDev, Min, Max, TargetName, TelescopeName, FocalLength, Filename, IsBayered, RmsText) | spec | Primary trigger for preview refresh. `Filename` is a local path → sanitize |
| Preview image | Advanced API | thumbnail / `/image/{index}` resized+stretched | spec + source | Server-side stretch; JPEG streaming |
| Camera temp / cooler | Advanced API | `camera/info` | spec + source | |
| Filter | Advanced API | `filterwheel/info`, WS `FILTERWHEEL-CHANGED` | spec | |
| Mount status | Advanced API | `mount/info`, WS `MOUNT-*` | spec + source | Epoch via `Coordinates.Epoch` / `EquatorialSystem` – verify |
| Guiding (N.I.N.A. view) | Advanced API | `guider/info`, `guider/graph`, WS `GUIDER-START/STOP/DITHER` | spec + source | Arcsec scale via `PixelScale` |
| Guiding (live per-frame) | PHD2 | TCP 4400 `GuideStep`, `StarLost`, `Paused`, `Resumed`, `GuidingStopped`, `SettleBegin`, `Settling`, `SettleDone`, `GuidingDithered`, `AppState`, `Alert` | wiki | Pixel units only |
| Image quality metrics | Advanced API | `IMAGE-SAVE` HFR/Stars, `image-history` | spec | Populated values must be confirmed during real session |
| Autofocus | Advanced API | WS `AUTOFOCUS-STARTING/FINISHED`, `ERROR-AF`, `focuser/last-af` | spec + source | |
| Weather (device) | Advanced API | `weather/info` | spec + source | Only if an ASCOM weather device is connected |
| Safety | Advanced API | `safetymonitor/info`, WS `SAFETY-CHANGED` | spec + source | Display only |
| Site location | Advanced API | `mount/info` `SiteLatitude`/`SiteLongitude`/`SiteElevation` | live | Privacy-sensitive; never logged or exported |
| FOV / optics | Advanced API + manual | `camera/info` XSize/YSize/PixelSize, `IMAGE-SAVE` FocalLength, profile telescope settings | spec | Camera rotation not reliably known → manual / flagged |
| Plate-solve orientation | — | none read-only at this version without triggering a solve | **gap** | Manual entry or derived later |

## 5. Risks

| ID | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | Control endpoints are `GET`; a bug or URL typo could move hardware | **Critical** | Path allowlist enforced in the HTTP client, not in views; unit test that every request path matches allowlist; network-log audit in M6 |
| R2 | No auth on plugin | High | LAN-only guidance; never proxy; never store/forward API base URL to third parties |
| R3 | `/image/{index}` stretches full-res frames on the telescope PC (MeLE Quieter C4, IMX571 ≈ 26 MP) – **measured 10.4 s per request** | Medium–High (could slow capture/download) | One in-flight request, only after `IMAGE-SAVE`, prefer thumbnail + one resized fetch; measure CPU impact in M0 live test |
| R4 | `guider/graph` uses reflection on N.I.N.A. internals | Medium | Treat as optional; fall back to PHD2 stream |
| R5 | `/event-history` grows unbounded for the session | Low–Medium | Fetch once on connect; avoid polling |
| R6 | WebSocket spec header says 2.2.13.0 | Low | Live capture of each event type in M0 |
| R7 | Plugin 3.x (`v3/api`, tags `3.0.0.x-b.*`) is in beta | Medium (future) | Version-gate client on `/version`; abstract REST paths behind a versioned adapter |
| R8 | Sequence JSON schema is untyped in spec | Medium | Build decoder from real fixtures only; tolerate unknown items |
| R9 | PHD2 protocol: inbound bytes on 4400 are JSON-RPC | High | PHD2 client never writes to the socket in phase 1 |
| R11 | `/profile/show` exposes API keys of third-party services to anyone on the LAN | High (data) | Not on the app allowlist; probe tooling excludes it; sanitizer redacts key/token/password/secret/url fields |
| R10 | Timestamps: N.I.N.A. responses use server local time without guaranteed offset | Medium | Use `/time` to measure skew; label times by source |

## 6. Go / no-go (desk research)

| Capability | Desk verdict | Live gate |
|---|---|---|
| Identify server read-only | **Go** | `/version` fixture |
| Sequence/exposure state | **Go, schema TBD** | `/sequence/json` fixture during a running sequence |
| Preview image | **Go** | thumbnail + resized image fetch, timing + CPU note |
| Camera/mount/filter/focuser | **Go** | `/equipment/info` fixture |
| Event delivery | **Go** | ≥ 1 `IMAGE-SAVE`, `FILTERWHEEL-CHANGED`, `GUIDER-DITHER` captured |
| PHD2 guide stream | **Go** | `Version`, `AppState`, `GuideStep` captured; `StarLost` if it occurs |
| Arcsec guide units | **Conditional** | `PixelScale` from N.I.N.A. present and non-zero |
| FOV rotation | **No-go (auto)** | Manual entry; revisit later |
| Plate-solve without triggering a solve | **No-go** | — |

No Windows-side helper is required by these findings.

## 7. Live findings

Owner's system, 2026-11-09, idle (equipment connected, no sequence running, mount parked). All Tier A endpoints and `focuser/last-af` returned HTTP 200 in 0.02–0.24 s from a Mac on the same LAN; ports 1888 and 4400 reachable.

| Topic | Finding | Consequence |
|---|---|---|
| Versions | `/version` → `2.2.15.3`; `/version/nina?friendly=true` → `"3.2 "` (trailing space) | Trim version strings |
| Timestamps | `/time`, `/application-start`, `ExposureEndTime`, event `Time`: ISO 8601 local time with offset and 7 fractional digits (`2026-11-09T19:32:58.9740673+01:00`); `mount/info.UTCDate` without offset | Custom ISO parser (fractional digits > 3); treat `UTCDate` as UTC |
| `guider/info.RMSError` | Each of RA/Dec/Total/PeakRA/PeakDec is an object `{"Pixel": n, "Arcseconds": n}` – **differs from spec** | Decoder follows live shape |
| Guide scale | `guider/info.PixelScale` and `guider/graph.PixelScale` = 0.773 ″/px; `guider/graph.Scale` = `"ARCSECONDS"` | Arcsecond display possible when PixelScale > 0 |
| Guider state | `guider/info.State` = `"Stopped"` | Map to PHD2-like states |
| Camera setpoint | `TargetTemp` = −10 and `TemperatureSetPoint` = 10 at the same time | **Ambiguous** – do not display a setpoint until clarified |
| Camera temperature | 53.2 °C with cooler off | Plausibility to be checked with cooler running; show raw value with unit only |
| Exposure end | `ExposureEndTime` populated while `IsExposing` = false | Use only while exposing |
| Mount coordinates | `EquatorialSystem` = `JNOW`, `Coordinates.Epoch` = `JNOW` | Precess for catalog (J2000) overlays |
| Weather | `SkyQuality` = `"NaN"` (string) | Lenient numeric decoding; NaN → unavailable |
| Sequence | `/sequence/json` and `/sequence/state`: array; first element `{"GlobalTriggers": []}`, then containers with `Name`, `Status` (`CREATED`), `Items`, `Triggers`, `Conditions` (`state` adds `Iterations`) | Decoder for running sequence still needs a fixture |
| Event history | Array of `{"Event": …, "Time": …}` | Usable for initial state after connect |
| `/profile/show` | Contains third-party API keys in plain text | Removed from allowlist (R11) |
| WebSocket | Connects; no messages while idle | – |
| PHD2 | On connect: `Version` (2.6.14, `PHDSubver` empty, `OverlapSupport` true), `CalibrationComplete`, `AppState` `Stopped`; `Timestamp` epoch seconds with milliseconds | Matches documentation |

### Snapshots and camera fault (2026-11-09, 19:43–19:50)

Manual 10 s snapshots from the Imaging tab with saving enabled; the camera driver crashed once during an exposure.

| Topic | Finding | Consequence |
|---|---|---|
| Hung exposure | `IsExposing` stayed `true` 3 min past `ExposureEndTime`, `LastDownloadTime` = −1, no events | App can flag an **overdue exposure** from REST alone |
| Camera fault sequence | WS: `CAMERA-DISCONNECTED` ×2 → `CAMERA-DOWNLOAD-TIMEOUT` → `CAMERA-CONNECTED` within 3 s | Alert fixture for "camera disconnected"; debounce reconnect flaps |
| Image events | Each saved frame: `IMAGE-PREPARED` (name only) then `IMAGE-SAVE` | Trigger preview fetch on `IMAGE-SAVE` |
| `IMAGE-SAVE` payload | **No `Index` field** (spec lists one); has `ImageType` (`SNAPSHOT`); `Date` ISO with offset; `Filename` is a local path | Resolve index via `/image-history?count=true`; never store `Filename` |
| Placeholders | Without star analysis: `Stars` = −1, `HFR` = 0, `HFRStDev` = `"NaN"` | Normalised to unavailable in `NINAImageSaveStatistics` |
| History entry | `/image-history?index=n` returns the same object shape as `IMAGE-SAVE.ImageStatistics` | One decoder for both |
| Thumbnail | 622×417 JPEG (not 256 px as documented), ~200 KB, 0.1 s | Good enough for the Overview tile |
| Full preview | 10.4 s server time for 1920×1080 request; aspect ratio kept (1920×1286) | Single in-flight request; only after `IMAGE-SAVE`; prefer thumbnail on Overview |
| PHD2 `LoopingExposures` | Carries undocumented `StarMass`, `SNR`, `HFD`, `ErrorCode` | Tolerated; usable for star quality while looping |
| PHD2 `CalibrationFailed` | `Reason` text, e.g. "RA Calibration Failed: star did not move enough"; repeated `Alert` events with localized (German) messages during failing calibration | State becomes unknown after failure; show alert text verbatim, never translate/interpret |

Pending: PHD2 `GuideStep`/dither/star-lost (simulator), sequence JSON while a sequence runs, `prepared-image`.
