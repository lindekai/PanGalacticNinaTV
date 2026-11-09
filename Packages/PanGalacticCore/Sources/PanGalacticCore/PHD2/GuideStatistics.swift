import Foundation

/// One guide error sample in pixels.
public struct GuideSample: Hashable, Sendable {
    public let receivedAt: Date
    public let frame: Int?
    public let raPixels: Double
    public let decPixels: Double

    public init(receivedAt: Date, frame: Int?, raPixels: Double, decPixels: Double) {
        self.receivedAt = receivedAt
        self.frame = frame
        self.raPixels = raPixels
        self.decPixels = decPixels
    }

    public init(step: PHD2GuideStep, receivedAt: Date) {
        self.init(receivedAt: receivedAt, frame: step.frame, raPixels: step.raDistanceRaw,
                  decPixels: step.decDistanceRaw)
    }
}

/// Guide camera image scale. Without it, values can only be shown in pixels.
public struct GuideImageScale: Hashable, Sendable {
    public let arcsecondsPerPixel: Double

    /// Returns `nil` for non-finite or non-positive scales (N.I.N.A. may report 0
    /// when the scale is unknown).
    public init?(arcsecondsPerPixel: Double) {
        guard arcsecondsPerPixel.isFinite, arcsecondsPerPixel > 0 else { return nil }
        self.arcsecondsPerPixel = arcsecondsPerPixel
    }
}

public enum GuideUnit: Hashable, Sendable {
    case pixels
    case arcseconds
}

/// A guide error figure with an explicit unit; never silently mislabelled.
public struct GuideValue: Hashable, Sendable {
    public let value: Double
    public let unit: GuideUnit

    /// Converts a pixel value to arcseconds when a scale is known, else keeps pixels.
    public static func from(pixels: Double, scale: GuideImageScale?) -> GuideValue {
        guard let scale else { return GuideValue(value: pixels, unit: .pixels) }
        return GuideValue(value: pixels * scale.arcsecondsPerPixel, unit: .arcseconds)
    }
}

/// RA, Dec and total guide error statistics over a set of samples, in pixels.
///
/// Two definitions are provided because which one N.I.N.A./PHD2 display as "RMS"
/// is to be confirmed against live fixtures (M0): root mean square about zero,
/// and standard deviation about the mean. Total is `sqrt(ra² + dec²)` of each.
public struct GuideStatistics: Hashable, Sendable {
    public let count: Int
    public let raRMS: Double
    public let decRMS: Double
    public let raStandardDeviation: Double
    public let decStandardDeviation: Double

    public var totalRMS: Double { (raRMS * raRMS + decRMS * decRMS).squareRoot() }
    public var totalStandardDeviation: Double {
        (raStandardDeviation * raStandardDeviation + decStandardDeviation * decStandardDeviation).squareRoot()
    }

    /// `nil` for an empty sample set: no data is not the same as zero error.
    public init?<S: Sequence>(samples: S) where S.Element == GuideSample {
        var n = 0
        var sumRA = 0.0, sumDec = 0.0, sumRA2 = 0.0, sumDec2 = 0.0
        for s in samples {
            n += 1
            sumRA += s.raPixels
            sumDec += s.decPixels
            sumRA2 += s.raPixels * s.raPixels
            sumDec2 += s.decPixels * s.decPixels
        }
        guard n > 0 else { return nil }
        let count = Double(n)
        let meanRA = sumRA / count, meanDec = sumDec / count
        self.count = n
        raRMS = (sumRA2 / count).squareRoot()
        decRMS = (sumDec2 / count).squareRoot()
        raStandardDeviation = max(0, sumRA2 / count - meanRA * meanRA).squareRoot()
        decStandardDeviation = max(0, sumDec2 / count - meanDec * meanDec).squareRoot()
    }
}

/// Fixed-capacity FIFO; the oldest element is dropped when full.
public struct RingBuffer<Element: Sendable>: Sendable, Sequence {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }

    /// Elements from oldest to newest.
    public var elements: [Element] {
        Array(storage[head...] + storage[..<head])
    }

    public func makeIterator() -> IndexingIterator<[Element]> {
        elements.makeIterator()
    }
}
