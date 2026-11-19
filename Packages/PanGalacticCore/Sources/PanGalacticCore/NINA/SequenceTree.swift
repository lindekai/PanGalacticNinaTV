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
