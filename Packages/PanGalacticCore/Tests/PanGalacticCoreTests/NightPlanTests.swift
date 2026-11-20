import Foundation
import Testing
@testable import PanGalacticCore

/// Every row of the spec's "Empty and special states" that the model decides.
@Suite("Night plan")
struct NightPlanTests {
    static let m31 = NightTarget(name: "M 31", coordinates: Equatorial(ra: 10.683333, dec: 41.268611),
                                 epoch: .j2000, source: .sequence)

    @Test func centralEuropeNightWithM31() throws {
        let ref = try ReferenceSite.load("central-europe-november")
        let plan = NightPlan.compute(site: ref.site, target: Self.m31, containing: ref.snapshotTime)
        let sunset = try #require(plan.events.sunset), sunrise = try #require(plan.events.sunrise)
        #expect(plan.chartRange.start == sunset.addingTimeInterval(-7200))
        #expect(plan.chartRange.end == sunrise.addingTimeInterval(3600))
        guard case .astronomical(let from, let until) = plan.darkness else { Issue.record("no darkness"); return }
        #expect(abs(from.timeIntervalSince(ref.sun["astronomical"]![0].time)) < 120)
        #expect(abs(until.timeIntervalSince(ref.sun["astronomical"]![1].time)) < 120)
        #expect(plan.targetVisibility == .visible)
        #expect(abs(try #require(plan.transit).timeIntervalSince(ref.m31Transit[0])) < 120)
        let now = NightNow.compute(plan: plan, at: ref.snapshotTime)
        #expect(abs(try #require(now.target).altitude - ref.m31Altitude) < 0.03)
        #expect(abs(try #require(now.moonSeparation) - ref.m31MoonSeparation) < 0.1)
        #expect(abs(now.moonIlluminated - ref.moonIlluminated) < 0.01)
        #expect(now.moonWaxing)
        #expect(abs(now.nextFullMoon.timeIntervalSince(ref.nextFullMoon)) < 15 * 60)
        let next = try #require(now.nextMoonEvent)
        #expect(!next.rising && next.date > ref.snapshotTime, "the Moon sets next (01:24 UT)")
    }

    @Test func noTarget() throws {
        let ref = try ReferenceSite.load("central-europe-november")
        let plan = NightPlan.compute(site: ref.site, target: nil, containing: ref.snapshotTime)
        #expect(plan.targetCurve == nil && plan.targetVisibility == nil && plan.transit == nil)
        let now = NightNow.compute(plan: plan, at: ref.snapshotTime)
        #expect(now.target == nil && now.moonSeparation == nil)
    }

    @Test func targetBelowTheHorizonAllNight() throws {
        let ref = try ReferenceSite.load("south-winter") // Polaris never rises at 34° S
        let south = NightTarget(name: "Polaris", coordinates: Equatorial(ra: 37.95, dec: 89.26), epoch: .j2000, source: .sequence)
        let plan = NightPlan.compute(site: ref.site, target: south, containing: ref.snapshotTime)
        #expect(plan.targetVisibility == .neverRises)
    }

    @Test func circumpolarTargetIsVisible() throws {
        let ref = try ReferenceSite.load("central-europe-november")
        let polaris = NightTarget(name: "Polaris", coordinates: Equatorial(ra: 37.95, dec: 89.26), epoch: .j2000, source: .sequence)
        let plan = NightPlan.compute(site: ref.site, target: polaris, containing: ref.snapshotTime)
        #expect(plan.targetVisibility == .visible)
        #expect(plan.targetCurve?.allSatisfy { $0.altitude > 0 } == true)
    }

    @Test func midsummerAt58NorthHasNoDarkness() throws {
        // The Sun only reaches about −8.6° at 58° N on 2026-06-21: neither astronomical nor nautical darkness.
        let ref = try ReferenceSite.load("north-midsummer")
        let plan = NightPlan.compute(site: ref.site, target: nil, containing: ref.snapshotTime)
        #expect(plan.darkness == .none)
    }

    @Test func midsummerAt52NorthFallsBackToNauticalDarkness() throws {
        // Invented site, not in reference.json: at 52° N on 2026-06-21 the Sun reaches about −14.6°,
        // below −12° but not −18°.
        let ref = try ReferenceSite.load("north-midsummer")
        let site = Site(latitude: 52, longitude: 12, elevation: 0)
        let plan = NightPlan.compute(site: site, target: nil, containing: ref.snapshotTime)
        guard case .nautical(let from, let until) = plan.darkness else { Issue.record("expected nautical, got \(plan.darkness)"); return }
        #expect(from < until)
    }

    @Test func polarNightHasNoSunEventsAndAFullWindowChart() throws {
        let ref = try ReferenceSite.load("arctic-polar-night")
        let plan = NightPlan.compute(site: ref.site, target: nil, containing: ref.snapshotTime)
        #expect(plan.events.sunAlwaysDown)
        #expect(plan.chartRange == plan.events.window)
    }

    @Test func recomputeOnlyWhenNightTargetOrSiteChanges() throws {
        let ref = try ReferenceSite.load("central-europe-november")
        let plan = NightPlan.compute(site: ref.site, target: Self.m31, containing: ref.snapshotTime)
        #expect(plan.isCurrent(site: ref.site, target: Self.m31, at: ref.snapshotTime.addingTimeInterval(3600)))
        #expect(!plan.isCurrent(site: ref.site, target: nil, at: ref.snapshotTime))
        #expect(!plan.isCurrent(site: ref.site, target: Self.m31, at: plan.events.window.end.addingTimeInterval(60)))
        let other = Site(latitude: 48, longitude: 11, elevation: 500)
        #expect(!plan.isCurrent(site: other, target: Self.m31, at: ref.snapshotTime))
    }

