import Foundation

/// Exponential backoff with symmetric jitter for reconnect attempts.
public struct ReconnectBackoff: Hashable, Sendable {
    public var base: TimeInterval
    public var maximum: TimeInterval
    /// Relative jitter, e.g. 0.2 spreads delays over ±20 %.
    public var jitter: Double

    public init(base: TimeInterval = 2, maximum: TimeInterval = 60, jitter: Double = 0.2) {
        self.base = base
        self.maximum = maximum
        self.jitter = jitter
    }

    /// Delay before retry number `attempt` (0-based). `unitRandom` must be in [0, 1].
    public func delay(attempt: Int, unitRandom: Double) -> TimeInterval {
        let exponent = min(max(attempt, 0), 30)
        let raw = min(maximum, base * pow(2, Double(exponent)))
        let spread = jitter * (2 * min(max(unitRandom, 0), 1) - 1)
        return max(0, raw * (1 + spread))
    }
}

public enum ConnectionPhase: Hashable, Sendable {
    /// No successful request yet since (re)start.
    case connecting
    /// Last poll succeeded and is recent.
    case live
    /// Data exists but is older than the stale threshold or the last poll failed.
    case stale
    /// Repeated failures; retrying with backoff.
    case offline
}

public struct ConnectionPolicy: Hashable, Sendable {
    public var pollInterval: TimeInterval
    public var staleAfter: TimeInterval
    /// Consecutive failures after which the instance counts as offline and backoff starts.
    public var offlineAfterFailures: Int
    public var backoff: ReconnectBackoff

    public init(pollInterval: TimeInterval = 5, staleAfter: TimeInterval = 15, offlineAfterFailures: Int = 3,
                backoff: ReconnectBackoff = ReconnectBackoff()) {
        self.pollInterval = pollInterval
        self.staleAfter = staleAfter
        self.offlineAfterFailures = offlineAfterFailures
        self.backoff = backoff
    }
}

/// Pure connection lifecycle: feed it poll outcomes, it tells you the phase and
/// when to poll next. Owns no timers, so it is fully testable.
public struct ConnectionStateMachine: Hashable, Sendable {
    public let policy: ConnectionPolicy
    public private(set) var lastSuccess: Date?
    public private(set) var lastError: String?
    public private(set) var consecutiveFailures = 0
    public private(set) var nextAttempt: Date?

    public init(policy: ConnectionPolicy = ConnectionPolicy()) {
        self.policy = policy
    }

    /// Records a successful poll; returns the delay until the next poll.
    @discardableResult
    public mutating func recordSuccess(at now: Date) -> TimeInterval {
        lastSuccess = now
        lastError = nil
        consecutiveFailures = 0
        nextAttempt = now.addingTimeInterval(policy.pollInterval)
        return policy.pollInterval
    }

    /// Records a failed poll; returns the delay until the next attempt.
    @discardableResult
    public mutating func recordFailure(at now: Date, error: String, unitRandom: Double) -> TimeInterval {
        consecutiveFailures += 1
        lastError = error
        let delay: TimeInterval
        if consecutiveFailures < policy.offlineAfterFailures {
            delay = policy.pollInterval
        } else {
            delay = policy.backoff.delay(attempt: consecutiveFailures - policy.offlineAfterFailures,
                                         unitRandom: unitRandom)
        }
        nextAttempt = now.addingTimeInterval(delay)
        return delay
    }

    /// Restarts the lifecycle, keeping the last success time for display.
    public mutating func reset() {
        consecutiveFailures = 0
        lastError = nil
        nextAttempt = nil
    }

    public func phase(at now: Date) -> ConnectionPhase {
        if consecutiveFailures >= policy.offlineAfterFailures { return .offline }
        guard let lastSuccess else { return .connecting }
        if consecutiveFailures > 0 || now.timeIntervalSince(lastSuccess) > policy.staleAfter { return .stale }
        return .live
    }
}
