import Foundation
import Testing
@testable import PanGalacticCore

/// Running-sequence captures from the owner's system on 2026-11-15, 4.5 min apart
/// (Advanced API 2.2.15.3, N.I.N.A. 3.2): a time-bound loop of 120 s lights.
/// Field semantics were checked in source (docs/api-capability-matrix.md §7).
@Suite("Sequence progress")
struct SequenceProgressTests {
    static func tree(_ name: String) throws -> JSONValue {
        let data = try LiveFixtureTests.fixture("nina/\(name).json")
        return try JSONDecoder().decode(NINAEnvelope<JSONValue>.self, from: data).payload()
    }

    static func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    @Test func runningTimeBoundLoop() throws {
        let progress = SequenceProgress(state: try Self.tree("sequence-state-running-1"),
                                        json: try Self.tree("sequence-json-running-1"))
        let end = try #require(NINADate.parse("2026-11-16T05:00:36.9999968+01:00"))
        #expect(progress.isRunning)
        #expect(progress.targetName == "Coma Cluster")
        #expect(progress.completedPasses == 4)
        #expect(progress.passIsSingleExposure)
        #expect(progress.loop == .until(end))
    }

    @Test func passesAdvanceBetweenCaptures() throws {
        let progress = SequenceProgress(state: try Self.tree("sequence-state-running-2"),
                                        json: try Self.tree("sequence-json-running-2"))
        #expect(progress.completedPasses == 5, "container Iterations, not the cumulative ExposureCount (382)")
        if case .until = progress.loop {} else { Issue.record("expected the time condition") }
    }

    @Test func idleSequence() throws {
        let progress = SequenceProgress(state: try Self.tree("sequence-state-idle"),
                                        json: try Self.tree("sequence-json-idle"))
        #expect(!progress.isRunning)
        #expect(progress.targetName == nil)
        #expect(progress.completedPasses == nil)
        #expect(progress.loop == nil)
    }

    @Test func withoutJSONTreeThereIsNoEndTime() throws {
        let progress = SequenceProgress(state: try Self.tree("sequence-state-running-1"), json: nil)
        #expect(progress.completedPasses == 4)
        #expect(progress.loop == nil)
    }

    @Test func countLoopComesFromTheLoopCondition() throws {
        let state = try Self.decode("""
        [{"GlobalTriggers": []},
         {"Name": "Flats", "Status": "RUNNING", "Iterations": 7, "Triggers": [],
          "Conditions": [{"Name": "Loop", "Status": "CREATED", "Iterations": 50, "CompletedIterations": 7}],
          "Items": [{"Name": "Take Exposure", "Status": "RUNNING", "ExposureTime": 1.0}]}]
        """)
        let progress = SequenceProgress(state: state, json: nil)
        #expect(progress.loop == .count(completed: 7, total: 50))
        #expect(progress.targetName == nil)
    }

    @Test func innermostRunningContainerWins() throws {
        let state = try Self.decode("""
        [{"GlobalTriggers": []},
         {"Name": "Targets", "Status": "RUNNING", "Iterations": 0, "Items": [
           {"Name": "M 42", "Status": "RUNNING", "Iterations": 0, "Target": {"TargetName": "M 42"}, "Items": [
             {"Name": "Lights", "Status": "RUNNING", "Iterations": 12, "Conditions": [], "Items": [
               {"Name": "Switch Filter", "Status": "FINISHED"},
               {"Name": "Take Exposure", "Status": "RUNNING", "ExposureTime": 300.0}]}]}]}]
        """)
        let progress = SequenceProgress(state: state, json: nil)
        #expect(progress.targetName == "M 42")
        #expect(progress.completedPasses == 12)
        #expect(!progress.passIsSingleExposure, "a pass with a filter switch is not one frame")
    }

    @Test func mismatchedJSONTreeIsIgnored() throws {
        // The plugin drops items that throw while serializing (unlocked reads), so
        // the two trees can disagree; an end time from the wrong container would lie.
        let state = try Self.decode("""
        [{"GlobalTriggers": []},
         {"Name": "Lights", "Status": "RUNNING", "Iterations": 3, "Conditions": [], "Items": [
           {"Name": "Take Exposure", "Status": "RUNNING", "ExposureTime": 60.0}]}]
        """)
        let json = try Self.decode("""
        [{"GlobalTriggers": []},
         {"Name": "Something else", "Status": "RUNNING", "Items": [],
          "Conditions": [{"Name": "Loop until time", "Status": "CREATED", "TargetTime": "2026-11-16T05:00:00+01:00"}]}]
        """)
        #expect(SequenceProgress(state: state, json: json).loop == nil)
    }

    @Test func unexpectedShapesAreUnknownNotZero() throws {
        let progress = SequenceProgress(state: try Self.decode(#"{"unexpected": true}"#), json: nil)
        #expect(!progress.isRunning)
        let noCount = try Self.decode("""
        [{"Name": "Lights", "Status": "RUNNING", "Items": [{"Name": "Take Exposure", "Status": "RUNNING"}]}]
        """)
        #expect(SequenceProgress(state: noCount, json: nil).completedPasses == nil)
    }
}

@Suite("Sequence pill")
struct SequenceDisplayTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func progress(loop: SequenceProgress.Loop?, passes: Int? = 5, single: Bool = true, running: Bool = true) -> SequenceProgress {
        SequenceProgress(isRunning: running, targetName: "Coma Cluster", completedPasses: passes,
                         passIsSingleExposure: single, loop: loop)
    }

    @Test func timeBoundLoopShowsFramesAndTimeLeft() {
        let display = SequenceDisplay.state(progress(loop: .until(now + 19_920.2)), phase: .live, now: now)
        #expect(display == .running(target: "Coma Cluster", progress: .frames(5), secondsLeft: 19_921))
    }

    @Test func countLoopShowsNofM() {
        let display = SequenceDisplay.state(progress(loop: .count(completed: 7, total: 50), passes: 7), phase: .live, now: now)
        #expect(display == .running(target: "Coma Cluster", progress: .count(7, of: 50), secondsLeft: nil))
    }

    @Test func passedEndTimeAndMultiStepPassesAreLeftOut() {
        let display = SequenceDisplay.state(progress(loop: .until(now - 1), single: false), phase: .live, now: now)
        #expect(display == .running(target: "Coma Cluster", progress: nil, secondsLeft: nil))
    }

    @Test func onlyLiveDataCounts() {
        #expect(SequenceDisplay.state(progress(loop: nil), phase: .stale, now: now) == .unknown)
        #expect(SequenceDisplay.state(nil, phase: .live, now: now) == .unknown)
        #expect(SequenceDisplay.state(progress(loop: nil, running: false), phase: .live, now: now) == .idle)
    }
}
