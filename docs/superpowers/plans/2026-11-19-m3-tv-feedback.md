# M3 TV Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sequence strip on the overview, a sequence tree page, the app version in Settings, a filter wheel icon and smaller margins – as specified in [the spec](../specs/2026-11-19-m3-tv-feedback-design.md).

**Architecture:** A pure domain model `SequenceTree` (Core) is built from the `/sequence/json` response that `InstanceConnection` already fetches every 15 s; a pure function `SequenceSteps` derives last/current/next. SwiftUI views (`SequenceStrip`, `SequenceView`) only read these values. No new endpoint.

**Tech Stack:** Swift 6, SwiftUI (tvOS 26), Swift Testing, Swift package `PanGalacticCore` (targets `PanGalacticCore`, `PanGalacticServices`), Python 3 tooling (`tools/m0`, `tools/demo`).

## Global Constraints

- Read-only: no endpoint outside `docs/api-capability-matrix.md` §3; no sequence control of any kind (ADR 0001, AGENTS.md).
- No real IP addresses, hostnames, site coordinates, file paths or Windows user names in commits or fixtures. Raw captures stay in `captures/` (git-ignored).
- `unknown`, `unavailable` and `stale` stay distinct from zero/false; a node missing from the tree is never "done".
- Wire DTOs separate from domain models; presentation never sees a mutating API.
- User-facing strings localized in `App/Resources/Localizable.xcstrings` (en source, de translation). N.I.N.A.'s step names are shown as sent, never translated.
- Margins: `Theme.margin` = 56, `Theme.marginVertical` = 36.
- Strip: full width, 62 px high, `Theme.surface`, `Theme.radius`; rubric `SEQUENCE`; ✓ last (`text2`), current with green LED (`text`), "Next:" (`text3`) + next (`text2`).
- Version text: "Version 0.1.0 (6)" from `CFBundleShortVersionString` and `CFBundleVersion`.
- Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_018pUwQWsnrgoakVNdTaya8P
  ```
- Build and test commands (AGENTS.md):
  - `cd Packages/PanGalacticCore && swift test`
  - `xcodebuild -project PanGalacticNinaTV.xcodeproj -scheme PanGalacticNinaTV -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build`
- After any Xcode build, check `git diff --stat App/Resources/Localizable.xcstrings`: Xcode may reformat the catalog and mark keys `stale`. Only commit intended string additions; otherwise `git restore` the file and add the strings by hand.

---

## File Structure

| File | Responsibility |
|---|---|
| `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/SequenceTree.swift` (new) | Domain tree from `/sequence/json`: nodes, status, display-safe details |
| `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/SequenceSteps.swift` (new) | Last/current/next instruction, expanded-by-default ids |
| `Packages/PanGalacticCore/Sources/PanGalacticServices/Connection/InstanceConnection.swift` | Keep the decoded `sequenceTree` next to `sequence` |
| `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/SequenceTreeTests.swift` (new) | Decoder tests on fixtures and inline JSON |
| `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/SequenceStepsTests.swift` (new) | Step derivation tests |
| `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/Fixtures/nina/sequence-json-live-*.json` (new) | Sanitised captures of 2026-11-19 |
| `App/Design/Theme.swift` | Margins |
| `App/Views/SequenceStrip.swift` (new) | Strip on the overview |
| `App/Views/SequenceView.swift` (new) | Tree page |
| `App/Views/DashboardView.swift` | Strip placement, focus sections, Mount tile width, filter icon |
| `App/Views/RootView.swift` | `Destination.sequence` |
| `App/Views/SettingsView.swift` | Version line |
| `App/Resources/Assets.xcassets/FilterWheel.imageset/*` (new) | Filter wheel symbol |
| `App/Resources/Localizable.xcstrings` | New strings (en, de) |
| `PanGalacticNinaTV.xcodeproj/project.pbxproj` | `CURRENT_PROJECT_VERSION = 6` |
| Docs | matrix, changelog, README, status, milestones |

---

### Task 1: Live fixtures for the sequence tree

**Files:**
- Create: `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/Fixtures/nina/sequence-json-live-exposing.json`
- Create: `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/Fixtures/nina/sequence-json-live-between.json`

**Interfaces:**
- Produces: two fixture files, each a full plugin envelope `{"Response": [...], "Success": true, ...}` as written by `m0probe.py rest`.

- [ ] **Step 1: Pick the captures**

The owner's session on 2026-11-19 wrote `captures/20261119-*-rest-live-1119-*/sequence_json.json`. Find one where the exposure instruction under `Light 120 UV/IR_Container` is `RUNNING` and one where it is `CREATED` while its container is `RUNNING` (between exposures or autofocus). The first capture (`live-1119-1`) is the "between" case and also contains `Autofokus ausführen` with `FAILED`.

```bash
cd /Users/lindek/Documents/GitLocal/PanGalacticNinaTV
for f in captures/20261119-*-rest-live-1119-*/sequence_json.json; do
  python3 - "$f" <<'EOF'
