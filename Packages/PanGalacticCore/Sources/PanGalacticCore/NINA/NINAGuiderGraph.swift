import Foundation

/// `GET /equipment/guider/graph`: N.I.N.A.'s guide graph history, serialised unchanged by
/// plugin 2.2.15.3 (`GuideStepsHistory`). Distances are guide-camera pixels; the history is
/// cleared only when the guider connects or the user clears the graph, not when guiding stops.
public struct NINAGuiderGraph: Decodable, Hashable, Sendable {
    public struct Step: Hashable, Sendable {
        public let id: Int
        public let raPixels: Double
        public let decPixels: Double
        /// N.I.N.A. inserts a marker step (distances 0, `Dither` 0.01) when it dithers.
        public let isDither: Bool

        public init(id: Int, raPixels: Double, decPixels: Double, isDither: Bool) {
            self.id = id
            self.raPixels = raPixels
            self.decPixels = decPixels
            self.isDither = isDither
        }
    }

    /// Oldest first.
    public let steps: [Step]
    public let pixelScale: GuideImageScale?
    public let changeId: Int?

    enum Keys: String, CodingKey { case steps = "GuideSteps", pixelScale = "PixelScale", changeId = "ChangeId" }
    enum StepKeys: String, CodingKey { case id = "Id", ra = "RADistanceRaw", dec = "DECDistanceRaw", dither = "Dither" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        steps = ((try? c.decodeIfPresent([WireStep].self, forKey: .steps)) ?? nil)?.compactMap(\.step) ?? []
        pixelScale = c.lenientDouble(.pixelScale).flatMap(GuideImageScale.init(arcsecondsPerPixel:))
        changeId = c.lenientInt(.changeId)
    }

    private struct WireStep: Decodable {
        let step: Step?

        init(from decoder: any Decoder) throws {
            // Never throws: a malformed entry is skipped, not the whole history.
            guard let s = try? decoder.container(keyedBy: StepKeys.self),
                  let id = s.lenientInt(.id), let ra = s.lenientDouble(.ra), let dec = s.lenientDouble(.dec) else {
                step = nil
                return
            }
            // Guide steps carry "NaN" (a string); dither markers a number.
            step = Step(id: id, raPixels: ra, decPixels: dec, isDither: s.lenientDouble(.dither) != nil)
        }
    }
}
