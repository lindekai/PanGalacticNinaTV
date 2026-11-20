import Foundation
import Testing
@testable import PanGalacticCore

/// Worked examples from Meeus, Astronomical Algorithms (2nd ed.).
@Suite("Astronomy engine")
struct AstronomyEngineTests {
    static func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func julianDayExample7a() {
        #expect(abs(JulianDay.calendar(year: 1957, month: 10, day: 4.81) - 2436116.31) < 1e-6)
        #expect(JulianDay.from(Self.utc("2000-01-01T12:00:00Z")) == 2451545.0)
        #expect(JulianDay.date(2451545.0) == Self.utc("2000-01-01T12:00:00Z"))
    }

    @Test func siderealTimeExamples12aAnd12b() {
        #expect(abs(SiderealTime.greenwichMean(Self.utc("1987-04-10T00:00:00Z")) - 197.693195) < 1e-5)
        #expect(abs(SiderealTime.greenwichMean(Self.utc("1987-04-10T19:21:00Z")) - 128.7378734) < 1e-5)
    }

    @Test func horizontalExample13b() {
        // Venus from the US Naval Observatory; LST = apparent θ0 − 77.06556° (west).
        let venus = Equatorial(ra: 347.3193375, dec: -6.7198917)
        let h = Sky.horizontal(venus, latitude: 38.92139, localSiderealTime: 128.7378733 - 77.06556)
        #expect(abs(h.altitude - 15.1249) < 0.001)
        #expect(abs(h.azimuth - 248.0337) < 0.001, "68.0337° from south = 248.0337° from north")
    }

    @Test func separationExample17a() {
        let arcturus = Equatorial(ra: 213.9154, dec: 19.1825)
        let spica = Equatorial(ra: 201.2983, dec: -11.1614)
        #expect(abs(Sky.separation(arcturus, spica) - 32.7930) < 0.0005)
    }

    @Test func precessionMovesM31AsTheEphemerisDoes() throws {
        let site = try ReferenceSite.load("central-europe-november")
        let m31 = Equatorial(ra: 10.683333, dec: 41.268611)
        let ofDate = Sky.precessFromJ2000(m31, to: site.snapshotTime)
        #expect(abs(ofDate.ra - site.m31RAOfDate) < 0.02)
        #expect(abs(ofDate.dec - site.m31DecOfDate) < 0.02)
    }

    @Test func siteZeroIsNoSite() {
        #expect(Site.reported(latitude: 0, longitude: 0, elevation: 0) == nil)
        #expect(Site.reported(latitude: nil, longitude: 8, elevation: 0) == nil)
        #expect(Site.reported(latitude: 50, longitude: 8, elevation: 0) == Site(latitude: 50, longitude: 8, elevation: 0))
    }

    @Test func siteDescriptionIsRedacted() {
        let site = Site(latitude: 50.1234, longitude: 8.5678, elevation: 123)
        for text in [String(describing: site), String(reflecting: site), "\(site)"] {
            #expect(!text.contains("50.1234") && !text.contains("8.5678"))
        }
    }
}

/// One site of `Fixtures/astronomy/reference.json` (JPL DE421 via Skyfield).
struct ReferenceSite {
    struct Event { let time: Date; let rising: Bool }
    let name: String
    let site: Site
    let timeZone: TimeZone
    let nightStart: Date
    let nightEnd: Date
    let sun: [String: [Event]]
    let moon: [Event]
    let snapshotTime: Date
    let sunRA, sunDec, sunAltitude, sunAzimuth: Double
    let moonRA, moonDec, moonAltitude, moonIlluminated: Double
    let m31RAOfDate, m31DecOfDate, m31Altitude, m31Azimuth, m31MoonSeparation: Double
    let m31Transit: [Date]
    let nextFullMoon: Date

    static func all() throws -> [ReferenceSite] {
        let data = try LiveFixtureTests.fixture("astronomy/reference.json")
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        return try (root["sites"]?.array ?? []).map(ReferenceSite.init)
    }

    static func load(_ name: String) throws -> ReferenceSite {
        try #require(try all().first { $0.name == name })
    }

    init(_ v: JSONValue) throws {
        func date(_ value: JSONValue?) throws -> Date {
            try #require(value?.string.flatMap { ISO8601DateFormatter().date(from: $0) })
        }
        func number(_ value: JSONValue?) throws -> Double { try #require(value?.double) }
        func events(_ value: JSONValue?) throws -> [Event] {
            try (value?.array ?? []).map { Event(time: try date($0["time"]), rising: $0["direction"]?.string == "rise") }
        }
        name = try #require(v["name"]?.string)
        site = Site(latitude: try number(v["latitude"]), longitude: try number(v["longitude"]),
                    elevation: try number(v["elevation"]))
        let zoneName = try #require(v["timeZone"]?.string)
        timeZone = try #require(TimeZone(identifier: zoneName))
        nightStart = try date(v["nightStart"])
        nightEnd = try date(v["nightEnd"])
        var sun: [String: [Event]] = [:]
        for key in ["horizon", "civil", "nautical", "astronomical"] { sun[key] = try events(v["sun"]?[key]) }
        self.sun = sun
        moon = try events(v["moon"])
        let snap = try #require(v["snapshot"])
        snapshotTime = try date(snap["time"])
        sunRA = try number(snap["sun"]?["ra"]); sunDec = try number(snap["sun"]?["dec"])
        sunAltitude = try number(snap["sun"]?["altitude"]); sunAzimuth = try number(snap["sun"]?["azimuth"])
        moonRA = try number(snap["moon"]?["ra"]); moonDec = try number(snap["moon"]?["dec"])
        moonAltitude = try number(snap["moon"]?["altitude"]); moonIlluminated = try number(snap["moon"]?["illuminated"])
        m31RAOfDate = try number(snap["m31"]?["raOfDate"]); m31DecOfDate = try number(snap["m31"]?["decOfDate"])
        m31Altitude = try number(snap["m31"]?["altitude"]); m31Azimuth = try number(snap["m31"]?["azimuth"])
        m31MoonSeparation = try number(snap["m31"]?["moonSeparation"])
        m31Transit = try (v["m31Transit"]?.array ?? []).map { try date($0) }
        nextFullMoon = try date(v["nextFullMoon"])
    }
}
