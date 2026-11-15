# Dashboard Redesign – Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the M2 overview with the approved "precision instrument" design: new visual system, overview with Camera/Object/Mount/Guiding/Filter modules, equatorial-mount icon, localized guider state, HFR sparkline from image history, and Top Shelf lettering.

**Architecture:** Pure derivations (mount activity, object altitude rule, status lights, image-history window) go into `PanGalacticCore` with unit tests. `InstanceConnection` (services) keeps a bounded window of recent history entries. The app gets a small design system in `App/Design/` (tokens + stateless components) and a rewritten overview in `App/Views/`.

**Tech Stack:** Swift 6, SwiftUI for tvOS 26, Swift Testing, String Catalogs (EN/DE), Python 3 + Pillow/NumPy for the artwork generator.

**Spec:** [`docs/superpowers/specs/2026-11-15-dashboard-redesign-design.md`](../specs/2026-11-15-dashboard-redesign-design.md)

## Global Constraints

- Read-only: no new API endpoints. Only `NINAEndpoint` cases that already exist (`.imageHistoryCount`, `.imageHistoryEntry(index:)`, `.equipmentInfo`, …). AGENTS.md safety rules apply.
- `unknown`, `unavailable` and `stale` are distinct from zero/false; a missing value renders as "—" in `Theme.text3`, never as 0.
- All user-facing strings localized EN (catalog key) and DE in `App/Resources/Localizable.xcstrings`. Humour never replaces alarm text.
- Palette tokens (hex): bg #161D21, surface #1E272C, raised #253036, line #2E3A40, text #DCE3E6, text2 #8C9AA2, text3 #5D6A71, accent #34B89C, warn #E3A23B, fault #E0584D, focus #F2F5F6.
- Teal (`accent`) only means running / OK / progress; never used for focus.
- Type scale (pt): display 52 semibold; key figure 72 medium (unit 34, text2); chart value 40; value 28–30 medium; label/meta 21–23 regular text2; rubric 18 semibold uppercase tracking +14 %. All numbers `.monospacedDigit()`.
- Layout grid: 8 pt; safe margins 80 pt left/right, 60 pt top/bottom; image column 1024 pt, gap 40 pt, module column 696 pt, 24 pt between modules.
- Object altitude (and RA/Dec under "Object") only while the mount is tracking; otherwise "—".
- No real hosts, coordinates or screenshots of the owner's system in commits.
- Xcode: `xcode-select` points to the Command Line Tools on the owner's Mac; prefix every `xcodebuild` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Branch: `m2/dashboard-redesign`. Commit messages end with the session's attribution lines.

## Deviation from the spec (owner to confirm at review)

