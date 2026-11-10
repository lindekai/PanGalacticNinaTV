import Foundation

/// Decides when to fetch metadata and the thumbnail of the newest image, based on
/// `GET /image-history?count=true`.
///
/// Plugin 2.2.15.3 appends to the history (index 0 = oldest) *before* it writes the
/// thumbnail file, so a thumbnail request right after the count changes can fail.
/// The tracker therefore retries the thumbnail on later polls, a bounded number of times.
/// A shrinking count means N.I.N.A. restarted and its history was cleared.
public struct LatestImageTracker: Hashable, Sendable {
    public static let maxThumbnailAttempts = 3

    public private(set) var count: Int?
    /// History index of the newest image; `nil` if there is none.
    public private(set) var latestIndex: Int?
    public private(set) var metadataLoaded = false
    public private(set) var thumbnailLoaded = false
    public private(set) var thumbnailAttempts = 0

    public init() {}

    /// Records a new history count. Returns `true` if the newest image changed.
    @discardableResult
    public mutating func update(count newCount: Int) -> Bool {
        guard newCount >= 0, newCount != count else { return false }
        count = newCount
        latestIndex = newCount > 0 ? newCount - 1 : nil
        metadataLoaded = false
        thumbnailLoaded = false
        thumbnailAttempts = 0
        return true
    }

    public var needsMetadata: Bool { latestIndex != nil && !metadataLoaded }

    public var needsThumbnail: Bool {
        latestIndex != nil && !thumbnailLoaded && thumbnailAttempts < Self.maxThumbnailAttempts
    }

    public mutating func metadataFetched() {
        metadataLoaded = true
    }

    public mutating func thumbnailFetched(success: Bool) {
        thumbnailAttempts += 1
        thumbnailLoaded = success
    }

    /// Forget everything, e.g. after reconnecting to a possibly different server.
    public mutating func reset() {
        self = LatestImageTracker()
    }
}

public enum ImageFormat {
    /// JPEG start-of-image marker. The thumbnail and image endpoints return JPEG on
    /// success but a JSON error envelope otherwise; never hand the latter to a decoder.
    public static func isJPEG(_ data: Data) -> Bool {
        data.count > 3 && data.prefix(3) == Data([0xFF, 0xD8, 0xFF])
    }
}
