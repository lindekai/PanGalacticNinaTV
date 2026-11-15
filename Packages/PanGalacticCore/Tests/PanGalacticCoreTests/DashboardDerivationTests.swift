import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Dashboard derivations")
struct DashboardDerivationTests {
    func summary(_ json: String) throws -> NINAEquipmentSummary {
        try JSONDecoder().decode(NINAEquipmentSummary.self, from: Data(json.utf8))
    }

    @Test func guiderStateParsesWireValues() {
        #expect(PHD2AppState(wire: "Stopped") == .stopped)
        #expect(PHD2AppState(wire: "Guiding") == .guiding)
        #expect(PHD2AppState(wire: "LostLock") == .lostLock)
        #expect(PHD2AppState(wire: "Dancing") == .other("Dancing"), "unknown values are kept verbatim")
    }

    @Test func mountActivity() throws {
        func activity(_ fields: String) throws -> MountActivity? {
            try summary(#"{"Mount":{"Connected":true"# + fields + "}}").mount?.activity
        }
        #expect(try activity(#","Slewing":true,"AtPark":true,"TrackingEnabled":true"#) == .slewing)
        #expect(try activity(#","AtPark":true,"TrackingEnabled":false"#) == .parked)
        #expect(try activity(#","AtPark":false,"TrackingEnabled":true"#) == .tracking)
        #expect(try activity(#","AtPark":false,"TrackingEnabled":false"#) == .notTracking)
        #expect(try activity("") == .unknown)
        #expect(try summary(#"{"Mount":{"Connected":false,"TrackingEnabled":true}}"#).mount?.activity == .unknown)
    }

    @Test func objectAltitudeOnlyWhileTracking() throws {
        let tracking = try #require(try summary(#"{"Mount":{"Connected":true,"TrackingEnabled":true,"AtPark":false,"Altitude":38.4,"RightAscensionString":"05:35:17","DeclinationString":"-05° 23' 28\""}}"#).mount)
        #expect(tracking.trackedObjectAltitude == 38.4)
        #expect(tracking.trackedRightAscension == "05:35:17")
        #expect(tracking.trackedDeclination == #"-05° 23' 28""#)

        let parked = try #require(try summary(#"{"Mount":{"Connected":true,"TrackingEnabled":false,"AtPark":true,"Altitude":52.3,"RightAscensionString":"04:41:15"}}"#).mount)
        #expect(parked.trackedObjectAltitude == nil, "parked altitude is the park position, not the object's")
        #expect(parked.trackedRightAscension == nil)
        #expect(parked.altitudeDegrees == 52.3, "raw pointing value stays available for the Mount page")
    }

    @Test func statusLights() throws {
        let connected = NINAEquipmentSummary.Device(connected: true, name: "X")
        let disconnected = NINAEquipmentSummary.Device(connected: false, name: "X")
        #expect(StatusLight.device(connected, phase: .live) == .normal)
        #expect(StatusLight.device(connected, phase: .stale) == .warning)
        #expect(StatusLight.device(connected, phase: .offline) == .unknown)
        #expect(StatusLight.device(connected, phase: .connecting) == .unknown)
        #expect(StatusLight.device(disconnected, phase: .live) == .unknown)
        #expect(StatusLight.device(nil, phase: .live) == .unknown)

        let now = Date(timeIntervalSince1970: 1_000_000)
        let overdue = try #require(try summary(#"{"Camera":{"Connected":true,"IsExposing":true,"ExposureEndTime":"1970-01-12T13:44:00.0000000+00:00"}}"#).camera)
        #expect(StatusLight.camera(overdue, phase: .live, now: now) == .warning)
        let idle = try #require(try summary(#"{"Camera":{"Connected":true,"IsExposing":false}}"#).camera)
        #expect(StatusLight.camera(idle, phase: .live, now: now) == .normal)
    }

    func entry(hfr: Double?) throws -> NINAImageSaveStatistics {
        let value = hfr.map { String($0) } ?? "0"
        return try JSONDecoder().decode(NINAImageSaveStatistics.self, from: Data(#"{"HFR":\#(value)}"#.utf8))
    }

    @Test func historyWindowBackfillsNewestFirstAndBoundsMemory() throws {
        var buffer = ImageHistoryBuffer(capacity: 5)
        #expect(buffer.missingIndices(limit: 4).isEmpty)

        buffer.update(count: 8)
        #expect(buffer.missingIndices(limit: 3) == [7, 6, 5])
        #expect(buffer.missingIndices(limit: 10) == [7, 6, 5, 4, 3], "only the newest `capacity` entries")

        buffer.record(try entry(hfr: 2.0), at: 7)
        buffer.record(nil, at: 6) // fetch failed: attempted, not retried
        buffer.record(try entry(hfr: 2.4), at: 5)
        #expect(buffer.missingIndices(limit: 10) == [4, 3])
        #expect(buffer.recent.compactMap(\.hfr) == [2.4, 2.0], "oldest first")

        buffer.update(count: 11)
        #expect(buffer.missingIndices(limit: 10) == [10, 9, 8], "window moved; 5 dropped out")
        #expect(buffer.recent.compactMap(\.hfr) == [2.0])

        buffer.update(count: 2)
        #expect(buffer.recent.isEmpty, "shrinking history = N.I.N.A. restarted")
        #expect(buffer.missingIndices(limit: 10) == [1, 0])
    }

    @Test func hfrSeriesSkipsPlaceholdersAndLimits() throws {
        var buffer = ImageHistoryBuffer(capacity: 50)
        buffer.update(count: 30)
        for index in 0..<30 {
            buffer.record(try entry(hfr: index == 10 ? nil : 1.0 + Double(index) / 100), at: index)
        }
        let series = buffer.hfrSeries(limit: 24)
        #expect(series.count == 24)
        #expect(series.last == 1.29)
        #expect(!series.contains(1.10), "placeholder HFR 0 is unavailable, not a data point")
    }
}
