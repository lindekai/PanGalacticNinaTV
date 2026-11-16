import Foundation

/// When the overview gives way to the full-screen ambient view (spec: "Ambient mode").
/// After `delay` without remote input the newest frame fills the screen; any input or
/// any alarm returns to the overview, and with an active alarm it is never entered.
public struct AmbientPolicy: Equatable, Sendable {
    public static let defaultDelayMinutes = 5
    /// Delays offered in Settings, in minutes.
    public static let delayChoices = [1, 2, 5, 10, 15, 30]
    /// The strip moves to its next position this often, against burn-in.
    public static let shiftInterval: TimeInterval = 180

    public var enabled: Bool
    public var delay: TimeInterval

    public init(enabled: Bool = true, delayMinutes: Int = Self.defaultDelayMinutes) {
        self.enabled = enabled
        delay = TimeInterval(max(1, delayMinutes) * 60)
    }

    /// Alarms keep the overview on screen: no connection, or an exposure that is overdue.
    public static func isAlarm(phase: ConnectionPhase, exposure: ExposureDisplay) -> Bool {
        phase == .offline || exposure == .overdue
    }

    public func showsAmbient(lastInput: Date, now: Date, alarm: Bool) -> Bool {
        enabled && !alarm && now.timeIntervalSince(lastInput) >= delay
    }

    /// Offset of the ambient strip in points; changes every `shiftInterval` and cycles
    /// through a small grid so no pixel shows the same text for long.
    public static func stripShift(at now: Date) -> (x: Double, y: Double) {
        let positions: [(Double, Double)] = [(0, 0), (40, -16), (-40, -32), (24, -48), (-24, -8), (40, -40)]
        let step = Int((now.timeIntervalSince1970 / shiftInterval).rounded(.down))
        let (x, y) = positions[((step % positions.count) + positions.count) % positions.count]
        return (x, y)
    }
}
