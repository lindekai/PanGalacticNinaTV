import Foundation

/// Right ascension and declination in degrees.
public struct Equatorial: Equatable, Sendable {
    public var ra: Double
    public var dec: Double
    public init(ra: Double, dec: Double) { self.ra = ra; self.dec = dec }
}

/// Altitude above the horizon and azimuth from north through east, in degrees.
public struct Horizontal: Equatable, Sendable {
    public var altitude: Double
    public var azimuth: Double
    public init(altitude: Double, azimuth: Double) { self.altitude = altitude; self.azimuth = azimuth }
}

/// Observing site; longitude east-positive. Privacy: never logged (ADR 0006), so the
/// descriptions are redacted.
public struct Site: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let latitude: Double
    public let longitude: Double
    public let elevation: Double

    public init(latitude: Double, longitude: Double, elevation: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
    }

    /// The site as N.I.N.A. reports it; `0, 0, 0` (no site set in N.I.N.A.) and missing
    /// fields are no site.
    public static func reported(latitude: Double?, longitude: Double?, elevation: Double?) -> Site? {
        guard let latitude, let longitude else { return nil }
        if latitude == 0, longitude == 0, (elevation ?? 0) == 0 { return nil }
        return Site(latitude: latitude, longitude: longitude, elevation: elevation ?? 0)
    }

    public var description: String { "Site(redacted)" }
    public var debugDescription: String { "Site(redacted)" }
}

public enum Sky {
    /// Meeus 13.5, 13.6 with azimuth from north.
    public static func horizontal(_ eq: Equatorial, latitude: Double, localSiderealTime: Double) -> Horizontal {
        let h = localSiderealTime - eq.ra
        let altitude = asinDeg(sinDeg(latitude) * sinDeg(eq.dec) + cosDeg(latitude) * cosDeg(eq.dec) * cosDeg(h))
        let fromSouth = atan2Deg(sinDeg(h), cosDeg(h) * sinDeg(latitude) - tanDeg(eq.dec) * cosDeg(latitude))
        return Horizontal(altitude: altitude, azimuth: normalizedDegrees(fromSouth + 180))
    }

    public static func horizontal(_ eq: Equatorial, site: Site, at date: Date) -> Horizontal {
        horizontal(eq, latitude: site.latitude, localSiderealTime: SiderealTime.localMean(date, longitude: site.longitude))
    }

    /// Hour angle in −180 ..< 180; 0 at the upper meridian transit.
    public static func hourAngle(_ eq: Equatorial, site: Site, at date: Date) -> Double {
        let h = normalizedDegrees(SiderealTime.localMean(date, longitude: site.longitude) - eq.ra)
        return h >= 180 ? h - 360 : h
    }

    /// Rigorous precession from J2000.0 to the mean equinox of the date (Meeus 21.2–21.4).
    public static func precessFromJ2000(_ eq: Equatorial, to date: Date) -> Equatorial {
        let t = JulianDay.centuries(fromJDE: JulianDay.ephemeris(date))
        let zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) / 3600
        let z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) / 3600
        let theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) / 3600
        let a = cosDeg(eq.dec) * sinDeg(eq.ra + zeta)
        let b = cosDeg(theta) * cosDeg(eq.dec) * cosDeg(eq.ra + zeta) - sinDeg(theta) * sinDeg(eq.dec)
        let c = sinDeg(theta) * cosDeg(eq.dec) * cosDeg(eq.ra + zeta) + cosDeg(theta) * sinDeg(eq.dec)
        return Equatorial(ra: normalizedDegrees(atan2Deg(a, b) + z), dec: asinDeg(c))
    }

    /// Angular distance (Meeus 17.1).
    public static func separation(_ a: Equatorial, _ b: Equatorial) -> Double {
        let d = sinDeg(a.dec) * sinDeg(b.dec) + cosDeg(a.dec) * cosDeg(b.dec) * cosDeg(a.ra - b.ra)
        return acos(max(-1, min(1, d))) * 180 / .pi
    }

    /// Nutation in longitude and obliquity in degrees, accurate to 0.5″ (Meeus ch. 22).
    public static func nutation(jde: Double) -> (longitude: Double, obliquity: Double) {
        let t = JulianDay.centuries(fromJDE: jde)
        let omega = 125.04452 - 1934.136261 * t
        let l = 280.4665 + 36000.7698 * t
        let lm = 218.3165 + 481267.8813 * t
        let dpsi = -17.20 * sinDeg(omega) - 1.32 * sinDeg(2 * l) - 0.23 * sinDeg(2 * lm) + 0.21 * sinDeg(2 * omega)
        let deps = 9.20 * cosDeg(omega) + 0.57 * cosDeg(2 * l) + 0.10 * cosDeg(2 * lm) - 0.09 * cosDeg(2 * omega)
        return (dpsi / 3600, deps / 3600)
    }

    /// Mean obliquity of the ecliptic (Meeus 22.2).
    public static func meanObliquity(jde: Double) -> Double {
        let t = JulianDay.centuries(fromJDE: jde)
        return 23.43929111 - (46.8150 * t + 0.00059 * t * t - 0.001813 * t * t * t) / 3600
    }

    /// Ecliptic → equatorial (Meeus 13.3, 13.4).
    public static func equatorial(eclipticLongitude l: Double, latitude b: Double, obliquity e: Double) -> Equatorial {
        let ra = atan2Deg(sinDeg(l) * cosDeg(e) - tanDeg(b) * sinDeg(e), cosDeg(l))
        let dec = asinDeg(sinDeg(b) * cosDeg(e) + cosDeg(b) * sinDeg(e) * sinDeg(l))
        return Equatorial(ra: normalizedDegrees(ra), dec: dec)
    }
}
