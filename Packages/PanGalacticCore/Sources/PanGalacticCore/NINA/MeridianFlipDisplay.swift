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
