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
        recent.suffix(limit).compactMap(\.hfr)
    }

    public mutating func reset() {
        count = 0
        entries = [:]
        attempted = []
    }
}
