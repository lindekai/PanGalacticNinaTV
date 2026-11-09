import Foundation
import Testing
import PanGalacticCore
@testable import PanGalacticServices

/// Scripted HTTP transport. Records every request; never touches the network.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, String)
    typealias DataHandler = @Sendable (URLRequest) throws -> (Int, Data)
    private let lock = NSLock()
    private var handler: DataHandler
    private(set) var requests: [URLRequest] = []

    init(_ handler: @escaping Handler) {
        self.handler = Self.wrap(handler)
    }

    private init(dataHandler: @escaping DataHandler) {
        self.handler = dataHandler
    }

    /// For binary responses such as JPEG thumbnails.
    static func binary(_ handler: @escaping DataHandler) -> FakeTransport {
        FakeTransport(dataHandler: handler)
    }

    func setHandler(_ handler: @escaping Handler) {
        lock.withLock { self.handler = Self.wrap(handler) }
    }

    private static func wrap(_ handler: @escaping Handler) -> DataHandler {
        { request in
            let (status, body) = try handler(request)
            return (status, Data(body.utf8))
        }
    }

    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

    var paths: [String] { lock.withLock { requests.compactMap { $0.url?.path() } } }

    func data(for request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let handler = lock.withLock {
            requests.append(request)
            return self.handler
        }
        let (status, data) = try handler(request)
        if data.count > maxBytes { throw NINAClientError.responseTooLarge(limit: maxBytes) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }

    static func ok(_ payload: String) -> (Int, String) {
        (200, #"{"Response":\#(payload),"Error":"","StatusCode":200,"Success":true,"Type":"API"}"#)
    }

    /// A healthy plugin 2.2.15.3 with minimal equipment info.
    static func healthyNINA() -> FakeTransport {
        FakeTransport { request in
            switch request.url?.path() {
            case "/v2/api/version": ok(#""2.2.15.3""#)
            case "/v2/api/version/nina": ok(#""3.2 ""#)
            case "/v2/api/equipment/info": ok(#"{"Camera":{"Connected":true,"Name":"Cam"}}"#)
            default: (404, "")
            }
        }
    }
}

@Suite("Connection testing")
struct ConnectionTesterTests {
    @Test func identifiesSupportedPlugin() async {
        let transport = FakeTransport.healthyNINA()
        let result = await ConnectionTester(transport: transport).test(host: "10.0.0.2", port: 1888)
        #expect(result == .found(pluginVersion: "2.2.15.3", ninaVersion: "3.2"))
        #expect(transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func rejectsUnreviewedMajorVersion() async {
        let transport = FakeTransport { _ in FakeTransport.ok(#""3.0.0.5""#) }
        #expect(await ConnectionTester(transport: transport).test(host: "h", port: 1888) == .unsupportedPlugin(version: "3.0.0.5"))
    }

    @Test func openPortWithOtherServiceIsNotNINA() async {
        let html = FakeTransport { _ in (200, "<html>router</html>") }
        #expect(await ConnectionTester(transport: html).test(host: "h", port: 1888) == .notNINA)
        let notFound = FakeTransport { _ in (404, "") }
        #expect(await ConnectionTester(transport: notFound).test(host: "h", port: 1888) == .notNINA)
        let wrongShape = FakeTransport { _ in FakeTransport.ok(#""hello""#) }
        #expect(await ConnectionTester(transport: wrongShape).test(host: "h", port: 1888) == .notNINA)
    }

    @Test func transportErrorIsUnreachable() async {
        let transport = FakeTransport { _ in throw URLError(.cannotConnectToHost) }
        guard case .unreachable = await ConnectionTester(transport: transport).test(host: "h", port: 1888) else {
            Issue.record("expected unreachable")
            return
        }
    }

    @Test func pluginCompatibility() {
        #expect(PluginCompatibility.isSupported("2.2.15.3"))
        #expect(PluginCompatibility.isSupported("2.8.0.0"))
        #expect(!PluginCompatibility.isSupported("3.0.0.5-b.6"))
        #expect(!PluginCompatibility.isSupported("1.0"))
        #expect(!PluginCompatibility.isSupported("garbage"))
    }
}

@Suite("NINA client")
struct NINAClientTests {
    @Test func mapsErrors() async {
        let transport = FakeTransport { request in
            switch request.url?.path() {
            case "/v2/api/version": (500, "")
            case "/v2/api/time": (200, #"{"Response":"","Error":"boom","StatusCode":500,"Success":false,"Type":"API"}"#)
            default: (200, "not json")
            }
        }
        let client = NINAClient(host: "h", port: 1888, transport: transport)
        await #expect(throws: NINAClientError.httpStatus(500)) { try await client.get(.version, as: String.self) }
        await #expect(throws: NINAClientError.api(.server(statusCode: 500, message: "boom"))) {
            try await client.get(.serverTime, as: String.self)
        }
        await #expect(throws: NINAClientError.self) { try await client.get(.equipmentInfo, as: NINAEquipmentSummary.self) }
    }

    @Test func invalidHostNeverReachesTransport() async {
        let transport = FakeTransport { _ in FakeTransport.ok(#""x""#) }
        let client = NINAClient(host: "evil/v2/api/equipment/mount/park?", port: 1888, transport: transport)
        await #expect(throws: NINAClientError.request(.invalidBaseURL)) { try await client.get(.version, as: String.self) }
        #expect(transport.requests.isEmpty)
    }

    @Test func enforcesSizeLimit() async {
        let transport = FakeTransport { _ in (200, String(repeating: "x", count: 100)) }
        let client = NINAClient(host: "h", port: 1888, transport: transport)
        await #expect(throws: NINAClientError.responseTooLarge(limit: 10)) { try await client.raw(.version, maxBytes: 10) }
    }

    @Test func shortTransportMessages() async {
        let transport = FakeTransport { _ in throw URLError(.appTransportSecurityRequiresSecureConnection) }
        let client = NINAClient(host: "h", port: 1888, transport: transport)
        await #expect(throws: NINAClientError.transport("Only local network addresses are allowed")) {
            try await client.get(.version, as: String.self)
        }
        #expect(NINAClient.transportMessage(for: URLError(.timedOut)) == "Timed out")
        #expect(NINAClient.transportMessage(for: URLError(.cannotConnectToHost)) == "Connection refused")
    }
}

@Suite("Instance store")
@MainActor
struct InstanceStoreTests {
    @Test func persistsAndRoutes() throws {
        let suite = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = UserDefaultsInstanceStorage(defaults: defaults)

        let store = InstanceStore(storage: storage)
        #expect(store.launchRoute == .setup)
        let a = DeviceInstance(name: "A", host: "10.0.0.2")
        store.upsert(a)
        #expect(store.launchRoute == .dashboard(a.id))
        store.upsert(DeviceInstance(name: "B", host: "10.0.0.3"))
        #expect(store.launchRoute == .picker)

        var renamed = a
        renamed.name = "A2"
        store.upsert(renamed)
        #expect(store.instances.count == 2)

        let reloaded = InstanceStore(storage: storage)
        #expect(reloaded.instances.map(\.name) == ["A2", "B"])
        #expect(reloaded.contains(host: "10.0.0.3", port: 1888))
        #expect(!reloaded.contains(host: "10.0.0.3", port: 1999))

        reloaded.remove(id: a.id)
        #expect(InstanceStore(storage: storage).instances.map(\.name) == ["B"])
    }

    @Test func markSeenIsThrottled() throws {
        let storage = InMemoryInstanceStorage([DeviceInstance(name: "A", host: "h")])
        let store = InstanceStore(storage: storage)
        let id = store.instances[0].id
        let t0 = Date(timeIntervalSince1970: 1000)
        store.markSeen(id: id, at: t0)
        store.markSeen(id: id, at: t0 + 10)
        #expect(store.instances[0].lastSeen == t0 + 10, "in-memory value always current")
        #expect(try storage.load()[0].lastSeen == t0, "persisted at most once a minute")
        store.markSeen(id: id, at: t0 + 70)
        #expect(try storage.load()[0].lastSeen == t0 + 70)
    }

    @Test func corruptStorageIsReported() throws {
        let suite = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("nope".utf8), forKey: UserDefaultsInstanceStorage.key)
        let store = InstanceStore(storage: UserDefaultsInstanceStorage(defaults: defaults))
        #expect(store.instances.isEmpty)
        #expect(store.persistenceError != nil)
    }
}

@Suite("Instance connection")
@MainActor
struct InstanceConnectionTests {
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 0)
    }

    func connection(_ transport: FakeTransport, clock: Clock) -> InstanceConnection {
        InstanceConnection(instance: DeviceInstance(name: "T", host: "10.0.0.2"),
                           policy: ConnectionPolicy(pollInterval: 5, staleAfter: 15, offlineAfterFailures: 2,
                                                    backoff: ReconnectBackoff(base: 2, maximum: 60, jitter: 0)),
                           transport: transport, now: { clock.now }, random: { 0.5 })
    }

    @Test func liveThenStaleThenOfflineThenRecovered() async {
        let clock = Clock()
        let transport = FakeTransport.healthyNINA()
        let conn = connection(transport, clock: clock)
        var seen: [Date] = []
        conn.onSuccess = { seen.append($0) }

        #expect(await conn.pollOnce() == 5)
        #expect(conn.phase == .live)
        #expect(conn.pluginVersion == "2.2.15.3")
        #expect(conn.ninaVersion == "3.2")
        #expect(conn.equipment?.camera?.device.name == "Cam")
        #expect(seen == [clock.now])

        transport.setHandler { _ in throw URLError(.timedOut) }
        clock.now += 5
        #expect(await conn.pollOnce() == 5)
        #expect(conn.phase == .stale)
        #expect(conn.equipment != nil, "last data kept while stale")

        clock.now += 5
        #expect(await conn.pollOnce() == 2)
        #expect(conn.phase == .offline)
        #expect(conn.lastSuccess == Date(timeIntervalSince1970: 0))

        transport.setHandler { request in
            switch request.url?.path() {
            case "/v2/api/version": FakeTransport.ok(#""2.2.15.3""#)
            case "/v2/api/version/nina": FakeTransport.ok(#""3.2""#)
            default: FakeTransport.ok(#"{}"#)
            }
        }
        clock.now += 2
        #expect(await conn.pollOnce() == 5)
        #expect(conn.phase == .live)
        #expect(transport.paths.filter { $0 == "/v2/api/version" }.count == 2, "re-identified after outage")
    }

    @Test func incompatiblePluginStopsPolling() async {
        let transport = FakeTransport { _ in FakeTransport.ok(#""3.0.0.5""#) }
        let conn = connection(transport, clock: Clock())
        conn.start()
        for _ in 0..<50 where conn.incompatibility == nil { await Task.yield(); try? await Task.sleep(for: .milliseconds(10)) }
        #expect(conn.incompatibility == "3.0.0.5")
        #expect(!conn.isRunning)
        #expect(!transport.paths.contains("/v2/api/equipment/info"))
    }

    @Test func onlyAllowlistedGETs() async {
        let transport = FakeTransport.healthyNINA()
        let conn = connection(transport, clock: Clock())
        _ = await conn.pollOnce()
        _ = await conn.pollOnce()
        for request in transport.requests {
            #expect(request.httpMethod == "GET")
            #expect(throws: Never.self) { try NINAReadOnlyGuard.validate(request) }
        }
        #expect(Set(transport.paths) == ["/v2/api/version", "/v2/api/version/nina", "/v2/api/equipment/info",
                                         "/v2/api/image-history"])
    }
}

@Suite("Latest image")
@MainActor
struct LatestImageTests {
    final class Server: @unchecked Sendable {
        let lock = NSLock()
        var count = 0
        var thumbnailReady = false
    }

    nonisolated static let entry = #"[{"ImageType":"LIGHT","TargetName":"M 31","Filter":"L","ExposureTime":300,"HFR":2.1,"Stars":812,"Date":"2026-11-09T22:15:00.1234567+01:00"}]"#

    func transport(_ server: Server) -> FakeTransport {
        FakeTransport.binary { request in
            let (count, ready) = server.lock.withLock { (server.count, server.thumbnailReady) }
            let path = request.url?.path() ?? ""
            let query = request.url?.query() ?? ""
            func json(_ payload: String) -> (Int, Data) {
                let (status, body) = FakeTransport.ok(payload)
                return (status, Data(body.utf8))
            }
            switch path {
            case "/v2/api/version": return json(#""2.2.15.3""#)
            case "/v2/api/version/nina": return json(#""3.2""#)
            case "/v2/api/equipment/info": return json("{}")
            case "/v2/api/image-history" where query.contains("count=true"): return json(String(count))
            case "/v2/api/image-history" where query.contains("index=\(count - 1)"): return json(Self.entry)
            case "/v2/api/image/thumbnail/\(count - 1)":
                return ready ? (200, FakeTransport.jpeg)
                             : (200, Data(#"{"Response":"","Error":"Unknown error","StatusCode":500,"Success":false,"Type":"API"}"#.utf8))
            default: return (404, Data())
            }
        }
    }

    func connection(_ transport: FakeTransport) -> InstanceConnection {
        InstanceConnection(instance: DeviceInstance(name: "T", host: "10.0.0.2"), transport: transport)
    }

    @Test func newImageLoadsMetadataAndRetriesThumbnail() async throws {
        let server = Server()
        let transport = transport(server)
        let conn = connection(transport)

        _ = await conn.pollOnce()
        #expect(conn.phase == .live)
        #expect(conn.latestImage == nil && conn.latestImageIndex == nil)

        server.lock.withLock { server.count = 4 }
        _ = await conn.pollOnce()
        #expect(conn.latestImageIndex == 3)
        #expect(conn.latestImage?.targetName == "M 31")
        #expect(conn.latestImage?.stars == 812)
        #expect(conn.latestThumbnail == nil, "history entry exists before the thumbnail file")
        #expect(conn.phase == .live, "a missing thumbnail is not a connection failure")

        server.lock.withLock { server.thumbnailReady = true }
        _ = await conn.pollOnce()
        #expect(conn.latestThumbnail == FakeTransport.jpeg)

        let before = transport.paths.count
        _ = await conn.pollOnce()
        let after = transport.paths.dropFirst(before)
        #expect(Array(after) == ["/v2/api/equipment/info", "/v2/api/image-history"], "steady state polls only two cheap endpoints")
        for request in transport.requests {
            #expect(throws: Never.self) { try NINAReadOnlyGuard.validate(request) }
        }
    }

    @Test func imageHistoryFailureKeepsConnectionLive() async {
        let transport = FakeTransport { request in
            switch request.url?.path() {
            case "/v2/api/version": FakeTransport.ok(#""2.2.15.3""#)
            case "/v2/api/equipment/info": FakeTransport.ok("{}")
            default: (500, "")
            }
        }
        let conn = connection(transport)
        _ = await conn.pollOnce()
        #expect(conn.phase == .live)
        #expect(conn.latestImage == nil)
    }

    @Test func renderServiceCachesAndRejectsNonJPEG() async throws {
        let transport = FakeTransport.binary { request in
            request.url?.path() == "/v2/api/image/7" ? (200, FakeTransport.jpeg) : (200, Data("{}".utf8))
        }
        let service = ImageRenderService(host: "10.0.0.2", port: 1888, transport: transport)
        let request = ImageRenderService.Request(index: 7)
        #expect(try await service.render(request) == FakeTransport.jpeg)
        #expect(try await service.render(request) == FakeTransport.jpeg)
        #expect(transport.paths == ["/v2/api/image/7"], "second call served from cache")
        await #expect(throws: NINAClientError.decoding("not a JPEG image")) {
            try await service.render(ImageRenderService.Request(index: 8))
        }
        let query = try #require(transport.requests.first?.url?.query())
        #expect(query.contains("size=1920x1080") && query.contains("quality=85") && query.contains("stream=true"))
    }
}

@Suite("Discovery")
struct DiscoveryTests {
    func ip(_ s: String) -> UInt32 {
        s.split(separator: ".").reduce(0) { $0 << 8 | UInt32($1)! }
    }

    @Test func subnetPlan() {
        let lan = IPv4Interface(name: "en0", address: ip("192.168.1.10"), netmask: ip("255.255.255.0"))
        let hosts = SubnetScanPlan.hosts(for: lan)
        #expect(hosts.count == 253)
        #expect(hosts.first == "192.168.1.1")
        #expect(hosts.last == "192.168.1.254")
        #expect(!hosts.contains("192.168.1.10"))

        let wide = IPv4Interface(name: "en0", address: ip("10.1.2.3"), netmask: ip("255.255.0.0"))
        let narrowed = SubnetScanPlan.hosts(for: wide)
        #expect(narrowed.count == 253, "large networks are narrowed to the device's /24")
        #expect(narrowed.allSatisfy { $0.hasPrefix("10.1.2.") })

        let tiny = IPv4Interface(name: "en0", address: ip("10.0.0.1"), netmask: ip("255.255.255.252"))
        #expect(SubnetScanPlan.hosts(for: tiny) == ["10.0.0.2"])
    }

    @Test func onlyPrivateNetworksAreScanned() {
        #expect(SubnetScanPlan.isPrivate(ip("192.168.0.1")))
        #expect(SubnetScanPlan.isPrivate(ip("10.9.9.9")))
        #expect(SubnetScanPlan.isPrivate(ip("172.20.0.1")))
        #expect(!SubnetScanPlan.isPrivate(ip("172.32.0.1")))
        #expect(!SubnetScanPlan.isPrivate(ip("8.8.8.8")))
        let interfaces = [IPv4Interface(name: "pub", address: ip("8.8.8.8"), netmask: ip("255.255.255.0")),
                          IPv4Interface(name: "en0", address: ip("192.168.5.5"), netmask: ip("255.255.255.0"))]
        let hosts = NetworkScanner.defaultHosts(interfaces: interfaces)
        #expect(hosts.count == 253)
        #expect(hosts.allSatisfy { $0.hasPrefix("192.168.5.") })
    }

    final class FakeProbe: PortProbe, @unchecked Sendable {
        let open: Set<String>
        private let lock = NSLock()
        private var active = 0
        private(set) var maxActive = 0

        init(open: Set<String>) { self.open = open }

        func isOpen(host: String, port: Int, timeout: TimeInterval) async -> Bool {
            lock.withLock { active += 1; maxActive = max(maxActive, active) }
            try? await Task.sleep(for: .milliseconds(2))
            lock.withLock { active -= 1 }
            return open.contains(host)
        }
    }

    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var items: [DiscoveredInstance] = []
        func add(_ item: DiscoveredInstance) { lock.withLock { items.append(item) } }
    }

    @Test func scanFindsAndVerifiesWithBoundedConcurrency() async {
        let hosts = (1...60).map { "10.0.0.\($0)" }
        let probe = FakeProbe(open: ["10.0.0.7", "10.0.0.42"])
        // 10.0.0.42 has an open port but is not N.I.N.A.
        let transport = FakeTransport { request in
            request.url?.host() == "10.0.0.7" ? (try FakeTransport.healthyNINAResponse(request)) : (200, "<html/>")
        }
        let scanner = NetworkScanner(concurrency: 8, connectTimeout: 0.1, probe: probe,
                                     tester: ConnectionTester(transport: transport))
        let collector = Collector()
        await scanner.scan(hosts: hosts) { collector.add($0) }

        #expect(probe.maxActive <= 8)
        let byHost = Dictionary(uniqueKeysWithValues: collector.items.map { ($0.host, $0.result) })
        #expect(byHost.count == 2)
        #expect(byHost["10.0.0.7"]?.isUsable == true)
        #expect(byHost["10.0.0.42"] == .notNINA)
    }

    @Test func scanStopsWhenCancelled() async {
        let hosts = (1...254).map { "10.0.0.\($0)" }
        let probe = FakeProbe(open: [])
        let scanner = NetworkScanner(concurrency: 4, probe: probe,
                                     tester: ConnectionTester(transport: FakeTransport { _ in (404, "") }))
        let counter = Collector()
        let task = Task {
            await scanner.scan(hosts: hosts, progress: { _ in }, found: { counter.add($0) })
        }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await task.value
        #expect(probe.maxActive <= 4)
    }
}

extension FakeTransport {
    static func healthyNINAResponse(_ request: URLRequest) throws -> (Int, String) {
        switch request.url?.path() {
        case "/v2/api/version": ok(#""2.2.15.3""#)
        case "/v2/api/version/nina": ok(#""3.2""#)
        default: (404, "")
        }
    }
}