The spec mentions "until then a single bar for the running exposure" at the bottom. The equipment info has no exposure start or duration, so a fraction would be guessed when the app joins mid-exposure. Phase 1 therefore shows the remaining time in the "Exposure" pill only; the bottom bar appears with sequence data (#4). The spec is updated in Task 9.

## File Structure

| File | Responsibility |
|---|---|
| `Packages/PanGalacticCore/Sources/PanGalacticCore/PHD2/PHD2Event.swift` (modify) | Make `PHD2AppState.init(wire:)` public |
| `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/MountActivity.swift` (new) | `MountActivity`, `Mount.activity`, `Mount.trackedObjectAltitude` |
| `Packages/PanGalacticCore/Sources/PanGalacticCore/Instances/StatusLight.swift` (new) | LED state derivation |
| `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/ImageHistoryBuffer.swift` (new) | Bounded window of history entries, backfill bookkeeping, HFR series |
| `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/DashboardDerivationTests.swift` (new) | Tests for the three core additions |
| `Packages/PanGalacticCore/Sources/PanGalacticServices/Connection/InstanceConnection.swift` (modify) | Fill the buffer; publish `recentImages` |
| `Packages/PanGalacticCore/Tests/PanGalacticServicesTests/ServicesTests.swift` (modify) | Backfill test |
| `App/Design/Theme.swift` (new) | Colour/type tokens, `Color(hex:)` |
| `App/Design/ButtonStyles.swift` (new) | `LiftButtonStyle`, `GearButtonStyle` (tvOS focus) |
| `App/Design/ModulePanel.swift` (new) | Panel with rubric header, icon, LED |
| `App/Design/Figures.swift` (new) | `KeyFigure`, `SideValues`, `TileValue` |
| `App/Design/StatusViews.swift` (new) | `StatusLED`, `StatusPill` |
| `App/Design/Sparkline.swift` (new) | Minimal line chart |
| `App/Design/Formatters.swift` (new) | Shared number/time formatting, guider state text |
| `App/Views/DashboardView.swift` (rewrite) | Overview layout, header, modules |
| `App/Views/LatestImageCard.swift` (rewrite) | Focusable frame with caption and sparkline |
| `App/Resources/Assets.xcassets/TelescopeMount.imageset/telescope-mount.svg` (replace) | Mount icon "F" |
| `App/Resources/Localizable.xcstrings` (modify) | New EN/DE strings |
| `tools/icons/make_placeholder_icons.py` (modify) | Top Shelf lettering |
| `CHANGELOG.md`, `docs/milestones.md`, spec (modify) | Docs |

---

### Task 1: Core derivations – guider state, mount activity, object altitude, status light

**Files:**
- Modify: `Packages/PanGalacticCore/Sources/PanGalacticCore/PHD2/PHD2Event.swift:8`
- Create: `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/MountActivity.swift`
- Create: `Packages/PanGalacticCore/Sources/PanGalacticCore/Instances/StatusLight.swift`
- Test: `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/DashboardDerivationTests.swift`

**Interfaces:**
- Consumes: `NINAEquipmentSummary.Mount`, `.Camera`, `.Device`, `ConnectionPhase` (existing).
- Produces:
  - `public init(wire: String)` on `PHD2AppState`
  - `public enum MountActivity: Hashable, Sendable { case slewing, parked, tracking, notTracking, unknown }`
  - `extension NINAEquipmentSummary.Mount { public var activity: MountActivity; public var trackedObjectAltitude: Double?; public var trackedRightAscension: String?; public var trackedDeclination: String? }`
  - `public enum StatusLight: Hashable, Sendable { case normal, warning, fault, unknown }` with `static func device(_ device: NINAEquipmentSummary.Device?, phase: ConnectionPhase) -> StatusLight` and `static func camera(_ camera: NINAEquipmentSummary.Camera?, phase: ConnectionPhase, now: Date) -> StatusLight`

- [ ] **Step 1: Write the failing tests**

Create `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/DashboardDerivationTests.swift`:

```swift
import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Dashboard derivations")
struct DashboardDerivationTests {
    func summary(_ json: String) throws -> NINAEquipmentSummary {
        try JSONDecoder().decode(NINAEquipmentSummary.self, from: Data(json.utf8))
    }

    @Test func guiderStateParsesWireValues() {
        #expect(PHD2AppState(wire: "Stopped") == .stopped)
        #expect(PHD2AppState(wire: "Guiding") == .guiding)
        #expect(PHD2AppState(wire: "LostLock") == .lostLock)
        #expect(PHD2AppState(wire: "Dancing") == .other("Dancing"), "unknown values are kept verbatim")
    }

    @Test func mountActivity() throws {
        func activity(_ fields: String) throws -> MountActivity? {
            try summary(#"{"Mount":{"Connected":true"# + fields + "}}").mount?.activity
        }
        #expect(try activity(#","Slewing":true,"AtPark":true,"TrackingEnabled":true"#) == .slewing)
        #expect(try activity(#","AtPark":true,"TrackingEnabled":false"#) == .parked)
        #expect(try activity(#","AtPark":false,"TrackingEnabled":true"#) == .tracking)
        #expect(try activity(#","AtPark":false,"TrackingEnabled":false"#) == .notTracking)
        #expect(try activity("") == .unknown)
        #expect(try summary(#"{"Mount":{"Connected":false,"TrackingEnabled":true}}"#).mount?.activity == .unknown)
    }

    @Test func objectAltitudeOnlyWhileTracking() throws {
        let tracking = try #require(try summary(#"{"Mount":{"Connected":true,"TrackingEnabled":true,"AtPark":false,"Altitude":38.4,"RightAscensionString":"05:35:17","DeclinationString":"-05° 23' 28\""}}"#).mount)
        #expect(tracking.trackedObjectAltitude == 38.4)
        #expect(tracking.trackedRightAscension == "05:35:17")
        #expect(tracking.trackedDeclination == #"-05° 23' 28""#)

        let parked = try #require(try summary(#"{"Mount":{"Connected":true,"TrackingEnabled":false,"AtPark":true,"Altitude":52.3,"RightAscensionString":"04:41:15"}}"#).mount)
        #expect(parked.trackedObjectAltitude == nil, "parked altitude is the park position, not the object's")
        #expect(parked.trackedRightAscension == nil)
        #expect(parked.altitudeDegrees == 52.3, "raw pointing value stays available for the Mount page")
    }

    @Test func statusLights() throws {
        let connected = NINAEquipmentSummary.Device(connected: true, name: "X")
        let disconnected = NINAEquipmentSummary.Device(connected: false, name: "X")
        #expect(StatusLight.device(connected, phase: .live) == .normal)
        #expect(StatusLight.device(connected, phase: .stale) == .warning)
        #expect(StatusLight.device(connected, phase: .offline) == .unknown)
        #expect(StatusLight.device(connected, phase: .connecting) == .unknown)
        #expect(StatusLight.device(disconnected, phase: .live) == .unknown)
        #expect(StatusLight.device(nil, phase: .live) == .unknown)

        let now = Date(timeIntervalSince1970: 1_000_000)
        let overdue = try #require(try summary(#"{"Camera":{"Connected":true,"IsExposing":true,"ExposureEndTime":"1970-01-12T13:44:00.0000000+00:00"}}"#).camera)
        #expect(StatusLight.camera(overdue, phase: .live, now: now) == .warning)
        let idle = try #require(try summary(#"{"Camera":{"Connected":true,"IsExposing":false}}"#).camera)
        #expect(StatusLight.camera(idle, phase: .live, now: now) == .normal)
    }
}
```

Note: `NINAEquipmentSummary.Device` has an implicit memberwise initializer that is `internal`; the test uses `@testable import`, so it compiles. `1970-01-12T13:44:00.0000000+00:00` (N.I.N.A.'s format with 7 fraction digits) is 999 840 s, i.e. 160 s before `now` (> 60 s grace).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/PanGalacticCore && swift test --filter DashboardDerivationTests`
Expected: compile errors – `MountActivity`, `StatusLight`, `trackedObjectAltitude` not found.

- [ ] **Step 3: Make `PHD2AppState.init(wire:)` public**

In `PHD2Event.swift` change line 8 from `    init(wire: String) {` to:

```swift
    public init(wire: String) {
```

- [ ] **Step 4: Create `MountActivity.swift`**

```swift
import Foundation

/// What the mount is doing, in order of precedence: slewing beats parked beats tracking.
public enum MountActivity: Hashable, Sendable {
    case slewing, parked, tracking, notTracking, unknown
}

extension NINAEquipmentSummary.Mount {
    public var activity: MountActivity {
        guard device.connected else { return .unknown }
        if slewing == true { return .slewing }
        if atPark == true { return .parked }
        switch trackingEnabled {
        case .some(true): return .tracking
        case .some(false): return .notTracking
        case nil: return .unknown
        }
    }

    /// N.I.N.A. reports where the mount points. That is the imaged object's position
    /// only while the mount tracks; parked or slewing values must not be shown as the
    /// object's. From M4 the object's altitude is computed from its coordinates instead.
    public var trackedObjectAltitude: Double? { activity == .tracking ? altitudeDegrees : nil }
    public var trackedRightAscension: String? { activity == .tracking ? rightAscension : nil }
    public var trackedDeclination: String? { activity == .tracking ? declination : nil }
}
```

- [ ] **Step 5: Create `StatusLight.swift`**

```swift
import Foundation

/// State of a module's status LED. Colour never carries meaning alone; views add a word
/// where the state is not obvious.
public enum StatusLight: Hashable, Sendable {
    case normal, warning, fault, unknown

    /// Connected devices are normal while live and a warning while stale. Without a
    /// current connection nothing is known about the device.
    public static func device(_ device: NINAEquipmentSummary.Device?, phase: ConnectionPhase) -> StatusLight {
        switch phase {
        case .offline, .connecting: return .unknown
        case .live, .stale: break
        }
        guard device?.connected == true else { return .unknown }
        return phase == .stale ? .warning : .normal
    }

    /// Like `device`, plus a warning for an exposure that is overdue (hung driver).
    public static func camera(_ camera: NINAEquipmentSummary.Camera?, phase: ConnectionPhase, now: Date) -> StatusLight {
        let base = device(camera?.device, phase: phase)
        if base == .normal, camera?.isOverdue(now: now) == true { return .warning }
        return base
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd Packages/PanGalacticCore && swift test`
Expected: all tests pass (previous 74 + 4 new).

- [ ] **Step 7: Commit**

```bash
git add Packages/PanGalacticCore/Sources/PanGalacticCore/PHD2/PHD2Event.swift \
        Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/MountActivity.swift \
        Packages/PanGalacticCore/Sources/PanGalacticCore/Instances/StatusLight.swift \
        Packages/PanGalacticCore/Tests/PanGalacticCoreTests/DashboardDerivationTests.swift
git commit -m "Core: mount activity, object altitude rule, status lights, public guider state"
```

---

### Task 2: Image history window in core

**Files:**
- Create: `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/ImageHistoryBuffer.swift`
- Test: `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/DashboardDerivationTests.swift` (append)

**Interfaces:**
- Consumes: `NINAImageSaveStatistics` (decodable; HFR placeholder 0 already decodes to `nil`).
- Produces: `public struct ImageHistoryBuffer: Hashable, Sendable` with
  - `public init(capacity: Int = 50)`
  - `public private(set) var count: Int`
  - `public mutating func update(count: Int)`
  - `public func missingIndices(limit: Int) -> [Int]` (newest first)
  - `public mutating func record(_ entry: NINAImageSaveStatistics?, at index: Int)`
  - `public var recent: [NINAImageSaveStatistics]` (oldest → newest)
  - `public func hfrSeries(limit: Int = 24) -> [Double]`
  - `public mutating func reset()`

- [ ] **Step 1: Write the failing test** – append inside `struct DashboardDerivationTests`:

```swift
    func entry(hfr: Double?) throws -> NINAImageSaveStatistics {
        let value = hfr.map { String($0) } ?? "0"
        return try JSONDecoder().decode(NINAImageSaveStatistics.self, from: Data(#"{"HFR":\#(value)}"#.utf8))
    }

    @Test func historyWindowBackfillsNewestFirstAndBoundsMemory() throws {
        var buffer = ImageHistoryBuffer(capacity: 5)
        #expect(buffer.missingIndices(limit: 4).isEmpty)

        buffer.update(count: 8)
        #expect(buffer.missingIndices(limit: 3) == [7, 6, 5])
        #expect(buffer.missingIndices(limit: 10) == [7, 6, 5, 4, 3], "only the newest `capacity` entries")

        buffer.record(try entry(hfr: 2.0), at: 7)
        buffer.record(nil, at: 6) // fetch failed: attempted, not retried
        buffer.record(try entry(hfr: 2.4), at: 5)
        #expect(buffer.missingIndices(limit: 10) == [4, 3])
        #expect(buffer.recent.compactMap(\.hfr) == [2.4, 2.0], "oldest first")

        buffer.update(count: 10)
        #expect(buffer.missingIndices(limit: 10) == [9, 8], "window moved; 5 dropped out")
        #expect(buffer.recent.compactMap(\.hfr) == [2.0])

        buffer.update(count: 2)
        #expect(buffer.recent.isEmpty, "shrinking history = N.I.N.A. restarted")
        #expect(buffer.missingIndices(limit: 10) == [1, 0])
    }

    @Test func hfrSeriesSkipsPlaceholdersAndLimits() throws {
        var buffer = ImageHistoryBuffer(capacity: 50)
        buffer.update(count: 30)
        for index in 0..<30 {
            buffer.record(try entry(hfr: index == 10 ? nil : 1.0 + Double(index) / 100), at: index)
        }
        let series = buffer.hfrSeries(limit: 24)
        #expect(series.count == 24)
        #expect(series.last == 1.29)
        #expect(!series.contains(1.10), "placeholder HFR 0 is unavailable, not a data point")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/PanGalacticCore && swift test --filter DashboardDerivationTests`
Expected: compile error – `ImageHistoryBuffer` not found.

- [ ] **Step 3: Implement `ImageHistoryBuffer.swift`**

```swift
import Foundation

/// The newest `capacity` entries of N.I.N.A.'s image history, filled newest first.
/// History indices are stable while N.I.N.A. runs (index 0 = oldest); a shrinking
/// count means N.I.N.A. restarted and everything is dropped. Failed fetches are
/// remembered as attempted so a broken entry never causes a request loop.
public struct ImageHistoryBuffer: Hashable, Sendable {
    public let capacity: Int
    public private(set) var count = 0
    private var entries: [Int: NINAImageSaveStatistics] = [:]
    private var attempted: Set<Int> = []

    public init(capacity: Int = 50) {
        self.capacity = capacity
    }

    private var lowestIndex: Int { max(0, count - capacity) }

    public mutating func update(count newCount: Int) {
        let newCount = max(0, newCount)
        if newCount < count { reset() }
        count = newCount
        let lowest = lowestIndex
        entries = entries.filter { $0.key >= lowest }
        attempted = attempted.filter { $0 >= lowest }
    }

    public func missingIndices(limit: Int) -> [Int] {
        guard count > 0, limit > 0 else { return [] }
        var result: [Int] = []
        for index in stride(from: count - 1, through: lowestIndex, by: -1)
        where entries[index] == nil && !attempted.contains(index) {
            result.append(index)
            if result.count == limit { break }
        }
        return result
    }

    public mutating func record(_ entry: NINAImageSaveStatistics?, at index: Int) {
        guard index >= lowestIndex, index < count else { return }
        attempted.insert(index)
        if let entry { entries[index] = entry }
    }

    public var recent: [NINAImageSaveStatistics] {
        entries.keys.sorted().compactMap { entries[$0] }
    }

    public func hfrSeries(limit: Int = 24) -> [Double] {
        Array(recent.compactMap(\.hfr).suffix(limit))
    }

    public mutating func reset() {
        count = 0
        entries = [:]
        attempted = []
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/PanGalacticCore && swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/ImageHistoryBuffer.swift \
        Packages/PanGalacticCore/Tests/PanGalacticCoreTests/DashboardDerivationTests.swift
git commit -m "Core: bounded image-history window with HFR series"
```

---

### Task 3: Connection keeps recent images

**Files:**
- Modify: `Packages/PanGalacticCore/Sources/PanGalacticServices/Connection/InstanceConnection.swift`
- Test: `Packages/PanGalacticCore/Tests/PanGalacticServicesTests/ServicesTests.swift` (inside `struct LatestImageTests`)

**Interfaces:**
- Consumes: `ImageHistoryBuffer` (Task 2).
- Produces: `public private(set) var recentImages: [NINAImageSaveStatistics]` on `InstanceConnection` (oldest → newest; kept while stale); `static let backfillPerPoll = 4`.

- [ ] **Step 1: Write the failing test** – add to `LatestImageTests`:

```swift
    @Test func backfillsRecentHistoryInSmallSteps() async {
        let transport = FakeTransport { request in
            let path = request.url?.path() ?? ""
            let query = request.url?.query() ?? ""
            switch path {
            case "/v2/api/version": return FakeTransport.ok(#""2.2.15.3""#)
            case "/v2/api/version/nina": return FakeTransport.ok(#""3.2""#)
            case "/v2/api/equipment/info": return FakeTransport.ok("{}")
            case "/v2/api/image-history" where query.contains("count=true"): return FakeTransport.ok("10")
            case "/v2/api/image-history":
                let index = Int(query.split(separator: "=").last ?? "") ?? 0
                return FakeTransport.ok(#"[{"ImageType":"LIGHT","HFR":\#(2.0 + Double(index) / 10)}]"#)
            default: return (404, "")
            }
        }
        let conn = connection(transport)

        _ = await conn.pollOnce()
        #expect(conn.recentImages.count == 1 + InstanceConnection.backfillPerPoll)
        _ = await conn.pollOnce()
        _ = await conn.pollOnce()
        #expect(conn.recentImages.count == 10)
        #expect(conn.recentImages.compactMap(\.hfr) == (0..<10).map { 2.0 + Double($0) / 10 })

        let before = transport.requests.count
        _ = await conn.pollOnce()
        let steady = transport.requests.dropFirst(before).compactMap { $0.url?.query() }
        #expect(!steady.contains { $0.contains("index=") }, "no history refetch in steady state")
        for request in transport.requests {
            #expect(throws: Never.self) { try NINAReadOnlyGuard.validate(request) }
        }
    }
```

The fake has no thumbnail route, so the tracker retries the thumbnail up to three times; that is expected. The requirement is that no `index=` request repeats in steady state.

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/PanGalacticCore && swift test --filter LatestImageTests`
Expected: compile error – `recentImages` / `backfillPerPoll` not found.

- [ ] **Step 3: Implement in `InstanceConnection.swift`**

Add below `latestThumbnail`:

```swift
    /// Recent history entries, oldest first, for trends (HFR sparkline, Image page).
    /// Kept while stale; never invented.
    public private(set) var recentImages: [NINAImageSaveStatistics] = []

    /// History entries fetched per poll while backfilling, to keep each cycle cheap.
    public static let backfillPerPoll = 4
```

Add below `@ObservationIgnored private var images = LatestImageTracker()`:

```swift
    @ObservationIgnored private var history = ImageHistoryBuffer()
```

In `pollOnce()`, in the offline branch next to `images.reset()` add:

```swift
                history.reset()
```

Replace `pollImages()` with:

```swift
    private func pollImages() async {
        guard let count = try? await client.get(.imageHistoryCount, as: Int.self) else { return }
        history.update(count: count)
        if images.update(count: count) {
            latestImageIndex = images.latestIndex
            if images.latestIndex == nil {
                latestImage = nil
                latestThumbnail = nil
            }
        }
        guard let index = images.latestIndex else {
            recentImages = history.recent
            return
        }
        if images.needsMetadata {
            guard let entries = try? await client.get(.imageHistoryEntry(index: index),
                                                      as: [NINAImageSaveStatistics].self) else { return }
            latestImage = entries.first
            latestThumbnail = nil
            images.metadataFetched()
            history.record(entries.first, at: index)
        }
        if images.needsThumbnail {
            let data = try? await client.raw(.thumbnail(index: index), maxBytes: Self.maxThumbnailBytes)
            let jpeg = data.flatMap { ImageFormat.isJPEG($0) ? $0 : nil }
            images.thumbnailFetched(success: jpeg != nil)
            if let jpeg { latestThumbnail = jpeg }
        }
        for older in history.missingIndices(limit: Self.backfillPerPoll) {
            let entries = try? await client.get(.imageHistoryEntry(index: older), as: [NINAImageSaveStatistics].self)
            history.record(entries?.first, at: older)
        }
        recentImages = history.recent
    }
```

The newest entry is recorded through the metadata path, so `missingIndices` never returns it after a successful metadata fetch (it is "attempted").

- [ ] **Step 4: Run all package tests**

Run: `cd Packages/PanGalacticCore && swift test`
Expected: all pass, including the existing `newImageLoadsMetadataAndRetriesThumbnail` (its steady-state assertion runs after backfill of indices 0–2 finished in the second poll).

- [ ] **Step 5: Commit**

```bash
git add Packages/PanGalacticCore/Sources/PanGalacticServices/Connection/InstanceConnection.swift \
        Packages/PanGalacticCore/Tests/PanGalacticServicesTests/ServicesTests.swift
git commit -m "Services: keep recent image history for trends (bounded backfill)"
```

---

### Task 4: Design system – tokens, focus styles, components

**Files:**
- Create: `App/Design/Theme.swift`, `App/Design/ButtonStyles.swift`, `App/Design/ModulePanel.swift`, `App/Design/Figures.swift`, `App/Design/StatusViews.swift`, `App/Design/Sparkline.swift`, `App/Design/Formatters.swift`

`App/` is a synchronized folder group: new files are part of the target automatically.

**Interfaces:**
- Consumes: `StatusLight`, `PHD2AppState` (Task 1).
- Produces (used by Task 6):
  - `enum Theme` with `static let bg, surface, raised, line, text, text2, text3, accent, warn, fault, focus: Color`; `static func color(for light: StatusLight) -> Color`
  - `extension Font { static let pgDisplay, pgKeyFigure, pgKeyUnit, pgTileValue, pgValue, pgLabel, pgRubric }`
  - `struct LiftButtonStyle: ButtonStyle` (`init(cornerRadius: CGFloat = 12, scale: CGFloat = 1.02)`)
  - `struct GearButtonStyle: ButtonStyle`
  - `struct ModulePanel<Content: View>: View` – `init(_ title: LocalizedStringKey, icon: Image, light: StatusLight?, accessory: String? = nil, @ViewBuilder content: () -> Content)`
  - `struct KeyFigure: View` – `init(_ value: String?, unit: String? = nil, label: LocalizedStringKey)`
  - `struct SideValues: View` – `init(_ rows: [(LocalizedStringKey, String?)])`
  - `struct TileValue: View` – `init(_ value: String?, detail: String?)`
  - `struct StatusLED: View` – `init(_ light: StatusLight)`
  - `struct StatusPill: View` – `init(_ key: LocalizedStringKey?, value: String, light: StatusLight? = nil, progress: Double? = nil)`
  - `struct Sparkline: View` – `init(_ values: [Double])`
  - `enum Format` – `celsius(_:) -> String`, `degrees(_:) -> String`, `percent(_:) -> String`, `seconds(_:) -> String`, `countdown(_ seconds: Int) -> String`, `hfr(_:) -> String`, `guiderState(_ wire: String?) -> String?`, `mountActivity(_:) -> String`

- [ ] **Step 1: `Theme.swift`**

```swift
import PanGalacticCore
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Design tokens of the dashboard (spec: "Visual system"). Teal is the only signal
/// colour; amber and red appear only for real warnings and faults.
enum Theme {
    static let bg = Color(hex: 0x161D21)
    static let surface = Color(hex: 0x1E272C)
    static let raised = Color(hex: 0x253036)
    static let line = Color(hex: 0x2E3A40)
    static let text = Color(hex: 0xDCE3E6)
    static let text2 = Color(hex: 0x8C9AA2)
    static let text3 = Color(hex: 0x5D6A71)
    static let accent = Color(hex: 0x34B89C)
    static let warn = Color(hex: 0xE3A23B)
    static let fault = Color(hex: 0xE0584D)
    static let focus = Color(hex: 0xF2F5F6)

    static let margin: CGFloat = 80
    static let marginVertical: CGFloat = 60
    static let imageWidth: CGFloat = 1024
    static let columnGap: CGFloat = 40
    static let moduleGap: CGFloat = 24
    static let radius: CGFloat = 12

    static func color(for light: StatusLight) -> Color {
        switch light {
        case .normal: accent
        case .warning: warn
        case .fault: fault
        case .unknown: text3
        }
    }
}

extension Font {
    static let pgDisplay = Font.system(size: 52, weight: .semibold)
    static let pgKeyFigure = Font.system(size: 72, weight: .medium).monospacedDigit()
    static let pgKeyUnit = Font.system(size: 34, weight: .regular)
    static let pgTileValue = Font.system(size: 40, weight: .medium).monospacedDigit()
    static let pgValue = Font.system(size: 28, weight: .medium).monospacedDigit()
    static let pgLabel = Font.system(size: 22, weight: .regular)
    static let pgRubric = Font.system(size: 18, weight: .semibold)
}
```

- [ ] **Step 2: `ButtonStyles.swift`**

```swift
import SwiftUI

/// tvOS focus for large content (the newest frame): slight lift, light border, shadow.
/// Teal is never used for focus.
struct LiftButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.radius
    var scale: CGFloat = 1.02

    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration, cornerRadius: cornerRadius, scale: scale)
    }

    private struct Body: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        let scale: CGFloat
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.focus, lineWidth: focused ? 3 : 0))
                .scaleEffect(focused ? (configuration.isPressed ? 1 : scale) : 1)
                .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 24, y: 12)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// Round icon button in the header; inverts when focused.
