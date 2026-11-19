# ADR 0005 – Start M4 while M3 part 2 waits for live data

- Status: Accepted (owner decision)
- Date: 2026-11-19

## Context

Milestones run one after another, each with a review ([milestones](../milestones.md)). M3 part 1 (overview guiding chart, meridian tile) is done in PR #18. M3 part 2 – PHD2 event stream (#6), N.I.N.A. WebSocket events (#7), foreground alerts – cannot be built yet: AGENTS.md forbids inferring undocumented API behaviour, and the events have not been captured. That needs a clear, guided night ([capture night checklist](../m3-capture-night.md)), which may take weeks in November.

M4 (astronomy) is mostly computed from the site, the clock and the mount coordinates that `/equipment/info` already delivers. It can be checked against reference values (e.g. ephemerides, planetarium software) without a telescope and needs no new endpoint.

## Decision

- M3 is **paused**, not closed: part 1 is merged with #18, part 2 resumes after the capture night. M3's review and approval follow then.
- **M4 starts next**, on its own branch (`m4/<topic>`) after #18 is merged, beginning with a design spec.
- Star map and FOV overlay need a star catalogue; its licence is settled in `docs/licensing-and-attribution.md` before any catalogue data enters the repository. They come last in M4.
- **M5 follows M4**, not in parallel. Parts that need no live data (source-labelled conditions from the existing weather poll, EN/DE, message engine) come first; statistics that need verified metrics wait for captures.
- Only one milestone is active at a time; M3 part 2 interrupts M4 only between tasks.

## Consequences

- Progress continues without the telescope; M3 stays open on the milestone page until part 2 is reviewed.
- Two milestones are open at once in the docs; [status](../status.md) names the active one.
- M4 adds no endpoint, so the allowlist (ADR 0001) is unchanged unless a later M4 design says otherwise.
