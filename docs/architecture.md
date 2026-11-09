# Architecture

Status: draft (M0). Decisions are recorded as ADRs in [`adr/`](adr/).

## Goals and constraints

- Native Swift/SwiftUI app for **tvOS 26.0+**, Apple TV HD and newer. Performance budgets are set against Apple TV HD.
- **Read-only** observatory monitor in phase 1: no telescope, camera, sequence or guider control ([ADR 0001](adr/0001-read-only-endpoint-allowlist.md)).
- Multiple N.I.N.A. instances; no hardcoded hosts, ports or hardware.
- German and English UI.

## Module overview

```text
PanGalacticNinaTV (SwiftUI tvOS)
 ├── AppShell: instance picker, settings, tabs/views, focus/remote navigation
 ├── Domain: DeviceInstance, ImagingSession, ImageFrame, MountStatus,
 │            GuideSample, Conditions, AstronomyTarget, AlarmEvent
 ├── Services (protocol-driven, dependency-injected)
 │    ├── NINAAdvancedAPIClient (allowlisted HTTP GET + passive WebSocket events)
 │    ├── PHD2EventClient (Network.framework TCP, newline-delimited JSON, receive-only)
 │    ├── DiscoveryService (saved-host probes, optional Bonjour, bounded opt-in scan)
 │    ├── AstronomyEngine (coordinates, ephemerides, catalogs, FOV)
 │    ├── ConditionsProvider (optional, sourced and timestamped)
 │    └── MessageEngine / AlertEngine
 ├── Stores: InstanceStore, RuntimeState, settings, ring buffers, image cache
 ├── Views: Overview, Imaging, Guiding, Astronomy, Conditions, Statistics
 └── Fixtures + Testing
```

## Data flow

1. `InstanceStore` loads saved instances. Routing: 0 → setup/discovery, 1 → dashboard, >1 → picker.
2. Per active instance, a `ConnectionSupervisor` actor owns the N.I.N.A. HTTP client, the N.I.N.A. event socket and the PHD2 event client; it is the single source of truth for connection lifecycle (connecting, live, stale, offline, retry with exponential backoff + jitter).
3. Wire DTOs are decoded from fixtures-verified JSON and mapped to domain models. Every value carries provenance: `measured`, `derived`, `estimated`, `unavailable`, plus a timestamp and a `stale` flag. Unknown ≠ zero.
4. Event-driven refresh: WebSocket `IMAGE-SAVE` triggers thumbnail/preview fetch; equipment state is polled at a modest interval; PHD2 `GuideStep` feeds a bounded ring buffer.
5. Views observe stores; they never call services that could mutate remote state, because none exist.

## Code layout

- `Packages/PanGalacticCore`, target `PanGalacticCore` – platform-independent protocol layer (wire DTOs, request allowlist, decoders, statistics, instance model, connection state machine); no UI and no networking I/O.
- `Packages/PanGalacticCore`, target `PanGalacticServices` – I/O behind protocols: allowlisted HTTP client (`HTTPTransport`), connection tester, `InstanceStore` ([ADR 0003](adr/0003-instance-persistence.md)), polling `InstanceConnection`, bounded `NetworkScanner`. Tested with fakes; never touches the network in tests.
- `App/` – tvOS app (SwiftUI). `AppModel` owns the store and the one active connection; polling runs only while the scene is active. Views never see a mutating API of N.I.N.A.
- `Config/Info.plist` – ATS and local network keys, merged into the generated Info.plist.

## Networking

See [ADR 0002](adr/0002-tvos-local-networking.md).


- N.I.N.A. Advanced API: `http://<host>:<port>/v2/api`, default port 1888; event stream `ws://<host>:<port>/v2/socket`. No authentication exists at plugin 2.2.15.3.
- PHD2: TCP `<host>:4400` (+1 per additional instance), CR LF-terminated JSON events. The decoder handles partial frames, oversized lines (bounded) and reconnects.
- tvOS local network: ATS `NSAllowsLocalNetworking` only; WebSocket and PHD2 via Network.framework; `NSBonjourServices` only if Bonjour is used ([ADR 0002](adr/0002-tvos-local-networking.md)).
- Server time vs. device time is measured via `/time` and shown when skew is significant.

## Images

- Preview images are rendered (debayered, stretched, resized) by the plugin and streamed as JPEG; tvOS does not parse FITS.
- Fetch policy: 256 px thumbnail first, then one resized image sized to the target view; at most one in-flight full render per instance; triggered only by completed-image events.
- Memory: downsampled decode, small LRU cache, no full-resolution images in memory on Apple TV HD.

## Persistence and secrets

- Instance metadata (name, host, ports, site, optics profile) via `Codable` on-device storage.
- Credentials, should a future API need them, go to Keychain only.
- No real network values or site coordinates in the repository, fixtures or logs.

## Testing

- Unit: DTO decoding against sanitized fixtures, allowlist enforcement, RMS and unit conversion, time/coordinate math, alert debounce, message selection, persistence, routing for 0/1/many instances.
- Integration: fake N.I.N.A. HTTP/WebSocket server and fake PHD2 TCP stream; no hardware in CI.
- M0 tooling under `tools/m0/` (Python 3, standard library only) captures raw data for fixtures.