struct GearButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration)
    }

    private struct Body: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(focused ? Theme.bg : Theme.text2)
                .frame(width: 64, height: 64)
                .background(focused ? Theme.focus : Theme.surface, in: .circle)
                .scaleEffect(focused ? 1.12 : 1)
                .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 16, y: 8)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}
```

- [ ] **Step 3: `StatusViews.swift`**

```swift
import PanGalacticCore
import SwiftUI

/// Filled dot for known states, hollow ring for unknown/unavailable.
struct StatusLED: View {
    let light: StatusLight

    init(_ light: StatusLight) { self.light = light }

    var body: some View {
        Group {
            if light == .unknown {
                Circle().strokeBorder(Theme.text3, lineWidth: 2)
            } else {
                Circle().fill(Theme.color(for: light))
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel(Text(label))
    }

    private var label: LocalizedStringKey {
        switch light {
        case .normal: "Normal"
        case .warning: "Warning"
        case .fault: "Fault"
        case .unknown: "Unknown"
        }
    }
}

/// Header pill: small uppercase key, value, optional LED and progress underline.
struct StatusPill: View {
    let key: LocalizedStringKey?
    let value: String
    let light: StatusLight?
    let progress: Double?

    init(_ key: LocalizedStringKey?, value: String, light: StatusLight? = nil, progress: Double? = nil) {
        self.key = key
        self.value = value
        self.light = light
        self.progress = progress
    }

    var body: some View {
        HStack(spacing: 12) {
            if let light { StatusLED(light) }
            if let key {
                Text(key).font(.pgRubric).tracking(2.5).textCase(.uppercase).foregroundStyle(Theme.text2)
            }
            Text(verbatim: value).font(.pgValue).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(Theme.surface, in: .capsule)
        .overlay(alignment: .bottom) {
            if let progress {
                GeometryReader { geo in
                    Capsule().fill(Theme.accent)
                        .frame(width: geo.size.width * min(max(progress, 0), 1), height: 3)
                }
                .frame(height: 3)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
    }
}
```

- [ ] **Step 4: `ModulePanel.swift`**

```swift
import PanGalacticCore
import SwiftUI

/// Flat module surface: rubric header with grey icon and LED, hairline, content.
struct ModulePanel<Content: View>: View {
    let title: LocalizedStringKey
    let icon: Image
    let light: StatusLight?
    let accessory: String?
    let content: Content

    init(_ title: LocalizedStringKey, icon: Image, light: StatusLight?, accessory: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.light = light
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                icon.resizable().scaledToFit().frame(width: 26, height: 26).foregroundStyle(Theme.text2)
                Text(title).font(.pgRubric).tracking(2.5).textCase(.uppercase).foregroundStyle(Theme.text2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let accessory {
                    Text(verbatim: accessory).font(.pgLabel).foregroundStyle(Theme.text).lineLimit(1)
                }
                if let light { StatusLED(light) }
            }
            .frame(height: 44)
            Rectangle().fill(Theme.line).frame(height: 1)
            content.padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
    }
}
```

- [ ] **Step 5: `Figures.swift`**

```swift
import SwiftUI

/// The one large number of a module. `nil` renders as a dash in `text3`.
struct KeyFigure: View {
    let value: String?
    let unit: String?
    let label: LocalizedStringKey

    init(_ value: String?, unit: String? = nil, label: LocalizedStringKey) {
        self.value = value
        self.unit = unit
        self.label = label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: value ?? "—").font(.pgKeyFigure)
                    .foregroundStyle(value == nil ? Theme.text3 : Theme.text)
                if let unit, value != nil {
                    Text(verbatim: unit).font(.pgKeyUnit).foregroundStyle(Theme.text2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(label).font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(1)
        }
    }
}

/// Label/value rows, values right-aligned on one edge, hairlines between rows.
struct SideValues: View {
    let rows: [(LocalizedStringKey, String?)]

    init(_ rows: [(LocalizedStringKey, String?)]) { self.rows = rows }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                if offset > 0 { Rectangle().fill(Theme.line.opacity(0.6)).frame(height: 1) }
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0).font(.pgLabel).foregroundStyle(Theme.text2)
                    Spacer(minLength: 16)
                    Text(verbatim: row.1 ?? "—").font(.pgValue)
                        .foregroundStyle(row.1 == nil ? Theme.text3 : Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(height: 44)
            }
        }
        .frame(width: 300)
    }
}

/// Compact value for the three small tiles (mount, guiding, filter).
struct TileValue: View {
    let value: String?
    let detail: String?

    init(_ value: String?, detail: String?) {
        self.value = value
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: value ?? "—").font(.pgTileValue)
                .foregroundStyle(value == nil ? Theme.text3 : Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let detail {
                Text(verbatim: detail).font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(2)
            }
        }
    }
}
```

- [ ] **Step 6: `Sparkline.swift`**

```swift
import SwiftUI

/// Minimal trend: baseline, one grey curve, newest point in teal. Hidden below two values.
struct Sparkline: View {
    let values: [Double]

