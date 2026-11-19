# M4.1 The Night: altitude curve, Sun and Moon, compass

Status: approved by the owner on 2026-11-20 (mock-up in the session, sections 1–3 "Ja").
Scope: first package of M4 ([ADR 0005](../../adr/0005-m4-before-m3-part-2.md)). Branch `m4/night`, TestFlight build 7.

## M4 packages

| Package | Content | Condition |
|---|---|---|
| **M4.1 The Night** (this spec) | Sun and Moon, twilight, altitude curve of the target, compass | – |
| M4.2 | Planets, time travel for all astronomy views | after M4.1 |
| M4.3 | Star map, FOV overlay | star catalogue licence settled first (ADR 0005) |

Each package has its own spec, plan and PR. M4's review follows after M4.3.

## Goal

The owner sees on the TV how tonight goes: when it gets dark, how high the target stands now and later, where the Moon is and how far from the target, and where the telescope points. Everything is computed from the site, the clock and target coordinates. No new endpoint; the allowlist (ADR 0001) is unchanged.

## Decisions (owner, 2026-11-20)

| Topic | Decision |
|---|---|
| Split | M4.1 → M4.2 → M4.3 as above. |
| Site | From `mount/info` (`SiteLatitude`, `SiteLongitude`, `SiteElevation`); the last reported site is kept locally per instance and used while the mount is off ([ADR 0006](../../adr/0006-site-cached-on-device.md)). The mount always wins. |
| Target | Running target container of the sequence; else the next target container not yet started; else the mount position while it is tracking. |
| Entry | Both: moon icon in the header **and** the Object module as a button (variant A + B of the mock-up). |
| Object module | Target name, current altitude (computed), mini altitude curve. RA/Dec leave the module; they appear on the night page and in the mount details. |
| Engine | Own Swift implementation of the algorithms in Jean Meeus, *Astronomical Algorithms* (2nd ed.). No dependency. |

## Astronomy engine (`PanGalacticCore`, `Astronomy/`)

Pure functions and value types, no I/O, no UI. Angles in degrees at the API, `Date` for instants.

| Unit | Content | Meeus |
|---|---|---|
| `JulianDay` | `Date` ↔ JD, centuries since J2000 (TT ≈ UTC + ΔT; ΔT a fixed 69 s, error below 1 s of time until 2030) | ch. 7, 10 |
| `SiderealTime` | Greenwich and local mean sidereal time | ch. 12 |
| `Equatorial`, `Horizontal` | RA/Dec ↔ altitude/azimuth for a site and instant; azimuth from north through east | ch. 13 |
| `Precession` | J2000 → mean equinox of date (rigorous method) | ch. 21 |
| `Sun` | Apparent position, low accuracy (≈ 0.01°) | ch. 25 |
| `Moon` | Geocentric position from the main periodic terms; topocentric parallax for altitude | ch. 47, 40 |
| `MoonPhase` | Illuminated fraction, waxing/waning, next full moon | ch. 48, 49 |
| `Separation` | Angular distance between two equatorial positions | ch. 17 |
| `RiseSet` | Instants when a body crosses a given altitude, found by sampling every 10 min and bisecting to 1 s | – |
| `Night` | The night window from local noon to the next local noon; Sun at −0.833° (sunset/sunrise), −6°, −12°, −18°; Moon rise/set at +0.125° (mean semi-diameter, parallax and refraction) | ch. 15 |
| `AltitudeCurve` | Altitude of an equatorial position every 5 min over the night window; meridian transit | – |

Altitudes in the curve are geometric (no refraction). Rise and set use the standard altitudes above, which include refraction.

## Inputs

### Site

- `Site` value type: latitude, longitude (east positive), elevation.
- `mount/info` reports `0, 0, 0` when no site is set in N.I.N.A.; that is treated as "no site", not as a site on the equator.
- **`SiteStore`** (`PanGalacticServices`): per instance ID, the last site from a connected mount with the date it was reported, in `UserDefaults` under its own key `site.v1` (ADR 0006). Removing an instance removes its site. The site is never logged, exported or sent anywhere.
- Shown on the page as "Site from the mount" or "Site last reported on <date>". No site: see "Empty and special states".

