import Foundation
import PanGalacticCore

/// Loads server-rendered JPEGs of history images for the full-screen viewer.
///
/// Rendering is expensive on the telescope PC (M0: 10.4 s for a 26 MP frame on a
/// mini PC), so the service runs at most one render at a time, joins callers asking
/// for the same image, and keeps the most recent result.
public actor ImageRenderService {
    public struct Request: Hashable, Sendable {
        public let index: Int
        public let size: PixelSize
        public let quality: Int

        public init(index: Int, size: PixelSize = PixelSize(width: 1920, height: 1080), quality: Int = 85) {
            self.index = index
            self.size = size
            self.quality = quality
        }
    }

    public static let maxBytes = NINAClient.maxImageBytes

    private let client: NINAClient
    private var cached: (request: Request, data: Data)?
    private var inFlight: (request: Request, task: Task<Data, any Error>)?

    public init(host: String, port: Int, timeout: TimeInterval = 60, transport: any HTTPTransport = URLSessionTransport()) {
        client = NINAClient(host: host, port: port, timeout: timeout, transport: transport)
    }

    public init(instance: DeviceInstance, transport: any HTTPTransport = URLSessionTransport()) {
        self.init(host: instance.host, port: instance.apiPort, transport: transport)
    }

    public func render(_ request: Request) async throws(NINAClientError) -> Data {
        if let cached, cached.request == request { return cached.data }
        let task: Task<Data, any Error>
        if let inFlight, inFlight.request == request {
            task = inFlight.task
        } else {
            inFlight?.task.cancel()
            let client = client
            task = Task {
                let data = try await client.raw(.image(index: request.index, size: request.size, quality: request.quality),
                                                maxBytes: Self.maxBytes)
                guard ImageFormat.isJPEG(data) else { throw NINAClientError.decoding("not a JPEG image") }
                return data
            }
            inFlight = (request, task)
        }
        do {
            let data = try await task.value
            if inFlight?.request == request { inFlight = nil }
            cached = (request, data)
            return data
        } catch let error as NINAClientError {
            if inFlight?.request == request { inFlight = nil }
            throw error
        } catch {
            if inFlight?.request == request { inFlight = nil }
            throw .transport("cancelled")
        }
    }
}
