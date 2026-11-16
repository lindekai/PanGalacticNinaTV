import Foundation
import PanGalacticCore

/// Shared display formatting. `nil` stays `nil` so views can render "—".
enum Format {
    static func celsius(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    static func degrees(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded())) %"
    }

    static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " s"
    }

    static func hfr(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    /// `m:ss`, or `h:mm:ss` from one hour.
    static func countdown(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Long remaining times for the sequence: `h:mm h` from one hour, else whole minutes.
    static func timeLeft(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600
            ? String(format: "%d:%02d h", s / 3600, s / 60 % 60)
            : "\((s + 59) / 60) min"
    }

    /// PHD2 application state as reported through N.I.N.A.; unknown values verbatim.
    static func guiderState(_ wire: String?) -> String? {
        guard let wire else { return nil }
        switch PHD2AppState(wire: wire) {
        case .stopped: return String(localized: "Stopped")
        case .selected: return String(localized: "Star selected")
        case .calibrating: return String(localized: "Calibrating")
        case .guiding: return String(localized: "Guiding")
        case .lostLock: return String(localized: "Star lost")
        case .paused: return String(localized: "Paused")
        case .looping: return String(localized: "Looping")
        case .other(let value): return value
        }
    }

    static func mountActivity(_ activity: MountActivity) -> String? {
        switch activity {
        case .slewing: String(localized: "Slewing")
        case .parked: String(localized: "Parked")
        case .tracking: String(localized: "Tracking")
        case .notTracking: String(localized: "Not tracking")
        case .unknown: nil
        }
    }
}
