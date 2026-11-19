# M3 part 1: guiding chart and meridian tile on the overview

Status: approved by the owner on 2026-11-17 (mock-up in the session, "MEGA! … Leg los").
Scope: M3, first part. Alerts, the PHD2 event stream and N.I.N.A. WebSocket events (#7) follow in their own specs.

## Goal

The overview answers "is the guiding fine?" at a glance, without a separate guiding page:

- A **guiding chart** in the free area of the module column, under the row of small tiles.
- The **total RMS** is the key number, coloured like a traffic light.
- The **Guiding tile goes away** (no duplication); a **Meridian tile** takes its place.

## Decisions (owner, 2026-11-17)

| Topic | Decision |
|---|---|
| Place | Overview, module column, below Mount · Meridian · Filter. No guiding page. |
| Data source | N.I.N.A. `/equipment/guider/graph` (already allowlisted), polled with the other data. PHD2 port 4400 is not used in this part. |
| Key number | Total RMS in arcseconds, shown first in the chart header, same font size as RA and Dec (no larger or bold text). |
| Colour | The value itself is coloured, not a dot: total < 1″ green (`accent`), 1″–2″ yellow (`warn`), > 2″ red (`fault`). Exactly 1.00″ and 2.00″ are yellow. |
| Guider state | In the chart header with the status LED of the guider device (e.g. "Guiding", "Star lost", "Stopped"). |
| Meridian tile | Replaces the Guiding tile: "2:21 h" key value, "until flip" below, plus the approximate clock time "≈ 22:12" smaller in `text3`. |

## Data (source review 2026-11-17)

Pins as in earlier reviews: plugin `christian-photo/ninaAPI` 2.2.15.3 (`353a853`), N.I.N.A. `Version-3.2` (`2393eae`). Live check against the owner's captures of 2026-11-15 (guiding, 101 steps, one dither).

**`/equipment/guider/graph`** (plugin `WebService/V2/Equipment/Guider.cs:243`) serialises N.I.N.A.'s `GuideStepsHistory` of the guider view model unchanged, read via reflection (`handler` → `GuideStepsHistory`). If that fails the plugin answers with its error table (`UNKNOWN_ERROR`); the app then shows the chart as unavailable.

- `GuideSteps`: oldest first, at most `HistorySize` guide steps (N.I.N.A. setting, default 100) plus dither markers. Fields per step: `Id` (increasing), `RADistanceRaw`, `DECDistanceRaw` (**guide-camera pixels**, as reported by the guider), `RADistanceRawDisplay`/`DECDistanceRawDisplay` (pixels × `PixelScale` when `Scale` is `"ARCSECONDS"`, else pixels), `RADuration`/`DECDuration` (ms), `Dither`.
- **Dither marker:** a step with `Dither` = 0.01 and all distances 0 (`HistoryStep.GenerateDitherStep`). Guide steps carry `Dither` = `"NaN"`. The app draws a marker, never a data point at 0.
- `RMS`: `RA`, `Dec`, `Total` in **pixels**, `Scale` = arcsec per pixel; `PeakRA`/`PeakDec`; `DataPoints`. `PixelScale` (arcsec/px) and `Scale` (`"ARCSECONDS"` or `"PIXELS"`, display setting only).
- `ChangeId` increases with every change.
- **The history is cleared only when the guider connects or the user clears the graph in N.I.N.A.** (`GuiderVM.ResetGraphValues`), not when guiding stops. Old steps and the old RMS stay after a stop.

**RMS definition (closes the N.I.N.A. half of #6):** N.I.N.A. computes RMS as the **population standard deviation about the mean** over the window (Welford, `NINA.Core/Model/RMS.cs`), per axis in pixels; `Total = sqrt(RA² + Dec²)`. Arcseconds = pixels × `PixelScale`. The app shows N.I.N.A.'s numbers unchanged, so they match N.I.N.A.'s guider pane; it does not recompute them from the steps.

**`/equipment/info` → `Guider.RMSError`** is built from the same `GuideStepsHistory.RMS` on every guide step (`GuiderVM.Guider_GuideEvent`): `{RA, Dec, Total, PeakRA, PeakDec}` each as `{Pixel, Arcseconds}`. The captures confirm identical values in both endpoints. **The total RMS therefore comes from `/equipment/info`**, which is already polled; the graph is needed only for the curves.

**`Mount.TimeToMeridianFlip`** (hours, N.I.N.A. `AscomTelescope.cs:686`, `NINA.Astrometry/MeridianFlip.cs:58`): computed only while tracking; **exactly 24 when not tracking or on error**. Otherwise 0 ≤ value < 24 (up to 12 h, more when the scope is already flipped); never negative (safeguard subtracts a day). `NaN` (string `"NaN"`) while the mount is disconnected.

## Display rules

### Guiding chart

- **Shown when** the guider is connected. Not connected: "—" and "Not connected" in the header, no chart.
- **Header:** guiding icon, "GUIDING" rubric, LED, localized guider state; right: `Total 0.55″ · ● RA 0.43″ · ● Dec 0.35″` (legend dots in the line colours). RA blue, Dec orange.
- **Total only while guiding:** when the state is not "Guiding" (stopped, looping, star lost, calibrating …) the RMS values are **old** (see above). Then total, RA and Dec show "—" and the curves are dimmed to `text3`. This avoids a green "0.55″" next to "Stopped".
- **Units:** arcseconds when `PixelScale` > 0, else pixels ("px") **without** traffic-light colour (the thresholds are in arcseconds).
- **Curves:** RA and Dec in arcseconds (raw × `PixelScale`), oldest left; dither markers as thin vertical `text3` lines; dashed lines at ±1″ (and ±2″ when in range), labelled at the right.
- **Y range:** symmetric, at least ±2″, grows to the largest |value| rounded up to the next whole arcsecond, at most ±8″; points beyond are clipped. (The owner's captures reach 5–7″, so a fixed ±2″ would hide bad guiding.)
- **Empty history** (connected, nothing guided yet): header as above, plot area with "No guide steps yet".
- **Graph unavailable** (request or decoding failed): the header still shows total RMS from `/equipment/info`; the plot area says "Guiding chart not available".
- **Stale or offline:** dimmed like the other modules, "As of …" handled by the column.

### Meridian tile

- Rubric "MERIDIAN", meridian icon. Key value `h:mm` + " h" (e.g. "2:21 h"), detail "until flip", right of the detail "≈ 22:12" in `text3`, smaller (local time = now + value, rounded to the minute).
- "—" without clock time when: mount not connected, value missing or `NaN`, value == 24 (not tracking), or the mount is not tracking (`TrackingEnabled` false). No colour in this part.

### Layout

- Small-tile row: Mount 268 pt, Meridian 190 pt, Filter 190 pt (unchanged widths).
- The chart panel fills the module column width (696 pt) under the row, 24 pt gap. It uses a **compact header** (no divider line, 44 pt) so the plot keeps at least 64 pt. If the image card is shorter than the column, the column may grow below the image.
- Strings in EN and DE (e.g. "until flip" → "bis zum Flip", "Total" → "Gesamt", "No guide steps yet" → "Noch keine Guide-Schritte", "Guiding chart not available" → "Guiding-Verlauf nicht verfügbar").

## Components

| Unit | Where | Responsibility |
|---|---|---|
| `NINAGuiderGraph` | `PanGalacticCore/NINA` | Decodes `/equipment/guider/graph`: steps (RA/Dec raw px, dither flag, id), `pixelScale`, `changeId`, RMS. Lenient: `"NaN"` → nil; unknown fields ignored. |
| `GuidingChartModel` | `PanGalacticCore/NINA` | Pure derivation: series in arcsec (or px), dither positions, y range, gridlines, "guiding active", total grade (`good`/`fair`/`poor`/`none`). Tested without UI. |
| `RMSGrade` | `PanGalacticCore/NINA` | `good` < 1″, `fair` 1–2″, `poor` > 2″; `none` for pixels or unknown. |
| `MeridianFlipDisplay` | `PanGalacticCore/NINA` | From mount summary + now: remaining time or nil, approximate clock time. |
| `NINAEquipmentSummary` | extended | `Guider.rmsError` (total/RA/Dec in px and arcsec), `Guider.pixelScale`, `Mount.timeToMeridianFlipHours`. |
| `InstanceConnection` | extended | Polls `.guiderGraph` every cycle while the guider is connected; keeps the last graph while stale; `nil` and "unavailable" are distinct. |
| `GuidingChartPanel`, `MeridianTile` | App | Views only; formatting in `Formatters`. Chart drawn with SwiftUI `Canvas` (no Charts framework needed for two lines). |

The Guiding tile and its "RMS not available yet" string are removed.

## Requests and safety

- No new endpoint: `.guiderGraph` and `.equipmentInfo` are allowlisted (ADR 0001).
- `/equipment/guider/graph` is about 25 KB with 100 steps; polled every 5 s only while the guider is connected.
- Nothing is sent to PHD2 or on the WebSocket.

## Testing

- Fixtures: `guider-graph-guiding.json` (sanitized from the 2026-11-15 capture: 101 steps incl. one dither, `HistorySize` 100) and the existing `guider-graph-idle.json`; `equipment-info` fixtures for `RMSError` and `TimeToMeridianFlip`.
- Unit tests: decoding incl. `"NaN"` dither; series conversion px → arcsec; dither markers not plotted as points; y range (min ±2″, growth, cap ±8″, clipping); grades at 0.99/1.00/2.00/2.01″; pixels → no grade; not guiding → no total; meridian: 24 → nil, NaN → nil, not tracking → nil, 2.35 h → "2:21" and clock time.
- Demo server: guider graph with a realistic random walk and one dither; screenshots for README and Discord.
- Simulator check against the owner's N.I.N.A.; device check on Apple TV.

## Out of scope (later M3 specs)

Foreground alerts (star lost, guiding stopped, RMS too high), PHD2 event stream, N.I.N.A. WebSocket events (#7), meridian colouring, peak values on the overview.