    init(_ values: [Double]) { self.values = values }

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2, let low = values.min(), let high = values.max() else { return }
            let span = max(high - low, 0.0001)
            let inset: CGFloat = 5
            func point(_ index: Int) -> CGPoint {
                let x = inset + (size.width - 2 * inset) * CGFloat(index) / CGFloat(values.count - 1)
                let y = inset + (size.height - 2 * inset) * (1 - CGFloat((values[index] - low) / span))
                return CGPoint(x: x, y: y)
            }
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: size.height - 0.5))
            baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(baseline, with: .color(Theme.line), lineWidth: 1)
            var curve = Path()
            curve.move(to: point(0))
            for index in 1..<values.count { curve.addLine(to: point(index)) }
            context.stroke(curve, with: .color(Theme.text2), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            let last = point(values.count - 1)
            context.fill(Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)),
                         with: .color(Theme.accent))
        }
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 7: `Formatters.swift`**

```swift
import Foundation
import PanGalacticCore

/// Shared display formatting. `nil` stays `nil` so views can render "—".
enum Format {
    static func celsius(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    static func degrees(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded())) %"
    }

    static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " s"
    }

    static func hfr(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    /// `m:ss`, or `h:mm:ss` from one hour.
    static func countdown(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// PHD2 application state as reported through N.I.N.A.; unknown values verbatim.
    static func guiderState(_ wire: String?) -> String? {
        guard let wire else { return nil }
        switch PHD2AppState(wire: wire) {
        case .stopped: return String(localized: "Stopped")
        case .selected: return String(localized: "Star selected")
        case .calibrating: return String(localized: "Calibrating")
        case .guiding: return String(localized: "Guiding")
        case .lostLock: return String(localized: "Star lost")
        case .paused: return String(localized: "Paused")
        case .looping: return String(localized: "Looping")
        case .other(let value): return value
        }
    }

    static func mountActivity(_ activity: MountActivity) -> String? {
        switch activity {
        case .slewing: String(localized: "Slewing")
        case .parked: String(localized: "Parked")
        case .tracking: String(localized: "Tracking")
        case .notTracking: String(localized: "Not tracking")
        case .unknown: nil
        }
    }
}
```

