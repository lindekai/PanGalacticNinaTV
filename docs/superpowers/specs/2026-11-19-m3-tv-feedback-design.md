# M3 TV feedback: sequence strip, sequence page, version, filter wheel icon

Status: approved by the owner on 2026-11-19 (mock-up in the session, "Go!").
Scope: small package between M3 part 1 and M4 ([ADR 0005](../../adr/0005-m4-before-m3-part-2.md)), like `m2/tv-feedback`. Branch `m3/tv-feedback`, TestFlight build 6.

## Goal

Feedback from the owner's TV after build 5:

1. The overview shows the **last, current and next step** of the Advanced Sequence in a slim strip at the bottom.
2. A **sequence page** shows the whole sequence as a tree.
3. **Settings** shows the app version at the bottom left.
4. The **Filter** tile gets a real **filter wheel icon** (five filters in a circle).
5. **Margins** shrink so the strip fits without making the image or the modules smaller.

## Decisions (owner, 2026-11-19)

| Topic | Decision |
|---|---|
| Margins | 36 px top and bottom (was 60), 56 px left and right (was 80). The right column takes the 48 px gained; the image keeps its size. Adjust later if it does not look right on the TV. Risk accepted: TVs with overscan may crop the outermost pixels (fix on the Apple TV: Settings → Video and Audio → Calibrate → Zoom and Overscan). |
| Strip | Full width under both columns, 62 px high, `surface` panel with `radius`, as in the approved mock-up: rubric `SEQUENCE`, ✓ last step (`text2`), › current step with green LED (`text`, its container name first, e.g. "Light 120 UV/IR · Belichtung ausführen"), › "Next:" (`text3`) and the next step (`text2`). |
| Entry to the page | The strip is a button. The Sequence pill in the header stays display-only (one entry, one focus stop). |
| Page layout | Tree as in N.I.N.A. (variant A): only the running branch is expanded at first, a click on a container expands or collapses it, the page opens scrolled to the current step. |
| Version | "Version 0.1.0 (6)" at the bottom left of Settings, from `CFBundleShortVersionString` and `CFBundleVersion`. |
| Filter icon | Own vector symbol, no active-filter highlight. |

## Data

No new endpoint; the allowlist (ADR 0001) is unchanged. The tree comes from `/sequence/json`, which `InstanceConnection` already fetches every 15 s (`sequenceInterval`) for the Sequence pill. Field semantics as in the capability matrix §7 (source review 2026-11-15, N.I.N.A. `Version-3.2`, plugin 2.2.15.3) and the owner's captures of 2026-11-15 and 2026-11-19.

Facts the design relies on:

- The response is an array: first `{"GlobalTriggers": [...]}`, then the top-level containers.
- Every node has `Name` and `Status` (`CREATED`, `RUNNING`, `FINISHED`, `FAILED`, `SKIPPED`, `DISABLED`). A node with `Items` is a container; containers also carry `Conditions` and `Triggers`.
- The plugin appends `_Container`, `_Condition` and `_Trigger` to names; a container may have only the suffix (`_Container`, an unnamed container).
- Names are N.I.N.A.'s display names in N.I.N.A.'s UI language (e.g. "Belichtung ausführen").
- Between two exposures, during dithering or autofocus, the exposure instruction is `CREATED` while its container stays `RUNNING` (capture 2026-11-19).
- The plugin reads the live tree without a lock and silently drops nodes that throw while serialising.
- Some instructions carry the site's coordinates (Alt/Az slew) and file paths (`FilePath`, with the Windows user name).

### Domain model (`PanGalacticCore`, `NINA/SequenceTree.swift`)

`SequenceTree` is built from the `/sequence/json` `JSONValue`, separate from the wire format:

```swift
public struct SequenceTree: Equatable, Sendable {
    public struct Node: Equatable, Sendable, Identifiable {
        public enum Status: Equatable, Sendable { case created, running, finished, failed, skipped, disabled, unknown(String) }
        public let id: [Int]            // index path from the root, stable while the tree keeps its shape
        public let name: String         // suffix stripped; "" for an unnamed container
        public let status: Status
        public let children: [Node]?    // nil = instruction, [] = empty container
        public let details: [Detail]    // conditions, triggers and parameters, already reduced to known fields
    }
    public let roots: [Node]
}
```

`Detail` is an enum of the known, display-safe facts only, each from a field seen in the captures:

| Detail | Source fields |
|---|---|
| `untilTime(Date)` | `TargetTime` of a condition ("loop until") or a wait instruction ("wait for time") |
| `iterations(completed, total)` | condition `CompletedIterations`, `Iterations` |
| `ditherEvery(done, target)` | trigger `Exposures`, `TargetExposures` |
| `exposure(seconds, type, gain)` | instruction `ExposureTime`, `Type`, `Gain` (gain only when ≥ 0) |
| `temperature(celsius)` | instruction `Temperature` (cool camera) |
| `filter(name)` | instruction `Filter` when it is a string |
| `trigger(name)` / `condition(name)` | any other trigger or condition, by name only |

