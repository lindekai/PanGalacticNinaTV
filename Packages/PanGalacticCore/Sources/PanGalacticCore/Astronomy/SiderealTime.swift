import Foundation

/// Mean sidereal time in degrees (Meeus 12.4).
public enum SiderealTime {
    public static func greenwichMean(_ date: Date) -> Double {
        let jd = JulianDay.from(date)
        let t = (jd - 2451545) / 36525
        return normalizedDegrees(280.46061837 + 360.98564736629 * (jd - 2451545)
                                 + 0.000387933 * t * t - t * t * t / 38710000)
    }

    /// Longitude east-positive.
    public static func localMean(_ date: Date, longitude: Double) -> Double {
        normalizedDegrees(greenwichMean(date) + longitude)
    }
}
