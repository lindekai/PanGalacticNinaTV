import Foundation

/// Position and phase of the Moon after Meeus ch. 47–48, with the main periodic terms
/// (error ≈ 0.01°, well inside the 0.1° the night page needs).
public enum Moon {
    /// (D, M, M', F, Σl coefficient, Σr coefficient)
    private static let longitudeDistanceTerms: [(Double, Double, Double, Double, Double, Double)] = [
        (0, 0, 1, 0, 6288774, -20905355), (2, 0, -1, 0, 1274027, -3699111), (2, 0, 0, 0, 658314, -2955968),
        (0, 0, 2, 0, 213618, -569925), (0, 1, 0, 0, -185116, 48888), (0, 0, 0, 2, -114332, -3149),
        (2, 0, -2, 0, 58793, 246158), (2, -1, -1, 0, 57066, -152138), (2, 0, 1, 0, 53322, -170733),
        (2, -1, 0, 0, 45758, -204586), (0, 1, -1, 0, -40923, -129620), (1, 0, 0, 0, -34720, 108743),
        (0, 1, 1, 0, -30383, 104755), (2, 0, 0, -2, 15327, 10321), (0, 0, 1, 2, -12528, 0),
        (0, 0, 1, -2, 10980, 79661), (4, 0, -1, 0, 10675, -34782), (0, 0, 3, 0, 10034, -23210),
        (4, 0, -2, 0, 8548, -21636), (2, 1, -1, 0, -7888, 24208), (2, 1, 0, 0, -6766, 30824),
        (1, 0, -1, 0, -5163, -8379), (1, 1, 0, 0, 4987, -16675), (2, -1, 1, 0, 4036, -12831),
        (2, 0, 2, 0, 3994, -10445), (4, 0, 0, 0, 3861, -11650), (2, 0, -3, 0, 3665, 14403),
        (0, 1, -2, 0, -2689, -7003), (2, 0, -1, 2, -2602, 0), (2, -1, -2, 0, 2390, 10056),
        (1, 0, 1, 0, -2348, 6322), (2, -2, 0, 0, 2236, -9884), (0, 1, 2, 0, -2120, 5751),
        (0, 2, 0, 0, -2069, 0),
    ]

    /// (D, M, M', F, Σb coefficient)
    private static let latitudeTerms: [(Double, Double, Double, Double, Double)] = [
        (0, 0, 0, 1, 5128122), (0, 0, 1, 1, 280602), (0, 0, 1, -1, 277693), (2, 0, 0, -1, 173237),
        (2, 0, -1, 1, 55413), (2, 0, -1, -1, 46271), (2, 0, 0, 1, 32573), (0, 0, 2, 1, 17198),
        (2, 0, 1, -1, 9266), (0, 0, 2, -1, 8822), (2, -1, 0, -1, 8216), (2, 0, -2, -1, 4324),
        (2, 0, 1, 1, 4200), (2, 1, 0, -1, -3359), (2, -1, -1, 1, 2463), (2, -1, 0, 1, 2211),
        (2, -1, -1, -1, 2065), (0, 1, -1, -1, -1870), (4, 0, -1, -1, 1828), (0, 1, 0, 1, -1794),
        (0, 0, 0, 3, -1749), (0, 1, -1, 1, -1565), (1, 0, 0, 1, -1491), (0, 1, 1, 1, -1475),
        (0, 1, 1, -1, -1410), (0, 1, 0, -1, -1344), (1, 0, 0, -1, -1335), (0, 0, 3, 1, 1107),
        (4, 0, 0, -1, 1021), (4, 0, -1, 1, 833),
    ]

    private struct Arguments {
        let lp, d, m, mp, f, e: Double
        init(t: Double) {
            let t2 = t * t, t3 = t2 * t, t4 = t3 * t
            lp = 218.3164477 + 481267.88123421 * t - 0.0015786 * t2 + t3 / 538841 - t4 / 65194000
            d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t2 + t3 / 545868 - t4 / 113065000
            m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t3 / 24490000
            mp = 134.9633964 + 477198.8675055 * t + 0.0087414 * t2 + t3 / 69699 - t4 / 14712000
            f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t2 - t3 / 3526000 + t4 / 863310000
            e = 1 - 0.002516 * t - 0.0000074 * t2
        }
        /// Eccentricity factor for terms with M (E for |M| = 1, E² for |M| = 2).
        func factor(_ mCoefficient: Double) -> Double { abs(mCoefficient) == 1 ? e : abs(mCoefficient) == 2 ? e * e : 1 }
    }

