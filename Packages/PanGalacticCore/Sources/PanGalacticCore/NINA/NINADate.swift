import Foundation

/// Timestamps as sent by the Advanced API, e.g. `2026-11-09T19:32:58.9740673+01:00`
/// (local time, offset, up to 7 fractional digits) or `2026-11-09T18:33:01.025`
/// (no offset; used by `mount/info.UTCDate`).
public enum NINADate {
    /// Parses an ISO 8601 timestamp. Strings without an offset are interpreted in
    /// `zoneWithoutOffset` (UTC by default). Returns `nil` for anything else.
    public static func parse(_ string: String, zoneWithoutOffset: TimeZone = .gmt) -> Date? {
        guard let match = string.wholeMatch(of: pattern) else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = Int(match.1)
        components.month = Int(match.2)
        components.day = Int(match.3)
        components.hour = Int(match.4)
        components.minute = Int(match.5)
        components.second = Int(match.6)
        components.timeZone = match.8.map(timeZone(fromOffset:)) ?? zoneWithoutOffset
        guard let zone = components.timeZone, let whole = components.calendar?.date(from: components),
              components.isValidDate(in: Calendar(identifier: .gregorian).with(zone))
        else { return nil }
        let fraction = match.7.flatMap { Double("0." + $0) } ?? 0
        return whole.addingTimeInterval(fraction)
    }

    nonisolated(unsafe) private static let pattern =
        /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})?/

    private static func timeZone(fromOffset offset: Substring) -> TimeZone {
        if offset == "Z" { return .gmt }
        let sign = offset.first == "-" ? -1 : 1
        let parts = offset.dropFirst().split(separator: ":")
        let seconds = (Int(parts[0]) ?? 0) * 3600 + (Int(parts[1]) ?? 0) * 60
        return TimeZone(secondsFromGMT: sign * seconds) ?? .gmt
    }
}

private extension Calendar {
    func with(_ zone: TimeZone) -> Calendar {
        var calendar = self
        calendar.timeZone = zone
        return calendar
    }
}
