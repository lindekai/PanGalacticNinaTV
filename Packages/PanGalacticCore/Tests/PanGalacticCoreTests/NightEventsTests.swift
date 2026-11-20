import Foundation
import Testing
@testable import PanGalacticCore

/// Night events and curves against JPL DE421 (Fixtures/astronomy/reference.json).
@Suite("Night events")
struct NightEventsTests {
    static let tolerance: TimeInterval = 120

    /// The window runs from the site's mean local noon (12:00 UT − longitude × 4 min) to the
    /// next. The fixture's own windows use the civil zone's noon; with daylight saving time
    /// both lie within two hours.
    @Test(arguments: try ReferenceSite.all())
    func windowIsTheSitesMeanLocalNoonToNoon(_ ref: ReferenceSite) {
        let window = NightEvents.window(containing: ref.snapshotTime, site: ref.site)
        let offset = ref.site.longitude * 240
        let localStart = (window.start.timeIntervalSince1970 + offset).truncatingRemainder(dividingBy: 86400)
        #expect(abs(localStart - 43200) < 1, "\(ref.name) starts at mean local noon")
        #expect(window.duration == 86400)
        #expect(window.contains(ref.snapshotTime))
        #expect(abs(window.start.timeIntervalSince(ref.nightStart)) <= 7200, "\(ref.name)")
        // Before noon the night started the previous day.
        let morning = window.end.addingTimeInterval(-3600)
        #expect(NightEvents.window(containing: morning, site: ref.site) == window)
        #expect(NightEvents.window(containing: window.end, site: ref.site).start == window.end)
    }

    @Test(arguments: try ReferenceSite.all())
    func sunCrossingsMatchTheEphemeris(_ ref: ReferenceSite) {
        let window = DateInterval(start: ref.nightStart, end: ref.nightEnd)
        let thresholds: [(String, Double)] = [("horizon", -0.833), ("civil", -6), ("nautical", -12), ("astronomical", -18)]
        for (key, threshold) in thresholds {
            let ours = Crossings.find(in: window, threshold: threshold) { Sun.horizontal(site: ref.site, at: $0).altitude }
            let expected = ref.sun[key] ?? []
            #expect(ours.count == expected.count, "\(ref.name) \(key)")
            for (a, b) in zip(ours, expected) {
                #expect(a.rising == b.rising, "\(ref.name) \(key)")
                #expect(abs(a.date.timeIntervalSince(b.time)) < Self.tolerance, "\(ref.name) \(key) \(a.date) vs \(b.time)")
            }
        }
    }

    @Test(arguments: try ReferenceSite.all())
    func moonCrossingsMatchTheEphemeris(_ ref: ReferenceSite) {
        let window = DateInterval(start: ref.nightStart, end: ref.nightEnd)
        let ours = Crossings.find(in: window, threshold: 0.125) { Moon.geocentricAltitude(site: ref.site, at: $0) }
        #expect(ours.count == ref.moon.count, "\(ref.name)")
        for (a, b) in zip(ours, ref.moon) {
            #expect(a.rising == b.rising)
            #expect(abs(a.date.timeIntervalSince(b.time)) < Self.tolerance, "\(ref.name) moon \(a.date) vs \(b.time)")
        }
    }

    @Test func centralEuropeNovemberEvents() throws {
        let ref = try ReferenceSite.load("central-europe-november")
        let night = NightEvents.compute(site: ref.site, containing: ref.snapshotTime)
        let sunset = try #require(night.sunset), sunrise = try #require(night.sunrise)
        #expect(abs(sunset.timeIntervalSince(ref.sun["horizon"]![0].time)) < Self.tolerance)
        #expect(abs(sunrise.timeIntervalSince(ref.sun["horizon"]![1].time)) < Self.tolerance)
        let dusk = try #require(night.astronomicalDusk), dawn = try #require(night.astronomicalDawn)
        #expect(abs(dusk.timeIntervalSince(ref.sun["astronomical"]![0].time)) < Self.tolerance)
        #expect(abs(dawn.timeIntervalSince(ref.sun["astronomical"]![1].time)) < Self.tolerance)
        #expect(night.moonrise != nil && night.moonset != nil)
        #expect(!night.sunAlwaysUp && !night.sunAlwaysDown)
    }

    @Test func midsummerHasNoAstronomicalDarkness() throws {
        let ref = try ReferenceSite.load("north-midsummer")
        let night = NightEvents.compute(site: ref.site, containing: ref.snapshotTime)
        #expect(night.astronomicalDusk == nil && night.astronomicalDawn == nil)
        // The Sun only dips to about -8.6 degrees here: civil twilight yes, nautical no (fixture agrees).
        #expect(night.nauticalDusk == nil && night.nauticalDawn == nil)
        #expect(night.civilDusk != nil && night.civilDawn != nil)
    }

    @Test func polarNightHasNoSunrise() throws {
        let ref = try ReferenceSite.load("arctic-polar-night")
        let night = NightEvents.compute(site: ref.site, containing: ref.snapshotTime)
        #expect(night.sunset == nil && night.sunrise == nil)
        #expect(night.sunAlwaysDown && !night.sunAlwaysUp)
    }

    @Test(arguments: try ReferenceSite.all())
    func m31TransitMatchesTheEphemeris(_ ref: ReferenceSite) throws {
        let window = DateInterval(start: ref.nightStart, end: ref.nightEnd)
        let m31 = Sky.precessFromJ2000(Equatorial(ra: 10.683333, dec: 41.268611), to: window.start)
        let transit = AltitudeCurve.transit(m31, site: ref.site, over: window)
        let expected = try #require(ref.m31Transit.first)
        let found = try #require(transit)
        #expect(abs(found.timeIntervalSince(expected)) < Self.tolerance, "\(ref.name)")
    }

    @Test func curvesSampleEveryFiveMinutes() throws {
        let ref = try ReferenceSite.load("central-europe-november")
        let window = DateInterval(start: ref.nightStart, end: ref.nightEnd)
        let m31 = Sky.precessFromJ2000(Equatorial(ra: 10.683333, dec: 41.268611), to: ref.snapshotTime)
        let curve = AltitudeCurve.target(m31, site: ref.site, over: window)
        #expect(curve.count == 289)
        #expect(curve.first?.date == window.start && curve.last?.date == window.end)
        let at2100 = try #require(curve.first { $0.date == ref.snapshotTime })
        #expect(abs(at2100.altitude - ref.m31Altitude) < 0.03)
        #expect(AltitudeCurve.moon(site: ref.site, over: window).count == 289)
        #expect(AltitudeCurve.sun(site: ref.site, over: window).count == 289)
    }
}
