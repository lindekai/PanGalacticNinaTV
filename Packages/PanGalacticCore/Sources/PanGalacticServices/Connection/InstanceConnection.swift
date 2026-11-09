import Foundation
import Observation
import PanGalacticCore

/// Live connection to one instance: polls allowlisted endpoints, tracks
/// live/stale/offline and reconnects with backoff. Single source of truth for
/// that instance's connection lifecycle.
@MainActor
@Observable
public final class InstanceConnection {
    public let instance: DeviceInstance

    public private(set) var phase: ConnectionPhase = .connecting
    public private(set) var lastSuccess: Date?
    public private(set) var lastError: String?
    public private(set) var nextAttempt: Date?
    public private(set) var pluginVersion: String?
    public private(set) var ninaVersion: String?
    /// Last successfully fetched equipment state; kept while stale, never invented.
    public private(set) var equipment: NINAEquipmentSummary?
    /// Set when the server is reachable but not a supported Advanced API.
    public private(set) var incompatibility: String?
    /// Metadata of the newest image in N.I.N.A.'s history (any type, incl. snapshots).
    public private(set) var latestImage: NINAImageSaveStatistics?
    /// History index of `latestImage`, for the full-resolution render.
    public private(set) var latestImageIndex: Int?
    /// JPEG thumbnail of `latestImage` as written by N.I.N.A. (about 600 px wide).
    public private(set) var latestThumbnail: Data?

    public static let maxThumbnailBytes = 4 * 1024 * 1024

    @ObservationIgnored private var images = LatestImageTracker()

    @ObservationIgnored private var machine: ConnectionStateMachine
    @ObservationIgnored private let client: NINAClient
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let random: @Sendable () -> Double
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored public var onSuccess: ((Date) -> Void)?

    public init(
        instance: DeviceInstance,
        policy: ConnectionPolicy = ConnectionPolicy(),
        transport: any HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = { Date() },
        random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        self.instance = instance
        machine = ConnectionStateMachine(policy: policy)
        client = NINAClient(instance: instance, transport: transport)
        self.now = now
        self.random = random
        lastSuccess = instance.lastSeen
    }

    public var isRunning: Bool { task != nil }

    public func start() {
        guard task == nil else { return }
        machine.reset()
        refreshPhase()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.pollOnce()
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Skips the current backoff wait (e.g. user pressed "Retry").
    public func retryNow() {
        stop()
        start()
    }

    /// One poll cycle; returns the delay before the next one. Internal for tests.
    func pollOnce() async -> TimeInterval {
        do {
            if pluginVersion == nil {
                let version = try await client.get(.version, as: String.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard PluginCompatibility.isSupported(version) else {
                    incompatibility = version
                    stop() // cancels the polling task; it exits after this cycle
                    return 0
                }
                pluginVersion = version
                ninaVersion = (try? await client.get(.ninaVersion, as: String.self))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            equipment = try await client.get(.equipmentInfo, as: NINAEquipmentSummary.self)
            await pollImages()
            let at = now()
            let delay = machine.recordSuccess(at: at)
            onSuccess?(at)
            refreshPhase()
            return delay
        } catch {
            let delay = machine.recordFailure(at: now(), error: Self.describe(error), unitRandom: random())
            if machine.phase(at: now()) == .offline {
                // Re-identify after an outage: the server may have been replaced or upgraded.
                pluginVersion = nil
                images.reset()
            }
            refreshPhase()
            return delay
        }
    }

    /// Fetches metadata and thumbnail only when the newest image changed. Reachability
    /// is judged by `/equipment/info`; image failures are retried on the next polls.
    private func pollImages() async {
        guard let count = try? await client.get(.imageHistoryCount, as: Int.self) else { return }
        if images.update(count: count) {
            latestImageIndex = images.latestIndex
            if images.latestIndex == nil {
                latestImage = nil
                latestThumbnail = nil
            }
        }
        guard let index = images.latestIndex else { return }
        if images.needsMetadata {
            guard let entries = try? await client.get(.imageHistoryEntry(index: index),
                                                      as: [NINAImageSaveStatistics].self) else { return }
            latestImage = entries.first
            latestThumbnail = nil
            images.metadataFetched()
        }
        if images.needsThumbnail {
            let data = try? await client.raw(.thumbnail(index: index), maxBytes: Self.maxThumbnailBytes)
            let jpeg = data.flatMap { ImageFormat.isJPEG($0) ? $0 : nil }
            images.thumbnailFetched(success: jpeg != nil)
            if let jpeg { latestThumbnail = jpeg }
        }
    }

    /// Re-evaluates time-based staleness; call periodically from the UI.
    public func refreshPhase() {
        let at = now()
        phase = machine.phase(at: at)
        lastSuccess = machine.lastSuccess ?? instance.lastSeen
        lastError = machine.lastError
        nextAttempt = machine.nextAttempt
    }

    static func describe(_ error: any Error) -> String {
        switch error as? NINAClientError {
        case .transport(let message): message
        case .httpStatus(let code): "HTTP \(code)"
        case .responseTooLarge: "Response too large"
        case .decoding: "Unexpected response format"
        case .api(.server(_, let message)): message.isEmpty ? "Server error" : message
        case .request(let error): String(describing: error)
        case nil: error.localizedDescription
        }
    }
}
