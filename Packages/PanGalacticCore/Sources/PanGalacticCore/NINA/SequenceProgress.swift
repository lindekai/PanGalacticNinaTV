import Foundation

/// Progress of the running Advanced Sequence, derived from `/sequence/state`
/// (pass counts, loop conditions, target) and `/sequence/json` (live end time of
/// time-bound loops). Semantics checked in source, N.I.N.A. 3.2 / plugin 2.2.15.3
/// (docs/api-capability-matrix.md §7):
///
/// - A container's `Iterations` counts completed passes of the current run; it is
///   reset when the container starts and is not saved with the sequence. The
///   exposure item's `ExposureCount` is saved and accumulates across nights, so
///   it is never used.
/// - `RemainingTime`/`TargetTime` exist only in `/sequence/json` (get-only
///   properties are not emitted by `/sequence/state`).
/// - The plugin reads the live tree without a lock and silently drops items that
///   throw, so anything missing is unknown, never zero.
public struct SequenceProgress: Equatable, Sendable {
    public enum Loop: Equatable, Sendable {
        /// Loop condition "n of m" of the innermost running container.
        case count(completed: Int, total: Int)
        /// Time-bound loop (until a time, for a timespan) ends at this instant.
        case until(Date)
    }

    public let isRunning: Bool
    /// Target of the innermost running target container, if any.
    public let targetName: String?
    /// Completed passes of the innermost running container in this run.
    public let completedPasses: Int?
    /// The container runs exactly one exposure per pass, so passes are frames.
    public let passIsSingleExposure: Bool
    public let loop: Loop?

    public init(state: JSONValue, json: JSONValue?) {
        let path = Self.runningPath(in: state)
        guard let innermost = path.last?.node else {
            self.init(isRunning: false, targetName: nil, completedPasses: nil, passIsSingleExposure: false, loop: nil)
            return
        }
        let target = path.reversed().lazy.compactMap { $0.node["Target"]?["TargetName"]?.string }
            .first { !$0.isEmpty }
        let items = innermost["Items"]?.array ?? []
        let singleExposure = items.count == 1 && items[0]["ExposureTime"] != nil && items[0]["Items"] == nil
        let loop = Self.countLoop(of: innermost) ?? json.flatMap { Self.timeLoop(following: path, in: $0) }
        self.init(isRunning: true, targetName: target, completedPasses: innermost["Iterations"]?.int,
                  passIsSingleExposure: singleExposure, loop: loop)
    }

    public init(isRunning: Bool, targetName: String?, completedPasses: Int?, passIsSingleExposure: Bool, loop: Loop?) {
        self.isRunning = isRunning
        self.targetName = targetName
        self.completedPasses = completedPasses
        self.passIsSingleExposure = passIsSingleExposure
        self.loop = loop
    }

    private struct Step {
        let index: Int
        let name: String?
        let node: JSONValue
    }

    /// Chain of running containers from the root down to the innermost one.
    private static func runningPath(in tree: JSONValue) -> [Step] {
        var path: [Step] = []
        var children = tree.array ?? []
        while let index = children.firstIndex(where: { $0["Status"]?.string == "RUNNING" && $0["Items"]?.array != nil }) {
            let node = children[index]
            path.append(Step(index: index, name: node["Name"]?.string, node: node))
            children = node["Items"]?.array ?? []
        }
        return path
    }

    private static func countLoop(of container: JSONValue) -> Loop? {
        for condition in container["Conditions"]?.array ?? [] {
            if let total = condition["Iterations"]?.int, let completed = condition["CompletedIterations"]?.int {
                return .count(completed: completed, total: total)
            }
        }
        return nil
    }

    /// Follows the same path through the `/sequence/json` tree, requiring matching
    /// names at every step, and returns the earliest end time of its conditions.
    private static func timeLoop(following path: [Step], in tree: JSONValue) -> Loop? {
        var children = tree.array ?? []
        var node: JSONValue?
        for step in path {
            guard children.indices.contains(step.index), children[step.index]["Name"]?.string == step.name else { return nil }
            node = children[step.index]
            children = node?["Items"]?.array ?? []
        }
        let ends = (node?["Conditions"]?.array ?? []).compactMap { $0["TargetTime"]?.string.flatMap { NINADate.parse($0) } }
        return ends.min().map(Loop.until)
    }
}

/// What the dashboard's Sequence pill shows. Like `ExposureDisplay`, only a live
/// connection yields a definite answer.
public enum SequenceDisplay: Equatable, Sendable {
    public enum Progress: Equatable, Sendable {
        /// Frames taken in this run (one exposure per pass).
        case frames(Int)
        /// Loop condition "n of m".
        case count(Int, of: Int)
    }

    case unknown
    case idle
    case running(target: String?, progress: Progress?, secondsLeft: Int?)

    public static func state(_ progress: SequenceProgress?, phase: ConnectionPhase, now: Date) -> SequenceDisplay {
        guard phase == .live, let progress else { return .unknown }
        guard progress.isRunning else { return .idle }
        var shown: Progress?
        var secondsLeft: Int?
        switch progress.loop {
        case .count(let completed, let total):
            shown = .count(completed, of: total)
        case .until(let end):
            if end > now { secondsLeft = Int(end.timeIntervalSince(now).rounded(.up)) }
        case nil:
            break
        }
        if shown == nil, progress.passIsSingleExposure, let passes = progress.completedPasses {
            shown = .frames(passes)
        }
        return .running(target: progress.targetName, progress: shown, secondsLeft: secondsLeft)
    }
}