- [ ] **Step 8: Build the app** (old views still compile; new files unused yet)

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PanGalacticNinaTV.xcodeproj \
  -scheme PanGalacticNinaTV -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning:|BUILD"
```
Expected: `** BUILD SUCCEEDED **`, no new warnings.

- [ ] **Step 9: Commit**

```bash
git add App/Design
git commit -m "App: design tokens, focus styles and dashboard components"
```

---

### Task 5: Equatorial-mount icon "F"

**Files:**
- Replace: `App/Resources/Assets.xcassets/TelescopeMount.imageset/telescope-mount.svg`

The imageset's `Contents.json` stays (template rendering, preserves vector).

- [ ] **Step 1: Replace the SVG with exactly this content**

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <!-- German equatorial mount: tripod, pier, tilted polar axis, counterweight, tube with dew shield -->
  <path fill="#000" fill-rule="nonzero" d="M10.43 16.59 L6.23 22.39 L7.37 23.21 L11.57 17.41 Z M10.43 17.41 L14.63 23.21 L15.77 22.39 L11.57 16.59 Z M10.30 17.00 L10.30 22.80 L11.70 22.80 L11.70 17.00 Z M12.20 17.60 L12.20 15.60 L9.80 15.60 L9.80 17.60 Z M11.86 16.68 L14.46 12.78 L12.14 11.22 L9.54 15.12 Z M9.84 10.94 L17.84 16.24 L18.56 15.16 L10.56 9.86 Z M10.53 12.00 L13.53 14.00 L14.87 12.00 L11.87 10.00 Z M17.51 13.49 L15.81 16.09 L17.99 17.51 L19.69 14.91 Z M6.65 15.23 L13.05 5.63 L10.55 3.97 L4.15 13.57 Z M12.68 6.95 L14.48 4.25 L11.32 2.15 L9.52 4.85 Z M4.37 14.60 L3.67 15.70 L4.93 16.50 L5.63 15.40 Z"/>
</svg>
```

- [ ] **Step 2: Verify rendering**

Run: `qlmanage -t -s 240 -o /tmp App/Resources/Assets.xcassets/TelescopeMount.imageset/telescope-mount.svg` and open the PNG. Expected: tripod, tilted polar axis, counterweight bottom right, tube top left.

- [ ] **Step 3: Commit**

```bash
git add App/Resources/Assets.xcassets/TelescopeMount.imageset/telescope-mount.svg
git commit -m "App: equatorial mount icon (filled silhouette)"
```

---

### Task 6: New overview

**Files:**
- Rewrite: `App/Views/DashboardView.swift`
- Rewrite: `App/Views/LatestImageCard.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–5; existing `InstanceConnection` (`phase`, `equipment`, `latestImage`, `latestThumbnail`, `latestImageIndex`, `recentImages`, `lastSuccess`, `nextAttempt`, `lastError`, `incompatibility`, `pluginVersion`, `ninaVersion`, `retryNow()`, `refreshPhase()`), `AppModel` (`store.instances`, `deactivate()`, `renderService`), `Destination.settings`, `ImageViewer`.
- Produces: `DashboardView(connection:)` (same signature as today), `LatestImageCard(image:thumbnail:hfrSeries:asOf:now:open:)`.

- [ ] **Step 1: Rewrite `LatestImageCard.swift`**

```swift
import PanGalacticCore
import SwiftUI
import UIKit

