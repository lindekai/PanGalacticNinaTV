# Feature proposal – surveillance camera view (RTSP)

- Status: Proposed – needs owner decisions before a milestone is assigned
- Requested: 2026-11-09

## Goal

Show the image of an IP surveillance camera (for example one watching the telescope or the sky) next to the N.I.N.A. overview, so that cable snags, dew or clouds are visible on the TV.

## Constraints

- tvOS has no built-in RTSP support. `AVPlayer` plays HLS and files only.
- The camera usually needs credentials. They must live in the Keychain, never in `UserDefaults`, fixtures, logs or screenshots.
- ATS `NSAllowsLocalNetworking` already covers HTTP to LAN addresses; RTSP over TCP would use Network.framework or a third-party library and is not subject to ATS.
- The app stays read-only: no PTZ, no camera settings, no talk-back.
- No additional software on the telescope PC (AGENTS.md, rule 5).

## Options

| Option | How | Pros | Cons |
|---|---|---|---|
| A. JPEG snapshot URL | Poll the camera's HTTP snapshot endpoint (most IP cameras offer one) every 1–5 s | No dependency, low CPU, simple, works on Apple TV HD | Not real-time video; URL format varies by vendor |
| B. RTSP via embedded player | Bundle an RTSP-capable library (e.g. VLCKit for tvOS, LGPL) | Real video stream | Large binary, license obligations (LGPL), more battery/CPU, maintenance |
| C. HLS from a relay | A relay on another LAN machine (e.g. a NAS) converts RTSP to HLS; app uses `AVPlayer` | Native playback, low app complexity | Needs extra software outside the app; must not run on the telescope PC |

Recommendation: start with **A** (snapshot), keep the source behind a `CameraFeed` protocol so B or C can be added later without UI changes.

## Open questions for the owner

1. Camera make and model? Does it offer an HTTP snapshot URL, and is RTSP the only stream?
2. Is a few seconds of latency acceptable (option A), or is live video needed?
3. Where should it appear: tile on the Overview, own tab, or picture-in-picture?
4. One camera per N.I.N.A. instance, or global?

## Placement

After M2. Candidate: M5 ("Conditions") as a source-labelled condition view, or a dedicated milestone if live video (B/C) is wanted.
