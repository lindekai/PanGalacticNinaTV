import Foundation
import PanGalacticCore

/// Where cached sites live; one dictionary per device (ADR 0006).
public protocol SiteStorage: Sendable {
    func load() -> [UUID: CachedSite]
    func save(_ sites: [UUID: CachedSite])
}

public struct UserDefaultsSiteStorage: SiteStorage, @unchecked Sendable {
    public static let key = "site.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> [UUID: CachedSite] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: CachedSite].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }

    public func save(_ sites: [UUID: CachedSite]) {
        let encodable = Dictionary(uniqueKeysWithValues: sites.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) { defaults.set(data, forKey: Self.key) }
    }
}

public final class InMemorySiteStorage: SiteStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [UUID: CachedSite] = [:]
    public init() {}
    public func load() -> [UUID: CachedSite] { lock.withLock { stored } }
    public func save(_ sites: [UUID: CachedSite]) { lock.withLock { stored = sites } }
}

/// The last site each instance's mount reported, so the night page works while the
/// mount is off. Never logged; never leaves the device.
@MainActor
public final class SiteStore {
    private let storage: any SiteStorage
    private var sites: [UUID: CachedSite]

    public init(storage: any SiteStorage = UserDefaultsSiteStorage()) {
        self.storage = storage
        sites = storage.load()
    }

    public func site(for id: UUID) -> CachedSite? { sites[id] }

    public func record(_ site: Site, for id: UUID, at date: Date) {
        if let old = sites[id], old.site == site, date.timeIntervalSince(old.reported) < 3600 { return }
        sites[id] = CachedSite(site: site, reported: date)
        storage.save(sites)
    }

    public func remove(id: UUID) {
        guard sites.removeValue(forKey: id) != nil else { return }
        storage.save(sites)
    }
}
