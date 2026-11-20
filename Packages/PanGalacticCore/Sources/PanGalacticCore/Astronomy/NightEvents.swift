import Foundation

/// Sun and Moon events of one night, from local noon to the next local noon.
public struct NightEvents: Equatable, Sendable {
    public static let horizonAltitude = -0.833
    public static let civilAltitude = -6.0
    public static let nauticalAltitude = -12.0
    public static let astronomicalAltitude = -18.0
    public static let moonAltitude = 0.125

    public let window: DateInterval
    public let sunset: Date?
    public let sunrise: Date?
    public let civilDusk: Date?
    public let civilDawn: Date?
    public let nauticalDusk: Date?
    public let nauticalDawn: Date?
    public let astronomicalDusk: Date?
    public let astronomicalDawn: Date?
    public let moonrise: Date?
    public let moonset: Date?
    public let sunAlwaysUp: Bool
    public let sunAlwaysDown: Bool

    /// The night that contains `date`: from local noon (today, or yesterday before noon)
    /// to the next local noon, DST-safe.
    public static func window(containing date: Date, timeZone: TimeZone) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let start = date >= noon ? noon : calendar.date(byAdding: .day, value: -1, to: noon)!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    /// Moonrises and moonsets in `interval` (Moon's centre at `moonAltitude`).
    public static func moonCrossings(site: Site, in interval: DateInterval) -> [Crossing] {
        Crossings.find(in: interval, threshold: moonAltitude) { Moon.geocentricAltitude(site: site, at: $0) }
    }

    public static func compute(site: Site, containing date: Date, timeZone: TimeZone) -> NightEvents {
        let window = window(containing: date, timeZone: timeZone)
        let sunAltitude = { (d: Date) in Sun.horizontal(site: site, at: d).altitude }
        func duskDawn(_ threshold: Double) -> (Date?, Date?) {
            let crossings = Crossings.find(in: window, threshold: threshold, altitude: sunAltitude)
            let dusk = crossings.first { !$0.rising }
            let dawn = crossings.first { $0.rising && (dusk == nil || $0.date > dusk!.date) }
            return (dusk?.date, dawn?.date)
        }
        let horizon = duskDawn(horizonAltitude)
        let civil = duskDawn(civilAltitude)
        let nautical = duskDawn(nauticalAltitude)
        let astronomical = duskDawn(astronomicalAltitude)
        let moon = moonCrossings(site: site, in: window)
        let noHorizonCrossing = horizon.0 == nil && horizon.1 == nil
        let startsUp = sunAltitude(window.start) > horizonAltitude
        return NightEvents(window: window, sunset: horizon.0, sunrise: horizon.1,
                           civilDusk: civil.0, civilDawn: civil.1,
                           nauticalDusk: nautical.0, nauticalDawn: nautical.1,
                           astronomicalDusk: astronomical.0, astronomicalDawn: astronomical.1,
                           moonrise: moon.first { $0.rising }?.date, moonset: moon.first { !$0.rising }?.date,
                           sunAlwaysUp: noHorizonCrossing && startsUp, sunAlwaysDown: noHorizonCrossing && !startsUp)
    }
}
