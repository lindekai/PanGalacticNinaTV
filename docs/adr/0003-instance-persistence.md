# ADR 0003 – Instance persistence on tvOS

- Status: Accepted (M1)
- Date: 2026-11-09

## Context

The app stores a short list of configured N.I.N.A. instances (name, host, ports, last seen). tvOS gives apps no guaranteed persistent file storage: the caches and temporary directories can be purged by the system, and Apple's guidance for small amounts of app data on tvOS is `UserDefaults` (or iCloud). The list holds no secrets – the Advanced API has no authentication.

## Decision

- Store the instance list as a versioned JSON envelope (`{"version": 1, "instances": [...]}`) under the `UserDefaults` key `instances.v1`.
- Access only through the `InstanceStorage` protocol (`UserDefaultsInstanceStorage`, `InMemoryInstanceStorage` for tests); presentation uses `InstanceStore`.
- Load and save failures are surfaced in the UI (`persistenceError`), never silently replaced by an empty list.
- `lastSeen` is written at most once per minute to keep defaults writes cheap.
- No iCloud sync in phase 1.

## Consequences

- Data may be lost if the user deletes the app; re-adding an instance takes seconds.
- A future format change adds a new envelope version and a migration test instead of breaking existing installs.
- For UI tests the list can be injected through the launch argument domain (`-instances.v1 <hex data>`), which needs no code path in the app.
