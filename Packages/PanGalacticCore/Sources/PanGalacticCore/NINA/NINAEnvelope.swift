import Foundation

/// Response wrapper used by every JSON route of the Advanced API v2:
/// `{"Response": …, "Error": "", "StatusCode": 200, "Success": true, "Type": "API"}`.
public struct NINAEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    /// `nil` when the call failed or the payload did not match `Payload`
    /// on an unsuccessful response (error responses often carry `""`).
    public let response: Payload?
    public let error: String?
    public let statusCode: Int?
    public let success: Bool
    public let type: String?

    enum CodingKeys: String, CodingKey {
        case response = "Response"
        case error = "Error"
        case statusCode = "StatusCode"
        case success = "Success"
        case type = "Type"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decode(Bool.self, forKey: .success)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        statusCode = try c.decodeIfPresent(Int.self, forKey: .statusCode)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        if success {
            response = try c.decode(Payload.self, forKey: .response)
        } else {
            response = try? c.decodeIfPresent(Payload.self, forKey: .response)
        }
    }

    /// The payload of a successful response, or an error describing the failure.
    public func payload() throws(NINAAPIError) -> Payload {
        guard success, let response else {
            throw .server(statusCode: statusCode, message: error ?? "")
        }
        return response
    }
}

public enum NINAAPIError: Error, Equatable, Sendable {
    case server(statusCode: Int?, message: String)
}
