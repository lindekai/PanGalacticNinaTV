import Foundation

/// Devices whose `/equipment/<device>/info` route is on the read-only allowlist.
public enum NINADevice: String, CaseIterable, Sendable {
    case camera, mount, filterwheel, focuser, guider, rotator, safetymonitor, weather, dome
    case `switch`
    case flatdevice
}

public struct PixelSize: Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// The complete set of N.I.N.A. Advanced API requests the app may issue.
///
/// Every case maps to a source-reviewed, side-effect-free route of plugin 2.2.15.3
/// (docs/api-capability-matrix.md §3). There is deliberately no case that takes a
/// free-form path. See ADR 0001.
public enum NINAEndpoint: Hashable, Sendable {
    case version
    case ninaVersion
    case serverTime
    case applicationStart
    case equipmentInfo
    case deviceInfo(NINADevice)
    case guiderGraph
    case focuserLastAutofocus
    case sequenceJSON
    case sequenceState
    case imageHistoryCount
    case imageHistoryEntry(index: Int)
    case eventHistory
    case plugins
    case framingInfo
    case profileHorizon
    case thumbnail(index: Int)
    /// Server-rendered (debayered, stretched, resized) JPEG of a history image.
    case image(index: Int, size: PixelSize, quality: Int)
    case preparedImage(size: PixelSize, quality: Int)
    case moonSeparation(raDegrees: Double, decDegrees: Double)

    public var path: String {
        switch self {
        case .version: "/version"
        case .ninaVersion: "/version/nina"
        case .serverTime: "/time"
        case .applicationStart: "/application-start"
        case .equipmentInfo: "/equipment/info"
        case .deviceInfo(let device): "/equipment/\(device.rawValue)/info"
        case .guiderGraph: "/equipment/guider/graph"
        case .focuserLastAutofocus: "/equipment/focuser/last-af"
        case .sequenceJSON: "/sequence/json"
        case .sequenceState: "/sequence/state"
        case .imageHistoryCount, .imageHistoryEntry: "/image-history"
        case .eventHistory: "/event-history"
        case .plugins: "/application/plugins"
        case .framingInfo: "/framing/info"
        case .profileHorizon: "/profile/horizon"
        case .thumbnail(let index): "/image/thumbnail/\(index)"
        case .image(let index, _, _): "/image/\(index)"
        case .preparedImage: "/prepared-image"
        case .moonSeparation: "/astro-util/moon-separation"
        }
    }

    public var queryItems: [URLQueryItem] {
        switch self {
        case .ninaVersion:
            [URLQueryItem(name: "friendly", value: "true")]
        case .imageHistoryCount:
            [URLQueryItem(name: "count", value: "true")]
        case .imageHistoryEntry(let index):
            [URLQueryItem(name: "index", value: String(index))]
        case .image(_, let size, let quality):
            Self.renderQuery(size: size, quality: quality) + [URLQueryItem(name: "stream", value: "true")]
        case .preparedImage(let size, let quality):
            Self.renderQuery(size: size, quality: quality)
        case .moonSeparation(let ra, let dec):
            [URLQueryItem(name: "ra", value: String(ra)), URLQueryItem(name: "dec", value: String(dec))]
        default:
            []
        }
    }

    /// Requests that make the telescope PC do significant work (full-frame render)
    /// or read files from its disk. Callers must rate-limit these.
    public var isExpensiveOrSensitive: Bool {
        switch self {
        case .image, .preparedImage, .thumbnail, .focuserLastAutofocus, .moonSeparation: true
        default: false
        }
    }

    func validateParameters() throws(NINARequestError) {
        switch self {
        case .imageHistoryEntry(let index), .thumbnail(let index):
            try Self.check(index >= 0, "index must be >= 0")
        case .image(let index, let size, let quality):
            try Self.check(index >= 0, "index must be >= 0")
            try Self.validate(size: size, quality: quality)
        case .preparedImage(let size, let quality):
            try Self.validate(size: size, quality: quality)
        case .moonSeparation(let ra, let dec):
            try Self.check(ra.isFinite && (0..<360).contains(ra), "ra must be in [0, 360)")
            try Self.check(dec.isFinite && (-90...90).contains(dec), "dec must be in [-90, 90]")
        default:
            break
        }
    }

    private static func renderQuery(size: PixelSize, quality: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "resize", value: "true"),
            URLQueryItem(name: "size", value: "\(size.width)x\(size.height)"),
            URLQueryItem(name: "quality", value: String(quality)),
            URLQueryItem(name: "autoPrepare", value: "true"),
        ]
    }

    private static func validate(size: PixelSize, quality: Int) throws(NINARequestError) {
        try check((1...8192).contains(size.width) && (1...8192).contains(size.height), "size out of range")
        try check((1...100).contains(quality), "quality must be in 1...100")
    }

    private static func check(_ condition: Bool, _ message: String) throws(NINARequestError) {
        if !condition { throw .invalidParameter(message) }
    }
}
