# ADR 0004 – Image updates by polling the image history

- Status: Accepted (M2)
- Date: 2026-11-09

## Context

The Overview shows the newest frame. N.I.N.A. announces saved frames with the `IMAGE-SAVE` WebSocket event, but in 2.2.15.3 the event carries no history index (M0), so the app has to call `/image-history?count=true` anyway. The app already polls `/equipment/info` every 5 s.

## Decision

- M2 detects new frames by polling `/image-history?count=true` in the same cycle as `/equipment/info`.
- Metadata (`/image-history?index=n`) and the thumbnail (`/image/thumbnail/n`) are fetched only when the count changes; the thumbnail is retried up to three times because the plugin writes it after appending to the history.
- A shrinking count means N.I.N.A. restarted; the tracker starts over.
- Image fetch failures never change the connection phase; reachability is judged by `/equipment/info`.
- Full-resolution renders (`/image/{n}`) are requested only from the full-screen viewer, one at a time, and cached for the last image.
- The read-only WebSocket listener (no application messages, ADR 0001) is deferred to M3, where guiding and alerts need low latency.

## Consequences

- A new frame appears on the TV within one poll interval (≤ 5 s) plus thumbnail time (0.1 s).
- No WebSocket code in M2; one fewer long-lived connection to keep healthy.
- If a later plugin version adds the index to `IMAGE-SAVE`, M3 can switch to event-driven updates without changing the UI.