/// The newest frame: focusable image with crosshair and a caption below it.
/// Old frames are labelled "As of …" so they are never mistaken for new ones.
struct LatestImageCard: View {
    let image: NINAImageSaveStatistics?
    let thumbnail: Data?
    let hfrSeries: [Double]
    let asOf: Date?
    let now: Date
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(spacing: 0) {
                preview
                caption
            }
            .background(Theme.surface)
            .clipShape(.rect(cornerRadius: Theme.radius))
        }
        .buttonStyle(LiftButtonStyle())
        .disabled(image == nil)
    }

    private var preview: some View {
        ZStack {
            Rectangle().fill(Color.black)
            if let thumbnail, let uiImage = UIImage(data: thumbnail) {
                Image(uiImage: uiImage).resizable().scaledToFit()
            } else if image != nil {
                ProgressView()
            } else {
                Text("No image in this N.I.N.A. session yet").font(.pgLabel).foregroundStyle(Theme.text3)
            }
            Crosshair().stroke(Theme.text.opacity(0.28), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let asOf {
                Text("As of \(asOf.formatted(date: .omitted, time: .shortened))")
                    .font(.pgLabel).foregroundStyle(Theme.bg)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Theme.warn, in: .capsule)
                    .padding(20)
            }
        }
    }

    private var caption: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: image?.targetName ?? "—").font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.text).lineLimit(1)
                Text(verbatim: metadata).font(.pgLabel).monospacedDigit().foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 16)
            if hfrSeries.count >= 2 {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("HFR · last \(hfrSeries.count) frames").font(.pgRubric).tracking(2)
                        .textCase(.uppercase).foregroundStyle(Theme.text2)
                    Sparkline(hfrSeries).frame(width: 220, height: 44)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    /// "Light · L · 300 s · HFR 2.14 · 1 834 stars · 12 s ago"; unknown parts are left out.
    private var metadata: String {
        guard let image else { return "" }
        var parts: [String] = []
        if let type = image.imageType { parts.append(type.capitalized) }
        if let filter = image.filter { parts.append(filter) }
        if let exposure = image.exposureTime { parts.append(Format.seconds(exposure)) }
        if let hfr = image.hfr { parts.append("HFR " + Format.hfr(hfr)) }
        if let stars = image.stars { parts.append(String(localized: "\(stars) stars")) }
        if let date = image.date { parts.append(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))) }
        return parts.joined(separator: " · ")
    }
}

