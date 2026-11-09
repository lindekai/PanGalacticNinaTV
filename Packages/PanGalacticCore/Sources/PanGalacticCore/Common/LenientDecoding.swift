import Foundation

extension KeyedDecodingContainer {
    /// Decodes a number that may arrive as Int or Double; `nil` if absent or not numeric.
    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value.isFinite ? value : nil }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        return nil
    }

    /// Decodes an integral number that may arrive as Double (e.g. `3.0`); `nil` otherwise.
    func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite, value.rounded() == value,
           abs(value) < Double(Int.max) {
            return Int(value)
        }
        return nil
    }
}
