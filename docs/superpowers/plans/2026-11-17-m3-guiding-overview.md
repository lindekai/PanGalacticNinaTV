# M3 Part 1: Guiding Chart and Meridian Tile – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the overview's Guiding tile with a Meridian tile and add a guiding chart (RA/Dec curves, traffic-light total RMS) below the tile row.

**Architecture:** Decoding and all derivations live in `PanGalacticCore` (pure, tested): the equipment summary gains guider RMS/pixel scale and the mount's time to flip; a new `NINAGuiderGraph` decodes `/equipment/guider/graph`; `GuidingChartModel`, `RMSGrade` and `MeridianFlipDisplay` derive what the views show. `InstanceConnection` polls the graph while the guider is connected. SwiftUI views only render.

**Tech Stack:** Swift 6, SwiftUI (`Canvas`), Swift Testing, tvOS 26; Python 3 demo server.

Spec: [`docs/superpowers/specs/2026-11-17-m3-guiding-overview-design.md`](../specs/2026-11-17-m3-guiding-overview-design.md)

## Global Constraints

- No new endpoint; only `.guiderGraph` and `.equipmentInfo` (allowlisted, ADR 0001). Nothing sent to PHD2 or on the WebSocket.
- Total RMS from `/equipment/info` `Guider.RMSError`; N.I.N.A.'s numbers unchanged (population standard deviation).
- Grades: total < 1″ good (`accent`), 1″–2″ fair (`warn`, 1.00 and 2.00 included), > 2″ poor (`fault`); pixels → no grade.
- Total, RA and Dec only while the guider state is `Guiding`; otherwise "—" and curves dimmed to `text3`.
- Y range symmetric, at least ±2, grows to ceil(max |value|), at most ±8; values beyond are clipped. Gridlines ±1, ±2.
- Meridian: `nil` when mount not connected, not tracking, value missing/NaN, or value ≥ 24 (N.I.N.A.: 24 = not applicable).
- Total in the chart header has the same font as RA/Dec; the value is coloured, not a dot.
- Strings EN + DE in `App/Resources/Localizable.xcstrings` (format `": "`, keys sorted case-insensitively, no trailing newline). Revert Xcode's own xcstrings rewrites.
- Commands need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

### Task 1: Summary fields and meridian flip display

**Files:**
- Modify: `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/NINAEquipmentSummary.swift`
- Create: `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/MeridianFlipDisplay.swift`
- Test: `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/GuidingOverviewTests.swift`

**Interfaces:**
- Produces: `NINAEquipmentSummary.Guider.rmsError: NINAGuiderInfo.RMSError?`, `.pixelScale: GuideImageScale?`; `NINAEquipmentSummary.Mount.timeToMeridianFlipHours: Double?`; `MeridianFlipDisplay(mount:now:)` with `wholeMinutes: Int`, `flipAt: Date`.

- [ ] **Step 1: Tests** (decode from JSON snippets; Mount/Guider are built through the decoder)

