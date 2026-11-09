# ADR 0002 – tvOS local networking configuration

- Status: Accepted (simulator-validated in M1; Apple TV hardware check open, #8)
- Date: 2026-11-09

## Context

The app talks to hosts on the owner's LAN over plain HTTP (`http://<ip-or-name>:1888/v2/api`), a plain WebSocket (`ws://…/v2/socket`) and raw TCP (PHD2, port 4400). Discovery may use Bonjour browsing and a bounded TCP connect scan.

Findings from Apple primary documentation (retrieved 2026-11-09):

| Topic | Finding | Source |
|---|---|---|
| Local Network Privacy | Not enforced on tvOS (TN3179 platform table: tvOS – no). `NSLocalNetworkUsageDescription` exists for tvOS 14+ but no prompt is shown. Simulator does not model LNP. | [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [NSLocalNetworkUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription) |
| ATS | `NSAllowsLocalNetworking` permits unqualified hostnames, `.local` names and IP addresses. Since iOS 17 IP-address loads are no longer exempt by default, so the key is required for `http://192.168.x.y`. Not on Apple's list of exceptions requiring App Review justification (unlike `NSAllowsArbitraryLoads`). | [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking), [Preventing insecure network connections](https://developer.apple.com/documentation/security/preventing-insecure-network-connections) |
| ATS scope | Applies to the URL Loading System, not to Network.framework. | same |
| Bonjour | `NSBonjourServices` lists each browsed service type (tvOS 14+). | [NSBonjourServices](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbonjourservices) |
| Multicast entitlement | Only for raw multicast/broadcast or browsing arbitrary types; not available on tvOS per docs; not needed for unicast TCP/HTTP/WebSocket. | [Multicast entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast) |
| WebSocket API | Apple recommends Network framework for new WebSocket code. | [TN3151](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api) |
| Apple TV HD | Supported by tvOS 26 ("Apple TV HD and Apple TV 4K (all models)"). Third-party reports say tvOS 27 drops it (unconfirmed by Apple). | [tvOS 26 security content](https://support.apple.com/en-us/125114), [tvOS updates](https://support.apple.com/en-us/106336) |
| Idle timer | `UIApplication.isIdleTimerDisabled` is available on tvOS; Apple advises enabling it only while needed. Effect on the tvOS screen saver to be verified on device. | [isIdleTimerDisabled](https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled) |

Not confirmed from primary sources: ATS enforcement details specific to tvOS, and whether ATS checks `ws://` URLs of `URLSessionWebSocketTask`.

## Decision

- Info.plist: `NSAppTransportSecurity` → `NSAllowsLocalNetworking = YES` only. No `NSAllowsArbitraryLoads`, no per-domain exceptions.
- Include `NSLocalNetworkUsageDescription` (no effect on tvOS today; harmless and future-proof).
- Include `NSBonjourServices` only once a concrete service type is browsed (N.I.N.A. is not known to advertise one).
- No multicast entitlement.
- HTTP: `URLSession` (ephemeral configuration, no cookies/cache for API JSON).
- N.I.N.A. WebSocket and PHD2 TCP: Network.framework (`NWConnection`; `NWProtocolWebSocket` for the socket). Unaffected by ATS.
- Handle `NWConnection` `.waiting` (including `localNetworkDenied`) as a distinct, visible connection state.
- Idle timer toggled by scene phase and session state; released when backgrounded or after the configured grace period.

## Consequences

- Internet hosts over plain HTTP are rejected by ATS, which matches the LAN-only design.
- M1 must verify on hardware: HTTP to an IP literal and to a bare Windows hostname, WebSocket via Network.framework, PHD2 TCP, idle-timer behaviour.
- The locally installed simulator runtime is tvOS 27; an Apple TV HD simulator needs a tvOS 26 runtime (to be installed for M1 testing, or test on the device).

## M1 validation (tvOS 26.5 simulator, 2026-11-09)

- `http://<private IPv4>:1888` loads with `NSAllowsLocalNetworking` alone; the app polled a real N.I.N.A. 3.2 / Advanced API 2.2.15.3.
- A non-local address (TEST-NET `192.0.2.10`) is rejected by ATS with `NSURLErrorAppTransportSecurityRequiresSecureConnection`. The app shows "Only local network addresses are allowed". Consequence: addresses outside the ranges ATS treats as local do not work; whether overlay networks such as 100.64.0.0/10 count as local is untested. Accepted for phase 1; revisit with a documented decision if remote viewing is requested.
- Still open on hardware (#8): bare Windows hostname, Wi-Fi vs. Ethernet, idle timer.
