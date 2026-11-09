# Security Policy

## Scope

Pan Galactic N.I.N.A. TV is designed to be **strictly read-only** towards the telescope PC. Please report privately anything that could:

- cause the app (or its tooling) to send a request outside the [read-only allowlist](docs/api-capability-matrix.md), open a control WebSocket, or write to the PHD2 socket;
- leak network details, site coordinates, file paths or other private data (logs, fixtures, crash reports);
- crash or hang the app through malicious or malformed data from the local network.

Weaknesses of N.I.N.A., the Advanced API plugin or PHD2 themselves should be reported to those projects.

## Reporting

Please use GitHub's **[private vulnerability reporting](https://github.com/lindekai/PanGalacticNinaTV/security/advisories/new)** rather than a public issue. Include steps to reproduce and affected versions. You can expect an initial response within a week.

## Network exposure

The N.I.N.A. Advanced API has no authentication. Never expose port 1888 (or PHD2's 4400) to the internet; keep them on a trusted local network.
