# Changelog

All notable changes to this project are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- M0 API capability matrix for N.I.N.A. Advanced API 2.2.15.3 and PHD2 event monitoring, with read-only endpoint allowlist, risks and go/no-go table.
- ADR 0001 (read-only endpoint allowlist) and ADR 0002 (tvOS local networking).
- M0 probe tooling (`tools/m0`): allowlisted REST capture, passive WebSocket and PHD2 listeners, sanitizer, self-tests.
- `PanGalacticCore` Swift package: allowlisted N.I.N.A. request factory and guard, response envelope and WebSocket event decoding, PHD2 line framer, event decoder and state tracker, guide statistics with explicit units.
- CI for the Swift package and the M0 tooling.
- Repository presentation: README with banner and roadmap, CONTRIBUTING, SECURITY policy, issue and pull request templates.
