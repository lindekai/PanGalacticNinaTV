import Foundation
import Observation
import PanGalacticCore
import PanGalacticServices

/// App-wide state: configured instances and the one active connection.
@MainActor
@Observable
final class AppModel {
    let store: InstanceStore
    private(set) var activeInstanceID: DeviceInstance.ID?
    private(set) var connection: InstanceConnection?

    init(store: InstanceStore = InstanceStore()) {
        self.store = store
        if case .dashboard(let id) = store.launchRoute {
            activate(id)
        }
    }

    var activeInstance: DeviceInstance? {
        activeInstanceID.flatMap(store.instance(id:))
    }

    /// Opens the dashboard of an instance and starts monitoring it.
    func activate(_ id: DeviceInstance.ID) {
        guard let instance = store.instance(id: id) else { return }
        connection?.stop()
        let connection = InstanceConnection(instance: instance)
        connection.onSuccess = { [weak self] date in
            self?.store.markSeen(id: id, at: date)
        }
        self.connection = connection
        activeInstanceID = id
        connection.start()
    }

    /// Leaves the dashboard (back to picker or setup).
    func deactivate() {
        connection?.stop()
        connection = nil
        activeInstanceID = nil
    }

    func save(_ instance: DeviceInstance) {
        store.upsert(instance)
        // Restart monitoring if the active instance was edited (host/port may have changed).
        if instance.id == activeInstanceID {
            activate(instance.id)
        } else if store.instances.count == 1 {
            activate(instance.id)
        }
    }

    func delete(_ id: DeviceInstance.ID) {
        if id == activeInstanceID { deactivate() }
        store.remove(id: id)
        if case .dashboard(let only) = store.launchRoute, activeInstanceID == nil {
            activate(only)
        }
    }

    /// Network activity only while the app is in the foreground.
    func scenePhaseChanged(isActive: Bool) {
        guard let connection else { return }
        if isActive {
            connection.start()
        } else {
            connection.stop()
        }
    }
}
