# Contributing

Thanks for your interest in Pan Galactic N.I.N.A. TV! The project is in an early phase (see the [roadmap](README.md#roadmap)), so issues with real-world data, ideas and reviews are especially welcome.

## Ground rules

Please read the [contributor guidelines](AGENTS.md) first. The short version:

- **Read-only.** Never add code, tests or tools that call N.I.N.A. control endpoints or write to the PHD2 socket – not even for testing. New endpoints need a source review and an entry in the [allowlist](docs/api-capability-matrix.md).
- **No private data.** No IP addresses, hostnames, site coordinates, file paths or logs from real systems in commits, fixtures, screenshots or issues. Use the sanitizer in [`tools/m0`](tools/m0/README.md).
- **No invented data.** If a value is not reliably available, show it as unavailable.

## Reporting issues

- Use the issue templates. For N.I.N.A./PHD2 related problems, include plugin, N.I.N.A. and PHD2 versions.
- Security or safety problems (anything that could make the app control hardware or leak data): see [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Pull requests

1. Open or reference an issue first for anything non-trivial.
2. Branch from `main` (`m<N>/<topic>` for milestone work, `fix/<topic>` otherwise).
3. Keep changes focused; add tests; update docs, ADRs and [CHANGELOG.md](CHANGELOG.md) where relevant.
4. Make sure CI is green:
   ```sh
   cd Packages/PanGalacticCore && swift test
   python3 tools/m0/tests/test_m0probe.py
   ```
5. Fill in the pull request checklist.

## Style

- Swift 6, strict concurrency, Swift Testing for new tests.
- Match the surrounding code; document *why*, not *what*.
- Commit messages: imperative subject line, body explaining the reason for the change.
