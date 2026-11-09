import Foundation

/// Where the app goes on launch, given the saved instances.
public enum LaunchRoute: Hashable, Sendable {
    /// No instance configured: discovery and manual setup.
    case setup
    /// Exactly one instance: open its dashboard directly.
    case dashboard(DeviceInstance.ID)
    /// Several instances: let the user choose.
    case picker

    public init(instances: [DeviceInstance]) {
        switch instances.count {
        case 0: self = .setup
        case 1: self = .dashboard(instances[0].id)
        default: self = .picker
        }
    }
}
