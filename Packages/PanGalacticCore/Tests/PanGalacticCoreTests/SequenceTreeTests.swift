import Foundation
import Testing
@testable import PanGalacticCore

/// `/sequence/json` as the domain tree. Fixtures: owner's captures of 2026-11-15
/// (Coma Cluster) and 2026-11-19 (M 31, telescope indoors).
@Suite("Sequence tree")
struct SequenceTreeTests {
    static func tree(_ name: String) throws -> SequenceTree {
        try #require(SequenceTree(json: try SequenceProgressTests.tree(name)))
    }

    static func tree(json: String) throws -> SequenceTree? {
        SequenceTree(json: try SequenceProgressTests.decode(json))
    }

    @Test func decodesTopLevelContainersWithoutGlobalTriggers() throws {
        let tree = try Self.tree("sequence-json-running-1")
        #expect(tree.roots.map(\.name) == ["Start", "Ziele", "Ende"])
        #expect(tree.roots.map(\.status) == [.finished, .running, .created])
        #expect(tree.roots[0].id == [1], "ids are wire offsets; GlobalTriggers is element 0")
    }

    @Test func stripsPluginSuffixes() throws {
        let tree = try #require(try Self.tree(json: #"""
            [{"GlobalTriggers":[]},
             {"Name":"Lights_Container","Status":"RUNNING","Items":[
                {"Name":"_Container","Status":"CREATED","Items":[]}],
              "Conditions":[{"Name":"Loop_Condition","Status":"CREATED"}],
              "Triggers":[{"Name":"Center after drift_Trigger","Status":"CREATED"}]}]
            """#))
        let lights = tree.roots[0]
        #expect(lights.name == "Lights")
        #expect(lights.children?.first?.name == "")
        #expect(lights.details == [.condition("Loop"), .trigger("Center after drift")])
    }

    @Test func instructionsHaveNoChildren() throws {
        let tree = try Self.tree("sequence-json-running-1")
        let exposure = try #require(tree.node(at: [2, 0, 1, 0]))
        #expect(exposure.name == "Belichtung ausführen")
        #expect(exposure.children == nil)
        #expect(!exposure.isContainer)
        #expect(exposure.status == .running)
        #expect(exposure.details == [.exposure(seconds: 120, type: "LIGHT", gain: 100)])
    }

    @Test func containerDetailsFromConditionsAndTriggers() throws {
        let tree = try Self.tree("sequence-json-running-1")
        let lights = try #require(tree.node(at: [2, 0, 1]))
        #expect(lights.name == "Light 120 UV/IR")
        let end = try #require(NINADate.parse("2026-11-16T05:00:36.9999968+01:00"))
        #expect(lights.details.first == .untilTime(end))
        #expect(lights.details.contains(.ditherEvery(done: 2, target: 3)))
        #expect(lights.details.contains(.trigger("Nach Drift zentrieren")))
    }

    @Test func instructionDetails() throws {
        let tree = try #require(try Self.tree(json: #"""
            [{"Name":"C","Status":"CREATED","Items":[
                {"Name":"Cool","Status":"CREATED","Temperature":-10,"MinCoolingTime":2},
                {"Name":"Switch Filter","Status":"CREATED","Filter":"UV/IR"},
                {"Name":"Exposure","Status":"CREATED","ExposureTime":1.06356,"Type":"FLAT","Gain":-1},
                {"Name":"Wait","Status":"CREATED","TargetTime":"2026-11-19T20:18:23.0851325+01:00"},
                {"Name":"Save","Status":"CREATED","FilePath":"C:\\Users\\x\\seq.json"}]}]
            """#))
        let items = try #require(tree.roots[0].children)
        #expect(items[0].details == [.temperature(celsius: -10)])
        #expect(items[1].details == [.filter("UV/IR")])
        #expect(items[2].details == [.exposure(seconds: 1.06356, type: "FLAT", gain: nil)], "gain -1 = camera default")
        #expect(items[3].details == [.untilTime(try #require(NINADate.parse("2026-11-19T20:18:23.0851325+01:00")))])
        #expect(items[4].details.isEmpty, "file paths never enter the model")
    }

    @Test func loopConditionCounts() throws {
        let tree = try #require(try Self.tree(json: #"""
            [{"Name":"Flats","Status":"CREATED","Items":[],
              "Conditions":[{"Name":"Loop_Condition","Status":"CREATED","Iterations":50,"CompletedIterations":3}]}]
            """#))
        #expect(tree.roots[0].details == [.iterations(completed: 3, total: 50)])
    }

    @Test func statusMapping() throws {
        let tree = try #require(try Self.tree(json: #"""
            [{"Name":"C","Status":"RUNNING","Items":[
                {"Name":"a","Status":"FINISHED"},{"Name":"b","Status":"FAILED"},{"Name":"c","Status":"SKIPPED"},
                {"Name":"d","Status":"DISABLED"},{"Name":"e","Status":"PAUSED"},{"Name":"f"}]}]
            """#))
        #expect(tree.roots[0].children?.map(\.status) == [.finished, .failed, .skipped, .disabled, .unknown("PAUSED"), .unknown(nil)])
    }

    @Test func undecodableTrees() throws {
        #expect(try Self.tree(json: #"{"Name":"x"}"#) == nil, "not an array")
        #expect(try Self.tree(json: #"[{"GlobalTriggers":[]}]"#) == nil, "no containers")
    }

    @Test func nodesWithoutANameAreDropped() throws {
        let tree = try #require(try Self.tree(json: #"""
            [{"Name":"C","Status":"RUNNING","Items":[{"Status":"FINISHED"},{"Name":"b","Status":"CREATED"}]}]
            """#))
        #expect(tree.roots[0].children?.map(\.name) == ["b"])
        #expect(tree.roots[0].children?.first?.id == [0, 1], "ids keep the wire index")
    }

    @Test func liveCapturesDecode() throws {
        for name in ["sequence-json-live-exposing", "sequence-json-live-between", "sequence-json-running-2", "sequence-json-idle"] {
            let tree = try Self.tree(name)
            #expect(!tree.roots.isEmpty, "\(name)")
        }
    }
}
