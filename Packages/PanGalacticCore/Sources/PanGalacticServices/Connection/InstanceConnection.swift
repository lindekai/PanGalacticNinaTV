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

    /// Recent history entries, oldest first, for trends (HFR sparkline, Image page).
    /// Kept while stale; never invented.
    public private(set) var recentImages: [NINAImageSaveStatistics] = []

    /// HFR values of the newest 24 history entries, oldest first; entries without HFR are skipped.
    public var recentHFR: [Double] { recentImages.suffix(24).compactMap(\.hfr) }

    /// History entries fetched per poll while backfilling, to keep each cycle cheap.
    public static let backfillPerPoll = 4

    /// Progress of the running sequence; `nil` while unknown (not fetched yet,
    /// request failed, or offline). Kept while stale, never invented.
    public private(set) var sequence: SequenceProgress?

    /// The sequence as a tree for the strip and the sequence page; `nil` while unknown.
    /// Kept while stale, never invented.
    public private(set) var sequenceTree: SequenceTree?
    /// `/sequence/json` answered, but without a container; distinct from an unknown tree.
    public private(set) var sequenceTreeIsEmpty = false
    /// Target of the running (else the next) target container, from `/sequence/state`;
    /// `nil` while unknown or when the sequence has none.
    public private(set) var sequenceTarget: NightTarget?

    /// N.I.N.A.'s guide graph while the guider is connected; kept while stale, never invented.
    public private(set) var guiderGraph: NINAGuiderGraph?
    /// The last graph request failed (the plugin reads it via reflection, which a N.I.N.A.
    /// update can break); the chart then says so instead of showing nothing.
    public private(set) var guiderGraphFailed = false

    /// The sequence tree is larger than the other polls (6–20 KB); fetch it at most this often.
    public static let sequenceInterval: TimeInterval = 15

    public static let maxThumbnailBytes = 4 * 1024 * 1024

    @ObservationIgnored private var images = LatestImageTracker()
    @ObservationIgnored private var history = ImageHistoryBuffer()
    @ObservationIgnored private var lastSequencePoll: Date?

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
            // `/equipment/info` is the reachability signal: record it before the
            // optional image work so slow or failing image requests cannot age it.
            let at = now()
            let delay = machine.recordSuccess(at: at)
            onSuccess?(at)
            refreshPhase()
            await pollGuiderGraph()
            await pollSequence(at: at)
            await pollImages()
            return delay
        } catch {
            let delay = machine.recordFailure(at: now(), error: Self.describe(error), unitRandom: random())
            if machine.phase(at: now()) == .offline {
                // Re-identify after an outage: the server may have been replaced or upgraded.
                pluginVersion = nil
                images.reset()
                history.reset()
                sequence = nil
                sequenceTree = nil
                sequenceTreeIsEmpty = false
                sequenceTarget = nil
                lastSequencePoll = nil
            }
            refreshPhase()
            return delay
        }
    }

    /// About 25 KB with 100 steps; requested only while a guider is connected.
    private func pollGuiderGraph() async {
        guard equipment?.guider?.device.connected == true else {
            guiderGraph = nil
            guiderGraphFailed = false
            return
        }
        do {
            guiderGraph = try await client.get(.guiderGraph, as: NINAGuiderGraph.self)
            guiderGraphFailed = false
        } catch {
            guiderGraph = nil
            guiderGraphFailed = true
        }
    }

    /// `/sequence/state` carries pass counts and loop conditions, `/sequence/json` the
    /// live end time of time-bound loops and the tree for the strip and the sequence page.
    /// Each is unknown on its own when its request fails.
    private func pollSequence(at now: Date) async {
        if let last = lastSequencePoll, now.timeIntervalSince(last) < Self.sequenceInterval { return }
        lastSequencePoll = now
        let state = try? await client.get(.sequenceState, as: JSONValue.self)
        let json = try? await client.get(.sequenceJSON, as: JSONValue.self)
        sequence = state.map { SequenceProgress(state: $0, json: json) }
        sequenceTree = json.flatMap { SequenceTree(json: $0) }
        sequenceTreeIsEmpty = json != nil && sequenceTree == nil
        sequenceTarget = state.flatMap { NightTarget.fromSequence(state: $0) }
    }

    /// Fetches metadata and thumbnail only when the newest image changed. Reachability
    /// is judged by `/equipment/info`; image failures are retried on the next polls.
    private func pollImages() async {
        guard let count = try? await client.get(.imageHistoryCount, as: Int.self) else { return }
        history.update(count: count)
        recentImages = history.recent // a shrunk history (restart) must not show the old session
        if images.update(count: count) {
            latestImageIndex = images.latestIndex
            if images.latestIndex == nil {
                latestImage = nil
                latestThumbnail = nil
            }
        }
        guard let index = images.latestIndex else {
            recentImages = history.recent
            return
        }
        if images.needsMetadata {
            guard let entries = try? await client.get(.imageHistoryEntry(index: index),
                                                      as: [NINAImageSaveStatistics].self) else { return }
            latestImage = entries.first
            latestThumbnail = nil
            images.metadataFetched()
            history.record(entries.first, at: index)
        }
        if images.needsThumbnail {
            let data = try? await client.raw(.thumbnail(index: index), maxBytes: Self.maxThumbnailBytes)
            let jpeg = data.flatMap { ImageFormat.isJPEG($0) ? $0 : nil }
            images.thumbnailFetched(success: jpeg != nil)
            if let jpeg { latestThumbnail = jpeg }
        }
        for older in history.missingIndices(limit: Self.backfillPerPoll) {
            let entries = try? await client.get(.imageHistoryEntry(index: older), as: [NINAImageSaveStatistics].self)
            history.record(entries?.first, at: older)
            if entries == nil {
                // Server struggling: stop requesting for this history state. The rest of
                // the window is given up (marked attempted) so the poll cadence stays cheap.
                for rest in history.missingIndices(limit: history.capacity) { history.record(nil, at: rest) }
                break
            }
        }
        recentImages = history.recent
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
