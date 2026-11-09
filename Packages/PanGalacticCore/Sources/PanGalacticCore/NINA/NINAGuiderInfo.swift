import Foundation

/// `GET /equipment/guider/info` response, shaped after live data from plugin 2.2.15.3.
public struct NINAGuiderInfo: Decodable, Hashable, Sendable {
    /// A guide error figure in both units, as reported by N.I.N.A.
    public struct ErrorValue: Decodable, Hashable, Sendable {
        public let pixels: Double?
        public let arcseconds: Double?

        enum CodingKeys: String, CodingKey { case pixels = "Pixel", arcseconds = "Arcseconds" }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pixels = c.lenientDouble(.pixels)
            arcseconds = c.lenientDouble(.arcseconds)
        }
    }

    public struct RMSError: Decodable, Hashable, Sendable {
        public let ra: ErrorValue?
        public let dec: ErrorValue?
        public let total: ErrorValue?
        public let peakRA: ErrorValue?
        public let peakDec: ErrorValue?

        enum CodingKeys: String, CodingKey {
            case ra = "RA", dec = "Dec", total = "Total", peakRA = "PeakRA", peakDec = "PeakDec"
        }
    }

    public let connected: Bool
    public let name: String?
    /// N.I.N.A.'s guider state string, e.g. `Stopped`, `Guiding`.
    public let state: String?
    public let rmsError: RMSError?
    /// Guide image scale; `nil` if not reported or not positive.
    public let pixelScale: GuideImageScale?

    enum CodingKeys: String, CodingKey {
        case connected = "Connected", name = "Name", state = "State", rmsError = "RMSError", pixelScale = "PixelScale"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        connected = try c.decode(Bool.self, forKey: .connected)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        state = try? c.decodeIfPresent(String.self, forKey: .state)
        rmsError = try? c.decodeIfPresent(RMSError.self, forKey: .rmsError)
        pixelScale = c.lenientDouble(.pixelScale).flatMap(GuideImageScale.init(arcsecondsPerPixel:))
    }
}
