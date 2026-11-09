import Foundation
import Testing
@testable import PanGalacticCore

@Suite("PHD2 event stream")
struct PHD2Tests {
    // Version line is the example from the PHD2 EventMonitoring wiki; the others
    // follow the documented attribute tables. Replace with live fixtures (M0).
    static let stream = [
        #"{"Event":"Version","Timestamp":1372082668.897,"Host":"HOST","Inst":1,"PHDVersion":"2.0.4","PHDSubver":"a","MsgVersion":1}"#,
        #"{"Event":"AppState","Timestamp":1372082668.9,"Host":"HOST","Inst":1,"State":"Guiding"}"#,
        #"{"Event":"GuideStep","Timestamp":1372082670.1,"Host":"HOST","Inst":1,"Frame":1,"Time":1.2,"Mount":"EQMOD","dx":0.3,"dy":-0.2,"RADistanceRaw":0.31,"DECDistanceRaw":-0.12,"RADistanceGuide":0.25,"DECDistanceGuide":0.0,"RADuration":120,"RADirection":"East","DECDuration":0,"DECDirection":"North","StarMass":12345.6,"SNR":42.1,"HFD":2.8,"AvgDist":0.29,"RALimited":true}"#,
        #"{"Event":"StarLost","Timestamp":1372082672.5,"Host":"HOST","Inst":1,"Frame":2,"Time":3.4,"StarMass":0,"SNR":0,"AvgDist":0.3,"ErrorCode":2,"Status":"Star lost - low SNR"}"#,
        #"{"Event":"SettleDone","Timestamp":1372082680,"Host":"HOST","Inst":1,"Status":1,"Error":"timed out","TotalFrames":10,"DroppedFrames":2}"#,
        #"{"jsonrpc":"2.0","result":1000,"id":1}"#,
    ].joined(separator: "\r\n") + "\r\n"

    @Test func framerReassemblesArbitrarilySplitInput() throws {
        let bytes = Data(Self.stream.utf8)
        for chunkSize in [1, 2, 7, 64, bytes.count] {
            var framer = JSONLineFramer()
            var lines: [Data] = []
            var offset = 0
            while offset < bytes.count {
                let end = min(offset + chunkSize, bytes.count)
                lines += try framer.append(bytes[offset..<end])
                offset = end
            }
            #expect(lines.count == 6, "chunk size \(chunkSize)")
            #expect(lines.allSatisfy { $0.last != 0x0D })
        }
    }

    @Test func framerKeepsPartialLineUntilTerminated() throws {
        var framer = JSONLineFramer()
        #expect(try framer.append(Data(#"{"Event":"Pau"#.utf8)).isEmpty)
        let lines = try framer.append(Data("sed\"}\r\n\n".utf8))
        #expect(lines == [Data(#"{"Event":"Paused"}"#.utf8)])
    }

