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

    /// Name of the deepest running container; `nil` when no container runs.
    public let runningContainer: String?

    /// A container runs, even if its current step is unknown.
    public var isRunning: Bool { runningContainer != nil }

    public init(tree: SequenceTree) {
        var flat: [Step] = []
        Self.flatten(tree.roots, container: "", into: &flat)
        runningContainer = Self.deepestRunningContainer(tree)?.name
        let index = flat.lastIndex { $0.status == .running } ?? Self.firstOpenInDeepestRunning(tree, flat)
        guard let index else {
            last = nil; current = nil; next = nil
            return
        }
        current = flat[index]
        last = flat[..<index].last { $0.status == .finished || $0.status == .failed }
        next = flat[(index + 1)...].first { $0.status == .created }
    }

    /// Ids of the chain of running containers (expanded by default on the page);
    /// follows the first running container per level.
    public static func runningContainers(in tree: SequenceTree) -> Set<[Int]> {
        var ids: Set<[Int]> = []
        var nodes = tree.roots
        while let running = nodes.first(where: { $0.isContainer && $0.status == .running }) {
            ids.insert(running.id)
            nodes = running.children ?? []
        }
        return ids
    }

    private static func deepestRunningContainer(_ tree: SequenceTree) -> SequenceTree.Node? {
        var found: SequenceTree.Node?
        var nodes = tree.roots
        while let running = nodes.first(where: { $0.isContainer && $0.status == .running }) {
            found = running
            nodes = running.children ?? []
        }
        return found
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
