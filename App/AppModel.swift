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
    /// Full-resolution renders for the image viewer; one per active instance.
    private(set) var renderService: ImageRenderService?
    let siteStore: SiteStore
    /// Night page and Object module of the active instance.
    private(set) var night: NightModel?

    init(store: InstanceStore = InstanceStore(), siteStore: SiteStore = SiteStore()) {
        self.store = store
        self.siteStore = siteStore
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
        connection.onSuccess = { [weak self, weak connection] date in
            self?.store.markSeen(id: id, at: date)
            if let site = connection?.equipment?.mount?.site { self?.siteStore.record(site, for: id, at: date) }
        }
        night = NightModel()
        self.connection = connection
        renderService = ImageRenderService(instance: instance)
        activeInstanceID = id
        connection.start()
    }

    /// Leaves the dashboard (back to picker or setup).
    func deactivate() {
        connection?.stop()
        connection = nil
        renderService = nil
        night = nil
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
        siteStore.remove(id: id)
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
