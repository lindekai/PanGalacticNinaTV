import Foundation
import Observation
import PanGalacticCore
import PanGalacticServices

/// The night of the active instance: the plan once per night/target/site, the moving
/// values once a minute. Computed on the device; nothing is fetched for it.
@MainActor
@Observable
final class NightModel {
    private(set) var plan: NightPlan?
    private(set) var now: NightNow?
    private(set) var siteSource: SiteSource?
    /// Where the telescope points, from `mount/info` while connected.
    private(set) var telescope: Horizontal?
    /// The pointing is from the last successful poll, not a live one.
    private(set) var telescopeIsStale = false
    /// The shown target (sequence or mount) is from the last successful poll, not a live one.
    private(set) var targetIsStale = false
    /// Connecting or offline without a target: unknown ("—"), not "No target".
    private(set) var targetIsUnknown = false
    @ObservationIgnored private var lastMinute: Date?

    func update(connection: InstanceConnection, cached: CachedSite?, at date: Date) {
        let mount = connection.equipment?.mount
        let pointing = mount.flatMap { m -> Horizontal? in
            guard m.device.connected, let alt = m.altitudeDegrees, let az = m.azimuthDegrees else { return nil }
            return Horizontal(altitude: alt, azimuth: az)
        }
        // Assign only on change: every assignment would invalidate the observing views.
        if telescope != pointing { telescope = pointing }
        let pointingStale = connection.phase != .live && pointing != nil
        if telescopeIsStale != pointingStale { telescopeIsStale = pointingStale }
        let target = NightTarget.resolve(sequence: connection.sequenceTarget, mount: mount,
                                         imageTarget: connection.latestImage?.targetName)
        let state = NightTargetState(target: target, phase: connection.phase)
        if targetIsStale != state.isStale { targetIsStale = state.isStale }
        if targetIsUnknown != state.isUnknown { targetIsUnknown = state.isUnknown }
        guard let resolved = SiteResolution.resolve(mount: mount?.site, cached: cached) else {
            if plan != nil { plan = nil }
            if now != nil { now = nil }
            if siteSource != nil { siteSource = nil }
            lastMinute = nil
            return
        }
        if siteSource != resolved.source { siteSource = resolved.source }
        var fresh = false
        if plan?.isCurrent(site: resolved.site, target: target, at: date) != true {
            plan = NightPlan.compute(site: resolved.site, target: target, containing: date)
            fresh = true
        }
        let minute = Calendar.current.dateInterval(of: .minute, for: date)?.start ?? date
        if fresh || lastMinute != minute, let plan {
            now = NightNow.compute(plan: plan, at: date)
            lastMinute = minute
        }
    }
}
