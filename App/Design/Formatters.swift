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

    /// "Coma Cluster · 5 frames · 5:32 h left"; unknown parts are left out.
    static func sequence(_ display: SequenceDisplay) -> String {
        switch display {
        case .running(let target, let progress, let secondsLeft):
            var parts: [String] = []
            if let target { parts.append(target) }
            switch progress {
            case .frames(let n): parts.append(String(localized: "\(n) frames"))
            case .count(let n, let total): parts.append("\(n)/\(total)")
            case nil: break
            }
            if let secondsLeft { parts.append(String(localized: "\(timeLeft(secondsLeft)) left")) }
            return parts.isEmpty ? String(localized: "Running") : parts.joined(separator: " · ")
        case .idle:
            return String(localized: "Not running")
        case .unknown:
            return "—"
        }
    }

    /// Long remaining times for the sequence: `h:mm h` from one hour, else whole minutes.
    static func timeLeft(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600
            ? String(format: "%d:%02d h", s / 3600, s / 60 % 60)
            : "\((s + 59) / 60) min"
    }

    /// `0.55″` or `0.71 px`.
    static func guideValue(_ value: GuideValue) -> String {
        let number = value.value.formatted(.number.precision(.fractionLength(2)))
        return value.unit == .arcseconds ? number + "″" : number + " px"
    }

    /// Clock time in the region's style without AM/PM ("3:37", "15:37"); short enough
    /// for a small tile, and only an approximate guide.
    static func clockWithoutDayPeriod(_ date: Date, locale: Locale = .current) -> String {
        let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? "HH:mm"
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = pattern.replacingOccurrences(of: "a", with: "")
            .trimmingCharacters(in: .whitespaces)
        return formatter.string(from: date)
    }

    /// Hour formatter in the region's style without AM/PM or "Uhr" ("4", "16"), for chart axes.
    static func hourWithoutDayPeriod(locale: Locale = .current) -> DateFormatter {
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "H"
        let formatter = DateFormatter()
        formatter.locale = locale
        // Quoted literals ("HH 'Uhr'") are not fields; the hour field tells 12 h from 24 h.
        let fields = pattern.replacing(#/'[^']*'/#, with: "")
        formatter.dateFormat = fields.contains("h") || fields.contains("K") ? "h" : "H"
        return formatter
    }

    /// `2:21` (hours:minutes) until the meridian flip.
    static func flipRemaining(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
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

    /// Right ascension from degrees as `HHh MMm` (rounded to the minute of time).
    static func rightAscension(_ degrees: Double) -> String {
        let minutes = Int((degrees / 15 * 60).rounded()) % (24 * 60)
        let total = minutes < 0 ? minutes + 24 * 60 : minutes
        return String(format: "%02dh %02dm", total / 60, total % 60)
    }

    /// Declination from degrees as `±DD° MM′` (rounded to the arcminute).
    static func declination(_ degrees: Double) -> String {
        let arcminutes = Int((abs(degrees) * 60).rounded())
        return String(format: "%@%02d° %02d′", degrees < 0 ? "−" : "+", arcminutes / 60, arcminutes % 60)
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
