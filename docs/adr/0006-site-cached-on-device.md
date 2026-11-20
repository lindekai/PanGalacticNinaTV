# ADR 0006 – The site is cached on the device

- Status: Accepted (owner decision)
- Date: 2026-11-20

## Context

M4.1 computes the night (Sun, Moon, darkness, the target's altitude) from the site. N.I.N.A. reports the site only through `mount/info` (`SiteLatitude`, `SiteLongitude`, `SiteElevation`) and only while the mount is connected; by day or with the mount off the app would not know it. The site is privacy-sensitive (AGENTS.md); the owner runs several observatories and already decided that coordinates may be shown on the TV (capability matrix §7, 2026-11-16).

## Decision

- The last site a connected mount reported is kept per instance on the Apple TV in `UserDefaults` under `site.v1` (`[instance UUID: {site, reported}]`), next to the instances (ADR 0003).
- The mount always wins; the cached site is used only while the mount reports none, and the night page says "Site last reported on <date>".
- `0, 0, 0` (no site set in N.I.N.A.) is never stored.
- Removing an instance removes its site.
- The site is never logged, exported, put in fixtures, screenshots or issues, or sent anywhere; `Site`'s descriptions are redacted.
- No manual entry (the owner chose the cache over typing coordinates with the remote).

## Consequences

- The night page works by day and with the mount off once the mount was connected one time.
- A moved telescope shows the old site until its mount reports the new one; the date on the page makes that visible.
