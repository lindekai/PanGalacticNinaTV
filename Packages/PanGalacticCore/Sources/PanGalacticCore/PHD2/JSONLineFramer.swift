import Foundation

/// Splits a TCP byte stream into newline-terminated lines (PHD2 uses CR LF).
/// Handles lines split across reads and bounds memory per line.
public struct JSONLineFramer: Sendable {
    public enum FramingError: Error, Equatable, Sendable {
        case lineTooLong(limit: Int)
    }

    public let maxLineBytes: Int
    private var buffer = Data()
    /// True while discarding the remainder of an oversized line.
    private var discarding = false

    public init(maxLineBytes: Int = 1 << 20) {
        self.maxLineBytes = maxLineBytes
    }

    /// Appends received bytes and returns all complete, non-empty lines (without CR/LF).
    /// Throws once per oversized line; framing resumes after its terminating newline.
    public mutating func append(_ data: Data) throws(FramingError) -> [Data] {
        var lines: [Data] = []
        var overflow = false
        for byte in data {
            if byte == 0x0A {
                if !discarding {
                    if buffer.last == 0x0D { buffer.removeLast() }
                    if !buffer.isEmpty { lines.append(buffer) }
                }
                buffer.removeAll(keepingCapacity: true)
                discarding = false
                continue
            }
            if discarding { continue }
            buffer.append(byte)
            if buffer.count > maxLineBytes {
                buffer.removeAll()
                discarding = true
                overflow = true
            }
        }
        if overflow { throw .lineTooLong(limit: maxLineBytes) }
        return lines
    }

    /// Drops any partial line, e.g. after a reconnect.
    public mutating func reset() {
        buffer.removeAll()
        discarding = false
    }
}
