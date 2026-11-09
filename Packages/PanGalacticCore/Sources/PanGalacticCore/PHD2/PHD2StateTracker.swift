import Foundation

/// Tracks PHD2's application state from the event stream.
///
/// PHD2 sends `AppState` only on connect; afterwards the state must be derived
/// from events. Only the transitions documented in the EventMonitoring wiki are
/// applied. Events that clearly end the known state but have no documented
/// successor (`GuidingStopped`, `Resumed`) set the state to `nil` (unknown) rather
/// than guessing; the next documented event re-establishes it.
public struct PHD2StateTracker: Hashable, Sendable {
    public private(set) var state: PHD2AppState?

    public init(state: PHD2AppState? = nil) {
        self.state = state
    }

    public mutating func apply(_ event: PHD2Event) {
        switch event {
        case .appState(let newState): state = newState
        case .guideStep: state = .guiding
        case .paused: state = .paused
        case .startCalibration: state = .calibrating
        case .loopingExposures: state = .looping
        case .loopingExposuresStopped: state = .stopped
        case .starLost: state = .lostLock
        case .guidingStopped, .resumed: state = nil
        default: break
        }
    }

    /// Call when the TCP connection drops; PHD2 resends `AppState` on reconnect.
    public mutating func connectionLost() {
        state = nil
    }
}
