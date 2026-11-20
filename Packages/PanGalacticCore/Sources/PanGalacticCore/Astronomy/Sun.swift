import Foundation

/// Apparent position of the Sun, low accuracy (≈ 0.01°; Meeus ch. 25).
public enum Sun {
    public static func position(jde: Double) -> (equatorial: Equatorial, longitude: Double) {
        let t = JulianDay.centuries(fromJDE: jde)
        let l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        let m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sinDeg(m)
            + (0.019993 - 0.000101 * t) * sinDeg(2 * m) + 0.000289 * sinDeg(3 * m)
        let omega = 125.04 - 1934.136 * t
        let lambda = l0 + c - 0.00569 - 0.00478 * sinDeg(omega)
        let epsilon = Sky.meanObliquity(jde: jde) + 0.00256 * cosDeg(omega)
        let ra = atan2Deg(cosDeg(epsilon) * sinDeg(lambda), cosDeg(lambda))
        let dec = asinDeg(sinDeg(epsilon) * sinDeg(lambda))
        return (Equatorial(ra: normalizedDegrees(ra), dec: dec), normalizedDegrees(lambda))
    }

    public static func position(at date: Date) -> Equatorial { position(jde: JulianDay.ephemeris(date)).equatorial }

    /// Geometric altitude of the Sun's centre (parallax 0.0024° neglected).
    public static func horizontal(site: Site, at date: Date) -> Horizontal {
        Sky.horizontal(position(at: date), site: site, at: date)
    }
}