    /// Geometric ecliptic coordinates, mean equinox of date.
    public static func ecliptic(jde: Double) -> (longitude: Double, latitude: Double, distanceKm: Double) {
        let t = JulianDay.centuries(fromJDE: jde)
        let a = Arguments(t: t)
        let a1 = 119.75 + 131.849 * t, a2 = 53.09 + 479264.290 * t, a3 = 313.45 + 481266.484 * t
        var sl = 0.0, sr = 0.0, sb = 0.0
        for (d, m, mp, f, l, r) in longitudeDistanceTerms {
            let arg = d * a.d + m * a.m + mp * a.mp + f * a.f
            sl += l * a.factor(m) * sinDeg(arg)
            sr += r * a.factor(m) * cosDeg(arg)
        }
        for (d, m, mp, f, b) in latitudeTerms {
            sb += b * a.factor(m) * sinDeg(d * a.d + m * a.m + mp * a.mp + f * a.f)
        }
        sl += 3958 * sinDeg(a1) + 1962 * sinDeg(a.lp - a.f) + 318 * sinDeg(a2)
        sb += -2235 * sinDeg(a.lp) + 382 * sinDeg(a3) + 175 * sinDeg(a1 - a.f) + 175 * sinDeg(a1 + a.f)
            + 127 * sinDeg(a.lp - a.mp) - 115 * sinDeg(a.lp + a.mp)
        return (normalizedDegrees(a.lp + sl / 1_000_000), sb / 1_000_000, 385000.56 + sr / 1000)
    }

    /// Apparent geocentric position (nutation applied).
    public static func position(at date: Date) -> (equatorial: Equatorial, longitude: Double, distanceKm: Double) {
        let jde = JulianDay.ephemeris(date)
        let geo = ecliptic(jde: jde)
        let nutation = Sky.nutation(jde: jde)
        let lambda = geo.longitude + nutation.longitude
        let epsilon = Sky.meanObliquity(jde: jde) + nutation.obliquity
        return (Sky.equatorial(eclipticLongitude: lambda, latitude: geo.latitude, obliquity: epsilon),
                normalizedDegrees(lambda), geo.distanceKm)
    }

    /// Altitude of the Moon's centre as seen from the Earth's centre; rise and set are
    /// its crossings of +0.125° (Meeus ch. 15).
    public static func geocentricAltitude(site: Site, at date: Date) -> Double {
        Sky.horizontal(position(at: date).equatorial, site: site, at: date).altitude
    }

    /// Topocentric altitude (parallax applied, no refraction) and azimuth.
    public static func horizontal(site: Site, at date: Date) -> Horizontal {
        let moon = position(at: date)
        let geo = Sky.horizontal(moon.equatorial, site: site, at: date)
        let parallax = asinDeg(6378.14 / moon.distanceKm)
        return Horizontal(altitude: geo.altitude - parallax * cosDeg(geo.altitude), azimuth: geo.azimuth)
    }

    /// Illuminated fraction from the phase angle, low accuracy (Meeus 48.4).
    public static func illuminatedFraction(jde: Double) -> Double {
        let a = Arguments(t: JulianDay.centuries(fromJDE: jde))
        let i = 180 - a.d - 6.289 * sinDeg(a.mp) + 2.100 * sinDeg(a.m) - 1.274 * sinDeg(2 * a.d - a.mp)
            - 0.658 * sinDeg(2 * a.d) - 0.214 * sinDeg(2 * a.mp) - 0.110 * sinDeg(a.d)
        return (1 + cosDeg(i)) / 2
    }

    public static func illuminatedFraction(at date: Date) -> Double { illuminatedFraction(jde: JulianDay.ephemeris(date)) }

    /// Elongation in longitude, 0 ..< 360: 0 new moon, 180 full moon.
    static func elongation(at date: Date) -> Double {
        let jde = JulianDay.ephemeris(date)
        return normalizedDegrees(ecliptic(jde: jde).longitude - Sun.position(jde: jde).longitude)
    }

    public static func isWaxing(at date: Date) -> Bool { elongation(at: date) < 180 }

    /// Next instant the elongation reaches 180°, to about a minute.
    public static func nextFullMoon(after date: Date) -> Date {
        var start = date
        var previous = elongation(at: start)
        for _ in 0 ..< 31 * 4 {
            let end = start.addingTimeInterval(6 * 3600)
            let next = elongation(at: end)
            if previous < 180, next >= 180 || next < previous {
                var low = start, high = end
                while high.timeIntervalSince(low) > 30 {
                    let mid = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                    let e = elongation(at: mid)
                    if e < 180, e >= elongation(at: low) { low = mid } else { high = mid }
                }
                return low
            }
            start = end
            previous = next
        }
        return start
    }
}
