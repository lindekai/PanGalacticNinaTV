# Dashboard redesign – design spec

- Status: Draft for owner review
- Date: 2026-11-15
- Milestone: M2 (phases 1–3), with hooks for #4, M3 and M4
- Mockups (local, not committed): `.superpowers/brainstorm/…/rams-dashboard-v2.html`

## Goal

A beautiful and genuinely useful tvOS monitor that meets the expectations of an Apple user. From the sofa, the owner grasps the most important values within a second; detail lives on sub-pages. Visual language: a precision instrument (Dieter Rams: as little design as possible) with the slate/teal character of the N.I.N.A. desktop, not a copy of it and not a gaming HUD.

## Decisions made with the owner

| Topic | Decision |
|---|---|
| Overview layout | "M1/H1": header with large instance name left, status pills right; newest frame left (~58 %), module column right; segmented progress bar along the bottom |
| Navigation | tvOS tab bar for sub-pages; settings as a focusable gear button in the header, right of the pills |
| Palette | Slate/petrol greys with teal as the only signal colour (tokens below) |
| Overview density | One key figure per module plus at most two side values; exception: camera shows **gain as key figure** with sensor temperature, setpoint and cooler as side values |
| Object vs. mount | Altitude belongs to the object, not the mount: own "Object" module (altitude as key figure, RA/Dec); slim "Mount" tile (state, pier side) in a row with Guiding and Filter |
| Mount icon | Filled silhouette of a German equatorial mount (variant "F") |
| Night mode | Not wanted |
| Ambient mode | Wanted (see below) |
| Top Shelf | Static artwork gets the text "Pan Galactic" and the subtitle "N.I.N.A. Observatory Monitor"; dynamic Top Shelf is a separate feature after M3 ([proposal](../../features/top-shelf-extension.md)) |

## Visual system

### Palette tokens

| Token | Hex | Use |
|---|---|---|
| `bg` | #161D21 | Background |
| `surface` | #1E272C | Module panels, pills |
| `raised` | #253036 | Floating layers (72 % opacity glass: tab bar, ambient strip, viewer caption) |
| `line` | #2E3A40 | Hairlines, progress and chart tracks |
| `text` | #DCE3E6 | Values, titles (no pure white) |
| `text2` | #8C9AA2 | Labels, chart curves |
| `text3` | #5D6A71 | "—", unavailable |
| `accent` | #34B89C | The only signal colour: running / OK / progress |
| `warn` | #E3A23B | Warning state only |
| `fault` | #E0584D | Fault state only |
| `focus` | #F2F5F6 | Focus border, inverted focus |

### Type scale (tvOS points at 1920 × 1080, SF Pro, `.monospacedDigit()` for all numbers)

| Level | Size / weight | Use |
|---|---|---|
| Display | 52 semibold | Instance name |
| Key figure | 72 medium, unit 34 in `text2` | One per module |
| Chart value | 40 medium | Current value above a chart |
| Value | 28–30 medium | Side values, image title, pill values |
| Tab | 25 | Tab bar |
| Label / meta | 21–23 regular, `text2` | Labels, version line, image metadata |
| Rubric | 18 semibold, uppercase, +14 % tracking | Module titles, pill keys |

### Rules

1. **Grid:** 8 pt base grid; safe area 80 pt left/right, 60 pt top/bottom. Image 1024 pt, gap 40 pt, module column 696 pt, 24 pt between modules. Side values right-aligned on one edge.
2. **Glanceability test:** every element on the overview must be readable from three metres within one second; otherwise it goes to a sub-page.
3. **One signal colour:** teal only means running / OK / progress. Titles and icons stay grey. Amber and red appear only for real warnings and faults.
4. **Surfaces, not boxes:** flat panels without borders, 1 px hairlines inside, radius 12 pt, no glow, no gradients. Glass only on floating layers.
5. **Status LEDs:** filled teal = connected and normal; amber = warning; red = fault; hollow ring in `text3` = unknown or unavailable. Where the meaning is not obvious, the state is also written as a word, so colour never carries meaning alone.
6. **Honest gaps:** a missing value is "—" in `text3`, never 0. Features without verified data (guiding RMS until M3, altitude chart until M4) show a dashed "Not available yet" frame. Stale values are dimmed to `text2` and labelled "As of 23:39"; the image line always shows the frame's age.
7. **Minimal charts:** one baseline, one `text2` curve, the newest point in teal; no grid, no legend, a single rubric as title. Only data that exists.
8. **tvOS focus:** on the overview only the image and the gear are focusable (plus the tab bar). Focus = scale 1.02 (image) / 1.12 (gear), 3 pt `focus` border, soft shadow; the gear inverts. Teal is never used for focus.
9. **Dark room:** the brightest area is the astrophoto itself. Crosshair 1 px with a gap in the centre.

## Pages

A `TabView` with the tvOS top tab bar; it hides while focus is in the content and returns on swipe-up or Menu.

