# Feature proposal – dynamic Top Shelf

- Status: Accepted by the owner – scheduled after M3 (needs guiding alerts)
- Requested: 2026-11-15

## Goal

When the app sits in the top row of the Apple TV Home Screen and is focused, the Top Shelf shows the session at a glance instead of the static artwork: the newest frame as background, a line such as "M 42 · exposure 14/40 · HFR 2.1 · 2 min ago", or an alarm such as "Guiding lost · 4 min ago". Selecting it opens the app on that frame (deep link).

## Constraints

- Only visible while the app is in the top row; tvOS decides when the extension runs. It is never a live stream, so every item carries its age.
- The extension is a separate process with a short time budget. It uses the same allowlisted, read-only request factory as the app (ADR 0001); no new endpoints.
- Instance list and the last thumbnail are shared through an App Group container. The instance list stays in the format of ADR 0003; no credentials are involved.
- If N.I.N.A. is unreachable or the data is older than a threshold, the extension falls back to the static Top Shelf image – never stale data without a label.
- Alarm text is factual (AGENTS.md: humour never replaces alarm text).

## Shape

- New target: TV Top Shelf Extension (`TVTopShelfContentProvider`), carousel style with one item.
- App Group entitlement for app and extension; requires the identifier in the developer account.
- The app calls `TVTopShelfContentProvider.topShelfContentDidChange()` when a new frame or an alarm arrives.

## Dependencies

- Sequence progress (#4) for "exposure n/m".
- Guiding state and alerts (M3) for alarm items.

## Effort

About one to two days including tests of the content builder (pure function from domain state to Top Shelf items) and a device check on Apple TV.
