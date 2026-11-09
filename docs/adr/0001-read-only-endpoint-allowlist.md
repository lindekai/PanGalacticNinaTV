# ADR 0001 – Read-only access via explicit endpoint allowlist

- Status: Proposed (M0)
- Date: 2026-11-09

## Context

Phase 1 is monitoring-only. The N.I.N.A. Advanced API plugin (2.2.15.3) exposes almost every action – parking, slewing, capturing, starting/stopping sequences, opening domes – as an HTTP `GET` route, and it has no authentication. PHD2's port 4400 accepts JSON-RPC commands on the same socket that delivers events. The plugin's event WebSocket also reacts to inbound text messages by toggling global server state.

A rule such as "only send GET requests" or "only read from sockets" stated in documentation is not enough: a single wrong path string would control hardware.

## Decision

1. All N.I.N.A. HTTP access goes through one client type whose request builder accepts only values of a closed `ReadOnlyEndpoint` enum. Each case maps to one path template from the allowlist in [`api-capability-matrix.md`](../api-capability-matrix.md) §3, with typed, validated query parameters. There is no API that takes a free-form path.
2. The client asserts at runtime (debug and release) that the final URL path matches the allowlist and the method is `GET`; violation is a programmer error that fails the request and is logged.
3. The N.I.N.A. WebSocket client connects only to `/v2/socket` and has no send method beyond protocol-level pong/close.
4. The PHD2 client has no write path at all in phase 1: the connection is read-only from the application's point of view.
5. Presentation and store layers receive only read-only service protocols. A future command layer (phase 2) will be a separate module with its own opt-in authorization and review; it is not stubbed now.
6. Unit tests enumerate every `ReadOnlyEndpoint` case and verify it against the allowlist document's table, and verify that excluded paths (e.g. `/equipment/mount/park`) cannot be constructed.

## Consequences

- Adding an endpoint requires a source review at the pinned plugin revision, an allowlist doc update and a test update.
- Plugin upgrades (notably 3.x with `/v3/api`) require re-review; the client refuses to run against an unknown major version.