    @Test func framerRejectsOversizedLineAndRecovers() throws {
        var framer = JSONLineFramer(maxLineBytes: 16)
        #expect(throws: JSONLineFramer.FramingError.lineTooLong(limit: 16)) {
            try framer.append(Data(String(repeating: "x", count: 40).utf8))
        }
        // The rest of the oversized line is discarded; the next line is intact.
        let lines = try framer.append(Data("yyy\n{\"Event\":\"A\"}\n".utf8))
        #expect(lines == [Data(#"{"Event":"A"}"#.utf8)])
    }

    @Test func framerResetDropsPartialLine() throws {
        var framer = JSONLineFramer()
        _ = try framer.append(Data("partial".utf8))
        framer.reset()
        #expect(try framer.append(Data("{}\n".utf8)) == [Data("{}".utf8)])
    }

    @Test func decodesDocumentedEvents() throws {
        var framer = JSONLineFramer()
        let messages = try framer.append(Data(Self.stream.utf8)).compactMap { try PHD2EventDecoder.decode(line: $0) }
        #expect(messages.count == 5, "JSON-RPC response line is ignored")

        #expect(messages[0].event == .version(phdVersion: "2.0.4", subversion: "a", messageVersion: 1))
        #expect(messages[0].instance == 1)
        #expect(messages[0].timestamp == Date(timeIntervalSince1970: 1372082668.897))
        #expect(messages[1].event == .appState(.guiding))

        guard case .guideStep(let step) = messages[2].event else {
            Issue.record("expected GuideStep")
            return
        }
        #expect(step.frame == 1)
        #expect(step.raDistanceRaw == 0.31)
        #expect(step.decDistanceRaw == -0.12)
        #expect(step.raLimited == true)
        #expect(step.decLimited == false, "omitted attribute means not limited")
        #expect(step.raDirection == "East")

        guard case .starLost(let lost) = messages[3].event else {
            Issue.record("expected StarLost")
            return
        }
        #expect(lost.errorCode == 2)

        guard case .settleDone(let done) = messages[4].event else {
            Issue.record("expected SettleDone")
            return
        }
        #expect(done.succeeded == false)
        #expect(done.droppedFrames == 2)
    }

    @Test func guideStepWithoutDistancesIsAnError() {
        #expect(throws: PHD2EventDecoder.DecodingError.missingField("RADistanceRaw")) {
            try PHD2EventDecoder.decode(line: Data(#"{"Event":"GuideStep","Frame":1}"#.utf8))
        }
    }

    @Test func unknownEventsAndStatesArePreserved() throws {
        let message = try #require(try PHD2EventDecoder.decode(line: Data(#"{"Event":"BrandNew"}"#.utf8)))
        #expect(message.event == .other(name: "BrandNew"))
        let state = try #require(try PHD2EventDecoder.decode(line: Data(#"{"Event":"AppState","State":"Dancing"}"#.utf8)))
        #expect(state.event == .appState(.other("Dancing")))
    }

    @Test func booleansAreNotReadAsNumbers() {
        #expect(throws: PHD2EventDecoder.DecodingError.missingField("RADistanceRaw")) {
            try PHD2EventDecoder.decode(line: Data(#"{"Event":"GuideStep","RADistanceRaw":true,"DECDistanceRaw":0}"#.utf8))
        }
    }

    @Test func stateTrackerFollowsDocumentedTransitions() {
        var tracker = PHD2StateTracker()
        #expect(tracker.state == nil)
        tracker.apply(.appState(.stopped))
        #expect(tracker.state == .stopped)
        tracker.apply(.loopingExposures(frame: 1))
        #expect(tracker.state == .looping)
        tracker.apply(.startCalibration(mount: nil))
        #expect(tracker.state == .calibrating)
        tracker.apply(.guideStep(Self.step(ra: 0, dec: 0)))
        #expect(tracker.state == .guiding)
        tracker.apply(.starLost(PHD2StarLost(frame: nil, time: nil, starMass: nil, snr: nil, avgDist: nil,
                                             errorCode: nil, status: nil)))
        #expect(tracker.state == .lostLock)
        tracker.apply(.paused)
        #expect(tracker.state == .paused)
        tracker.apply(.resumed)
        #expect(tracker.state == nil, "no documented successor state")
        tracker.apply(.guideStep(Self.step(ra: 0, dec: 0)))
        tracker.apply(.guidingStopped)
        #expect(tracker.state == nil)
        tracker.apply(.loopingExposuresStopped)
        #expect(tracker.state == .stopped)
        tracker.apply(.settleBegin)
        #expect(tracker.state == .stopped, "unrelated events leave state unchanged")
        tracker.connectionLost()
        #expect(tracker.state == nil)
    }

    static func step(ra: Double, dec: Double) -> PHD2GuideStep {
        PHD2GuideStep(frame: nil, time: nil, mount: nil, dx: nil, dy: nil, raDistanceRaw: ra, decDistanceRaw: dec,
                      raDurationMs: nil, raDirection: nil, decDurationMs: nil, decDirection: nil, starMass: nil,
                      snr: nil, hfd: nil, avgDist: nil, raLimited: false, decLimited: false, errorCode: nil)
    }
}

@Suite("Guide statistics")
struct GuideStatisticsTests {
    let now = Date(timeIntervalSince1970: 0)

    func samples(_ pairs: [(Double, Double)]) -> [GuideSample] {
        pairs.enumerated().map { GuideSample(receivedAt: now, frame: $0.offset, raPixels: $0.element.0, decPixels: $0.element.1) }
    }

    @Test func emptySetHasNoStatistics() {
        #expect(GuideStatistics(samples: [GuideSample]()) == nil)
    }

    @Test func computesRMSAndStandardDeviation() throws {
        let stats = try #require(GuideStatistics(samples: samples([(1, 0), (-1, 0), (1, 2), (-1, 2)])))
        #expect(stats.count == 4)
        #expect(stats.raRMS == 1)
        #expect(stats.raStandardDeviation == 1)
        #expect(abs(stats.decRMS - 2.0.squareRoot()) < 1e-12)
        #expect(stats.decStandardDeviation == 1, "mean of 1 removed")
        #expect(abs(stats.totalRMS - 3.0.squareRoot()) < 1e-12)
        #expect(abs(stats.totalStandardDeviation - 2.0.squareRoot()) < 1e-12)
    }

    @Test func constantOffsetHasZeroDeviationButNonZeroRMS() throws {
        let stats = try #require(GuideStatistics(samples: samples(Array(repeating: (0.5, -0.5), count: 10))))
        #expect(abs(stats.raRMS - 0.5) < 1e-12)
        #expect(stats.raStandardDeviation < 1e-9)
    }

    @Test func unitsAreExplicit() {
        #expect(GuideValue.from(pixels: 0.5, scale: nil) == GuideValue(value: 0.5, unit: .pixels))
        let scale = GuideImageScale(arcsecondsPerPixel: 3.86)
        #expect(GuideValue.from(pixels: 0.5, scale: scale) == GuideValue(value: 1.93, unit: .arcseconds))
        #expect(GuideImageScale(arcsecondsPerPixel: 0) == nil)
        #expect(GuideImageScale(arcsecondsPerPixel: -1) == nil)
        #expect(GuideImageScale(arcsecondsPerPixel: .infinity) == nil)
    }

    @Test func ringBufferKeepsNewestInOrder() {
        var buffer = RingBuffer<Int>(capacity: 3)
        #expect(buffer.isEmpty)
        for i in 1...5 { buffer.append(i) }
        #expect(buffer.count == 3)
        #expect(buffer.elements == [3, 4, 5])
        #expect(Array(buffer) == [3, 4, 5])
        buffer.removeAll()
        buffer.append(9)
        #expect(buffer.elements == [9])
    }
}
