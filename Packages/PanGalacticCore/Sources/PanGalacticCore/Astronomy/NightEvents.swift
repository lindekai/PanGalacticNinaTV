import Foundation

/// Sun and Moon events of one night at a site, from the site's mean local noon to the next.
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

    /// The night at `site` that contains `date`: from the site's mean local noon (today, or
    /// yesterday before noon) to the next one, exactly 24 h. Mean local time follows the
    /// longitude (4 min per degree, DST-free), so the night belongs to the site, not to the
    /// time zone of the device showing it; times are displayed in the device's zone.
    public static func window(containing date: Date, site: Site) -> DateInterval {
        let offset = (site.longitude * 240).rounded()
        let local = date.timeIntervalSince1970 + offset
        var noon = (local / 86400).rounded(.down) * 86400 + 43200
        if local < noon { noon -= 86400 }
        return DateInterval(start: Date(timeIntervalSince1970: noon - offset), duration: 86400)
    }

    /// Moonrises and moonsets in `interval` (Moon's centre at `moonAltitude`).
    public static func moonCrossings(site: Site, in interval: DateInterval) -> [Crossing] {
        Crossings.find(in: interval, threshold: moonAltitude) { Moon.geocentricAltitude(site: site, at: $0) }
    }

    public static func compute(site: Site, containing date: Date) -> NightEvents {
        let window = window(containing: date, site: site)
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
