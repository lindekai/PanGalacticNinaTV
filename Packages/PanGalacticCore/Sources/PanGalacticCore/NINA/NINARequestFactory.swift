import Foundation

public enum NINARequestError: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidParameter(String)
    case notAllowed(String)
}

/// Second line of defence behind `NINAEndpoint`: validates a finished request
/// against the read-only allowlist, independent of how it was built.
public enum NINAReadOnlyGuard {
    public static let apiPrefix = "/v2/api"

    static let allowedPathPatterns: [String] = [
        "/version",
        "/version/nina",
        "/time",
        "/application-start",
        "/equipment/info",
        "/equipment/(" + NINADevice.allCases.map(\.rawValue).joined(separator: "|") + ")/info",
        "/equipment/guider/graph",
        "/equipment/focuser/last-af",
        "/sequence/json",
        "/sequence/state",
        "/image-history",
        "/event-history",
        "/application/plugins",
        "/framing/info",
        "/profile/horizon",
        "/profile/show",
        "/image/thumbnail/[0-9]+",
        "/image/[0-9]+",
        "/prepared-image",
        "/astro-util/moon-separation",
    ]

    static let allowedQueryNames: Set<String> = [
        "friendly", "count", "index", "active", "resize", "size", "quality", "stream", "autoPrepare", "ra", "dec",
    ]

    nonisolated(unsafe) private static let allowedPathRegexes: [Regex<AnyRegexOutput>] = allowedPathPatterns.map {
        // Patterns are compile-time constants; a failure here is a programmer error.
        try! Regex("^" + NSRegularExpression.escapedPattern(for: apiPrefix) + $0 + "$")
    }

    public static func validate(_ request: URLRequest) throws(NINARequestError) {
        guard request.httpMethod == "GET" else {
            throw .notAllowed("method \(request.httpMethod ?? "nil")")
        }
        guard request.httpBody == nil, request.httpBodyStream == nil else {
            throw .notAllowed("request body")
        }
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "http" || components.scheme == "https",
              components.host?.isEmpty == false
        else {
            throw .notAllowed("malformed URL")
        }
        let path = components.percentEncodedPath
        guard allowedPathRegexes.contains(where: { path.wholeMatch(of: $0) != nil }) else {
            throw .notAllowed("path \(path)")
        }
        let names = (components.queryItems ?? []).map(\.name)
        if let bad = names.first(where: { !allowedQueryNames.contains($0) }) {
            throw .notAllowed("query parameter \(bad)")
        }
    }
}

/// Builds `URLRequest`s for allowlisted endpoints only.
public struct NINARequestFactory: Sendable {
    public let host: String
    public let port: Int
    public let timeout: TimeInterval

    public init(host: String, port: Int = 1888, timeout: TimeInterval = 10) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    public func request(for endpoint: NINAEndpoint) throws(NINARequestError) -> URLRequest {
        try endpoint.validateParameters()
        guard (1...65535).contains(port), !host.isEmpty, !host.contains("/"), !host.contains("@") else {
            throw .invalidBaseURL
        }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = NINAReadOnlyGuard.apiPrefix + endpoint.path
        let items = endpoint.queryItems
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else { throw .invalidBaseURL }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        try NINAReadOnlyGuard.validate(request)
        return request
    }
}
