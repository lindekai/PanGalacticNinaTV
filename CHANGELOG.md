# Changelog

All notable changes to this project are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added (M1)
- tvOS app (`PanGalacticNinaTV.xcodeproj`, tvOS 26.0): setup, add/edit instance with read-only connection test, opt-in local network search, instance picker, dashboard placeholder with live/stale/offline badge and equipment overview, settings.
- English and German string catalogs, including the local network usage description.
- `PanGalacticServices` package target: allowlisted HTTP client, connection tester, instance store, polling instance connection, bounded subnet scan.
- Instance model, host validation, launch routing and connection state machine in `PanGalacticCore`.
- ADR 0003 (instance persistence); ADR 0002 accepted with simulator findings.
- CI builds the tvOS app.

### Changed (M1)
- Common network failures are reported as short, localizable messages.

### Changed
- `IMAGE-SAVE` statistics: placeholder values (`Stars` −1, `HFR` 0, `"NaN"`) become unavailable; `ImageType` decoded; `Date` parsed.
- PHD2 state tracker: `CalibrationFailed` sets the state to unknown.
- Sanitizer redacts API keys, tokens, passwords, secrets and URLs; only LAN-style IP addresses are redacted.

### Security
- `/profile/show` removed from all allowlists: it returns third-party API keys in plain text.

### Added
- M0 report with go/no-go and carry-over items.
- Live fixtures from a real N.I.N.A. 3.2 / Advanced API 2.2.15.3 / PHD2 2.6.14 system (sanitized) with decoding tests.
- `NINADate` parser for N.I.N.A. timestamps; `NINAGuiderInfo` decoder.
- M0 API capability matrix for N.I.N.A. Advanced API 2.2.15.3 and PHD2 event monitoring, with read-only endpoint allowlist, risks and go/no-go table.
- ADR 0001 (read-only endpoint allowlist) and ADR 0002 (tvOS local networking).
- M0 probe tooling (`tools/m0`): allowlisted REST capture, passive WebSocket and PHD2 listeners, sanitizer, self-tests.
- `PanGalacticCore` Swift package: allowlisted N.I.N.A. request factory and guard, response envelope and WebSocket event decoding, PHD2 line framer, event decoder and state tracker, guide statistics with explicit units.
- CI for the Swift package and the M0 tooling.
- MIT license.
- Repository presentation: README with banner and roadmap, CONTRIBUTING, SECURITY policy, issue and pull request templates.
