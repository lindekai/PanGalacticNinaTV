import Foundation
import Observation
import PanGalacticCore

/// Persists the instance list. tvOS has no guaranteed persistent file storage,
/// so the default implementation uses `UserDefaults` (ADR 0003).
public protocol InstanceStorage: Sendable {
    func load() throws -> [DeviceInstance]
    func save(_ instances: [DeviceInstance]) throws
}

public struct UserDefaultsInstanceStorage: InstanceStorage, @unchecked Sendable {
    /// Versioned so the format can evolve without losing user data.
    struct Envelope: Codable {
        var version: Int
        var instances: [DeviceInstance]
    }

    public static let key = "instances.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() throws -> [DeviceInstance] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return try JSONDecoder().decode(Envelope.self, from: data).instances
    }

    public func save(_ instances: [DeviceInstance]) throws {
        let data = try JSONEncoder().encode(Envelope(version: 1, instances: instances))
        defaults.set(data, forKey: Self.key)
    }
}

public final class InMemoryInstanceStorage: InstanceStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [DeviceInstance]

    public init(_ instances: [DeviceInstance] = []) {
        stored = instances
    }

    public func load() throws -> [DeviceInstance] { lock.withLock { stored } }
    public func save(_ instances: [DeviceInstance]) throws { lock.withLock { stored = instances } }
}

/// Source of truth for configured instances.
@MainActor
@Observable
public final class InstanceStore {
    public private(set) var instances: [DeviceInstance] = []
    /// Set when loading or saving failed; the UI surfaces it instead of silently losing data.
    public private(set) var persistenceError: String?

    private let storage: any InstanceStorage

    public init(storage: any InstanceStorage = UserDefaultsInstanceStorage()) {
        self.storage = storage
        do {
            instances = try storage.load()
        } catch {
            persistenceError = String(describing: error)
        }
    }

    public var launchRoute: LaunchRoute { LaunchRoute(instances: instances) }

    public func instance(id: DeviceInstance.ID) -> DeviceInstance? {
        instances.first { $0.id == id }
    }

    /// Adds or replaces (by id) an instance.
    public func upsert(_ instance: DeviceInstance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        } else {
            instances.append(instance)
        }
        persist()
    }

    public func remove(id: DeviceInstance.ID) {
        instances.removeAll { $0.id == id }
        persist()
    }

    /// Records a successful contact. Persisted at most once a minute per instance
    /// to avoid rewriting defaults on every poll.
    public func markSeen(id: DeviceInstance.ID, at date: Date) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        let previous = instances[index].lastSeen
        instances[index].lastSeen = date
        if previous.map({ date.timeIntervalSince($0) >= 60 }) ?? true {
            persist()
        }
    }

    /// Whether an instance with the same host and port already exists.
    public func contains(host: String, port: Int) -> Bool {
        instances.contains { $0.host.caseInsensitiveCompare(host) == .orderedSame && $0.apiPort == port }
    }

    private func persist() {
        do {
            try storage.save(instances)
            persistenceError = nil
        } catch {
            persistenceError = String(describing: error)
        }
    }
}
