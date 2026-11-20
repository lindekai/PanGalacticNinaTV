import Foundation

public enum SiteSource: Equatable, Sendable {
    case mount
    case cached(reported: Date)
}

/// The last site a connected mount reported, kept on the device (ADR 0006).
public struct CachedSite: Codable, Equatable, Sendable {
    public let site: Site
    public let reported: Date
    public init(site: Site, reported: Date) { self.site = site; self.reported = reported }
}

public enum SiteResolution {
    /// The mount always wins; the cache covers the hours the mount is off.
    public static func resolve(mount: Site?, cached: CachedSite?) -> (site: Site, source: SiteSource)? {
        if let mount { return (mount, .mount) }
        if let cached { return (cached.site, .cached(reported: cached.reported)) }
        return nil
    }
}

/// Everything about one night that does not change by the minute; computed once per
/// night, target or site.
public struct NightPlan: Equatable, Sendable {
    public enum TargetVisibility: Equatable, Sendable { case visible, neverRises }
    public enum Darkness: Equatable, Sendable {
        case astronomical(from: Date, until: Date)
        case nautical(from: Date, until: Date)
        case none
    }

    public let site: Site
    public let target: NightTarget?
    public let events: NightEvents
    public let chartRange: DateInterval
    public let sunCurve: [AltitudePoint]
    public let moonCurve: [AltitudePoint]
    public let targetCurve: [AltitudePoint]?
    public let transit: Date?
    public let targetVisibility: TargetVisibility?
    /// Moonrises and moonsets in the 24 h after the window, so the next Moon event is
    /// known in the morning too.
    public let laterMoonEvents: [Crossing]
    /// Target coordinates of date (middle of the night); `nil` without target.
    let targetOfDate: Equatorial?

    /// The target is above the horizon somewhere in the chart range (its curve is drawn
    /// only there); `false` without target.
    public var targetRisesInChart: Bool { targetCurve?.contains { $0.altitude > 0 } == true }

    public var darkness: Darkness {
        if let from = events.astronomicalDusk, let until = events.astronomicalDawn { return .astronomical(from: from, until: until) }
        if let from = events.nauticalDusk, let until = events.nauticalDawn { return .nautical(from: from, until: until) }
        return .none
    }

    public static func compute(site: Site, target: NightTarget?, containing date: Date) -> NightPlan {
        let events = NightEvents.compute(site: site, containing: date)
        let window = events.window
        let start = max(window.start, events.sunset?.addingTimeInterval(-7200) ?? window.start)
        let end = min(window.end, events.sunrise?.addingTimeInterval(3600) ?? window.end)
        let range = start < end ? DateInterval(start: start, end: end) : window
        let ofDate = target?.ofDate(window.start.addingTimeInterval(window.duration / 2))
        let visibility: TargetVisibility? = ofDate.map { eq in
            AltitudeCurve.target(eq, site: site, over: window).allSatisfy { $0.altitude <= 0 } ? .neverRises : .visible
        }
        return NightPlan(site: site, target: target, events: events, chartRange: range,
                         sunCurve: AltitudeCurve.sun(site: site, over: range),
                         moonCurve: AltitudeCurve.moon(site: site, over: range),
                         targetCurve: ofDate.map { AltitudeCurve.target($0, site: site, over: range) },
                         transit: ofDate.flatMap { AltitudeCurve.transit($0, site: site, over: window) },
                         targetVisibility: visibility,
                         laterMoonEvents: NightEvents.moonCrossings(site: site, in: DateInterval(start: window.end, duration: 86400)),
                         targetOfDate: ofDate)
    }

    /// Targets match when name, source and epoch agree and the positions lie within
    /// 0.01°: a tracking mount reports slightly different coordinates on every poll.
    static func sameTarget(_ a: NightTarget?, _ b: NightTarget?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.name == b.name && a.source == b.source && a.epoch == b.epoch
            && Sky.separation(a.coordinates, b.coordinates) < 0.01
    }

    public func isCurrent(site: Site, target: NightTarget?, at date: Date) -> Bool {
        self.site == site && Self.sameTarget(self.target, target)
            && events.window == NightEvents.window(containing: date, site: site)
    }
}

/// Values that move with the clock; recomputed once a minute.
public struct NightNow: Equatable, Sendable {
    public let sun: Horizontal
    public let moon: Horizontal
    public let moonIlluminated: Double
    public let moonWaxing: Bool
    public let nextFullMoon: Date
    public let target: Horizontal?
    public let moonSeparation: Double?
    public let nextMoonEvent: Crossing?

    public static func compute(plan: NightPlan, at date: Date) -> NightNow {
        let site = plan.site
        let moonPosition = Moon.position(at: date)
        let tonight = [plan.events.moonrise.map { Crossing(date: $0, rising: true) },
                       plan.events.moonset.map { Crossing(date: $0, rising: false) }].compactMap { $0 }
        let events = (tonight + plan.laterMoonEvents).filter { $0.date > date }.sorted { $0.date < $1.date }
        return NightNow(sun: Sun.horizontal(site: site, at: date),
                        moon: Moon.horizontal(site: site, at: date),
                        moonIlluminated: Moon.illuminatedFraction(at: date),
                        moonWaxing: Moon.isWaxing(at: date),
                        nextFullMoon: Moon.nextFullMoon(after: date),
                        target: plan.targetOfDate.map { Sky.horizontal($0, site: site, at: date) },
                        moonSeparation: plan.targetOfDate.map { Sky.separation(moonPosition.equatorial, $0) },
                        nextMoonEvent: events.first)
    }
}