### Target

`NightTarget`: name, J2000 RA/Dec, source (`sequence` or `mount`).

1. **Sequence**: the deepest running target container (N.I.N.A.'s deep sky object container) in `/sequence/json`; if none runs, the first target container whose status is `CREATED`. Name and coordinates come from the container's target fields. **The exact field names are settled by a source review** of N.I.N.A. `Version-3.2` and the plugin at 2.2.15.3 before implementation, recorded in the capability matrix §7 and checked against the 2026-11-19 captures (M31 with `Epoch` `J2000`). If the review finds no reliable target field, the coordinates of the container's "Slew and center" instruction are used, and failing that the sequence is not a target source.
2. **Mount**: while the mount is tracking, its RA/Dec (`JNOW`, used as of date, no precession) with the name of the latest image's target if there is one, else no name.
3. Otherwise no target.

`SequenceTree` keeps ignoring Alt/Az instructions and `FilePath`. Reading target coordinates does not touch the site.

### Telescope position

Compass only: `Altitude` and `Azimuth` from `mount/info` while the mount is connected. Not computed.

### Clock and time zone

Device clock; all times shown in the Apple TV's time zone like the rest of the app.

## App

### NightModel

Built from site, target, telescope position and `now`. Sun, Moon, twilight and the curve are recomputed only when the night window, the target or the site changes; `now`-dependent values (current altitudes, compass positions, the now line) once a minute through the existing `TimelineView`. Values that depend only on site and clock stay valid while the connection is stale or offline; the target follows the sequence's freshness (dimmed with "as of" when stale, "—" while unknown).

### Header

New `NavigationLink` to `Destination.night` with `moon.stars`, left of the devices and settings icons. One more focus stop in the header section.

### Object module

- A `Button`/`NavigationLink` to `Destination.night`, focusable like the sequence strip.
- Rubric "Object" with the target name as accessory; key figure: current altitude of the target, computed; right: mini curve of the night (target line in `accent`, astronomical night darker, now line in `focus` white), no axes.
- No target: key figure "—", no curve. No site: key figure "—" and "Site unknown".
- RA/Dec are removed from this module.
- Focus: image → right → Object module; left back to the image; down → sequence strip. Menu on the night page returns to the element it came from.

### Night page (`NightView`)

Layout as the approved mock-up (1920 × 1080, margins as `Theme`):

- Title "Night" (DE "Die Nacht"), instance name and date, site source at the right.
- **Altitude panel** (left, about 60 % width): rubric "Altitude above horizon", target name and source ("from the sequence" / "from the mount"), RA/Dec (J2000) under the name, current altitude as key figure. Chart over the night window from 2 h before sunset to 1 h after sunrise: background bands for day, civil, nautical, astronomical twilight and astronomical night; 0°, 30°, 60° grid lines; hour labels; target curve in `accent`; Moon curve dashed in `text2`, only above the horizon; meridian transit dashed with time; now line in `focus`. Legend under the chart.
- **Compass** (right, top): circle with N/E/S/W (DE N/O/S/W), rings for 30° and 60° altitude, centre = zenith. Telescope dot in `accent`; Sun (`warn`) and Moon (`text2`) as rings, dashed below the horizon and then drawn on the rim. Text: telescope direction as compass point and degrees, altitude.
- **Sun** panel: astronomical dark from/until, duration of darkness; sunset and sunrise in small text.
- **Moon** panel: phase drawing, illuminated %, waxing/waning; next set (or rise, whichever comes next); separation from the target; rise, set and next full moon in small text.
- The page has no actions; nothing is focusable except what tvOS needs for Menu to return.

### Empty and special states

| State | Shown |
|---|---|
| No site | Page and module: "Site unknown – connect the mount once"; all computed values "—" |
| No target | Curve panel without target line, "No target"; Sun, Moon and compass as usual |
| Target below the horizon all night | "Not above the horizon tonight" |
| Target circumpolar | Curve fully above the horizon; no special text |
| No astronomical darkness | "No astronomical darkness"; the Sun panel shows nautical dark from/until instead |
| No sunrise/sunset (polar day/night) | Times "—", text "Sun does not set" / "Sun does not rise" |
| Moon does not rise or set tonight | That time "—" |

### Ambient mode

Unchanged; focus moves and clicks count as input.

## Localisation

New strings in `Localizable.xcstrings` (en, de), among them: "Night"/"Die Nacht", "Altitude above horizon", "from the sequence", "from the mount", "Site from the mount", "Site last reported on %@", "Site unknown – connect the mount once", "No target", "Not above the horizon tonight", "No astronomical darkness", "Sun does not set", "Sun does not rise", "Astronomical dark from", "until", "Darkness", "Sunset", "Sunrise", "Moonrise", "Moonset", "illuminated", "waxing", "waning", "Full moon", "Separation", "Meridian", compass points. Target names are shown as sent.

## Testing

- **Engine, worked examples**: the Meeus examples for JD (7.a), sidereal time (12.a), precession (21.b), Sun (25.a), Moon (47.a), illuminated fraction (48.a), separation (17.a), transit/rise/set (15.a).
- **Engine, reference table** (`Fixtures/astronomy/reference.json`, with source and retrieval date): sunrise, sunset, civil/nautical/astronomical twilight, moonrise, moonset and Sun/Moon positions from the U.S. Naval Observatory and JPL Horizons (public data) for invented sites only:
  - 50° N 8° E, 2026-11-19 (Central Europe, November);
  - 58° N 12° E, 2026-06-21 (no astronomical darkness);
  - 0° N 30° E, 2026-03-20 (equator);
  - 34° S 151° E, 2026-07-15 (southern hemisphere);
  - 70° N 20° E, 2026-12-21 (no sunrise).

  Tolerances: times ±2 min; Sun 0.01°, Moon 0.1° (topocentric altitude 0.2°).
- **Target**: from the sanitised 2026-11-19 fixtures (M31, J2000); order running → next → mount; containers without coordinates; nothing running and nothing created.
- **SiteStore**: per instance; mount wins; `0, 0, 0` is no site; date of the last report; removed with the instance; no site value in any log string.
- **NightModel**: every row of "Empty and special states".
- **Performance**: computing a whole night (Sun, Moon, twilight, curve) stays well below 50 ms in the test; it runs once per night, target or site change.
- **App**: tvOS build; simulator against the demo server (invented site and a target container added to `tools/demo/demo_server.py`) in EN and DE: night page, Object module, header icon, focus paths image ⇄ Object module ⇄ strip and back from the page; README screenshots in en_US.
- Device check on the owner's TV with build 7 (gate "usable on Apple TV HD" is checked on the Apple TV 4K the owner has; HD remains a budget, not a device test).

## Documentation

- This spec; implementation plan in `docs/superpowers/plans/`.
- [ADR 0006](../../adr/0006-site-cached-on-device.md): the site is kept on the device per instance; what, where, never leaves the device.
- Capability matrix §7: target container fields from the source review; §4 site row notes the local cache.
- `docs/licensing-and-attribution.md` (new): Meeus as the source of the algorithms; USNO and JPL Horizons as sources of the reference values.
- README section "The night" with screenshots, CHANGELOG, milestones (M4 split into M4.1–M4.3), status.

## Out of scope

- Planets, time travel (M4.2); star map, FOV overlay (M4.3).
- Refraction in the curve, horizon profile, weather.
- Any mount control ("go to target"): never, ADR 0001.
- `/astro-util/moon-separation`: not used; the separation is computed locally.
