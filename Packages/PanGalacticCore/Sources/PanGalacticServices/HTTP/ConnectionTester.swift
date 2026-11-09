import Foundation
import PanGalacticCore

public enum ConnectionTestResult: Hashable, Sendable {
    /// A supported Advanced API answered.
    case found(pluginVersion: String, ninaVersion: String?)
    /// An Advanced API answered, but with a major version this app was not reviewed against.
    case unsupportedPlugin(version: String)
    /// Something answered on the port, but not with an Advanced API version response.
    case notNINA
    case unreachable(message: String)

    public var isUsable: Bool {
        if case .found = self { true } else { false }
    }
}

public enum PluginCompatibility {
    /// Majors whose endpoints were source-reviewed for the allowlist (ADR 0001).
    public static let supportedMajors: Set<Int> = [2]

    public static func isSupported(_ version: String) -> Bool {
        guard let major = version.split(separator: ".").first.flatMap({ Int($0) }) else { return false }
        return supportedMajors.contains(major)
    }
}

/// Identifies an Advanced API server with read-only requests only.
/// An open port alone is never treated as proof of N.I.N.A.
public struct ConnectionTester: Sendable {
    private let transport: any HTTPTransport
    private let timeout: TimeInterval

    public init(transport: any HTTPTransport = URLSessionTransport(), timeout: TimeInterval = 5) {
        self.transport = transport
        self.timeout = timeout
    }

    public func test(host: String, port: Int) async -> ConnectionTestResult {
        let client = NINAClient(host: host, port: port, timeout: timeout, transport: transport)
        let pluginVersion: String
        do {
            pluginVersion = try await client.get(.version, as: String.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch .transport(let message) {
            return .unreachable(message: message)
        } catch .request(let error) {
            return .unreachable(message: String(describing: error))
        } catch {
            return .notNINA
        }
        guard pluginVersion.first?.isNumber == true else { return .notNINA }
        guard PluginCompatibility.isSupported(pluginVersion) else { return .unsupportedPlugin(version: pluginVersion) }
        let nina = try? await client.get(.ninaVersion, as: String.self)
        return .found(pluginVersion: pluginVersion, ninaVersion: nina?.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
