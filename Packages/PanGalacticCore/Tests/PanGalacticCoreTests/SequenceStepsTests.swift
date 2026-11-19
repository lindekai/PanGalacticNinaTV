import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Sequence steps")
struct SequenceStepsTests {
    static func steps(_ json: String) throws -> SequenceSteps {
        SequenceSteps(tree: try #require(try SequenceTreeTests.tree(json: json)))
    }

    @Test func runningInstruction() throws {
        let steps = SequenceSteps(tree: try SequenceTreeTests.tree("sequence-json-running-1"))
        #expect(steps.current?.name == "Belichtung ausführen")
        #expect(steps.current?.container == "Light 120 UV/IR")
        #expect(steps.last?.name == "Send to Pushover")
        #expect(steps.next?.name == "Stoppe Guiding")
        #expect(steps.next?.container == "Lights Ende")
    }

    @Test func betweenExposuresTheContainerKeepsTheStep() throws {
        let steps = try Self.steps(#"""
            [{"Name":"Lights","Status":"RUNNING","Items":[
                {"Name":"Filter","Status":"FINISHED"},
                {"Name":"Exposure","Status":"CREATED"}]},
             {"Name":"End","Status":"CREATED","Items":[{"Name":"Park","Status":"CREATED"}]}]
            """#)
        #expect(steps.current?.name == "Exposure")
        #expect(steps.last?.name == "Filter")
        #expect(steps.next?.name == "Park")
    }

    @Test func failedStepIsShownAsLast() throws {
        let steps = try Self.steps(#"""
            [{"Name":"Target","Status":"RUNNING","Items":[
                {"Name":"Autofocus","Status":"FAILED"},
                {"Name":"Slew","Status":"SKIPPED"},
                {"Name":"Off","Status":"DISABLED"},
                {"Name":"Exposure","Status":"RUNNING"}]}]
            """#)
        #expect(steps.last?.name == "Autofocus")
        #expect(steps.last?.status == .failed)
        #expect(steps.next == nil)
    }

    @Test func liveBetweenCapture() throws {
        let steps = SequenceSteps(tree: try SequenceTreeTests.tree("sequence-json-live-between"))
        #expect(steps.current?.name == "Belichtung ausführen")
        #expect(steps.current?.container == "Light 120 UV/IR")
        #expect(steps.next?.name == "Stoppe Guiding")
    }

    @Test func nothingRunning() throws {
        let steps = SequenceSteps(tree: try SequenceTreeTests.tree("sequence-json-idle"))
        #expect(!steps.isRunning)
        #expect(steps.runningContainer == nil)
        #expect(steps.last == nil && steps.next == nil)
    }

    @Test func lastInstructionOfTheSequence() throws {
        let steps = try Self.steps(#"""
            [{"Name":"End","Status":"RUNNING","Items":[
                {"Name":"Park","Status":"FINISHED"},{"Name":"Wait","Status":"RUNNING"}]}]
            """#)
        #expect(steps.current?.name == "Wait")
        #expect(steps.next == nil)
    }

    @Test func runningContainerWithoutOpenInstruction() throws {
        let steps = try Self.steps(#"""
            [{"Name":"Lights","Status":"RUNNING","Items":[{"Name":"Exposure","Status":"FINISHED"}]},
             {"Name":"End","Status":"CREATED","Items":[{"Name":"Park","Status":"CREATED"}]}]
            """#)
        #expect(steps.current == nil, "a dropped or finished item is not invented")
        #expect(steps.isRunning, "a running container is running, even without a known step")
        #expect(steps.runningContainer == "Lights")
    }

    @Test func runningContainersAreTheRunningChain() throws {
        let tree = try SequenceTreeTests.tree("sequence-json-running-1")
        let ids = SequenceSteps.runningContainers(in: tree)
        let names = ids.compactMap { tree.node(at: $0)?.name }.sorted()
        #expect(names == ["Coma Cluster", "Light 120 UV/IR", "Ziele"])
    }
}
