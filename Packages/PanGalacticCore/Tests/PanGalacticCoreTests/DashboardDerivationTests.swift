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
}