| Tab | Purpose | Content | Data |
|---|---|---|---|
| Overview | Is everything fine? | Newest frame (focus → full-screen viewer) with caption and HFR sparkline of the last 24 frames; Camera (gain; sensor temperature, setpoint, cooler); Object (target name in the module header, altitude; RA, Dec); then one row of three tiles: Mount (state; pier side), Guiding (RMS – empty until M3; PHD2 state), Filter (name; position); header pills; segmented progress bar | M2 |
| Image | Judge frame quality | Newest frame medium size; HFR and star-count charts with shared time axis (median dashed); table of recent frames | M2 (image history) |
| Sequence | Where is the night? | Target, exposures n/m per filter, running exposure, current step | #4 |
| Mount | Where does the telescope point? | RA/Dec, pointing altitude/azimuth, pier side, state; later object altitude curve and azimuth chart | M2; charts M4 |
| Guiding | Guiding accuracy | RMS total/RA/Dec, RA/Dec error chart | M3 (empty state until then) |
| System | Technical state | Camera details, filter wheel, connection, N.I.N.A./plugin versions, last update per source | M2 |

### Overview details

- **Header pills:** "Sequence" (target · n/m) shows "—" until #4 delivers verified data; "Exposure" shows the remaining time of the running exposure (available now) with a thin progress underline; "LIVE · HH:MM" uses the existing live/stale/offline state (stale/offline: amber/red word instead of LIVE).
- **Bottom bar:** one segment per exposure of the sequence once #4 is done; until then a single bar for the running exposure.
- **Object altitude:** until M4 the only source is the mount's pointing altitude from N.I.N.A. It is shown as the object's altitude only while the mount is tracking; when parked, slewing or not tracking, the value is "—". From M4 the app computes the object's altitude from its coordinates and the site, independent of the mount.
- **Guider state** is localized (e.g. "Stopped" → "Gestoppt"); unknown wire values are shown as received.
- **Alerts:** a factual banner directly below the header in amber or red, never a modal. Humour never replaces alarm text.
- **Offline fallback:** existing behaviour (last values dimmed, "As of …") mapped onto the new tokens.

### Ambient mode

- After a period without remote input (default 5 min, configurable in Settings, can be switched off) the app shows the newest frame full-screen with a slim glass strip at the bottom: target · sequence n/m · alarm state · LIVE + time.
- Any remote input or any alarm returns to the overview immediately; with an active alarm the app does not enter ambient mode.
- New frames cross-fade (0.6 s). The strip shifts by a few points every few minutes to avoid burn-in.
- While ambient mode is enabled and the app is in the foreground, the system screensaver is suppressed (`isIdleTimerDisabled`); when ambient mode is switched off, the system default applies. This is the only place the idle timer is touched.

### Icons and artwork

- Mount icon: filled equatorial-mount silhouette as a template SVG in the asset catalog, drawn on the same 24 pt grid and optical weight as the SF Symbols used for camera (`camera`), guiding (`scope`) and filter (`circle.grid.cross`).
- Static Top Shelf: generator script adds "Pan Galactic" (SF Pro, semibold) and "N.I.N.A. Observatory Monitor" on the star field, left of the nebula, inside the safe area of both Top Shelf sizes.

## Architecture

- `App/Design/`: `Theme` (colour and type tokens as `Color`/`Font` extensions), reusable components `ModulePanel`, `KeyFigure`, `SideValue`, `StatusLED`, `StatusPill`, `SegmentedProgress`, `Sparkline`, `UnavailableFrame`. Components are pure views fed with already-formatted values.
- Formatting and state derivation (LED state, pill texts, guider-state localization, sparkline series from image history, ambient-mode eligibility) live in small testable types in `PanGalacticServices` or `PanGalacticCore`, not in views.
- Image history: the connection keeps the last N history entries (N = 50) instead of only the newest, for the sparkline and the Image page. Same allowlisted endpoint, same polling (ADR 0004).
- `RootView` hosts a `TabView` once an instance is active; `DashboardView` becomes the Overview tab. Settings stays a navigation destination.
- Ambient mode: an `AmbientController` (observable) tracks the last remote input and alarm state; the overview presents `AmbientView` as a full-screen cover.

## Phases

1. **Visual system and overview:** tokens, components, new overview, mount icon, guider-state localization, image history buffer + sparkline, Top Shelf text.
2. **Tab shell and sub-pages Image, Mount, System;** Guiding as empty state.
3. **Ambient mode** with setting.
4. Later: Sequence page and pills/segments (#4), Guiding page (M3), sky charts (M4), dynamic Top Shelf (after M3).

## Testing

- Unit tests for every formatter/derivation: LED state per connection phase and device state, object altitude only while tracking, guider-state mapping incl. unknown values, pill texts incl. "—" cases, sparkline series (ordering, gaps, placeholder HFR values from `IMAGE-SAVE` treated as unavailable), ambient eligibility (idle time, alarm, setting off).
- Simulator gate per phase: screenshots of overview live, stale and offline; focus on image and gear; tab navigation; ambient enter/exit. Screenshots used for review are not committed if they show real data.
- Localization: all new strings in the EN/DE catalogs.

## Out of scope

Night mode; control actions of any kind; new API endpoints; dynamic Top Shelf (separate proposal).
