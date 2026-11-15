import Foundation

/// What the dashboard's Exposure pill shows. Only a live connection with a
/// connected camera yields a definite answer; stale or offline data is `unknown`
/// so a frozen exposure end time can never read as "overdue".
public enum ExposureDisplay: Equatable, Sendable {
    case unknown
    case idle
    case running(secondsLeft: Int)
    case overdue

    public static func state(camera: NINAEquipmentSummary.Camera?, phase: ConnectionPhase, now: Date) -> ExposureDisplay {
        guard phase == .live, let camera, camera.device.connected else { return .unknown }
        if camera.isOverdue(now: now) { return .overdue }
        if camera.isExposing == true {
            if let end = camera.exposureEndTime, end > now {
                return .running(secondsLeft: Int(end.timeIntervalSince(now).rounded(.up)))
            }
            return .unknown
        }
        return camera.isExposing == false ? .idle : .unknown
    }
}