```swift
import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Guiding overview")
struct GuidingOverviewTests {
    static func summary(_ json: String) throws -> NINAEquipmentSummary {
        try JSONDecoder().decode(NINAEquipmentSummary.self, from: Data(json.utf8))
    }

    static func mount(tracking: Bool = true, flip: String) throws -> NINAEquipmentSummary.Mount? {
        try summary(#"{"Mount": {"Connected": true, "TrackingEnabled": \#(tracking), "TimeToMeridianFlip": \#(flip)}}"#).mount
    }

    @Test func guiderCarriesRMSAndScale() throws {
        let s = try Self.summary(#"""
        {"Guider": {"Connected": true, "State": "Guiding", "PixelScale": 0.773494,
          "RMSError": {"Total": {"Pixel": 3.03, "Arcseconds": 2.34}, "RA": {"Pixel": 0.18, "Arcseconds": 0.14},
                       "Dec": {"Pixel": 3.02, "Arcseconds": 2.34}}}}
        """#)
        #expect(s.guider?.rmsError?.total?.pixels == 3.03)
        #expect(s.guider?.pixelScale?.arcsecondsPerPixel == 0.773494)
    }

    @Test func meridianFlipFromMount() throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let display = try #require(MeridianFlipDisplay(mount: try Self.mount(flip: "2.35"), now: now))
        #expect(display.wholeMinutes == 141)
        #expect(display.flipAt == now.addingTimeInterval(141 * 60))
    }

    @Test func noMeridianFlipWhenNotApplicable() throws {
        let now = Date()
        #expect(MeridianFlipDisplay(mount: try Self.mount(flip: "24"), now: now) == nil, "24 = not applicable")
        #expect(MeridianFlipDisplay(mount: try Self.mount(flip: #""NaN""#), now: now) == nil)
        #expect(MeridianFlipDisplay(mount: try Self.mount(tracking: false, flip: "2.35"), now: now) == nil)
        #expect(MeridianFlipDisplay(mount: nil, now: now) == nil)
    }
}
```

- [ ] **Step 2: Run** `cd Packages/PanGalacticCore && swift test --filter GuidingOverviewTests` → fails (unknown members).

- [ ] **Step 3: Implement.** In `NINAEquipmentSummary`: add `timeToMeridianFlipHours` to `Mount`, `rmsError` and `pixelScale` to `Guider`, field keys `rmsError = "RMSError"`, `pixelScale = "PixelScale"`, `timeToMeridianFlip = "TimeToMeridianFlip"`, and decode:

```swift
// Mount(...)
timeToMeridianFlipHours: dev.connected ? d.lenientDouble(.timeToMeridianFlip) : nil
// Guider(...)
Guider(device: dev, state: try? d.decodeIfPresent(String.self, forKey: .state),
       rmsError: dev.connected ? (try? d.decodeIfPresent(NINAGuiderInfo.RMSError.self, forKey: .rmsError)) ?? nil : nil,
       pixelScale: d.lenientDouble(.pixelScale).flatMap(GuideImageScale.init(arcsecondsPerPixel:)))
```

`MeridianFlipDisplay.swift`:

```swift
import Foundation

/// Time until the meridian flip as N.I.N.A. computes it (`Mount.TimeToMeridianFlip`, hours).
public struct MeridianFlipDisplay: Hashable, Sendable {
    /// Remaining time, rounded to whole minutes.
    public let wholeMinutes: Int
    /// Approximate local time of the flip (now + remaining).
    public let flipAt: Date

    /// `nil` when no flip applies: mount disconnected or not tracking, value missing or
    /// `NaN`, or N.I.N.A.'s "not applicable" value 24 (returned when not tracking).
    public init?(mount: NINAEquipmentSummary.Mount?, now: Date) {
        guard let mount, mount.device.connected, mount.trackingEnabled == true,
              let hours = mount.timeToMeridianFlipHours, hours >= 0, hours < 24 else { return nil }
        wholeMinutes = Int((hours * 60).rounded())
        flipAt = now.addingTimeInterval(TimeInterval(wholeMinutes * 60))
    }
}
```

- [ ] **Step 4: Run** the filter again → pass; then full `swift test` → pass.
- [ ] **Step 5: Commit** "Core: guider RMS, pixel scale and time to meridian flip from /equipment/info".

### Task 2: Guider graph decoder

**Files:**
- Create: `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/NINAGuiderGraph.swift`
- Create: `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/Fixtures/nina/guider-graph-guiding.json` (copy of `captures/20261115-232324-rest-running-1/equipment_guider_graph.json`; numbers only, no host data)
- Test: `GuidingOverviewTests.swift`

**Interfaces:**
- Produces: `NINAGuiderGraph { steps: [Step]; pixelScale: GuideImageScale?; changeId: Int? }`, `Step { id: Int; raPixels: Double; decPixels: Double; isDither: Bool }`.

- [ ] **Step 1: Tests**

