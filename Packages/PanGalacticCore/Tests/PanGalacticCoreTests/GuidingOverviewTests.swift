import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Guiding overview")
struct GuidingOverviewTests {
    static func summary(_ json: String) throws -> NINAEquipmentSummary {
        try JSONDecoder().decode(NINAEquipmentSummary.self, from: Data(json.utf8))
    }

    static func mount(tracking: Bool = true, flip: String) throws -> NINAEquipmentSummary.Mount? {
        try summary(#"{"Mount": {"Connected": true, "TrackingEnabled": \#(tracking), "TimeToMeridianFlip": \#(flip)}}"#).mount
    }

    static func guider(state: String = "Guiding", total: Double = 0.7, scale: String = "0.773494") throws -> NINAEquipmentSummary.Guider? {
        try summary(#"""
        {"Guider": {"Connected": true, "State": "\#(state)", "PixelScale": \#(scale),
          "RMSError": {"Total": {"Pixel": \#(total)}, "RA": {"Pixel": 0.5}, "Dec": {"Pixel": 0.4}}}}
        """#).guider
    }

    /// Steps as (RA px, Dec px, dither).
    static func graph(_ steps: [(Double, Double, Bool)]) throws -> NINAGuiderGraph {
        let items = steps.enumerated().map { i, s in
            #"{"Id": \#(i + 1), "RADistanceRaw": \#(s.0), "DECDistanceRaw": \#(s.1), "Dither": \#(s.2 ? "0.01" : #""NaN""#)}"#
        }
        let json = #"{"GuideSteps": [\#(items.joined(separator: ","))], "PixelScale": 1, "ChangeId": 7}"#
        return try JSONDecoder().decode(NINAGuiderGraph.self, from: Data(json.utf8))
    }

    static func fixture(_ name: String) throws -> NINAGuiderGraph {
        let envelope = try JSONDecoder().decode(NINAEnvelope<NINAGuiderGraph>.self,
                                                from: LiveFixtureTests.fixture("nina/\(name)"))
        return try #require(envelope.response)
    }

    // MARK: Summary and meridian

    @Test func guiderCarriesRMSAndScale() throws {
        let s = try Self.summary(#"""
        {"Guider": {"Connected": true, "State": "Guiding", "PixelScale": 0.773494,
          "RMSError": {"Total": {"Pixel": 3.03, "Arcseconds": 2.34}, "RA": {"Pixel": 0.18, "Arcseconds": 0.14},
                       "Dec": {"Pixel": 3.02, "Arcseconds": 2.34}}}}
        """#)
        #expect(s.guider?.rmsError?.total?.pixels == 3.03)
        #expect(s.guider?.pixelScale?.arcsecondsPerPixel == 0.773494)
    }

    @Test func meridianFlipFromMount() throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let display = try #require(MeridianFlipDisplay(mount: try Self.mount(flip: "2.35"), now: now))
        #expect(display.wholeMinutes == 141)
        #expect(display.flipAt == now.addingTimeInterval(141 * 60))
    }

    @Test func noMeridianFlipWhenNotApplicable() throws {
        let now = Date()
        #expect(MeridianFlipDisplay(mount: try Self.mount(flip: "24"), now: now) == nil, "24 = not applicable")
        #expect(MeridianFlipDisplay(mount: try Self.mount(flip: #""NaN""#), now: now) == nil)
        #expect(MeridianFlipDisplay(mount: try Self.mount(tracking: false, flip: "2.35"), now: now) == nil)
        #expect(MeridianFlipDisplay(mount: nil, now: now) == nil)
    }

    // MARK: Graph decoding

    @Test func decodesGuidingGraph() throws {
        let graph = try Self.fixture("guider-graph-guiding.json")
        #expect(graph.steps.count == 101)
        #expect(graph.steps.filter(\.isDither).map(\.id) == [112])
        #expect(graph.steps.first == .init(id: 90, raPixels: -0.336, decPixels: -0.446, isDither: false))
        #expect(graph.pixelScale?.arcsecondsPerPixel == 0.773494)
        #expect(graph.changeId == 193)
    }

    @Test func decodesIdleGraph() throws {
        #expect(try Self.fixture("guider-graph-idle.json").steps.isEmpty)
    }

    // MARK: Chart model

    @Test(arguments: [(0.99, RMSGrade.good), (1.0, .fair), (2.0, .fair), (2.01, .poor)])
    func grades(arcseconds: Double, grade: RMSGrade) {
        #expect(RMSGrade(arcseconds: arcseconds) == grade)
    }

    @Test func totalInArcsecondsWithGrade() throws {
        let model = GuidingChartModel(guider: try Self.guider(total: 1.0), graph: nil)
        #expect(model.total?.unit == .arcseconds)
        #expect(model.grade == .good, "1.0 px × 0.773″/px = 0.77″")
    }

    @Test func pixelsHaveNoGrade() throws {
        let model = GuidingChartModel(guider: try Self.guider(scale: "0"), graph: nil)
        #expect(model.total?.unit == .pixels)
        #expect(model.grade == nil)
    }

    @Test func noTotalWhileNotGuiding() throws {
        let model = GuidingChartModel(guider: try Self.guider(state: "Stopped"), graph: nil)
        #expect(model.total == nil && model.ra == nil && model.dec == nil)
        #expect(!model.isGuiding)
    }

    @Test func rangeGrowsAndClips() throws {
        let guider = try Self.guider(scale: "1")
        let small = GuidingChartModel(guider: guider, graph: try Self.graph([(0.3, -0.2, false)]))
        #expect(small.range == 2)
        let large = GuidingChartModel(guider: guider, graph: try Self.graph([(1, 0, false), (3.2, -12, false)]))
        #expect(large.range == 8)
        #expect(large.points.last?.dec == -8)
        #expect(large.points.last?.ra == 3.2)
    }

    @Test func ditherIsAMarkerNotAPoint() throws {
        let model = GuidingChartModel(guider: try Self.guider(scale: "1"),
                                      graph: try Self.graph([(0.1, 0.1, false), (0, 0, true), (0.2, 0.2, false)]))
        #expect(model.points.map(\.position) == [0, 1])
        #expect(model.ditherPositions == [0.5])
    }

    @Test func fixtureNeedsAWiderRange() throws {
        let graph = try Self.fixture("guider-graph-guiding.json")
        let model = GuidingChartModel(guider: try Self.guider(), graph: graph)
        #expect(model.range == 6, "Dec reaches about 5.3″ in the owner's capture")
        #expect(model.ditherPositions.count == 1)
    }

    @Test func noCurvesWithoutConnectedGuider() throws {
        let graph = try Self.fixture("guider-graph-guiding.json")
        #expect(GuidingChartModel(guider: nil, graph: graph).points.isEmpty)
    }
}
