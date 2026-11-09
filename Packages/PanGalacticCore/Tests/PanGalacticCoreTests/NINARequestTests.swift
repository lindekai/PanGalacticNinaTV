import Foundation
import Testing
@testable import PanGalacticCore

@Suite("N.I.N.A. read-only requests")
struct NINARequestTests {
    let factory = NINARequestFactory(host: "nina.example", port: 1888)

    static let allEndpoints: [NINAEndpoint] = [
        .version, .ninaVersion, .serverTime, .applicationStart, .equipmentInfo,
        .guiderGraph, .focuserLastAutofocus, .sequenceJSON, .sequenceState,
        .imageHistoryCount, .imageHistoryEntry(index: 3), .eventHistory, .plugins, .framingInfo,
        .profileHorizon, .activeProfile, .thumbnail(index: 0),
        .image(index: 2, size: PixelSize(width: 1920, height: 1080), quality: 85),
        .preparedImage(size: PixelSize(width: 1280, height: 720), quality: 80),
        .moonSeparation(raDegrees: 10.68, decDegrees: 41.27),
    ] + NINADevice.allCases.map { .deviceInfo($0) }

    @Test("every endpoint builds a GET request that passes the guard", arguments: allEndpoints)
    func endpointsAreAllowed(endpoint: NINAEndpoint) throws {
        let request = try factory.request(for: endpoint)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path().hasPrefix("/v2/api/") == true)
        #expect(request.httpBody == nil)
        try NINAReadOnlyGuard.validate(request)
    }

    @Test func buildsExpectedURLs() throws {
        #expect(try factory.request(for: .version).url?.absoluteString == "http://nina.example:1888/v2/api/version")
        #expect(try factory.request(for: .deviceInfo(.switch)).url?.absoluteString
            == "http://nina.example:1888/v2/api/equipment/switch/info")
        #expect(try factory.request(for: .image(index: 4, size: PixelSize(width: 1920, height: 1080), quality: 85))
            .url?.absoluteString
            == "http://nina.example:1888/v2/api/image/4?resize=true&size=1920x1080&quality=85&autoPrepare=true&stream=true")
    }

    static let forbidden: [String] = [
        "/v2/api/equipment/mount/park",
        "/v2/api/equipment/mount/unpark",
        "/v2/api/equipment/mount/slew?ra=1&dec=2",
        "/v2/api/equipment/mount/flip",
        "/v2/api/equipment/camera/capture",
        "/v2/api/equipment/camera/capture/statistics",
        "/v2/api/equipment/camera/cool",
        "/v2/api/equipment/camera/connect",
        "/v2/api/equipment/dome/open",
        "/v2/api/equipment/guider/start",
        "/v2/api/equipment/guider/stop",
        "/v2/api/equipment/focuser/move?position=1",
        "/v2/api/equipment/filterwheel/change-filter?filterId=1",
        "/v2/api/equipment/switch/set?index=0&value=1",
        "/v2/api/sequence/start",
        "/v2/api/sequence/stop",
        "/v2/api/sequence/skip",
        "/v2/api/profile/change-value",
        "/v2/api/framing/slew",
        "/v2/api/image/3/solve",
        "/v2/api/prepared-image/solve",
        "/v2/api/application/screenshot",
        "/v2/api/application/logs?lineCount=10",
        "/v2/api/application/windows/close",
        "/v2/api/livestack/start",
        "/v2/api/flats/skyflat",
        "/v2/api/version/../equipment/mount/park",
        "/v2/api/version%2F..%2Fequipment%2Fmount%2Fpark",
        "/v1/api/version",
        "/v2/api/image/1?raw_fits=true",
        "/v2/api/version?sneaky=1",
    ]

    @Test("control routes and unknown parameters are rejected", arguments: forbidden)
    func forbiddenRequestsAreRejected(pathAndQuery: String) throws {
        let request = URLRequest(url: try #require(URL(string: "http://nina.example:1888" + pathAndQuery)))
        #expect(throws: NINARequestError.self) { try NINAReadOnlyGuard.validate(request) }
    }

    @Test func nonGETMethodsAreRejected() throws {
        for method in ["POST", "PUT", "DELETE", "PATCH", "HEAD"] {
            var request = URLRequest(url: try #require(URL(string: "http://nina.example:1888/v2/api/version")))
            request.httpMethod = method
            #expect(throws: NINARequestError.notAllowed("method \(method)")) { try NINAReadOnlyGuard.validate(request) }
        }
    }

    @Test func invalidParametersAreRejected() {
        #expect(throws: NINARequestError.self) { try factory.request(for: .thumbnail(index: -1)) }
        #expect(throws: NINARequestError.self) {
            try factory.request(for: .image(index: 0, size: PixelSize(width: 0, height: 10), quality: 85))
        }
        #expect(throws: NINARequestError.self) {
            try factory.request(for: .preparedImage(size: PixelSize(width: 100, height: 100), quality: 101))
        }
        #expect(throws: NINARequestError.self) { try factory.request(for: .moonSeparation(raDegrees: 360, decDegrees: 0)) }
        #expect(throws: NINARequestError.self) {
            try factory.request(for: .moonSeparation(raDegrees: .nan, decDegrees: 0))
        }
    }

    @Test func invalidHostsAreRejected() {
        for host in ["", "evil.example/v2/api/equipment/mount/park?x=", "user@nina"] {
            #expect(throws: NINARequestError.invalidBaseURL) {
                try NINARequestFactory(host: host).request(for: .version)
            }
        }
        #expect(throws: NINARequestError.invalidBaseURL) {
            try NINARequestFactory(host: "nina", port: 0).request(for: .version)
        }
    }

    @Test("allowlist matches docs/api-capability-matrix.md")
    func allowlistMatchesCapabilityMatrix() throws {
        let doc = try String(contentsOf: Self.repositoryRoot.appending(path: "docs/api-capability-matrix.md"), encoding: .utf8)
        var documented = Set<String>()
        for match in doc.matches(of: /`GET (\/[^`?\s]*)/) {
            let path = String(match.1)
            if let group = path.firstMatch(of: /\{([a-z,]+)\}/), group.1.contains(",") {
                for device in group.1.split(separator: ",") {
                    documented.insert(path.replacingOccurrences(of: String(group.0), with: String(device)))
                }
            } else {
                documented.insert(path)
            }
        }
        for endpoint in Self.allEndpoints {
            let templated = endpoint.path.replacing(/\/[0-9]+$/, with: "/{index}")
            #expect(documented.contains(templated), "\(templated) missing from capability matrix")
        }
    }

    static var repositoryRoot: URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../..").standardized
    }
}

extension NINAEndpoint: CustomTestStringConvertible {
    public var testDescription: String { path }
}
