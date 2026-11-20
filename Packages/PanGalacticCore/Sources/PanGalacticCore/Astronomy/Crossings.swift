import Foundation

public struct Crossing: Equatable, Sendable {
    public let date: Date
    public let rising: Bool
    public init(date: Date, rising: Bool) { self.date = date; self.rising = rising }
}

/// Instants when an altitude crosses a threshold: sampled every `step`, then bisected to 1 s.
public enum Crossings {
    public static func find(in interval: DateInterval, threshold: Double, step: TimeInterval = 600,
                            altitude: (Date) -> Double) -> [Crossing] {
        var result: [Crossing] = []
        var t0 = interval.start
        var above0 = altitude(t0) > threshold
        while t0 < interval.end {
            let t1 = min(t0.addingTimeInterval(step), interval.end)
            let above1 = altitude(t1) > threshold
            if above1 != above0 {
                var low = t0, high = t1
                while high.timeIntervalSince(low) > 1 {
                    let mid = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                    if (altitude(mid) > threshold) == above0 { low = mid } else { high = mid }
                }
                result.append(Crossing(date: high, rising: above1))
            }
            t0 = t1
            above0 = above1
        }
        return result
    }
}
