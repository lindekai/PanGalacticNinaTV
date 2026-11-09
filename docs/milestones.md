# Milestones

Each milestone ends with a review; the next one starts only after approval.

| Milestone | Scope | Gate | Status |
|---|---|---|---|
| **M0** API feasibility | Pin plugin/PHD2 sources, capability matrix, read-only allowlist, probe tooling, live read-only fixtures from the owner's system, go/no-go | Data availability proven or explicitly downgraded; no UI work before | **In progress** – desk research done, live capture pending |
| M1 Skeleton & connections | Xcode project (tvOS 26), instance store, manual add/test, saved-host discovery, bounded subnet scan, routing 0/1/many, reconnect + stale state | Fresh app connects to real Advanced API; routing rules hold | Not started |
| M2 Overview & imaging | Live session metrics, preview on completed image, full-screen viewer, offline fallback | No fake-live metrics; latency and memory measured | Not started |
| M3 Guiding & alerts | Streaming chart, RMS with validated units, history, full screen, foreground-only alerts | Replays incl. pause, star lost, reconnect, dither, empty stream | Not started |
| M4 Astronomy | Compass, altitude plot, Sun/Moon/planets, time travel, star map, FOV overlay | Reference comparisons across sites/dates; usable on Apple TV HD | Not started |
| M5 Conditions, statistics, i18n, personality | Source-labelled conditions, verified metrics only, EN/DE, message engine | Freshness distinguishable; humor never replaces alarms | Not started |
| M6 Reliability & release readiness | Overnight soak, profiling, Wi-Fi dropouts, lifecycle, accessibility, docs, licenses | Overnight stability; no write requests in network log | Not started |

## M0 checklist

- [x] Locate authoritative Advanced API source and pin revision matching installed 2.2.15.3
- [x] Locate PHD2 event protocol documentation and pin revision
- [x] Draft capability matrix, risks, go/no-go ([api-capability-matrix.md](api-capability-matrix.md))
- [x] Draft read-only allowlist decision ([ADR 0001](adr/0001-read-only-endpoint-allowlist.md))
- [x] Read-only probe tooling with self-tests ([tools/m0](../tools/m0/README.md))
- [x] Owner test procedure ([m0-test-procedure.md](m0-test-procedure.md))
- [ ] Record PHD2 version
- [ ] Live capture: Advanced API REST (idle and during a running sequence)
- [ ] Live capture: Advanced API WebSocket events incl. `IMAGE-SAVE`
- [ ] Live capture: PHD2 events incl. `GuideStep`
- [ ] Preview image timing and telescope-PC CPU observation
- [ ] LAN reachability from Mac and Apple TV (same subnet, Windows firewall)
- [ ] Sanitize and commit fixtures; update matrix to *verified*
- [ ] Review and approval for M1
