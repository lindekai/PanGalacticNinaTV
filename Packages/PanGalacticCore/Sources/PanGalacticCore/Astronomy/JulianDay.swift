import Foundation

/// Julian Day (Meeus ch. 7). Dynamical time is UT + ΔT with a fixed ΔT.
public enum JulianDay {
    /// TT − UT in seconds; about 69 s in the 2020s, an error below 1 s of time until 2030.
    public static let deltaT: Double = 69

    public static func from(_ date: Date) -> Double { date.timeIntervalSince1970 / 86400 + 2440587.5 }

    public static func date(_ jd: Double) -> Date { Date(timeIntervalSince1970: (jd - 2440587.5) * 86400) }

    /// Gregorian calendar date with fractional day (Meeus 7.1).
    public static func calendar(year: Int, month: Int, day: Double) -> Double {
        var y = Double(year), m = Double(month)
        if month <= 2 { y -= 1; m += 12 }
        let a = (y / 100).rounded(.down)
        let b = 2 - a + (a / 4).rounded(.down)
        return (365.25 * (y + 4716)).rounded(.down) + (30.6001 * (m + 1)).rounded(.down) + day + b - 1524.5
    }

    /// Julian Ephemeris Day for a UT instant.
    public static func ephemeris(_ date: Date) -> Double { from(date) + deltaT / 86400 }

    /// Julian centuries since J2000.0.
    public static func centuries(fromJDE jde: Double) -> Double { (jde - 2451545) / 36525 }
}