```swift
@Test func decodesGuidingGraph() throws {
    let envelope = try JSONDecoder().decode(NINAEnvelope<NINAGuiderGraph>.self,
                                            from: LiveFixtureTests.fixture("nina/guider-graph-guiding.json"))
    let graph = try #require(envelope.response)
    #expect(graph.steps.count == 101)
    #expect(graph.steps.filter(\.isDither).map(\.id) == [112])
    #expect(graph.steps.first == .init(id: 90, raPixels: -0.336, decPixels: -0.446, isDither: false))
    #expect(graph.pixelScale?.arcsecondsPerPixel == 0.773494)
    #expect(graph.changeId == 193)
}

@Test func decodesIdleGraph() throws {
    let envelope = try JSONDecoder().decode(NINAEnvelope<NINAGuiderGraph>.self,
                                            from: LiveFixtureTests.fixture("nina/guider-graph-idle.json"))
    #expect(try #require(envelope.response).steps.isEmpty)
}
```

- [ ] **Step 2: Run** → fails.
- [ ] **Step 3: Implement**

```swift
import Foundation

/// `GET /equipment/guider/graph`: N.I.N.A.'s guide graph history, serialised unchanged by
/// plugin 2.2.15.3 (`GuideStepsHistory`). Distances are guide-camera pixels; the history is
/// cleared only when the guider connects or the user clears the graph, not when guiding stops.
public struct NINAGuiderGraph: Decodable, Hashable, Sendable {
    public struct Step: Hashable, Sendable {
        public let id: Int
        public let raPixels: Double
        public let decPixels: Double
        /// N.I.N.A. inserts a marker step (distances 0, `Dither` 0.01) when it dithers.
        public let isDither: Bool

        public init(id: Int, raPixels: Double, decPixels: Double, isDither: Bool) {
            self.id = id
            self.raPixels = raPixels
            self.decPixels = decPixels
            self.isDither = isDither
        }
    }

    /// Oldest first.
    public let steps: [Step]
    public let pixelScale: GuideImageScale?
    public let changeId: Int?

    enum Keys: String, CodingKey { case steps = "GuideSteps", pixelScale = "PixelScale", changeId = "ChangeId" }
    enum StepKeys: String, CodingKey { case id = "Id", ra = "RADistanceRaw", dec = "DECDistanceRaw", dither = "Dither" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        var list = (try? c.nestedUnkeyedContainer(forKey: .steps))
        var steps: [Step] = []
        while var items = list, !items.isAtEnd {
            if let s = try? items.nestedContainer(keyedBy: StepKeys.self),
               let id = s.lenientInt(.id), let ra = s.lenientDouble(.ra), let dec = s.lenientDouble(.dec) {
                // Guide steps carry "NaN" (a string); dither markers a number.
                steps.append(Step(id: id, raPixels: ra, decPixels: dec, isDither: s.lenientDouble(.dither) != nil))
            } else {
                _ = try? items.decode(JSONValue.self) // skip a malformed entry
            }
            list = items
        }
        self.steps = steps
        pixelScale = c.lenientDouble(.pixelScale).flatMap(GuideImageScale.init(arcsecondsPerPixel:))
        changeId = c.lenientInt(.changeId)
    }
}
```

- [ ] **Step 4: Run** → pass. **Step 5: Commit** "Core: decode /equipment/guider/graph".

### Task 3: Chart model and RMS grade

**Files:**
- Create: `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/GuidingChartModel.swift`
- Test: `GuidingOverviewTests.swift`

**Interfaces:**
- Consumes: Task 1 summary fields, Task 2 `NINAGuiderGraph`, existing `GuideValue`, `GuideUnit`, `PHD2AppState`.
- Produces: `RMSGrade { good, fair, poor; init(arcseconds:) }`; `GuidingChartModel(guider:graph:)` with `isGuiding`, `unit`, `total/ra/dec: GuideValue?`, `grade: RMSGrade?`, `points: [Point]` (`position` 0…1, `ra`, `dec` in unit, clipped), `ditherPositions: [Double]`, `range: Double`, `static gridlines`.