/// 1 px crosshair with a gap in the centre so the object is never covered.
private struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        let gap: CGFloat = 22
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - gap))
        path.move(to: CGPoint(x: rect.midX, y: rect.midY + gap)); path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY)); path.addLine(to: CGPoint(x: rect.midX - gap, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX + gap, y: rect.midY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
```

- [ ] **Step 2: Rewrite `DashboardView.swift`**

```swift
import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// Overview of one N.I.N.A. instance (spec: "Overview details"). Answers at a glance:
/// is everything running, how good is the newest frame, how is the camera set, where
/// is the object. Unknown values are "—"; data that is not live is labelled with its age.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    let connection: InstanceConnection
    @State private var viewerItem: ViewerItem?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 32) {
                header(now: context.date)
                if let version = connection.incompatibility {
                    Label("Advanced API \(version) is not supported yet (supported: 2.x). Monitoring stopped.",
                          systemImage: "xmark.octagon.fill")
                        .font(.pgValue).foregroundStyle(Theme.fault)
                    Spacer()
                } else {
                    if connection.phase == .offline { offlineBanner(now: context.date) }
                    overview(now: context.date)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, Theme.marginVertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
            .onChange(of: context.date) { connection.refreshPhase() }
        }
        #if DEBUG
        // Simulator gate tests have no remote: `-debug.openViewer YES` opens the viewer once an image is known.
        .onChange(of: connection.latestImageIndex) { _, index in
            if let index, UserDefaults.standard.bool(forKey: "debug.openViewer"), viewerItem == nil {
                viewerItem = ViewerItem(index: index)
            }
        }
        #endif
        .fullScreenCover(item: $viewerItem) { item in
            ImageViewer(index: item.index, image: connection.latestImage, thumbnail: connection.latestThumbnail,
                        service: model.renderService)
        }
    }

    private var asOf: Date? {
        connection.phase == .live ? nil : connection.lastSuccess
    }

    // MARK: Header

    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: connection.instance.displayName).font(.pgDisplay).foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let plugin = connection.pluginVersion {
                    Text("N.I.N.A. \(connection.ninaVersion ?? "?") · Advanced API \(plugin)")
                        .font(.pgLabel).foregroundStyle(Theme.text2)
                }
            }
            Spacer(minLength: 24)
            // Sequence progress needs the running-sequence schema (#4); until then honestly "—".
            StatusPill("Sequence", value: "—")
            exposurePill(now: now)
            livePill(now: now)
            if model.store.instances.count > 1 {
                Button { model.deactivate() } label: { Image(systemName: "rectangle.2.swap") }
                    .buttonStyle(GearButtonStyle())
                    .accessibilityLabel(Text("Switch Observatory"))
            }
            NavigationLink(value: Destination.settings) { Image(systemName: "gearshape") }
                .buttonStyle(GearButtonStyle())
                .accessibilityLabel(Text("Settings"))
        }
    }

    private func exposurePill(now: Date) -> some View {
        let camera = connection.equipment?.camera
        if let camera, camera.isOverdue(now: now) {
            return StatusPill("Exposure", value: String(localized: "Overdue"), light: .warning)
        }
        if camera?.isExposing == true, let end = camera?.exposureEndTime, end > now {
            let left = Int(end.timeIntervalSince(now).rounded(.up))
            return StatusPill("Exposure", value: String(localized: "\(Format.countdown(left)) left"))
        }
        return StatusPill("Exposure", value: "—")
    }

    private func livePill(now: Date) -> some View {
        let time = now.formatted(date: .omitted, time: .shortened)
        switch connection.phase {
        case .live:
            return StatusPill(nil, value: String(localized: "LIVE · \(time)"), light: .normal)
        case .stale:
            let since = connection.lastSuccess?.formatted(date: .omitted, time: .shortened) ?? "—"
            return StatusPill(nil, value: String(localized: "Stale · as of \(since)"), light: .warning)
        case .offline:
            return StatusPill(nil, value: String(localized: "Offline"), light: .fault)
        case .connecting:
            return StatusPill(nil, value: String(localized: "Connecting…"), light: .unknown)
        }
    }

    /// Factual banner below the header – never a modal.
    private func offlineBanner(now: Date) -> some View {
        HStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.fault)
            Text(verbatim: offlineText(now: now)).font(.pgValue).foregroundStyle(Theme.text).lineLimit(1)
            Spacer()
            Button("Retry Now", systemImage: "arrow.clockwise") { connection.retryNow() }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Theme.fault.opacity(0.16), in: .rect(cornerRadius: Theme.radius))
    }

    private func offlineText(now: Date) -> String {
        // Service messages are stable English sentences used as catalog keys.
        let error = connection.lastError.map { String(localized: String.LocalizationValue($0)) } ?? ""
        guard let next = connection.nextAttempt else { return error }
        let seconds = max(0, Int(next.timeIntervalSince(now).rounded(.up)))
        return String(localized: "N.I.N.A. not reachable · retry in \(seconds) s · \(error)")
    }

    // MARK: Body

    private func overview(now: Date) -> some View {
        let equipment = connection.equipment
        let phase = connection.phase
        return HStack(alignment: .top, spacing: Theme.columnGap) {
            LatestImageCard(image: connection.latestImage, thumbnail: connection.latestThumbnail,
                            hfrSeries: Array(connection.recentImages.compactMap(\.hfr).suffix(24)),
                            asOf: asOf, now: now) {
                if let index = connection.latestImageIndex { viewerItem = ViewerItem(index: index) }
            }
            .frame(width: Theme.imageWidth)

            VStack(spacing: Theme.moduleGap) {
                CameraModule(camera: equipment?.camera, light: StatusLight.camera(equipment?.camera, phase: phase, now: now))
                ObjectModule(target: connection.latestImage?.targetName, mount: equipment?.mount)
                HStack(alignment: .top, spacing: Theme.moduleGap) {
                    MountTile(mount: equipment?.mount, light: StatusLight.device(equipment?.mount?.device, phase: phase))
                        .layoutPriority(1)
                    GuidingTile(guider: equipment?.guider, light: StatusLight.device(equipment?.guider?.device, phase: phase))
                    FilterTile(wheel: equipment?.filterWheel, light: StatusLight.device(equipment?.filterWheel?.device, phase: phase))
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .opacity(asOf != nil && equipment != nil ? 0.55 : 1)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct ViewerItem: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: Modules

struct CameraModule: View {
    let camera: NINAEquipmentSummary.Camera?
    let light: StatusLight

    var body: some View {
        ModulePanel("Camera", icon: Image(systemName: "camera"), light: light) {
            let on = camera?.device.connected == true
            HStack(alignment: .bottom) {
                KeyFigure(on ? camera?.gain.map(String.init) : nil, label: "Gain")
                Spacer(minLength: 24)
                SideValues([
                    ("Sensor", on ? camera?.temperature.map(Format.celsius) : nil),
                    // Setpoint only while the cooler runs (#5: driver value, not the panel value).
                    ("Setpoint", on ? camera?.activeSetpoint.map(Format.celsius) : nil),
                    ("Cooler", on ? coolerText : nil),
                ])
            }
        }
    }

    private var coolerText: String? {
        guard let camera, let coolerOn = camera.coolerOn else { return nil }
        guard coolerOn else { return String(localized: "Off") }
        return camera.coolerPower.map(Format.percent) ?? String(localized: "On")
    }
}

struct ObjectModule: View {
    let target: String?
    let mount: NINAEquipmentSummary.Mount?

    var body: some View {
        ModulePanel("Object", icon: Image(systemName: "scope"), light: nil, accessory: target) {
            HStack(alignment: .bottom) {
                KeyFigure(mount?.trackedObjectAltitude.map(Format.degrees), unit: "°", label: "Altitude above horizon")
                Spacer(minLength: 24)
                SideValues([
                    ("RA", mount?.trackedRightAscension),
                    ("Dec", mount?.trackedDeclination),
                ])
            }
        }
    }
}

struct MountTile: View {
    let mount: NINAEquipmentSummary.Mount?
    let light: StatusLight

    var body: some View {
        // No SF Symbol for an equatorial mount exists on tvOS 26; custom template vector.
        ModulePanel("Mount", icon: Image("TelescopeMount"), light: light) {
            TileValue(mount.flatMap { Format.mountActivity($0.activity) }, detail: pierText)
        }
        .frame(minWidth: 280)
    }

    private var pierText: String? {
        switch mount?.sideOfPier {
        case .east: String(localized: "Pier side east")
        case .west: String(localized: "Pier side west")
        case nil: nil
        }
    }
}

struct GuidingTile: View {
    let guider: NINAEquipmentSummary.Guider?
    let light: StatusLight

    var body: some View {
        ModulePanel("Guiding", icon: Image(systemName: "target"), light: light) {
            // RMS needs the validated definition from M3 (#6); until then "—".
            TileValue(nil, detail: Format.guiderState(guider?.device.connected == true ? guider?.state : nil)
                      ?? String(localized: "RMS not available yet"))
        }
    }
}

struct FilterTile: View {
    let wheel: NINAEquipmentSummary.FilterWheel?
    let light: StatusLight

    var body: some View {
        ModulePanel("Filter", icon: Image(systemName: "circle.grid.cross"), light: light) {
            TileValue(wheel?.device.connected == true ? wheel?.selectedFilter : nil, detail: nil)
        }
    }
}
```

Notes for the implementer:
- `MountTile` uses `TileValue` whose value font is 40 pt; "Nachführung"/"Keine Nachführung" must fit. `minimumScaleFactor(0.6)` in `TileValue` handles it; check DE in the simulator (Step 5).
- `Image(systemName: "scope")` exists in SF Symbols 5+; if it does not render on tvOS 26, use `"sparkle"`.

- [ ] **Step 3: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PanGalacticNinaTV.xcodeproj -scheme PanGalacticNinaTV -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning:|BUILD"`
Expected: `** BUILD SUCCEEDED **`, no warnings.

- [ ] **Step 4: Add German translations**

The build extracts new keys into `App/Resources/Localizable.xcstrings`. Add DE for every new key with this script (run from the repo root; it only fills missing `de` entries):

```bash
python3 - <<'EOF'
import json
path = "App/Resources/Localizable.xcstrings"
catalog = json.load(open(path))
de = {
    "Sequence": "Sequenz", "Exposure": "Belichtung", "Overdue": "Überfällig",
    "%@ left": "noch %@", "LIVE · %@": "LIVE · %@", "Stale · as of %@": "Veraltet · Stand %@",
    "Offline": "Offline", "Connecting…": "Verbinde…", "Settings": "Einstellungen",
    "Switch Observatory": "Sternwarte wechseln", "Retry Now": "Jetzt erneut versuchen",
    "N.I.N.A. not reachable · retry in %lld s · %@": "N.I.N.A. nicht erreichbar · neuer Versuch in %lld s · %@",
    "Camera": "Kamera", "Gain": "Gain", "Sensor": "Sensor", "Setpoint": "Soll", "Cooler": "Kühlung",
    "Off": "Aus", "On": "Ein", "Object": "Objekt", "Altitude above horizon": "Höhe über Horizont",
    "RA": "RA", "Dec": "Dec", "Mount": "Montierung", "Pier side east": "Seite Ost", "Pier side west": "Seite West",
    "Slewing": "Schwenkt", "Parked": "Geparkt", "Tracking": "Nachführung", "Not tracking": "Keine Nachführung",
    "Guiding": "Guiding", "RMS not available yet": "RMS noch nicht verfügbar", "Filter": "Filter",
    "Stopped": "Gestoppt", "Star selected": "Stern gewählt", "Calibrating": "Kalibriert",
    "Star lost": "Stern verloren", "Paused": "Pausiert", "Looping": "Schleife",
    "Normal": "Normal", "Warning": "Warnung", "Fault": "Fehler", "Unknown": "Unbekannt",
    "HFR · last %lld frames": "HFR · letzte %lld Bilder", "%lld stars": "%lld Sterne",
    "As of %@": "Stand %@", "No image in this N.I.N.A. session yet": "Noch kein Bild in dieser N.I.N.A.-Sitzung",
}
missing = []
for key, entry in catalog["strings"].items():
    locs = entry.setdefault("localizations", {})
    if "de" in locs:
        continue
    if key in de:
        locs["de"] = {"stringUnit": {"state": "translated", "value": de[key]}}
    else:
        missing.append(key)
json.dump(catalog, open(path, "w"), ensure_ascii=False, indent=2, sort_keys=True)
print("still without German:", missing)
EOF
```

Expected: `still without German: []` or only keys that already existed without DE before this task (check with `git diff` that pre-existing keys are untouched). Translate any remaining new key by hand in the same file. Xcode writes `.xcstrings` with `"  "` indentation and `" : "` separators; if the diff shows whole-file reformatting, re-save the catalog once in Xcode or match the original style (`json.dump(..., indent=2, separators=(",", " : "))`) so the diff only contains new entries.

- [ ] **Step 5: Simulator gate (owner-visible check)**

Boot a tvOS 26 simulator, install, and launch against the test instance as described in `docs/status.md` ("Running in the simulator against a real N.I.N.A."), with the simulator language set to German (`xcrun simctl spawn <device> defaults write -g AppleLanguages '("de")'`, then relaunch). Take screenshots with `xcrun simctl io <device> screenshot <scratchpad>/overview-live.png`. Check:
- Header: name, version line, three pills, gear; focus moves image ↔ gear with arrow keys (Simulator: Hardware keyboard arrows); focused gear inverts, focused image lifts with a light border.
- Camera: Gain large; Sensor, Soll, Kühlung right-aligned.
- Object: target name in header; altitude "—" when the mount is parked (expected on a parked rig), RA/Dec "—" too.
- Tiles: "Geparkt" fits; Guiding shows "Gestoppt"; filter name.
- Kill the N.I.N.A. host connection (or use an unreachable test instance) to see the offline banner and the dimmed values with "Stand …".
Do not commit screenshots (they show the owner's data).

- [ ] **Step 6: Commit**

```bash
git add App/Views/DashboardView.swift App/Views/LatestImageCard.swift App/Resources/Localizable.xcstrings
git commit -m "App: precision-instrument overview with object module and HFR sparkline"
```

---

### Task 7: Top Shelf lettering

**Files:**
- Modify: `tools/icons/make_placeholder_icons.py`
- Regenerate: `App/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets/Top Shelf Image*.imageset/*.png`

- [ ] **Step 1: Add lettering to `write_top_shelf`**

Add near the other imports: `from PIL import Image, ImageDraw, ImageFont`. Add these helpers above `write_top_shelf`:

```python
TITLE = "Pan Galactic"
SUBTITLE = "N.I.N.A. Observatory Monitor"
TEXT = (220, 227, 230)      # Theme.text
TEXT2 = (140, 154, 162)     # Theme.text2


def font(size: int, weight: str) -> ImageFont.FreeTypeFont:
    """SF Pro from the system (variable font); Helvetica Neue as fallback."""
    try:
        f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
        f.set_variation_by_name(weight)
        return f
    except (OSError, ValueError):
        return ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", size)


def letter(image: Image.Image) -> Image.Image:
    """Name and subtitle on the star field, left of the nebula, inside the safe area."""
    w, h = image.size
    draw = ImageDraw.Draw(image)
    x = round(w * 0.06)
    title = font(round(h * 0.15), "Semibold")
    subtitle = font(round(h * 0.055), "Regular")
    title_box = draw.textbbox((0, 0), TITLE, font=title)
    y = round(h * 0.40) - (title_box[3] - title_box[1])
    draw.text((x, y), TITLE, font=title, fill=TEXT)
    draw.text((x + round(h * 0.006), y + (title_box[3] - title_box[1]) + round(h * 0.07)), SUBTITLE, font=subtitle, fill=TEXT2)
    return image
```

In `write_top_shelf`, change

```python
    full = flatten(render(base_size[0] * 2, base_size[1] * 2, TOP_SHELF))
```

to

```python
    full = letter(flatten(render(base_size[0] * 2, base_size[1] * 2, TOP_SHELF)))
```

- [ ] **Step 2: Regenerate and inspect**

Run: `python3 tools/icons/make_placeholder_icons.py`
Then view `App/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets/Top Shelf Image Wide.imageset/top-shelf@1x.png` and `Top Shelf Image.imageset/top-shelf@1x.png`. Expected: "Pan Galactic" large, subtitle below, left half, not overlapping stars with spikes too badly; nebula unchanged on the right. If a bright star sits behind the text, move that star in `TOP_SHELF.bright_stars` (x < 0.45 entries) rather than the text.

- [ ] **Step 3: Build** (asset catalog validates sizes)

Run the build command from Task 4 Step 8. Expected: success, no asset warnings.

- [ ] **Step 4: Commit**

```bash
git add tools/icons/make_placeholder_icons.py "App/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
git commit -m "Artwork: Top Shelf lettering"
```

---

### Task 8: Docs and review gate

**Files:**
- Modify: `CHANGELOG.md`, `docs/milestones.md`, `docs/superpowers/specs/2026-11-15-dashboard-redesign-design.md`

- [ ] **Step 1: Spec deviation** – in the spec's "Overview details", replace the "Bottom bar" bullet with:

```markdown
- **Bottom bar:** one segment per exposure of the sequence once #4 is done. Until then no bar: the equipment info has no exposure start or duration, so a fraction would be guessed when the app joins mid-exposure; the "Exposure" pill shows the remaining time instead.
```

and in the Object row of the Pages table make sure RA/Dec are described as "only while tracking".

- [ ] **Step 2: CHANGELOG** – under `## [Unreleased]` → `### Added (M2)` add:

```markdown
- Redesigned overview ("precision instrument"): slate/teal design system, header with sequence/exposure/live pills and settings button, newest frame with crosshair, caption and HFR trend of recent frames, modules Camera (gain first), Object (altitude only while tracking), Mount, Guiding and Filter with status LEDs.
- Equatorial mount icon; Top Shelf lettering.
- Connection keeps the last 50 image-history entries (backfilled four per poll).
```

and under `### Changed (M2)`:

```markdown
- Guider state is localized (e.g. "Stopped" → "Gestoppt"); unknown states are shown as received.
```

- [ ] **Step 3: Milestones** – in the M2 checklist add above "Review and approval for M3":

```markdown
- [x] Dashboard redesign phase 1: design system, overview, mount icon, Top Shelf lettering ([spec](superpowers/specs/2026-11-15-dashboard-redesign-design.md))
- [ ] Dashboard redesign phase 2: tab bar with Image, Mount, System pages
- [ ] Dashboard redesign phase 3: ambient mode
```

- [ ] **Step 4: Full verification**

```bash
(cd Packages/PanGalacticCore && swift test)
python3 tools/m0/tests/test_m0probe.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PanGalacticNinaTV.xcodeproj -scheme PanGalacticNinaTV \
  -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning:|BUILD"
```
Expected: all tests pass; build succeeded without warnings.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md docs/milestones.md docs/superpowers/specs/2026-11-15-dashboard-redesign-design.md
git commit -m "Docs: changelog and milestones for dashboard redesign phase 1"
```

- [ ] **Step 6: Owner review** – show simulator screenshots of the overview (live, offline) to the owner; collect feedback before Phase 2.

---

## Phase 2 outline (separate plan after Phase 1 review)

- `RootView`: when an instance is active, host `TabView` with tabs Overview, Image, Sequence (placeholder "Available with sequence data"), Mount, Guiding (empty state), System; tab bar styled with `Theme.raised` glass.
- Image page: medium frame; HFR and star-count charts with shared time axis from `recentImages` (median dashed, newest point teal); table of the last frames (time, filter, exposure, HFR, stars).
- Mount page: RA/Dec, pointing altitude, pier side, activity; placeholders for M4 charts.
- System page: camera details (offset, cooler power), filter wheel, focuser, connection (phase, last success, next attempt), versions.
- Core tests for the chart series (median, time axis from `date`, gaps).

## Phase 3 outline

- `AmbientController` (observable, injectable clock): last input time, alarm flag, enabled + delay (default 300 s) from `UserDefaults`; tests for eligibility.
- Settings: toggle and delay picker (1, 3, 5, 10, 15 min).
- `AmbientView`: full-screen newest frame, glass strip (target · sequence · alarm · LIVE + time), 0.6 s cross-fade, strip offset changes every 3 min by ±8 pt.
- `UIApplication.shared.isIdleTimerDisabled = true` only while ambient mode is enabled and the app is active; restored on disable and background.
