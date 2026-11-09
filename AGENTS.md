# Contributor and Automation Guidelines

Rules for anyone – human or automated tooling – changing this repository.

## Safety constraints (non-negotiable in phase 1)

1. **No control of hardware or software on the telescope PC.** Never call an Advanced API endpoint that is not on the allowlist in [`docs/api-capability-matrix.md`](docs/api-capability-matrix.md) §3 – not even "just to test it". At plugin 2.2.15.x almost every control action is an HTTP `GET`; the verb is not a safety signal.
2. Never send application messages on the Advanced API WebSocket (`/v2/socket`); never open `/v2/tppa`, `/v2/mount`, `/v2/filterwheel` or `/v2/rotator`.
3. Never write to the PHD2 socket (port 4400). Its JSON-RPC methods include state-changing commands.
4. Never infer undocumented API behaviour. New endpoints require a source review at the pinned plugin revision, an allowlist update, an ADR note if relevant, and tests.
5. Never install or require additional software on the telescope PC without an explicit, documented decision.

## Privacy

- No credentials, tokens, real IP addresses, hostnames, site coordinates, file paths or private logs in commits, fixtures, screenshots or issues.
- Raw captures stay in `captures/` (git-ignored). Only sanitized and reviewed data goes to `Tests/Fixtures/`.

## Workflow

- Work milestone by milestone ([`docs/milestones.md`](docs/milestones.md)); each milestone ends with a review before the next starts.
- One task at a time, on a scoped branch (`m<N>/<topic>`), with a tracking issue/checklist.
- Each change: tests, docs/ADR updates where decisions change, changelog entry once `CHANGELOG.md` exists, meaningful commit messages.
- Record assumptions, blockers and decisions in GitHub issues or `docs/adr/`.

## Code conventions

- Swift 6, SwiftUI, tvOS 26.0 deployment target; async/await and actors for shared state.
- Wire DTOs separate from domain models; `unknown`, `unavailable` and `stale` are distinct from zero/false.
- Services are protocol-based and injected; presentation never sees a mutating API.
- User-facing strings localized (de, en); humorous messages never replace factual alarm text.

## Build and test

- Core package: `cd Packages/PanGalacticCore && swift test`
- Core package for tvOS: `xcodebuild -scheme PanGalacticCore -destination 'generic/platform=tvOS' build` (in `Packages/PanGalacticCore`)
- M0 tooling: `python3 tools/m0/tests/test_m0probe.py`
- App (tvOS): `xcodebuild -project PanGalacticNinaTV.xcodeproj -scheme PanGalacticNinaTV -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build`
- App in the simulator: use a `platform=tvOS Simulator` destination; seed instances with the launch argument `-instances.v1 '<hex JSON>'` (ADR 0003). Use documentation addresses (192.0.2.0/24) in anything committed.
