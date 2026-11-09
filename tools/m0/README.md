# M0 probe tooling

`m0probe.py` captures read-only data from the N.I.N.A. Advanced API and PHD2 for fixture creation. Python 3 standard library only.

| Command | What it does |
|---|---|
| `rest` | GETs the allowlisted endpoints (Tier A, plus `/profile/show?active=true` and `/equipment/focuser/last-af` unless `--skip-profile`); `--images` adds the latest thumbnail and one resized, server-stretched preview |
| `ws` | Passive listener on `ws://<host>:1888/v2/socket`; writes `events.jsonl` |
| `phd2` | Passive listener on PHD2 TCP 4400; writes `events.jsonl`; never writes to the socket |
| `sanitize` | Copies JSON/JSONL captures with site, path, host and IP values redacted |

Procedure: [docs/m0-test-procedure.md](../../docs/m0-test-procedure.md). Allowlist rationale: [ADR 0001](../../docs/adr/0001-read-only-endpoint-allowlist.md).

Self-tests (local fake servers, no hardware):

```sh
python3 tools/m0/tests/test_m0probe.py
```