import json, sys
tree = json.load(open(sys.argv[1]))["Response"]
def walk(x):
    if isinstance(x, dict):
        if x.get("Name") == "Belichtung ausführen" and x.get("Type") == "LIGHT":
            print(sys.argv[1], x.get("Status"))
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for v in x: walk(v)
walk(tree)
EOF
done
```

Expected: at least one `RUNNING` and one `CREATED` line. If no `RUNNING` exists, take another snapshot while the owner's sequence exposes: `python3 tools/m0/m0probe.py rest --host <HOST> --skip-tier-b --label live-1119-x` (host from the session, never committed).

- [ ] **Step 2: Sanitise**

```bash
python3 tools/m0/m0probe.py sanitize captures/<exposing-run> captures/sanitized/<exposing-run>
python3 tools/m0/m0probe.py sanitize captures/<between-run> captures/sanitized/<between-run>
cp captures/sanitized/<exposing-run>/sequence_json.json Packages/PanGalacticCore/Tests/PanGalacticCoreTests/Fixtures/nina/sequence-json-live-exposing.json
cp captures/sanitized/<between-run>/sequence_json.json Packages/PanGalacticCore/Tests/PanGalacticCoreTests/Fixtures/nina/sequence-json-live-between.json
```

- [ ] **Step 3: Review by hand**

```bash
cd Packages/PanGalacticCore/Tests/PanGalacticCoreTests/Fixtures/nina
grep -n -i -E 'latitude|longitude|elevation|\\\\|[A-Z]:\\|192\.168|users|lindek' sequence-json-live-*.json
```

Expected: no output except redaction placeholders (`<redacted>`, `<path>`, `0`). Also read both files once for anything personal (Pushover keys, user names in names). Owner accepted parked-mount altitude in fixtures; site coordinates are not accepted.

- [ ] **Step 4: Commit**

```bash
git add Packages/PanGalacticCore/Tests/PanGalacticCoreTests/Fixtures/nina/sequence-json-live-*.json
git commit -m "Fixtures: running sequence trees of 2026-11-19 (exposing, between exposures)"
```

---

### Task 2: `SequenceTree` domain model

**Files:**
- Create: `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/SequenceTree.swift`
- Test: `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/SequenceTreeTests.swift`

**Interfaces:**
- Consumes: `JSONValue` (`subscript(String)`, `.array`, `.string`, `.int`, `.double`), `NINADate.parse(_:)`, fixtures from Task 1.
- Produces:
  ```swift
  public struct SequenceTree: Equatable, Sendable {
      public struct Node: Equatable, Sendable, Identifiable {
          public enum Status: Equatable, Sendable { case created, running, finished, failed, skipped, disabled, unknown(String?) }
          public let id: [Int]
          public let name: String
          public let status: Status
          public let children: [Node]?
          public let details: [Detail]
          public var isContainer: Bool { get }
      }
      public enum Detail: Equatable, Sendable {
          case untilTime(Date)
          case iterations(completed: Int, total: Int)
          case ditherEvery(done: Int, target: Int)
          case exposure(seconds: Double, type: String?, gain: Int?)
          case temperature(celsius: Double)
          case filter(String)
          case trigger(String)
          case condition(String)
      }
      public let roots: [Node]
      public init?(json: JSONValue)
      public func node(at id: [Int]) -> Node?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import PanGalacticCore

/// `/sequence/json` as the domain tree. Fixtures: owner's captures of 2026-11-15
/// (Coma Cluster) and 2026-11-19 (M 31, telescope indoors).
@Suite("Sequence tree")
struct SequenceTreeTests {
    static func tree(_ name: String) throws -> SequenceTree {
        try #require(SequenceTree(json: try SequenceProgressTests.tree(name)))
    }

    static func tree(json: String) throws -> SequenceTree? {
        SequenceTree(json: try SequenceProgressTests.decode(json))
    }

    @Test func decodesTopLevelContainersWithoutGlobalTriggers() throws {
        let tree = try Self.tree("sequence-json-running-1")
        #expect(tree.roots.map(\.name) == ["Start", "Ziele", "Ende"])
        #expect(tree.roots.map(\.status) == [.finished, .running, .created])
        #expect(tree.roots[0].id == [1], "ids are wire offsets; GlobalTriggers is element 0")
    }

    @Test func stripsPluginSuffixes() throws {
        let tree = try #require(try Self.tree(json: #"""
            [{"GlobalTriggers":[]},
             {"Name":"Lights_Container","Status":"RUNNING","Items":[
                {"Name":"_Container","Status":"CREATED","Items":[]}],
              "Conditions":[{"Name":"Loop_Condition","Status":"CREATED"}],
              "Triggers":[{"Name":"Center after drift_Trigger","Status":"CREATED"}]}]
            """#))
        let lights = tree.roots[0]
        #expect(lights.name == "Lights")
        #expect(lights.children?.first?.name == "")
        #expect(lights.details == [.condition("Loop"), .trigger("Center after drift")])
    }

    @Test func instructionsHaveNoChildren() throws {
        let tree = try Self.tree("sequence-json-running-1")
        let exposure = try #require(tree.node(at: [2, 0, 1, 0]))
        #expect(exposure.name == "Belichtung ausführen")
        #expect(exposure.children == nil)
        #expect(!exposure.isContainer)
        #expect(exposure.status == .running)
        #expect(exposure.details == [.exposure(seconds: 120, type: "LIGHT", gain: 100)])
    }

    @Test func containerDetailsFromConditionsAndTriggers() throws {
        let tree = try Self.tree("sequence-json-running-1")
        let lights = try #require(tree.node(at: [2, 0, 1]))
        #expect(lights.name == "Light 120 UV/IR")
        let end = try #require(NINADate.parse("2026-11-16T05:00:36.9999968+01:00"))
        #expect(lights.details.first == .untilTime(end))
        #expect(lights.details.contains(.ditherEvery(done: 2, target: 3)))
        #expect(lights.details.contains(.trigger("Nach Drift zentrieren")))
    }

    @Test func instructionDetails() throws {
        let tree = try #require(try Self.tree(json: #"""
            [{"Name":"C","Status":"CREATED","Items":[
                {"Name":"Cool","Status":"CREATED","Temperature":-10,"MinCoolingTime":2},
                {"Name":"Switch Filter","Status":"CREATED","Filter":"UV/IR"},
                {"Name":"Exposure","Status":"CREATED","ExposureTime":1.06356,"Type":"FLAT","Gain":-1},
                {"Name":"Wait","Status":"CREATED","TargetTime":"2026-11-19T20:18:23.0851325+01:00"},
                {"Name":"Save","Status":"CREATED","FilePath":"C:\\Users\\x\\seq.json"}]}]
            """#))
        let items = try #require(tree.roots[0].children)
        #expect(items[0].details == [.temperature(celsius: -10)])
        #expect(items[1].details == [.filter("UV/IR")])
        #expect(items[2].details == [.exposure(seconds: 1.06356, type: "FLAT", gain: nil)], "gain -1 = camera default")
        #expect(items[3].details == [.untilTime(try #require(NINADate.parse("2026-11-19T20:18:23.0851325+01:00")))])
        #expect(items[4].details.isEmpty, "file paths never enter the model")
    }

    @Test func loopConditionCounts() throws {
        let tree = try #require(try Self.tree(json: #"""
            [{"Name":"Flats","Status":"CREATED","Items":[],
              "Conditions":[{"Name":"Loop_Condition","Status":"CREATED","Iterations":50,"CompletedIterations":3}]}]
            """#))
        #expect(tree.roots[0].details == [.iterations(completed: 3, total: 50)])
    }

    @Test func statusMapping() throws {
        let tree = try #require(try Self.tree(json: #"""
            [{"Name":"C","Status":"RUNNING","Items":[
                {"Name":"a","Status":"FINISHED"},{"Name":"b","Status":"FAILED"},{"Name":"c","Status":"SKIPPED"},
                {"Name":"d","Status":"DISABLED"},{"Name":"e","Status":"PAUSED"},{"Name":"f"}]}]
            """#))
        #expect(tree.roots[0].children?.map(\.status) == [.finished, .failed, .skipped, .disabled, .unknown("PAUSED"), .unknown(nil)])
    }

    @Test func undecodableTrees() throws {
        #expect(try Self.tree(json: #"{"Name":"x"}"#) == nil, "not an array")
        #expect(try Self.tree(json: #"[{"GlobalTriggers":[]}]"#) == nil, "no containers")
    }

    @Test func nodesWithoutANameAreDropped() throws {
        let tree = try #require(try Self.tree(json: #"""
            [{"Name":"C","Status":"RUNNING","Items":[{"Status":"FINISHED"},{"Name":"b","Status":"CREATED"}]}]
            """#))
        #expect(tree.roots[0].children?.map(\.name) == ["b"])
        #expect(tree.roots[0].children?.first?.id == [0, 1], "ids keep the wire index")
    }

    @Test func liveCapturesDecode() throws {
        for name in ["sequence-json-live-exposing", "sequence-json-live-between", "sequence-json-running-2", "sequence-json-idle"] {
            let tree = try Self.tree(name)
            #expect(!tree.roots.isEmpty, "\(name)")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/PanGalacticCore && swift test --filter SequenceTreeTests`
Expected: compile error "cannot find 'SequenceTree' in scope".

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The Advanced Sequence as a tree, from `/sequence/json` (plugin 2.2.15.3,
/// N.I.N.A. 3.2; docs/api-capability-matrix.md §7):
///
/// - The response is an array: `{"GlobalTriggers": [...]}` first, then the
///   top-level containers. A node with `Items` is a container.
/// - The plugin appends `_Container`, `_Condition` and `_Trigger` to names.
/// - The plugin reads the live tree without a lock and drops nodes that throw,
///   so a missing node is unknown, never done.
/// - Only display-safe fields are read: never coordinates or file paths.
public struct SequenceTree: Equatable, Sendable {
    public struct Node: Equatable, Sendable, Identifiable {
        public enum Status: Equatable, Sendable {
            case created, running, finished, failed, skipped, disabled
            case unknown(String?)

            init(_ raw: String?) {
                switch raw {
                case "CREATED": self = .created
                case "RUNNING": self = .running
                case "FINISHED": self = .finished
                case "FAILED": self = .failed
                case "SKIPPED": self = .skipped
                case "DISABLED": self = .disabled
                default: self = .unknown(raw)
                }
            }
        }

        /// Index path from the root as sent by the plugin; stable while the tree keeps its shape.
        public let id: [Int]
        public let name: String
        public let status: Status
        /// `nil` for an instruction, the (possibly empty) items for a container.
        public let children: [Node]?
        public let details: [Detail]

        public var isContainer: Bool { children != nil }
    }

    public enum Detail: Equatable, Sendable {
        case untilTime(Date)
        case iterations(completed: Int, total: Int)
        case ditherEvery(done: Int, target: Int)
        case exposure(seconds: Double, type: String?, gain: Int?)
        case temperature(celsius: Double)
        case filter(String)
        case trigger(String)
        case condition(String)
    }

    public let roots: [Node]

    public init?(json: JSONValue) {
        guard let items = json.array else { return nil }
        let roots = items.enumerated().compactMap { Self.node($0.element, id: [$0.offset]) }
        guard !roots.isEmpty else { return nil }
        self.roots = roots
    }

    public func node(at id: [Int]) -> Node? {
        var nodes = roots
        var found: Node?
        for index in id {
            guard let next = nodes.first(where: { $0.id.last == index }) else { return nil }
            found = next
            nodes = next.children ?? []
        }
        return found
    }

    private static func node(_ value: JSONValue, id: [Int]) -> Node? {
        guard let rawName = value["Name"]?.string else { return nil }
        let items = value["Items"]?.array
        let children = items.map { items in
            items.enumerated().compactMap { node($0.element, id: id + [$0.offset]) }
        }
        var details: [Detail] = []
        if children == nil { details += instructionDetails(value) }
        for condition in value["Conditions"]?.array ?? [] { details += conditionDetails(condition) }
        for trigger in value["Triggers"]?.array ?? [] { details += triggerDetails(trigger) }
        return Node(id: id, name: strip(rawName), status: .init(value["Status"]?.string),
                    children: children, details: details)
    }

    private static func instructionDetails(_ value: JSONValue) -> [Detail] {
        if let seconds = value["ExposureTime"]?.double {
            let gain = value["Gain"]?.int.flatMap { $0 >= 0 ? $0 : nil }
            return [.exposure(seconds: seconds, type: value["Type"]?.string, gain: gain)]
        }
        if let celsius = value["Temperature"]?.double { return [.temperature(celsius: celsius)] }
        if let filter = value["Filter"]?.string, !filter.isEmpty { return [.filter(filter)] }
        if let end = value["TargetTime"]?.string.flatMap({ NINADate.parse($0) }) { return [.untilTime(end)] }
        return []
    }

    private static func conditionDetails(_ value: JSONValue) -> [Detail] {
        if let end = value["TargetTime"]?.string.flatMap({ NINADate.parse($0) }) { return [.untilTime(end)] }
        if let total = value["Iterations"]?.int, let completed = value["CompletedIterations"]?.int {
            return [.iterations(completed: completed, total: total)]
        }
        return value["Name"]?.string.map { [.condition(strip($0))] } ?? []
    }

    private static func triggerDetails(_ value: JSONValue) -> [Detail] {
        if let done = value["Exposures"]?.int, let target = value["TargetExposures"]?.int {
            return [.ditherEvery(done: done, target: target)]
        }
        return value["Name"]?.string.map { [.trigger(strip($0))] } ?? []
    }

    private static func strip(_ name: String) -> String {
        for suffix in ["_Container", "_Condition", "_Trigger"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
}
```

Note for the implementer: `Exposures`/`TargetExposures` belong to N.I.N.A.'s "Dither after exposures" trigger in the captures; if another trigger type turns out to carry the same pair, it is still shown as "Dither every n" – acceptable for now, recorded in the matrix (Task 8).

- [ ] **Step 4: Run tests**

Run: `cd Packages/PanGalacticCore && swift test --filter SequenceTreeTests`
Expected: all PASS. Ids are wire offsets by design: in `sequence-json-running-1` element 0 is `GlobalTriggers` (dropped), so `Start` is `[1]`, `Ziele` `[2]`, and Ziele → Coma Cluster → Light 120 UV/IR → Belichtung ausführen is `[2, 0, 1, 0]`.

- [ ] **Step 5: Commit**

```bash
git add Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/SequenceTree.swift Packages/PanGalacticCore/Tests/PanGalacticCoreTests/SequenceTreeTests.swift
git commit -m "Core: sequence tree from /sequence/json with display-safe details"
```

---

### Task 3: `SequenceSteps` – last, current, next

**Files:**
- Create: `Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/SequenceSteps.swift`
- Test: `Packages/PanGalacticCore/Tests/PanGalacticCoreTests/SequenceStepsTests.swift`

**Interfaces:**
- Consumes: `SequenceTree`, `SequenceTree.Node` (Task 2).
- Produces:
  ```swift
  public struct SequenceSteps: Equatable, Sendable {
      public struct Step: Equatable, Sendable {
          public let id: [Int]
          public let name: String        // instruction name
          public let container: String   // name of the parent container ("" if unnamed)
          public let status: SequenceTree.Node.Status
      }
      public let last: Step?
      public let current: Step?
      public let next: Step?
      public var isRunning: Bool { current != nil }
      public init(tree: SequenceTree)
      /// Ids of the chain of running containers (expanded by default on the page).
      public static func runningContainers(in tree: SequenceTree) -> Set<[Int]>
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Sequence steps")
struct SequenceStepsTests {
    static func steps(_ json: String) throws -> SequenceSteps {
        SequenceSteps(tree: try #require(try SequenceTreeTests.tree(json: json)))
    }

    @Test func runningInstruction() throws {
        let steps = SequenceSteps(tree: try SequenceTreeTests.tree("sequence-json-running-1"))
        #expect(steps.current?.name == "Belichtung ausführen")
        #expect(steps.current?.container == "Light 120 UV/IR")
        #expect(steps.last?.name == "Send to Pushover")
        #expect(steps.next?.name == "Stoppe Guiding")
        #expect(steps.next?.container == "Lights Ende")
    }

    @Test func betweenExposuresTheContainerKeepsTheStep() throws {
        let steps = try Self.steps(#"""
            [{"Name":"Lights","Status":"RUNNING","Items":[
                {"Name":"Filter","Status":"FINISHED"},
                {"Name":"Exposure","Status":"CREATED"}]},
             {"Name":"End","Status":"CREATED","Items":[{"Name":"Park","Status":"CREATED"}]}]
            """#)
        #expect(steps.current?.name == "Exposure")
        #expect(steps.last?.name == "Filter")
        #expect(steps.next?.name == "Park")
    }

    @Test func failedStepIsShownAsLast() throws {
        let steps = try Self.steps(#"""
            [{"Name":"Target","Status":"RUNNING","Items":[
                {"Name":"Autofocus","Status":"FAILED"},
                {"Name":"Slew","Status":"SKIPPED"},
                {"Name":"Off","Status":"DISABLED"},
                {"Name":"Exposure","Status":"RUNNING"}]}]
            """#)
        #expect(steps.last?.name == "Autofocus")
        #expect(steps.last?.status == .failed)
        #expect(steps.next == nil)
    }

    @Test func liveBetweenCapture() throws {
        let steps = SequenceSteps(tree: try SequenceTreeTests.tree("sequence-json-live-between"))
        #expect(steps.current?.name == "Belichtung ausführen")
        #expect(steps.current?.container == "Light 120 UV/IR")
        #expect(steps.next?.name == "Stoppe Guiding")
    }

    @Test func nothingRunning() throws {
        let steps = SequenceSteps(tree: try SequenceTreeTests.tree("sequence-json-idle"))
        #expect(!steps.isRunning)
        #expect(steps.last == nil && steps.next == nil)
    }

    @Test func lastInstructionOfTheSequence() throws {
        let steps = try Self.steps(#"""
            [{"Name":"End","Status":"RUNNING","Items":[
                {"Name":"Park","Status":"FINISHED"},{"Name":"Wait","Status":"RUNNING"}]}]
            """#)
        #expect(steps.current?.name == "Wait")
        #expect(steps.next == nil)
    }

    @Test func runningContainerWithoutOpenInstruction() throws {
        let steps = try Self.steps(#"""
            [{"Name":"Lights","Status":"RUNNING","Items":[{"Name":"Exposure","Status":"FINISHED"}]},
             {"Name":"End","Status":"CREATED","Items":[{"Name":"Park","Status":"CREATED"}]}]
            """#)
        #expect(steps.current == nil, "a dropped or finished item is not invented")
        #expect(!steps.isRunning)
    }

    @Test func runningContainersAreTheRunningChain() throws {
        let tree = try SequenceTreeTests.tree("sequence-json-running-1")
        let ids = SequenceSteps.runningContainers(in: tree)
        let names = ids.compactMap { tree.node(at: $0)?.name }.sorted()
        #expect(names == ["Coma Cluster", "Light 120 UV/IR", "Ziele"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/PanGalacticCore && swift test --filter SequenceStepsTests`
Expected: compile error "cannot find 'SequenceSteps' in scope".

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Last, current and next instruction of the running sequence, for the strip on
/// the overview. Between two exposures, during dithering or autofocus, N.I.N.A.
/// reports the exposure as `CREATED` while its container keeps `RUNNING`
/// (capture 2026-11-19); the first open instruction of the deepest running
/// container is then the current step, so the strip does not flicker.
public struct SequenceSteps: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public let id: [Int]
        public let name: String
        public let container: String
        public let status: SequenceTree.Node.Status
    }

    public let last: Step?
    public let current: Step?
    public let next: Step?

    public var isRunning: Bool { current != nil }

    public init(tree: SequenceTree) {
        var flat: [Step] = []
        Self.flatten(tree.roots, container: "", into: &flat)
        let index = flat.lastIndex { $0.status == .running } ?? Self.firstOpenInDeepestRunning(tree, flat)
        guard let index else {
            last = nil; current = nil; next = nil
            return
        }
        current = flat[index]
        last = flat[..<index].last { $0.status == .finished || $0.status == .failed }
        next = flat[(index + 1)...].first { $0.status == .created }
    }

    public static func runningContainers(in tree: SequenceTree) -> Set<[Int]> {
        var ids: Set<[Int]> = []
        var nodes = tree.roots
        while let running = nodes.first(where: { $0.isContainer && $0.status == .running }) {
            ids.insert(running.id)
            nodes = running.children ?? []
        }
        return ids
    }

    private static func flatten(_ nodes: [SequenceTree.Node], container: String, into flat: inout [Step]) {
        for node in nodes {
            if let children = node.children {
                flatten(children, container: node.name, into: &flat)
            } else {
                flat.append(Step(id: node.id, name: node.name, container: container, status: node.status))
            }
        }
    }

    private static func firstOpenInDeepestRunning(_ tree: SequenceTree, _ flat: [Step]) -> Int? {
        guard let deepest = runningContainers(in: tree).max(by: { $0.count < $1.count }) else { return nil }
        return flat.firstIndex { $0.status == .created && $0.id.starts(with: deepest) }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/PanGalacticCore && swift test --filter SequenceStepsTests`
Expected: all PASS. If `runningInstruction` reports a different `last`, print the flattened steps and correct the expectation to the closest `FINISHED`/`FAILED` instruction before the exposure in the fixture (expected: "Send to Pushover", the container-level item after the guiding group).

- [ ] **Step 5: Commit**

```bash
git add Packages/PanGalacticCore/Sources/PanGalacticCore/NINA/SequenceSteps.swift Packages/PanGalacticCore/Tests/PanGalacticCoreTests/SequenceStepsTests.swift
git commit -m "Core: last, current and next sequence step"
```

---

### Task 4: Keep the tree in `InstanceConnection`

**Files:**
- Modify: `Packages/PanGalacticCore/Sources/PanGalacticServices/Connection/InstanceConnection.swift` (properties near `sequence`, `pollSequence`, the offline reset)
- Test: `Packages/PanGalacticCore/Tests/PanGalacticServicesTests/ServicesTests.swift` (`sequenceIsPolledAtMostEveryFifteenSeconds`)

**Interfaces:**
- Consumes: `SequenceTree(json:)` (Task 2).
- Produces: `public private(set) var sequenceTree: SequenceTree?` on `InstanceConnection` – `nil` while unknown, kept while stale.

- [ ] **Step 1: Extend the existing test**

In `sequenceIsPolledAtMostEveryFifteenSeconds`, after `#expect(conn.sequence?.loop == ...)` add:

```swift
        #expect(conn.sequenceTree?.roots.map(\.name) == ["Lights"])
```

and at the end, after `#expect(conn.sequence == nil, ...)`:

```swift
        #expect(conn.sequenceTree == nil, "the json request failed too (404 from the handler)")
```

Add a new test below it:

```swift
    @Test func sequenceTreeDoesNotNeedTheStateTree() async {
        let transport = FakeTransport { request in
            switch request.url?.path() {
            case "/v2/api/version": FakeTransport.ok(#""2.2.15.3""#)
            case "/v2/api/version/nina": FakeTransport.ok(#""3.2""#)
            case "/v2/api/equipment/info": FakeTransport.ok("{}")
            case "/v2/api/sequence/state": (500, "")
            case "/v2/api/sequence/json":
                FakeTransport.ok(#"[{"GlobalTriggers":[]},{"Name":"Lights","Status":"RUNNING","Items":[]}]"#)
            default: (404, "")
            }
        }
        let conn = connection(transport, clock: Clock())
        _ = await conn.pollOnce()
        #expect(conn.sequence == nil)
        #expect(conn.sequenceTree?.roots.first?.name == "Lights")
    }
```

Note: the handler at the end of the existing test returns `FakeTransport.ok("{}")` for `/sequence/json`; `{}` is not an array, so `SequenceTree(json:)` is `nil` – the expectation holds.

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/PanGalacticCore && swift test --filter ServicesTests`
Expected: compile error "value of type 'InstanceConnection' has no member 'sequenceTree'".

- [ ] **Step 3: Implement**

Below `public private(set) var sequence: SequenceProgress?` add:

```swift
    /// The sequence as a tree for the strip and the sequence page; `nil` while unknown.
    /// Kept while stale, never invented.
    public private(set) var sequenceTree: SequenceTree?
```

Replace `pollSequence`:

```swift
    /// `/sequence/state` carries pass counts and loop conditions, `/sequence/json` the
    /// live end time of time-bound loops and the tree for the strip and the sequence page.
    /// Each is unknown on its own when its request fails.
    private func pollSequence(at now: Date) async {
        if let last = lastSequencePoll, now.timeIntervalSince(last) < Self.sequenceInterval { return }
        lastSequencePoll = now
        let state = try? await client.get(.sequenceState, as: JSONValue.self)
        let json = try? await client.get(.sequenceJSON, as: JSONValue.self)
        sequence = state.map { SequenceProgress(state: $0, json: json) }
        sequenceTree = json.flatMap { SequenceTree(json: $0) }
    }
```

In the offline reset block, next to `sequence = nil`, add `sequenceTree = nil`.

- [ ] **Step 4: Run all package tests**

Run: `cd Packages/PanGalacticCore && swift test`
Expected: all PASS. `sequenceIsPolledAtMostEveryFifteenSeconds` still counts 2 sequence requests per poll (both endpoints are always requested now; before, `json` was skipped when `state` failed – the failure case at the end of the test does not count requests).

- [ ] **Step 5: Commit**

```bash
git add Packages/PanGalacticCore/Sources/PanGalacticServices/Connection/InstanceConnection.swift Packages/PanGalacticCore/Tests/PanGalacticServicesTests/ServicesTests.swift
git commit -m "Services: keep the sequence tree from the existing poll"
```

---

### Task 5: Margins, sequence strip and focus path on the overview

**Files:**
- Modify: `App/Design/Theme.swift:27-28,32`
- Create: `App/Views/SequenceStrip.swift`
- Modify: `App/Views/DashboardView.swift` (`body` VStack, `overview(now:)`, Mount tile frame)
- Modify: `App/Views/RootView.swift:31-45,59-66`
- Create: `App/Views/SequenceView.swift` (placeholder body only in this task; filled in Task 6)
- Modify: `App/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `InstanceConnection.sequenceTree`, `SequenceSteps(tree:)`, `.isRunning`, `Step.name/.container/.status`, `ConnectionPhase`.
- Produces: `Destination.sequence`; `struct SequenceStrip: View { let steps: SequenceSteps?; let dimmed: Bool }`; `struct SequenceView: View { let connection: InstanceConnection }`.

- [ ] **Step 1: Margins and Mount tile**

In `Theme.swift` set:

```swift
    static let margin: CGFloat = 56
    static let marginVertical: CGFloat = 36
```

Remove `static let mountTileWidth: CGFloat = 268`. In `DashboardView.overview(now:)` replace `.frame(width: Theme.mountTileWidth)` on `MountTile` with `.frame(maxWidth: .infinity)` so the tile row takes the 48 px the column gained.

- [ ] **Step 2: Destination and placeholder page**

`RootView.swift`: add `case sequence` to `Destination` and in the `navigationDestination` switch:

```swift
                case .sequence:
                    if let connection = model.connection { SequenceView(connection: connection) }
```

`App/Views/SequenceView.swift`:

```swift
import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// The whole Advanced Sequence as a tree, from the same `/sequence/json` poll as the strip.
struct SequenceView: View {
    let connection: InstanceConnection

    var body: some View {
        Text("Sequence").font(.pgDisplay).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .ignoresSafeArea()
    }
}
```

- [ ] **Step 3: The strip**

`App/Views/SequenceStrip.swift`:

```swift
import PanGalacticCore
import SwiftUI

/// Last, current and next step of the running sequence, under both overview columns.
/// N.I.N.A.'s step names are shown as sent.
struct SequenceStrip: View {
    /// `nil` while the tree is unknown.
    let steps: SequenceSteps?
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 28) {
            Text("SEQUENCE").font(.pgRubric).tracking(3).foregroundStyle(Theme.text2)
            content
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
        .opacity(dimmed ? 0.55 : 1)
    }

    @ViewBuilder private var content: some View {
        if let steps, let current = steps.current {
            if let last = steps.last {
                HStack(spacing: 10) {
                    Image(systemName: last.status == .failed ? "xmark.circle" : "checkmark.circle")
                        .foregroundStyle(last.status == .failed ? Theme.fault : Theme.text2)
                    Text(verbatim: last.name).foregroundStyle(Theme.text2)
                }
                .font(.pgLabel)
                chevron
            }
            HStack(spacing: 12) {
                Circle().fill(Theme.accent).frame(width: 16, height: 16)
                if !current.container.isEmpty {
                    Text(verbatim: current.container).font(.pgValue).foregroundStyle(Theme.text)
                    Text(verbatim: "·").font(.pgLabel).foregroundStyle(Theme.text2)
                }
                Text(verbatim: current.name).font(.pgLabel).foregroundStyle(Theme.text)
            }
            .layoutPriority(1)
            chevron
            HStack(spacing: 6) {
                Text("Next:").foregroundStyle(Theme.text3)
                if let next = steps.next {
                    if !next.container.isEmpty {
                        Text(verbatim: "\(next.container) · ").foregroundStyle(Theme.text2)
                    }
                    Text(verbatim: next.name).foregroundStyle(Theme.text2)
                } else {
                    Text(verbatim: "—").foregroundStyle(Theme.text2)
                }
            }
            .font(.pgLabel)
        } else if steps != nil {
            Text("Not running").font(.pgLabel).foregroundStyle(Theme.text2)
        } else {
            Text(verbatim: "—").font(.pgLabel).foregroundStyle(Theme.text2)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.pgLabel).foregroundStyle(Theme.text3)
    }
}
```

- [ ] **Step 4: Place the strip with its own focus section**

In `DashboardView.body`, replace `overview(now: context.date)` with:

```swift
                    overview(now: context.date)
                    NavigationLink(value: Destination.sequence) {
                        SequenceStrip(steps: connection.sequenceTree.map(SequenceSteps.init(tree:)),
                                      dimmed: asOf != nil)
                    }
                    .buttonStyle(LiftButtonStyle(scale: 1.01))
                    // Full width like the header: a swipe down from the image reaches the strip,
                    // a swipe up returns to the image.
                    .focusSection()
                    .accessibilityLabel(Text("Sequence"))
```

and reduce the outer `VStack(alignment: .leading, spacing: 32)` spacing to `24` so header, columns and strip fit 1080 − 2 × 36.

- [ ] **Step 5: Strings**

Add to `Localizable.xcstrings` (en source, de translation, state `translated`): `"SEQUENCE"` → `"SEQUENZ"`, `"Next:"` → `"Als Nächstes:"`, `"Not running"` (check whether it already exists – the Sequence pill uses it; reuse), `"Sequence"` (exists for the pill – reuse).

- [ ] **Step 6: Build and look**

```bash
xcodebuild -project PanGalacticNinaTV.xcodeproj -scheme PanGalacticNinaTV -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build | tail -3
git diff --stat App/Resources/Localizable.xcstrings
```

Expected: `** BUILD SUCCEEDED **`. Then run in the tvOS simulator against `python3 tools/demo/demo_server.py` (it already serves `sequence-json-running-2.json`) and check: nothing clipped at 1920×1080, strip below both columns, swipe down image → strip, up → image, up → header; click on the strip opens the placeholder, Menu returns with focus on the strip. Take a screenshot (`xcrun simctl io booted screenshot`).

- [ ] **Step 7: Commit**

```bash
git add App/Design/Theme.swift App/Views/SequenceStrip.swift App/Views/SequenceView.swift App/Views/DashboardView.swift App/Views/RootView.swift App/Resources/Localizable.xcstrings
git commit -m "Overview: sequence strip with last, current and next step; smaller margins"
```

---

### Task 6: Sequence page (tree)

**Files:**
- Modify: `App/Views/SequenceView.swift`
- Modify: `App/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `InstanceConnection.sequenceTree`, `.phase`, `.lastSuccess`, `.instance.displayName`, `.refreshPhase()`; `SequenceTree.Node` (`id`, `name`, `status`, `children`, `details`, `isContainer`); `SequenceSteps.runningContainers(in:)`, `SequenceSteps(tree:).current?.id`; `LiftButtonStyle`.

- [ ] **Step 1: Implement the page**

Replace `SequenceView.swift`:

```swift
import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// The whole Advanced Sequence as a tree, from the same `/sequence/json` poll as the
/// strip. Only the running branch is expanded at first; a click on a container
/// expands or collapses it. Read-only: nothing here acts on the sequence.
struct SequenceView: View {
    let connection: InstanceConnection

    @State private var expanded: Set<[Int]> = []
    @State private var seeded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sequence").font(.pgDisplay).foregroundStyle(Theme.text)
                    Text(verbatim: subtitle).font(.pgLabel).foregroundStyle(Theme.text2)
                }
                if let tree = connection.sequenceTree {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(rows(tree)) { row in
                                    SequenceRow(node: row.node, depth: row.depth,
                                                expanded: expanded.contains(row.node.id)) {
                                        toggle(row.node.id)
                                    }
                                    .id(row.node.id)
                                }
                            }
                            .padding(.vertical, 12)
                        }
                        .onAppear { seed(tree, proxy: proxy) }
                        .onChange(of: tree) { prune(tree) }
                    }
                } else {
                    Text("No sequence loaded").font(.pgValue).foregroundStyle(Theme.text2)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, Theme.marginVertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
            .ignoresSafeArea()
            .opacity(connection.phase == .live ? 1 : 0.55)
            .onChange(of: context.date) { connection.refreshPhase() }
        }
    }

    private var subtitle: String {
        guard connection.phase != .live, let since = connection.lastSuccess else { return connection.instance.displayName }
        return "\(connection.instance.displayName) · " + String(localized: "As of \(since.formatted(date: .omitted, time: .shortened))")
    }

    private struct Row: Identifiable {
        let node: SequenceTree.Node
        let depth: Int
        var id: [Int] { node.id }
    }

    private func rows(_ tree: SequenceTree) -> [Row] {
        var rows: [Row] = []
        func add(_ nodes: [SequenceTree.Node], depth: Int) {
            for node in nodes {
                rows.append(Row(node: node, depth: depth))
                if let children = node.children, expanded.contains(node.id) { add(children, depth: depth + 1) }
            }
        }
        add(tree.roots, depth: 0)
        return rows
    }

    private func toggle(_ id: [Int]) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Once per visit: expand the running chain and scroll to the current step.
    private func seed(_ tree: SequenceTree, proxy: ScrollViewProxy) {
        guard !seeded else { return }
        seeded = true
        expanded = SequenceSteps.runningContainers(in: tree)
        if let current = SequenceSteps(tree: tree).current?.id {
            DispatchQueue.main.async { proxy.scrollTo(current, anchor: .center) }
        }
    }

    /// After a reload, forget ids that no longer exist.
    private func prune(_ tree: SequenceTree) {
        expanded = expanded.filter { tree.node(at: $0)?.isContainer == true }
    }
}

private struct SequenceRow: View {
    let node: SequenceTree.Node
    let depth: Int
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: { if node.isContainer { toggle() } }) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                symbol.frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: node.name.isEmpty ? "—" : node.name)
                        .font(node.isContainer ? .pgValue : .pgLabel)
                        .foregroundStyle(node.status == .disabled || node.status == .skipped ? Theme.text3 : Theme.text)
                        .strikethrough(node.status == .disabled)
                    if !details.isEmpty {
                        Text(verbatim: details).font(.pgLabel).foregroundStyle(Theme.text2)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 16)
                if node.isContainer {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").foregroundStyle(Theme.text3)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .padding(.leading, CGFloat(depth) * 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(LiftButtonStyle(scale: 1.01))
    }

    @ViewBuilder private var symbol: some View {
        switch node.status {
        case .finished: Image(systemName: "checkmark").foregroundStyle(Theme.text2)
        case .running: Circle().fill(Theme.accent).frame(width: 16, height: 16)
        case .created: Image(systemName: "circle").foregroundStyle(Theme.text3)
        case .failed: Image(systemName: "xmark").foregroundStyle(Theme.fault)
        case .skipped: Image(systemName: "arrow.turn.down.right").foregroundStyle(Theme.text3)
        case .disabled: Image(systemName: "minus").foregroundStyle(Theme.text3)
        case .unknown: Text(verbatim: "?").foregroundStyle(Theme.text3)
        }
    }

    private var details: String {
        node.details.map(Self.text).joined(separator: " · ")
    }

    static func text(_ detail: SequenceTree.Detail) -> String {
        switch detail {
        case .untilTime(let date):
            String(localized: "until \(date.formatted(date: .omitted, time: .shortened))")
        case .iterations(let completed, let total):
            String(localized: "\(completed) of \(total)")
        case .ditherEvery(let done, let target):
            String(localized: "Dither every \(target) (\(done)/\(target))")
        case .exposure(let seconds, let type, let gain):
            ([seconds.formatted(.number.precision(.fractionLength(0...2))) + " s", type]
                + [gain.map { String(localized: "Gain \($0)") }]).compactMap { $0 }.joined(separator: " · ")
        case .temperature(let celsius):
            celsius.formatted(.number.precision(.fractionLength(0...1))) + " °C"
        case .filter(let name), .trigger(let name), .condition(let name):
            name
        }
    }
}
```

- [ ] **Step 2: Strings**

Add (en → de): `"No sequence loaded"` → `"Keine Sequenz geladen"`, `"until %@"` → `"bis %@"`, `"%lld of %lld"` → `"%1$lld von %2$lld"`, `"Dither every %lld (%lld/%lld)"` → `"Dither alle %1$lld (%2$lld/%3$lld)"`, `"Gain %lld"` → `"Gain %lld"`. `"As of %@"` exists already (image card) – reuse.

- [ ] **Step 3: Build and check in the simulator**

```bash
xcodebuild -project PanGalacticNinaTV.xcodeproj -scheme PanGalacticNinaTV -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build | tail -3
git diff --stat App/Resources/Localizable.xcstrings
```

Expected: `** BUILD SUCCEEDED **`. In the simulator with the demo server, EN and DE (`-AppleLanguages '(de)'`): the page opens with Ziele → M 31 → Light 120 UV/IR expanded and the exposure centred; click on "Start" expands it, again collapses; details read "until …", "Dither every 3 (n/3)", "120 s · LIGHT · Gain 100"; Menu returns to the overview with focus on the strip.

- [ ] **Step 4: Commit**

```bash
git add App/Views/SequenceView.swift App/Resources/Localizable.xcstrings
git commit -m "Sequence page: the whole sequence as a tree, running branch expanded"
```

---

### Task 7: Version in Settings and filter wheel icon

**Files:**
- Modify: `App/Views/SettingsView.swift` (`Section("About")`)
- Create: `App/Resources/Assets.xcassets/FilterWheel.imageset/Contents.json`
- Create: `App/Resources/Assets.xcassets/FilterWheel.imageset/filter-wheel.svg`
- Modify: `App/Views/DashboardView.swift` (`FilterTile`)
- Modify: `App/Views/DevicesView.swift` / wherever `DeviceKind.icon` maps `.filterWheel` (grep `circle.grid.cross`)
- Modify: `App/Resources/Localizable.xcstrings`

- [ ] **Step 1: Version line**

In `SettingsView`, inside `Section("About")` after the existing text:

```swift
                Text("Version \(Self.version) (\(Self.build))")
                    .font(.pgLabel).foregroundStyle(Theme.text3)
```

and in the struct:

```swift
    private static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
```

The About section is the last one, so the line sits at the bottom left of the list. String: `"Version %@ (%@)"` → de `"Version %1$@ (%2$@)"`.

- [ ] **Step 2: Filter wheel symbol**

`filter-wheel.svg` (24×24 like `telescope-mount.svg`; even-odd so the windows are holes):

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <!-- Filter wheel: disc with hub and five filter windows at 72° steps, first at the top -->
  <path fill="#000" fill-rule="evenodd" d="M12 1.5 A10.5 10.5 0 1 0 12 22.5 A10.5 10.5 0 1 0 12 1.5 Z
    M12 3.6 A2.4 2.4 0 1 1 12 8.4 A2.4 2.4 0 1 1 12 3.6 Z
    M18.18 8.09 A2.4 2.4 0 1 1 18.18 12.89 A2.4 2.4 0 1 1 18.18 8.09 Z
    M15.82 15.36 A2.4 2.4 0 1 1 15.82 20.16 A2.4 2.4 0 1 1 15.82 15.36 Z
    M8.18 15.36 A2.4 2.4 0 1 1 8.18 20.16 A2.4 2.4 0 1 1 8.18 15.36 Z
    M5.82 8.09 A2.4 2.4 0 1 1 5.82 12.89 A2.4 2.4 0 1 1 5.82 8.09 Z
    M12 10.9 A1.1 1.1 0 1 1 12 13.1 A1.1 1.1 0 1 1 12 10.9 Z"/>
</svg>
```

Window centres lie on a ring of radius 6 around (12, 12): (12, 6), (17.71, 10.15), (15.53, 16.85), (8.47, 16.85), (6.29, 10.15); each path starts at the window's top point (centre − 2.4 in y). Verify the geometry by rendering it once (`qlmanage -t -s 256 -o /tmp filter-wheel.svg` or open in Safari) before committing.

`Contents.json`: copy `TelescopeMount.imageset/Contents.json` and change the filename to `filter-wheel.svg` (keeps `preserves-vector-representation` and `template-rendering-intent: template`).

- [ ] **Step 3: Use it**

`FilterTile`: `icon: Image("FilterWheel")`. Find other uses of the old symbol:

```bash
grep -rn "circle.grid.cross" App
```

Replace each filter wheel use with `Image("FilterWheel")` (device list and device detail use `DeviceKind.icon`).

- [ ] **Step 4: Version bump**

In `PanGalacticNinaTV.xcodeproj/project.pbxproj` set both `CURRENT_PROJECT_VERSION = 5;` to `6;`.

- [ ] **Step 5: Build, check, commit**

```bash
xcodebuild -project PanGalacticNinaTV.xcodeproj -scheme PanGalacticNinaTV -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build | tail -3
git diff --stat App/Resources/Localizable.xcstrings
```

Simulator: Settings shows "Version 0.1.0 (6)" at the bottom; Filter tile and device list show the wheel in the panel colour.

```bash
git add App/Views/SettingsView.swift App/Resources/Assets.xcassets/FilterWheel.imageset App/Views/DashboardView.swift App/Views App/Resources/Localizable.xcstrings PanGalacticNinaTV.xcodeproj/project.pbxproj
git commit -m "Settings: app version; filter wheel icon; build 6"
```

---

### Task 8: Documentation and screenshots

**Files:**
- Modify: `docs/api-capability-matrix.md` (§7 running sequence table)
- Modify: `CHANGELOG.md` (Unreleased → Added/Changed (M3))
- Modify: `README.md` (overview tour; new sequence page section; screenshots)
- Create: `docs/assets/screenshots/sequence.jpg`; replace `docs/assets/screenshots/overview.jpg`
- Modify: `docs/status.md`, `docs/milestones.md`

- [ ] **Step 1: Matrix**

Add rows to the §7 "Running sequence" table:

```markdown
| Names | Plugin appends `_Container`, `_Condition`, `_Trigger`; unnamed containers are just `_Container`. Names are N.I.N.A.'s display names in its UI language | Suffix stripped; names shown as sent, never translated |
| Between exposures (2026-11-19) | During download, dither or autofocus the exposure instruction is `CREATED` while its container stays `RUNNING` | Current step = first open instruction of the deepest running container |
| Fields shown on the sequence page | `TargetTime` (conditions, wait instruction), `Iterations`/`CompletedIterations`, `Exposures`/`TargetExposures` (dither trigger), `ExposureTime`/`Type`/`Gain` (≥ 0), `Temperature`, `Filter` | Everything else ignored; coordinates and `FilePath` never read |
```

- [ ] **Step 2: Changelog**

Under `## [Unreleased]` → `### Added (M3)`:

```markdown
- Sequence strip on the overview: last step (✓, or ✕ when it failed), current step with its container, and the next step, from the existing `/sequence/json` poll. A click opens the sequence page.
- Sequence page: the whole Advanced Sequence as a tree with status per step; the running branch is expanded and centred, containers expand and collapse with a click; loop end, iterations, dither interval and exposure settings under each step.
- Settings: app version and build.
- Filter wheel icon for the Filter tile and the device list.
```

Under `### Changed (M3)`:

```markdown
- Overview margins 56 px left/right and 36 px top/bottom (were Apple's 80/60 safe area), so the strip fits without shrinking the image.
```

- [ ] **Step 3: Screenshots and README**

Demo server + simulator, English UI: overview (replaces `docs/assets/screenshots/overview.jpg`) and the sequence page (`docs/assets/screenshots/sequence.jpg`), 1920×1080 JPEG. In README "What it does today → The overview" mention the strip; add a short "### The sequence" section with the new screenshot.

- [ ] **Step 4: Status and milestones**

`docs/status.md`: Resume-here bullet "Branch `m3/tv-feedback`, PR open: sequence strip and page, version, filter icon; build 6 after merge". `docs/milestones.md` M3 checklist: add `- [x] TV feedback after build 5: sequence strip and page, version, filter wheel icon ([spec](superpowers/specs/2026-11-19-m3-tv-feedback-design.md))`.

- [ ] **Step 5: Final verification and commit**

```bash
cd Packages/PanGalacticCore && swift test 2>&1 | tail -3 && cd ../..
xcodebuild -project PanGalacticNinaTV.xcodeproj -scheme PanGalacticNinaTV -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build | tail -1
git status --short
```

Expected: all tests pass, `** BUILD SUCCEEDED **`, only intended files changed.

```bash
git add docs README.md CHANGELOG.md
git commit -m "Docs: sequence strip and page – matrix, changelog, README, status"
git push
```

Then open the PR `m3/tv-feedback` → `main` with summary, screenshots and test results.
