import Foundation

/// A configured N.I.N.A. installation the app can monitor.
public struct DeviceInstance: Codable, Hashable, Identifiable, Sendable {
    public static let defaultAPIPort = 1888
    public static let defaultPHD2Port = 4400

    public var id: UUID
    /// User-facing name, e.g. "Backyard EQ6".
    public var name: String
    /// IPv4/IPv6 literal or hostname, without scheme, port or path.
    public var host: String
    public var apiPort: Int
    /// PHD2 event server; `nil` when PHD2 monitoring is disabled for this instance.
    public var phd2Port: Int?
    /// Last time a request to this instance succeeded.
    public var lastSeen: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        apiPort: Int = DeviceInstance.defaultAPIPort,
        phd2Port: Int? = DeviceInstance.defaultPHD2Port,
        lastSeen: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.apiPort = apiPort
        self.phd2Port = phd2Port
        self.lastSeen = lastSeen
    }

    /// `name`, or the host when no name was given.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? host : trimmed
    }
}

public enum InstanceValidationError: Error, Equatable, Sendable {
    case emptyHost
    case invalidHost
    case invalidPort
}

public enum InstanceValidation {
    /// Normalises user input ("http://nina.local:1888/" → "nina.local") and validates it.
    /// Returns the host only; a port in the input is ignored in favour of the port field.
    public static func normalizedHost(_ input: String) throws(InstanceValidationError) -> String {
        var host = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw .emptyHost }
        if let schemeEnd = host.range(of: "://") {
            host = String(host[schemeEnd.upperBound...])
        }
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        if host.hasPrefix("[") {
            // [IPv6]:port
            guard let close = host.firstIndex(of: "]") else { throw .invalidHost }
            host = String(host[host.index(after: host.startIndex)..<close])
        } else if host.filter({ $0 == ":" }).count == 1, let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        guard !host.isEmpty else { throw .emptyHost }
        guard isIPv4(host) || isIPv6(host) || isHostname(host) else { throw .invalidHost }
        return host
    }

    public static func validatePort(_ port: Int) throws(InstanceValidationError) {
        guard (1...65535).contains(port) else { throw .invalidPort }
    }

    static func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { p in
            !p.isEmpty && p.count <= 3 && p.allSatisfy(\.isASCIIDigit) && Int(p)! <= 255
        }
    }

    static func isIPv6(_ s: String) -> Bool {
        // Optional zone index after "%" (e.g. fe80::1%en0).
        let parts = s.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
        let address = parts[0]
        guard address.contains(":"), address.count <= 45,
              address.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." })
        else { return false }
        return parts.count == 1 || (!parts[1].isEmpty && parts[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    static func isHostname(_ s: String) -> Bool {
        guard s.count <= 253, !s.allSatisfy({ $0.isASCIIDigit || $0 == "." }) else { return false }
        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            (1...63).contains(label.count) && label.first != "-" && label.last != "-"
                && label.allSatisfy { ($0.isASCII && $0.isLetter) || $0.isASCIIDigit || $0 == "-" || $0 == "_" }
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
