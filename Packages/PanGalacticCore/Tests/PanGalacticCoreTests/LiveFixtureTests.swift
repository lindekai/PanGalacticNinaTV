import Foundation
import Testing
@testable import PanGalacticCore

/// Sanitized captures from the owner's system on 2026-11-09
/// (Advanced API 2.2.15.3, N.I.N.A. 3.2, PHD2 2.6.14). See api-capability-matrix.md §7.
@Suite("Live fixtures")
struct LiveFixtureTests {
    static func fixture(_ path: String) throws -> Data {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        return try Data(contentsOf: root.appending(path: path))
    }

    static func lines(_ path: String) throws -> [Data] {
        var framer = JSONLineFramer()
        return try framer.append(fixture(path))
    }

    @Test func pluginVersion() throws {
        let envelope = try JSONDecoder().decode(NINAEnvelope<String>.self, from: Self.fixture("nina/version.json"))
        #expect(try envelope.payload() == "2.2.15.3")
        let nina = try JSONDecoder().decode(NINAEnvelope<String>.self, from: Self.fixture("nina/version-nina-friendly.json"))
        #expect(try nina.payload() == "3.2 ", "N.I.N.A. sends a trailing space; callers trim")
    }

    @Test func serverTimeParsesWithSevenFractionalDigits() throws {
        let envelope = try JSONDecoder().decode(NINAEnvelope<String>.self, from: Self.fixture("nina/time.json"))
        let date = try #require(NINADate.parse(try envelope.payload()))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let expected = try #require(utc.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 18, minute: 32, second: 58)))
        #expect(abs(date.timeIntervalSince(expected) - 0.9740673) < 1e-6)
    }

    @Test func dateParserEdgeCases() throws {
        #expect(NINADate.parse("2026-11-09T18:33:01.025") != nil, "no offset → UTC")
        #expect(NINADate.parse("2026-11-09T18:33:01Z") != nil)
        #expect(NINADate.parse("2026-02-30T10:00:00Z") == nil, "invalid day")
        #expect(NINADate.parse("09.11.2026 18:33") == nil)
        #expect(NINADate.parse("") == nil)
        let a = try #require(NINADate.parse("2026-11-09T19:00:00+01:00"))
        let b = try #require(NINADate.parse("2026-11-09T18:00:00Z"))
        #expect(a == b)
    }

    @Test func guiderInfoIdle() throws {
        let envelope = try JSONDecoder().decode(NINAEnvelope<NINAGuiderInfo>.self, from: Self.fixture("nina/guider-info-idle.json"))
        let info = try envelope.payload()
        #expect(info.connected)
        #expect(info.name == "PHD2")
        #expect(info.state == "Stopped")
        #expect(info.pixelScale?.arcsecondsPerPixel == 0.773494)
        #expect(info.rmsError?.total?.pixels == 0)
        #expect(info.rmsError?.total?.arcseconds == 0)
    }

    @Test func socketSession() throws {
        let events = try Self.lines("nina/socket-session.jsonl").map { try NINASocketEvent.decode($0) }
        #expect(Array(events.prefix(4).map(\.name)) == [
            .cameraDisconnected, .cameraDisconnected, .cameraDownloadTimeout, .cameraConnected,
        ])
        #expect(events.contains { $0.name == .guiderDisconnected })
        #expect(events.contains { $0.name == .guiderConnected })
        let saves = events.filter { $0.name == .imageSave }
        #expect(!saves.isEmpty)
        #expect(saves.allSatisfy { $0.imageStatistics != nil })

        let stats = try #require(saves.first?.imageStatistics)
        #expect(stats.index == nil, "live IMAGE-SAVE has no Index field")
        #expect(stats.imageType == "SNAPSHOT")
        #expect(stats.exposureTime == 10)
        #expect(stats.filter == "UV/IR")
        #expect(stats.gain == 100)
        #expect(stats.focalLength == 1000)
        #expect(stats.isBayered == true)
        #expect(stats.stars == nil, "Stars -1 means not analysed")
        #expect(stats.hfr == nil, "HFR 0 is a placeholder")
        #expect(stats.hfrStDev == nil)
        #expect(stats.date != nil)
    }

    @Test func imageHistoryEntryHasSameShapeAsImageSave() throws {
        let envelope = try JSONDecoder().decode(NINAEnvelope<[NINAImageSaveStatistics]>.self,
                                                from: Self.fixture("nina/image-history-entry.json"))
        let entry = try #require(try envelope.payload().first)
        #expect(entry.imageType == "SNAPSHOT")
        #expect(entry.exposureTime == 10)
        #expect(entry.stars == nil)
    }

    @Test func phd2Session() throws {
        let messages = try Self.lines("phd2/session.jsonl").map { try PHD2EventDecoder.decode(line: $0) }
        #expect(messages.allSatisfy { $0 != nil })
        let events = messages.compactMap { $0?.event }

        #expect(events.first == .version(phdVersion: "2.6.14", subversion: "", messageVersion: 1))
        #expect(events.contains(.appState(.stopped)))
        #expect(events.contains(.calibrationFailed(reason: "RA Calibration Failed: star did not move enough")))
        #expect(events.contains(.lockPositionLost))
        #expect(events.contains { if case .alert(let message, _) = $0 { message?.isEmpty == false } else { false } })
        let starLost = events.compactMap { if case .starLost(let lost) = $0 { lost } else { nil } }
        #expect(!starLost.isEmpty)
        #expect(starLost.allSatisfy { $0.errorCode != nil && $0.status?.isEmpty == false })
        // Undocumented attributes on LoopingExposures (StarMass, SNR, …) are tolerated.
        #expect(events.contains(.loopingExposures(frame: 1)))

        var tracker = PHD2StateTracker()
        var visited: [PHD2AppState?] = []
        for event in events {
            tracker.apply(event)
            if visited.last != tracker.state { visited.append(tracker.state) }
        }
        #expect(visited.starts(with: [nil, .stopped, .looping, .stopped]), "\(visited)")
        #expect(visited.contains(.calibrating))
        #expect(visited.contains(nil), "CalibrationFailed has no documented successor state")
    }
}
