import Foundation

/// State of a module's status LED. Colour never carries meaning alone; views add a word
/// where the state is not obvious.
public enum StatusLight: Hashable, Sendable {
    case normal, warning, fault, unknown

    /// Connected devices are normal while live and a warning while stale. Without a
    /// current connection nothing is known about the device.
    public static func device(_ device: NINAEquipmentSummary.Device?, phase: ConnectionPhase) -> StatusLight {
        switch phase {
        case .offline, .connecting: return .unknown
        case .live, .stale: break
        }
        guard device?.connected == true else { return .unknown }
        return phase == .stale ? .warning : .normal
    }

    /// Like `device`, plus a warning for an exposure that is overdue (hung driver).
    public static func camera(_ camera: NINAEquipmentSummary.Camera?, phase: ConnectionPhase, now: Date) -> StatusLight {
        let base = device(camera?.device, phase: phase)
        if base == .normal, camera?.isOverdue(now: now) == true { return .warning }
        return base
    }
}
