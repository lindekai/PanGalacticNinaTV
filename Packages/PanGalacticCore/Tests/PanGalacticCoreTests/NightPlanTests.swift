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
        let plan = NightPlan.compute(site: ref.site, target: Self.m31, containing: ref.snapshotTime, timeZone: ref.timeZone)
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
        let plan = NightPlan.compute(site: ref.site, target: nil, containing: ref.snapshotTime, timeZone: ref.timeZone)
        #expect(plan.targetCurve == nil && plan.targetVisibility == nil && plan.transit == nil)
        let now = NightNow.compute(plan: plan, at: ref.snapshotTime)
        #expect(now.target == nil && now.moonSeparation == nil)
    }

    @Test func targetBelowTheHorizonAllNight() throws {
        let ref = try ReferenceSite.load("south-winter") // Polaris never rises at 34° S
        let south = NightTarget(name: "Polaris", coordinates: Equatorial(ra: 37.95, dec: 89.26), epoch: .j2000, source: .sequence)
        let plan = NightPlan.compute(site: ref.site, target: south, containing: ref.snapshotTime, timeZone: ref.timeZone)
        #expect(plan.targetVisibility == .neverRises)
    }

    @Test func circumpolarTargetIsVisible() throws {
        let ref = try ReferenceSite.load("central-europe-november")
        let polaris = NightTarget(name: "Polaris", coordinates: Equatorial(ra: 37.95, dec: 89.26), epoch: .j2000, source: .sequence)
        let plan = NightPlan.compute(site: ref.site, target: polaris, containing: ref.snapshotTime, timeZone: ref.timeZone)
        #expect(plan.targetVisibility == .visible)
        #expect(plan.targetCurve?.allSatisfy { $0.altitude > 0 } == true)
    }

    @Test func midsummerAt58NorthHasNoDarkness() throws {
        // The Sun only reaches about −8.6° at 58° N on 2026-06-21: neither astronomical nor nautical darkness.
        let ref = try ReferenceSite.load("north-midsummer")
        let plan = NightPlan.compute(site: ref.site, target: nil, containing: ref.snapshotTime, timeZone: ref.timeZone)
        #expect(plan.darkness == .none)
    }

    @Test func midsummerAt52NorthFallsBackToNauticalDarkness() throws {
        // Invented site, not in reference.json: at 52° N on 2026-06-21 the Sun reaches about −14.6°,
        // below −12° but not −18°.
        let ref = try ReferenceSite.load("north-midsummer")
        let site = Site(latitude: 52, longitude: 12, elevation: 0)
        let plan = NightPlan.compute(site: site, target: nil, containing: ref.snapshotTime, timeZone: ref.timeZone)
        guard case .nautical(let from, let until) = plan.darkness else { Issue.record("expected nautical, got \(plan.darkness)"); return }
        #expect(from < until)
    }

    @Test func polarNightHasNoSunEventsAndAFullWindowChart() throws {
        let ref = try ReferenceSite.load("arctic-polar-night")
        let plan = NightPlan.compute(site: ref.site, target: nil, containing: ref.snapshotTime, timeZone: ref.timeZone)
        #expect(plan.events.sunAlwaysDown)
        #expect(plan.chartRange == plan.events.window)
    }

    @Test func recomputeOnlyWhenNightTargetOrSiteChanges() throws {
        let ref = try ReferenceSite.load("central-europe-november")
        let plan = NightPlan.compute(site: ref.site, target: Self.m31, containing: ref.snapshotTime, timeZone: ref.timeZone)
        #expect(plan.isCurrent(site: ref.site, target: Self.m31, at: ref.snapshotTime.addingTimeInterval(3600), timeZone: ref.timeZone))
        #expect(!plan.isCurrent(site: ref.site, target: nil, at: ref.snapshotTime, timeZone: ref.timeZone))
        #expect(!plan.isCurrent(site: ref.site, target: Self.m31, at: ref.nightEnd.addingTimeInterval(60), timeZone: ref.timeZone))
        let other = Site(latitude: 48, longitude: 11, elevation: 500)
        #expect(!plan.isCurrent(site: other, target: Self.m31, at: ref.snapshotTime, timeZone: ref.timeZone))
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
            _ = NightPlan.compute(site: ref.site, target: Self.m31, containing: ref.snapshotTime, timeZone: ref.timeZone)
        }
        #expect(elapsed < .milliseconds(50), "took \(elapsed)")
    }
}
