import Foundation
import PanGalacticCore

public enum NINAClientError: Error, Equatable, Sendable {
    case request(NINARequestError)
    case transport(String)
    case httpStatus(Int)
    case responseTooLarge(limit: Int)
    case decoding(String)
    case api(NINAAPIError)
}

/// Performs an HTTP request. Abstracted so tests can run without a network.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession`-backed transport: ephemeral (no cookies, no cache), size-capped.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.expectedContentLength > Int64(maxBytes) { throw NINAClientError.responseTooLarge(limit: maxBytes) }
        var data = Data()
        data.reserveCapacity(Int(max(0, min(http.expectedContentLength, Int64(maxBytes)))))
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes { throw NINAClientError.responseTooLarge(limit: maxBytes) }
        }
        return (data, http)
    }
}

/// Read-only Advanced API client. It can only issue requests produced by
/// `NINARequestFactory`, which in turn only accepts allowlisted endpoints (ADR 0001).
public struct NINAClient: Sendable {
    public static let maxJSONBytes = 8 * 1024 * 1024
    public static let maxImageBytes = 32 * 1024 * 1024

    public let factory: NINARequestFactory
    private let transport: any HTTPTransport

    public init(host: String, port: Int, timeout: TimeInterval = 10, transport: any HTTPTransport = URLSessionTransport()) {
        factory = NINARequestFactory(host: host, port: port, timeout: timeout)
        self.transport = transport
    }

    public init(instance: DeviceInstance, transport: any HTTPTransport = URLSessionTransport()) {
        self.init(host: instance.host, port: instance.apiPort, transport: transport)
    }

    /// Fetches a JSON endpoint and returns the envelope's payload.
    public func get<Payload: Decodable & Sendable>(_ endpoint: NINAEndpoint, as _: Payload.Type = Payload.self)
        async throws(NINAClientError) -> Payload
    {
        let data = try await raw(endpoint, maxBytes: Self.maxJSONBytes)
        let envelope: NINAEnvelope<Payload>
        do {
            envelope = try JSONDecoder().decode(NINAEnvelope<Payload>.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
        do {
            return try envelope.payload()
        } catch {
            throw .api(error)
        }
    }

    /// Fetches raw bytes (e.g. a JPEG preview).
    public func raw(_ endpoint: NINAEndpoint, maxBytes: Int) async throws(NINAClientError) -> Data {
        let request: URLRequest
        do {
            request = try factory.request(for: endpoint)
        } catch {
            throw .request(error)
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request, maxBytes: maxBytes)
        } catch let error as NINAClientError {
            throw error
        } catch is CancellationError {
            throw .transport("cancelled")
        } catch {
            throw .transport(Self.transportMessage(for: error))
        }
        guard (200..<300).contains(response.statusCode) else { throw .httpStatus(response.statusCode) }
        return data
    }
}

extension NINAClient {
    /// Short, stable English sentences for common network failures. The app uses
    /// them as localization keys, so change them together with the string catalog.
    static func transportMessage(for error: any Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .timedOut: return "Timed out"
        case .cannotConnectToHost: return "Connection refused"
        case .cannotFindHost, .dnsLookupFailed: return "Host not found"
        case .notConnectedToInternet, .networkConnectionLost: return "No network connection"
        case .appTransportSecurityRequiresSecureConnection: return "Only local network addresses are allowed"
        case .cancelled: return "cancelled"
        default: return urlError.localizedDescription
        }
    }
}