    @Test func mountJitterKeepsThePlanButAMoveDoesNot() throws {
        let ref = try ReferenceSite.load("central-europe-november")
        func mount(_ ra: Double, _ dec: Double) -> NightTarget {
            NightTarget(name: nil, coordinates: Equatorial(ra: ra, dec: dec), epoch: .ofDate, source: .mount)
        }
        let plan = NightPlan.compute(site: ref.site, target: mount(10.9, 41.4), containing: ref.snapshotTime)
        #expect(plan.isCurrent(site: ref.site, target: mount(10.901, 41.401), at: ref.snapshotTime))
        #expect(!plan.isCurrent(site: ref.site, target: mount(11.9, 41.4), at: ref.snapshotTime))
        #expect(!plan.isCurrent(site: ref.site, target: mount(10.9, 42.4), at: ref.snapshotTime))
    }

    @Test func nextMoonEventInTheMorningLooksPastTheWindow() throws {
        let ref = try ReferenceSite.load("central-europe-november")
        let morning = ref.nightEnd.addingTimeInterval(-7200)
        let plan = NightPlan.compute(site: ref.site, target: nil, containing: morning)
        let next = try #require(NightNow.compute(plan: plan, at: morning).nextMoonEvent)
        #expect(next.rising && next.date > ref.nightEnd, "moonrise after noon the next day")
    }

    /// The night belongs to the site, not to the Apple TV: a remote observatory far from the
    /// device's time zone (here: an Apple TV in Central Europe) still gets its whole night, the
    /// window starting at the site's mean local noon. With the device's noon (11:00 / 10:00 UT)
    /// both lost their sunrise.
    @Test(arguments: [
        // Invented site at 33° N 107° W, evening there; 04:00 UT is 21:00 mean local time.
        (Site(latitude: 33, longitude: -107, elevation: 0), "2026-11-21T04:00:00Z"),
        // south-winter's site (34° S 151° E), 21:00 local on 2026-07-15.
        (Site(latitude: -34, longitude: 151, elevation: 0), "2026-07-15T11:00:00Z"),
    ])
    func remoteSiteGetsItsWholeNight(_ site: Site, _ evening: String) throws {
        let date = try #require(ISO8601DateFormatter().date(from: evening))
        let plan = NightPlan.compute(site: site, target: nil, containing: date)
        let sunset = try #require(plan.events.sunset), sunrise = try #require(plan.events.sunrise)
        #expect(sunset < date && date < sunrise)
        guard case .astronomical(let from, let until) = plan.darkness else { Issue.record("no darkness: \(plan.darkness)"); return }
        #expect(sunset < from && from < until && until < sunrise)
        #expect(plan.isCurrent(site: site, target: nil, at: date.addingTimeInterval(3600)))
    }

    /// Owner decision: the target curve, like the Moon's, is drawn only above the horizon.
    @Test func curveSegmentsOnlyAboveTheHorizon() {
        let t0 = Date(timeIntervalSince1970: 0)
        let points = [-5.0, 2, 4, 0, -1, 3, -2, 1, 6].enumerated().map {
            AltitudePoint(date: t0.addingTimeInterval(Double($0.offset) * 300), altitude: $0.element)
        }
        let segments = AltitudeCurve.segmentsAboveHorizon(points)
        #expect(segments.map { $0.map(\.altitude) } == [[2, 4], [3], [1, 6]], "0° counts as not above; [3] is an isolated sample")
        #expect(AltitudeCurve.segmentsAboveHorizon([]).isEmpty)
        #expect(AltitudeCurve.segmentsAboveHorizon(points.map { AltitudePoint(date: $0.date, altitude: -abs($0.altitude)) }).isEmpty)
    }

    @Test func targetAboveTheHorizonInTheChart() throws {
        let ref = try ReferenceSite.load("south-winter")
        let polaris = NightTarget(name: "Polaris", coordinates: Equatorial(ra: 37.95, dec: 89.26), epoch: .j2000, source: .sequence)
        #expect(!NightPlan.compute(site: ref.site, target: polaris, containing: ref.snapshotTime).targetRisesInChart)
        #expect(!NightPlan.compute(site: ref.site, target: nil, containing: ref.snapshotTime).targetRisesInChart)
        let home = try ReferenceSite.load("central-europe-november")
        #expect(NightPlan.compute(site: home.site, target: Self.m31, containing: home.snapshotTime).targetRisesInChart)
    }

    @Test func mountSiteWinsOverTheCache() {
        let mount = Site(latitude: 50, longitude: 8, elevation: 0)
        let cached = CachedSite(site: Site(latitude: 48, longitude: 11, elevation: 0), reported: Date(timeIntervalSince1970: 0))
        #expect(SiteResolution.resolve(mount: mount, cached: cached)?.source == .mount)
        #expect(SiteResolution.resolve(mount: nil, cached: cached)?.source == .cached(reported: Date(timeIntervalSince1970: 0)))
        #expect(SiteResolution.resolve(mount: nil, cached: nil) == nil)
    }

    @Test func wholeNightStaysWellBelow50Milliseconds() throws {
        let ref = try ReferenceSite.load("central-europe-november")
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = NightPlan.compute(site: ref.site, target: Self.m31, containing: ref.snapshotTime)
        }
        #expect(elapsed < .milliseconds(50), "took \(elapsed)")
    }
}