Everything else is ignored. Coordinates, `FilePath` and other paths are never read into the model.

### Current step (`SequenceSteps`)

A pure function `SequenceSteps(tree:)` → `last`, `current`, `next` (each a step with its instruction name and the name of its parent container), computed over the instructions in document order:

1. **Current** is the deepest instruction with `RUNNING`. If there is none, it is the first `CREATED` instruction inside the deepest `RUNNING` container. If no container runs, there is no current step and the strip shows "Not running".
2. **Last** is the closest instruction before the current one with `FINISHED` or `FAILED`. `SKIPPED` and `DISABLED` are passed over. `FAILED` is shown with a red ✕.
3. **Next** is the first `CREATED` instruction after the current one. None: "Next: —".

A dropped node is simply absent: it is never counted as done. If the tree cannot be decoded (not an array, no containers), the strip shows "—".

### Freshness

The strip and the page follow the connection phase like the other modules: dimmed with "as of" when stale, "—" while unknown. The 15 s interval stays; the strip may lag a step by up to 15 s.

## Overview and navigation

- `Theme.margin` 56, `Theme.marginVertical` 36. The module column width follows from the screen width minus image and gaps.
- Below the two columns: `SequenceStrip`, a `Button` wrapped in its own full-width `.focusSection()`.
- Focus order top to bottom: header (full-width section, as today), image card, strip. Swipe down from the image reaches the strip, swipe up returns to the image; swipe up from the image reaches the header as today.
- A click on the strip pushes `Destination.sequence` on the existing `NavigationStack`. Menu returns; tvOS restores focus to the strip.
- Ambient mode is unchanged: focus moves and clicks count as input.

## Sequence page (`SequenceView`)

- Title "Sequence" with the as-of label; a scrollable list in the style of the device page.
- One row per node, indented 32 px per level. Leading status symbol: ✓ finished, ● running (`accent`), ○ created, ✕ failed (`fault`), ⤼ skipped (`text3`), disabled struck through in `text3`, `unknown` as "?".
- Containers show ▸/▾ and are focusable buttons that toggle their children. Instructions are focusable rows (needed for scrolling) without an action.
- `details` in one line under the name, `pgLabel` in `text2`, joined with " · " (e.g. "until 05:00 · Dither every 3 (2/3)").
- Initially expanded: the chain of `RUNNING` containers. Opening the page scrolls to the current step (`ScrollViewReader`). Expanded state is kept while the page is open, keyed by `id`; after a tree reload, ids that no longer exist are dropped.
- Not running: the loaded tree, collapsed below the top level. Empty or undecodable: "No sequence loaded".

## Settings

`Text("Version \(short) (\(build))")` in `pgLabel`/`text3`, bottom left below the existing content.

## Filter wheel icon

`App/Resources/Assets.xcassets/FilterWheel.imageset/filter-wheel.svg`, template rendering and preserved vector data, same viewBox and stroke weight as `TelescopeMount`: outer disc, small hub, five circular filter windows on a ring at 72° steps, first window at the top. Used in `FilterTile` instead of `circle.grid.cross`.

## Localisation

New strings in `Localizable.xcstrings` (en, de): "Sequence", "Next:", "Not running", "No sequence loaded", "Version %@ (%@)", the detail formats ("until %@", "%lld of %lld", "Dither every %lld (%lld/%lld)"). Step and container names are shown as sent and never translated.

## Testing

- **Fixtures:** sequence JSON from the 2026-11-19 captures (exposing, between exposures, autofocus running, autofocus failed), sanitised with `m0probe.py sanitize` and reviewed by hand (no coordinates, paths or hostnames); the existing 2026-11-15 fixtures stay.
- **`SequenceTreeTests`:** decoding of all fixtures; suffix stripping incl. the bare `_Container`; status mapping incl. unknown strings; details only from known fields; no path or coordinate value anywhere in the model.
- **`SequenceStepsTests`:** running instruction; between exposures (container running, instruction created); autofocus failed as last step with ✕; skipped and disabled passed over; nothing running; last instruction of the sequence (no next); a dropped node.
- **App:** built for tvOS; checked in the simulator against the demo server (sequence tree added to `tools/demo/demo_server.py`) in EN and DE: strip, page, expand/collapse, focus paths image ⇄ strip ⇄ header and back from the page.
- Device check on the owner's TV with build 6.

## Documentation

Capability matrix (fields used by the strip and the page), changelog, README tour (strip and sequence page screenshots from the demo server), milestones/status, this spec.

## Out of scope

- Any sequence control (start, stop, skip): never, ADR 0001.
- Translating N.I.N.A.'s step names.
- A faster sequence poll; revisit only if the 15 s lag bothers on the TV.
- Global triggers on the page.
