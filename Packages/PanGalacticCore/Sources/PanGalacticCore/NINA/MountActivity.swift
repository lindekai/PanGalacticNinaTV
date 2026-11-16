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

    /// N.I.N.A. reports where the mount points. That is the imaged object's position
    /// only while the mount tracks; parked or slewing values must not be shown as the
    /// object's. From M4 the object's altitude is computed from its coordinates instead.
    public var trackedObjectAltitude: Double? { activity == .tracking ? altitudeDegrees : nil }
    public var trackedRightAscension: String? { activity == .tracking ? rightAscension : nil }
    public var trackedDeclination: String? { activity == .tracking ? declination : nil }
}
