# Pan Galactic N.I.N.A. TV

> Don't Panic. Your Telescope Is Probably Fine.

A native tvOS app that turns an Apple TV into a read-only observatory monitor for [N.I.N.A.](https://nighttime-imaging.eu/) (via the [Advanced API](https://github.com/christian-photo/ninaAPI) plugin) and [PHD2](https://openphdguiding.org/): live imaging progress, latest frame preview, guiding graph, sky position and conditions – readable from the couch.

**Status:** early development, milestone M0 (API feasibility). No app build yet. See [docs/milestones.md](docs/milestones.md).

## Principles

- **Monitoring only.** The app never controls the telescope, camera, guider or sequence. See [ADR 0001](docs/adr/0001-read-only-endpoint-allowlist.md).
- **No invented data.** Values are shown as measured, derived, estimated or unavailable – never silently faked.
- **Your network, your hardware.** Hosts, ports and site data are configured in the app, not built in.

## Requirements (planned)

- Apple TV HD or newer, tvOS 26+
- N.I.N.A. with the Advanced API plugin (developed against 2.2.15.3), reachable on the local network
- PHD2 with its server enabled (optional, for live guiding data)

## Documentation

- [Architecture](docs/architecture.md)
- [API capability matrix](docs/api-capability-matrix.md)
- [Milestones](docs/milestones.md)
- [M0 live test procedure](docs/m0-test-procedure.md)
- [Decisions (ADRs)](docs/adr/)
- [Changelog](CHANGELOG.md)
- [Contributor guidelines](AGENTS.md)

## Disclaimer

Independent, unofficial companion app. Not affiliated with or endorsed by the N.I.N.A. project, the Advanced API plugin author or the PHD2 project.

## License

To be decided before first public release.