- [ ] **Step 1: Tests**

```swift
static func guider(state: String = "Guiding", total: Double = 0.7, scale: String = "0.773494") throws -> NINAEquipmentSummary.Guider? {
    try summary(#"""
    {"Guider": {"Connected": true, "State": "\#(state)", "PixelScale": \#(scale),
      "RMSError": {"Total": {"Pixel": \#(total)}, "RA": {"Pixel": 0.5}, "Dec": {"Pixel": 0.4}}}}
    """#).guider
}

static func graph(_ steps: [(Double, Double, Bool)]) -> String { … builds GuideSteps JSON … }

@Test(arguments: [(0.99, RMSGrade.good), (1.0, .fair), (2.0, .fair), (2.01, .poor)])
func grades(arcseconds: Double, grade: RMSGrade) { #expect(RMSGrade(arcseconds: arcseconds) == grade) }

@Test func totalInArcsecondsWithGrade() throws {
    let model = GuidingChartModel(guider: try Self.guider(total: 1.0), graph: nil)
    #expect(model.total?.unit == .arcseconds)
    #expect(model.grade == .good) // 1.0 px × 0.773 = 0.77″
}

@Test func pixelsHaveNoGrade() throws {
    let model = GuidingChartModel(guider: try Self.guider(scale: "0"), graph: nil)
    #expect(model.total?.unit == .pixels)
    #expect(model.grade == nil)
}

@Test func noTotalWhileNotGuiding() throws {
    let model = GuidingChartModel(guider: try Self.guider(state: "Stopped"), graph: nil)
    #expect(model.total == nil && model.ra == nil && model.dec == nil && !model.isGuiding)
}

@Test func rangeGrowsAndClips() throws { /* steps 1 px, 12 px with scale 1 → range 8, clipped 8 */ }
@Test func ditherIsAMarkerNotAPoint() throws { /* 3 steps, middle dither → 2 points, ditherPositions [0.5] */ }
@Test func fixtureRange() throws { /* guiding fixture: |Dec| up to ~5.3″ → range 6 */ }
```

(Write the elided bodies in full when implementing; the expectations are stated in the comments.)

- [ ] **Step 2: Run** → fails.
- [ ] **Step 3: Implement**

```swift
import Foundation

/// Traffic-light grade of the total guide error (owner's thresholds, 2026-11-17).
public enum RMSGrade: Hashable, Sendable {
    case good, fair, poor

    /// < 1″ good, 1″–2″ fair (both ends included), > 2″ poor.
    public init(arcseconds: Double) {
        self = arcseconds < 1 ? .good : arcseconds <= 2 ? .fair : .poor
    }
}

/// What the overview's guiding chart shows, derived from `/equipment/info` (state, RMS)
/// and `/equipment/guider/graph` (curves). N.I.N.A.'s RMS figures are used unchanged.
public struct GuidingChartModel: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        /// 0 (oldest) … 1 (newest), over all history entries incl. dither markers.
        public let position: Double
        public let ra: Double
        public let dec: Double
    }

    public static let minimumRange: Double = 2
    public static let maximumRange: Double = 8
    public static let gridlines: [Double] = [-2, -1, 1, 2]

    public let isGuiding: Bool
    public let unit: GuideUnit
    /// Only while guiding: after a stop N.I.N.A. keeps the old RMS.
    public let total: GuideValue?
    public let ra: GuideValue?
    public let dec: GuideValue?
    public let points: [Point]
    public let ditherPositions: [Double]
    /// Symmetric half-range of the y axis, in `unit`.
    public let range: Double

    public var grade: RMSGrade? {
        guard let total, total.unit == .arcseconds else { return nil }
        return RMSGrade(arcseconds: total.value)
    }

    public init(guider: NINAEquipmentSummary.Guider?, graph: NINAGuiderGraph?) {
        let connected = guider?.device.connected == true
        isGuiding = connected && guider?.state.map { PHD2AppState(wire: $0) } == .guiding
        let scale = guider?.pixelScale ?? graph?.pixelScale
        unit = scale == nil ? .pixels : .arcseconds
        let rms = isGuiding ? guider?.rmsError : nil
        func value(_ v: NINAGuiderInfo.ErrorValue?) -> GuideValue? {
            v?.pixels.map { GuideValue.from(pixels: $0, scale: scale) }
        }
        total = value(rms?.total)
        ra = value(rms?.ra)
        dec = value(rms?.dec)

        let steps = connected ? graph?.steps ?? [] : []
        let factor = scale?.arcsecondsPerPixel ?? 1
        let span = Double(max(steps.count - 1, 1))
        let largest = steps.filter { !$0.isDither }
            .map { max(abs($0.raPixels), abs($0.decPixels)) * factor }.max() ?? 0
        range = min(Self.maximumRange, max(Self.minimumRange, largest.rounded(.up)))
        let clip = { (v: Double) in min(max(v, -range), range) }
        var points: [Point] = []
        var dithers: [Double] = []
        for (i, step) in steps.enumerated() {
            let position = steps.count == 1 ? 1 : Double(i) / span
            if step.isDither { dithers.append(position); continue }
            points.append(Point(position: position, ra: clip(step.raPixels * factor), dec: clip(step.decPixels * factor)))
        }
        self.points = points
        ditherPositions = dithers
    }
}
```

