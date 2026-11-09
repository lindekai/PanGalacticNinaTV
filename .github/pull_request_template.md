## Summary

<!-- What does this change and why? Link the issue: Closes #… -->

## Checklist

- [ ] **Read-only preserved:** no new network calls outside the [allowlist](../docs/api-capability-matrix.md); no writes to PHD2 or the N.I.N.A. WebSocket
- [ ] **No private data:** no IPs, hostnames, coordinates, paths or unsanitized logs in code, fixtures or screenshots
- [ ] Tests added/updated; `swift test` and `python3 tools/m0/tests/test_m0probe.py` pass
- [ ] Docs / ADR / [CHANGELOG](../CHANGELOG.md) updated where relevant
- [ ] UI changes: screenshot attached, checked for distance readability and focus navigation

## Notes for reviewers

<!-- Risks, open questions, things to look at closely. -->
