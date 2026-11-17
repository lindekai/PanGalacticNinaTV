import Foundation

/// Traffic-light grade of the total guide error (owner's thresholds, 2026-11-17).
public enum RMSGrade: Hashable, Sendable {
    case good, fair, poor

    /// < 1″ good, 1″–2″ fair (both ends included), > 2″ poor.
    public init(arcseconds: Double) {
        self = arcseconds < 1 ? .good : arcseconds <= 2 ? .fair : .poor
    }
}

/// What the overview's guiding chart shows, derived from `/equipment/info` (state, RMS)
/// and `/equipment/guider/graph` (curves). N.I.N.A.'s RMS figures are used unchanged.
public struct GuidingChartModel: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        /// 0 (oldest) … 1 (newest), over all history entries incl. dither markers.
        public let position: Double
        public let ra: Double
        public let dec: Double
    }

    public static let minimumRange: Double = 2
    public static let maximumRange: Double = 8
    public static let gridlines: [Double] = [-2, -1, 1, 2]

    public let isGuiding: Bool
    public let unit: GuideUnit
    /// Only while guiding: after a stop N.I.N.A. keeps the old RMS.
    public let total: GuideValue?
    public let ra: GuideValue?
    public let dec: GuideValue?
    public let points: [Point]
    public let ditherPositions: [Double]
    /// Symmetric half-range of the y axis, in `unit`.
    public let range: Double

    public var grade: RMSGrade? {
        guard let total, total.unit == .arcseconds else { return nil }
        return RMSGrade(arcseconds: total.value)
    }

    public init(guider: NINAEquipmentSummary.Guider?, graph: NINAGuiderGraph?) {
        let connected = guider?.device.connected == true
        isGuiding = connected && guider?.state.map { PHD2AppState(wire: $0) } == .guiding
        let scale = guider?.pixelScale ?? graph?.pixelScale
        unit = scale == nil ? .pixels : .arcseconds
        let rms = isGuiding ? guider?.rmsError : nil
        func value(_ v: NINAGuiderInfo.ErrorValue?) -> GuideValue? {
            v?.pixels.map { GuideValue.from(pixels: $0, scale: scale) }
        }
        total = value(rms?.total)
        ra = value(rms?.ra)
        dec = value(rms?.dec)

        let steps = connected ? graph?.steps ?? [] : []
        let factor = scale?.arcsecondsPerPixel ?? 1
        let span = Double(max(steps.count - 1, 1))
        let largest = steps.filter { !$0.isDither }
            .map { max(abs($0.raPixels), abs($0.decPixels)) * factor }.max() ?? 0
        let range = min(Self.maximumRange, max(Self.minimumRange, largest.rounded(.up)))
        self.range = range
        let clip = { (v: Double) in min(max(v, -range), range) }
        var points: [Point] = []
        var dithers: [Double] = []
        for (i, step) in steps.enumerated() {
            let position = steps.count == 1 ? 1 : Double(i) / span
            if step.isDither {
                dithers.append(position)
                continue
            }
            points.append(Point(position: position, ra: clip(step.raPixels * factor), dec: clip(step.decPixels * factor)))
        }
        self.points = points
        ditherPositions = dithers
    }
}