- [ ] **Step 4: Run** → pass. **Step 5: Commit** "Core: guiding chart model and RMS grade".

### Task 4: Poll the graph

**Files:**
- Modify: `Packages/PanGalacticCore/Sources/PanGalacticServices/Connection/InstanceConnection.swift`
- Test: `Packages/PanGalacticCore/Tests/PanGalacticServicesTests/ServicesTests.swift` (follow the existing fake-transport tests there)

- [ ] **Step 1: Tests:** guider connected → one `/equipment/guider/graph` request per poll and `guiderGraph` set; guider disconnected → no request, `guiderGraph == nil`; graph request fails → `guiderGraphFailed == true`, poll still succeeds (phase live).
- [ ] **Step 2: Run** → fails.
- [ ] **Step 3: Implement**

```swift
/// N.I.N.A.'s guide graph while the guider is connected; kept while stale, never invented.
public private(set) var guiderGraph: NINAGuiderGraph?
/// The last graph request failed (the plugin reads it via reflection, which a N.I.N.A.
/// update can break); the chart then says so instead of showing nothing.
public private(set) var guiderGraphFailed = false

/// About 25 KB with 100 steps; only while a guider is connected.
private func pollGuiderGraph() async {
    guard equipment?.guider?.device.connected == true else {
        guiderGraph = nil
        guiderGraphFailed = false
        return
    }
    do {
        guiderGraph = try await client.get(.guiderGraph, as: NINAGuiderGraph.self)
        guiderGraphFailed = false
    } catch {
        guiderGraph = nil
        guiderGraphFailed = true
    }
}
```

Call `await pollGuiderGraph()` in `pollOnce()` right after `refreshPhase()`, before `pollSequence`.

- [ ] **Step 4: Run** `swift test` → pass. **Step 5: Commit** "Services: poll the guider graph while a guider is connected".

### Task 5: Views

**Files:**
- Create: `App/Views/GuidingChartPanel.swift`
- Modify: `App/Views/DashboardView.swift` (replace `GuidingTile` with `MeridianTile`, add the chart below the tile row), `App/Design/Theme.swift` (`guidingTileWidth` → `meridianTileWidth`), `App/Design/Formatters.swift` (`guideValue`, `flipRemaining`), `App/Resources/Localizable.xcstrings`

- [ ] **Step 1: Formatters**

