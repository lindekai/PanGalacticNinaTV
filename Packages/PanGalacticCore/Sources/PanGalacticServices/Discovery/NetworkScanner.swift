import Foundation
import Network
import PanGalacticCore

/// An IPv4 interface address with its netmask.
public struct IPv4Interface: Hashable, Sendable {
    public let name: String
    public let address: UInt32
    public let netmask: UInt32

    public init(name: String, address: UInt32, netmask: UInt32) {
        self.name = name
        self.address = address
        self.netmask = netmask
    }

    /// Active, non-loopback IPv4 interfaces of this device.
    public static func current() -> [IPv4Interface] {
        var result: [IPv4Interface] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = entry.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let mask = entry.ifa_netmask
            else { continue }
            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            result.append(IPv4Interface(name: String(cString: entry.ifa_name), address: address, netmask: netmask))
        }
        return result
    }
}

public enum SubnetScanPlan {
    /// Smallest prefix scanned; larger networks are narrowed to the /24 around the device.
    public static let minimumPrefixLength = 24

    /// Host addresses to probe on the interface's subnet, excluding network,
    /// broadcast and the device itself. Never more than 254 hosts.
    public static func hosts(for interface: IPv4Interface) -> [String] {
        let prefix = max(minimumPrefixLength, interface.netmask.nonzeroBitCount)
        let mask: UInt32 = prefix >= 32 ? .max : ~(UInt32.max >> UInt32(prefix))
        let network = interface.address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        return ((network + 1)..<broadcast)
            .filter { $0 != interface.address }
            .map(format)
    }

    public static func format(_ address: UInt32) -> String {
        "\(address >> 24 & 0xFF).\(address >> 16 & 0xFF).\(address >> 8 & 0xFF).\(address & 0xFF)"
    }

    /// Only private (RFC 1918) networks are scanned.
    public static func isPrivate(_ address: UInt32) -> Bool {
        let a = address >> 24, b = (address >> 16) & 0xFF
        return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
    }
}

/// Checks whether a TCP port accepts connections. Sends no data.
public protocol PortProbe: Sendable {
    func isOpen(host: String, port: Int, timeout: TimeInterval) async -> Bool
}

public struct NWPortProbe: PortProbe {
    public init() {}

    public func isOpen(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let once = ResumeOnce()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                @Sendable func finish(_ open: Bool) {
                    guard once.claim() else { return }
                    connection.cancel()
                    continuation.resume(returning: open)
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: finish(true)
                    case .failed, .cancelled, .waiting: finish(false)
                    default: break
                    }
                }
                connection.start(queue: .global(qos: .utility))
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
            }
        } onCancel: {
            connection.cancel()
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            defer { done = true }
            return !done
        }
    }
}

public struct DiscoveredInstance: Hashable, Sendable {
    public let host: String
    public let port: Int
    public let result: ConnectionTestResult
}

/// Opt-in, bounded LAN scan: TCP connect on one port, then a read-only
/// `/version` check for every open port. Cancel the surrounding task to stop.
public struct NetworkScanner: Sendable {
    public var concurrency: Int
    public var connectTimeout: TimeInterval
    private let probe: any PortProbe
    private let tester: ConnectionTester

    public init(concurrency: Int = 16, connectTimeout: TimeInterval = 0.6,
                probe: any PortProbe = NWPortProbe(), tester: ConnectionTester = ConnectionTester()) {
        self.concurrency = max(1, concurrency)
        self.connectTimeout = connectTimeout
        self.probe = probe
        self.tester = tester
    }

    /// Hosts on all private /24-or-smaller subnets of this device.
    public static func defaultHosts(interfaces: [IPv4Interface] = IPv4Interface.current()) -> [String] {
        var seen = Set<String>()
        return interfaces.filter { SubnetScanPlan.isPrivate($0.address) }
            .flatMap(SubnetScanPlan.hosts(for:))
            .filter { seen.insert($0).inserted }
    }

    /// Scans `hosts` and reports every host whose port is open, with its identification.
    /// `progress` receives the number of hosts checked so far.
    public func scan(hosts: [String], port: Int = DeviceInstance.defaultAPIPort,
                     progress: @escaping @Sendable (Int) async -> Void = { _ in },
                     found: @escaping @Sendable (DiscoveredInstance) async -> Void) async {
        await withTaskGroup(of: DiscoveredInstance?.self) { group in
            var iterator = hosts.makeIterator()
            var checked = 0

            func addNext() -> Bool {
                guard !Task.isCancelled, let host = iterator.next() else { return false }
                group.addTask {
                    guard await probe.isOpen(host: host, port: port, timeout: connectTimeout) else { return nil }
                    return DiscoveredInstance(host: host, port: port, result: await tester.test(host: host, port: port))
                }
                return true
            }

            for _ in 0..<concurrency where addNext() {}
            while let next = await group.next() {
                checked += 1
                await progress(checked)
                if let next { await found(next) }
                _ = addNext()
            }
        }
    }
}
