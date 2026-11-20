import Foundation

public struct AltitudePoint: Equatable, Sendable {
    public let date: Date
    public let altitude: Double
}

/// Altitudes every 5 minutes, both ends included; geometric (no refraction).
public enum AltitudeCurve {
    public static let step: TimeInterval = 300

    static func sample(_ interval: DateInterval, _ altitude: (Date) -> Double) -> [AltitudePoint] {
        let count = Int((interval.duration / step).rounded(.down))
        var points = (0 ... count).map { i -> AltitudePoint in
            let date = interval.start.addingTimeInterval(Double(i) * step)
            return AltitudePoint(date: date, altitude: altitude(date))
        }
        if let last = points.last, last.date < interval.end {
            points.append(AltitudePoint(date: interval.end, altitude: altitude(interval.end)))
        }
        return points
    }

    /// `ofDate`: coordinates of the equinox of date (precess J2000 targets once per night).
    public static func target(_ ofDate: Equatorial, site: Site, over interval: DateInterval) -> [AltitudePoint] {
        sample(interval) { Sky.horizontal(ofDate, site: site, at: $0).altitude }
    }

    public static func sun(site: Site, over interval: DateInterval) -> [AltitudePoint] {
        sample(interval) { Sun.horizontal(site: site, at: $0).altitude }
    }

    /// Topocentric.
    public static func moon(site: Site, over interval: DateInterval) -> [AltitudePoint] {
        sample(interval) { Moon.horizontal(site: site, at: $0).altitude }
    }

    /// Upper meridian transit in the interval: the hour angle passes from negative to positive.
    public static func transit(_ ofDate: Equatorial, site: Site, over interval: DateInterval) -> Date? {
        let crossing = Crossings.find(in: interval, threshold: 0, step: 600) { date in
            let h = Sky.hourAngle(ofDate, site: site, at: date)
            // Fold the lower transit (±180°) away so only the upper one is a crossing.
            return abs(h) > 90 ? -1 : h
        }
        return crossing.first { $0.rising }?.date
    }
}
