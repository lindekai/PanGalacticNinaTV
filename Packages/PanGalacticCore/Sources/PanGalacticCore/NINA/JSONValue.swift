import Foundation

/// Untyped JSON for free-form payloads such as the sequence tree, whose shape
/// depends on the user's sequence and installed plugins (capability matrix R8).
public enum JSONValue: Decodable, Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Double.self) {
            self = .number(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    public var array: [JSONValue]? {
        if case .array(let array) = self { array } else { nil }
    }

    public var string: String? {
        if case .string(let string) = self { string } else { nil }
    }

    /// Whole numbers only; `4.5` or `"4"` are not an Int.
    public var int: Int? {
        guard case .number(let number) = self, number.rounded() == number, abs(number) < 1e15 else { return nil }
        return Int(number)
    }
}