```swift
/// `0.55″` or `0.71 px`.
static func guideValue(_ value: GuideValue) -> String {
    let number = value.value.formatted(.number.precision(.fractionLength(2)))
    return value.unit == .arcseconds ? number + "″" : number + " px"
}

/// `2:21` (hours:minutes) for the meridian tile.
static func flipRemaining(_ minutes: Int) -> String {
    String(format: "%d:%02d", minutes / 60, minutes % 60)
}
```

and in `Theme`: `static func grade(_ grade: RMSGrade?) -> Color` → `accent` / `warn` / `fault`, `text` for nil.

- [ ] **Step 2: `MeridianTile`** (in `DashboardView.swift`, next to `MountTile`): `ModulePanel("Meridian", icon: Image(systemName: "globe"), light: nil, fillHeight: true)`; content: key value `Format.flipRemaining` + " h" in `pgKeyUnit`-style smaller text, detail row `HStack { Text("until flip"); Spacer(); Text(flip time, format: .dateTime.hour().minute()).font(.pgCaption-ish 18).foregroundStyle(Theme.text3) }`; "—" via `TileValue(nil, detail: nil)` when `MeridianFlipDisplay` is nil. Uses `TimelineView`'s `now` passed from `overview(now:)`.

- [ ] **Step 3: `GuidingChartPanel`**: compact header (`HStack`: `target` icon, "GUIDING" rubric tracking 2.5, `StatusLED`, state via `Format.guiderState`, `Spacer`, `Text("Total")` + coloured total, RA/Dec legend dots + values; all `.pgLabel`); `Canvas` plot: zero line `Theme.line`, dashed gridlines with labels `+1″`/`−1″` (only ±1 labelled), dither lines `Theme.text3`, Dec then RA paths (`#E58A6F`, `#6CB4EE`; `Theme.text3` when not guiding). States: not connected → header with "Not connected", no plot; `points.isEmpty` → centred "No guide steps yet"; `connection.guiderGraphFailed` → "Guiding chart not available". Minimum plot height 64.

- [ ] **Step 4: Layout:** in `overview(now:)` the module `VStack` gets `GuidingChartPanel(model: GuidingChartModel(guider: equipment?.guider, graph: connection.guiderGraph), guider: equipment?.guider, graphFailed: connection.guiderGraphFailed, light: …)` after the tile row, with `.frame(maxHeight: .infinity)` so it fills to the image bottom.

- [ ] **Step 5: Strings (EN → DE):** "Meridian" → "Meridian", "until flip" → "bis zum Flip", "Total" → "Gesamt", "No guide steps yet" → "Noch keine Guide-Schritte", "Guiding chart not available" → "Guiding-Verlauf nicht verfügbar", "Not connected" (exists). Remove "RMS not available yet".

- [ ] **Step 6: Build** the app for the simulator; **commit** "Overview: guiding chart and meridian tile".

### Task 6: Demo server, docs, verification

**Files:** `tools/demo/demo_server.py`, `docs/api-capability-matrix.md`, `docs/milestones.md`, `docs/status.md`, `CHANGELOG.md`, `README.md`, `docs/assets/screenshots/overview.jpg`, issue #6 comment.

- [ ] Demo server: `/equipment/guider/graph` with 100 seeded random-walk steps (RA σ≈0.5 px, Dec σ≈0.4 px at 3.87″/px… scaled so total ≈ 0.55″) and one dither marker; `Guider.RMSError` consistent with it; `Mount.TimeToMeridianFlip` stays 2.35.
- [ ] Capability matrix: section "Guider graph and meridian flip (source review, 2026-11-17)" with the facts from the spec; mark `guider/graph` as used by the app.
- [ ] Changelog (Added M3), milestones (M3 checklist part 1), status, README overview text + new screenshot.
- [ ] Verify: `swift test`, app build, simulator screenshots with the demo server (guiding, not guiding, pixels), then live against the owner's N.I.N.A. if reachable.
- [ ] Comment on #6: N.I.N.A.'s RMS definition answered from source; PHD2 stream part remains.
- [ ] PR to `main`.
