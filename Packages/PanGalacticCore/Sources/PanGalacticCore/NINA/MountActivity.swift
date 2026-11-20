import Foundation

/// What the mount is doing, in order of precedence: slewing beats parked beats tracking.
public enum MountActivity: Hashable, Sendable {
    case slewing, parked, tracking, notTracking, unknown
}

extension NINAEquipmentSummary.Mount {
    public var activity: MountActivity {
        guard device.connected else { return .unknown }
        if slewing == true { return .slewing }
        if atPark == true { return .parked }
        switch trackingEnabled {
        case .some(true): return .tracking
        case .some(false): return .notTracking
        case nil: return .unknown
        }
    }
}
