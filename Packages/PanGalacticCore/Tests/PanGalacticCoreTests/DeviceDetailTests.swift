import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Device details")
struct DeviceDetailTests {
    let summary: NINAEquipmentSummary

    init() throws {
        let envelope = try JSONDecoder().decode(NINAEnvelope<NINAEquipmentSummary>.self,
                                                from: LiveFixtureTests.fixture("nina/equipment-info-idle.json"))
        summary = try #require(envelope.response)
    }

    func detail(_ kind: NINAEquipmentSummary.DeviceKind) -> DeviceDetail {
        DeviceDetail(kind: kind, object: summary.objects[kind])
    }

    func value(_ detail: DeviceDetail, _ label: String) -> DeviceDetail.Value? {
        detail.sections.flatMap(\.rows).first { $0.label == .key(label) }?.value
    }

    func object(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    @Test func everyDeviceObjectIsKept() {
        #expect(Set(summary.objects.keys) == Set(NINAEquipmentSummary.DeviceKind.allCases))
    }

    @Test func cameraGroupsCoolingExposureSensorAndDriver() {
        let camera = detail(.camera)
        #expect(camera.sections.map(\.title) == ["Cooling", "Exposure", "Sensor", "Driver"])
        #expect(value(camera, "Sensor temperature") == .number(53.2, digits: 1, unit: "°C"))
        #expect(value(camera, "Cooler") == .onOff(false))
        #expect(value(camera, "Setpoint") == nil, "the setpoint only applies while the cooler runs")
        #expect(value(camera, "State") == .word("Unknown"), "NoState")
        #expect(value(camera, "Resolution") == .text("6224 × 4168 px"))
        #expect(value(camera, "Battery") == nil, "-1: no battery")
    }

    @Test func disconnectedAndUnknownDevicesHaveNoSections() {
        let dome = detail(.dome) // Connected: false, default values such as "ShutterNone"
        #expect(dome.connected == false && dome.sections.isEmpty)
        let focuser = detail(.focuser) // {} in the idle capture
        #expect(focuser.connected == nil && focuser.sections.isEmpty)
        #expect(DeviceDetail(kind: .mount, object: nil).connected == nil)
    }

    @Test func mountShowsPositionMotionAndSite() {
        let mount = detail(.mount)
        #expect(value(mount, "Side of pier") == .word("East"))
        #expect(value(mount, "Tracking rate") == .word("Stopped"))
        #expect(value(mount, "Latitude") == .number(0, digits: 4, unit: "°"), "sanitized fixture")
        #expect(value(mount, "Time to flip") == nil, "24 h: no flip due while not tracking")
    }

    @Test func filterWheelHighlightsTheActiveFilter() throws {
        let filters = try #require(detail(.filterWheel).sections.first { $0.title == "Filters" })
        #expect(filters.rows.map(\.label) == [.verbatim("UV/IR"), .verbatim("DNB")])
        #expect(filters.rows.map(\.highlighted) == [true, false])
        #expect(filters.rows.first?.value == .text("#1"))
    }

    @Test func switchChannelsWithAZeroOneRangeAreOnOff() throws {
        let outputs = try #require(detail(.switchHub).sections.first { $0.title == "Outputs" })
        #expect(outputs.rows.first == .init(.verbatim("SW EQ6"), .onOff(true)))
        let readings = try #require(detail(.switchHub).sections.first { $0.title == "Readings" })
        #expect(!readings.rows.isEmpty)
    }

    @Test func weatherLeavesOutSensorsTheStationDoesNotHave() {
        let weather = detail(.weather)
        #expect(value(weather, "Humidity") == .number(93, digits: 0, unit: "%"))
        #expect(value(weather, "Sky quality") == nil, "\"NaN\"")
    }

    @Test func flatPanelUsesMachineReadableStatesNotLocalizedLabels() throws {
        let flat = detail(.flatDevice)
        #expect(value(flat, "Cover") == .word("Unknown"))
        #expect(value(flat, "Brightness") == .level(0, min: 0, max: 255))
        let german = try object(#"{"Connected": true, "SupportsOnOff": true, "LightOn": true, "LocalizedLightOnState": "An"}"#)
        #expect(DeviceDetail(kind: .flatDevice, object: german).sections.first?.rows == [.init("Light", .onOff(true))])
    }

    @Test func guiderRMSUsesArcsecondsWhenThePixelScaleIsKnown() throws {
        let guider = detail(.guider)
        #expect(value(guider, "State") == .guiderState("Stopped"))
        #expect(value(guider, "RMS total") == .number(0, digits: 2, unit: "″"))
        let unscaled = try object(#"{"Connected": true, "PixelScale": 0, "RMSError": {"RA": {"Pixel": 0.4, "Arcseconds": 0}}}"#)
        #expect(value(DeviceDetail(kind: .guider, object: unscaled), "RMS RA") == .number(0.4, digits: 2, unit: "px"))
    }

    @Test func safetyMonitorIsUnsafeOnlyWhenConnected() throws {
        let unsafe = try object(#"{"Connected": true, "IsSafe": false}"#)
        #expect(DeviceDetail(kind: .safetyMonitor, object: unsafe).sections.first?.rows
            == [.init("Conditions", .word("Unsafe"), highlighted: true)])
        let disconnected = try object(#"{"Connected": false, "IsSafe": false}"#)
        #expect(DeviceDetail(kind: .safetyMonitor, object: disconnected).sections.isEmpty)
    }

    @Test func unknownEnumMembersAreShownAsSent() throws {
        let camera = try object(#"{"Connected": true, "CameraState": "Calibrating", "SensorType": "RGGB"}"#)
        let detail = DeviceDetail(kind: .camera, object: camera)
        #expect(value(detail, "State") == .text("Calibrating"))
        #expect(value(detail, "Sensor type") == .text("RGGB"))
    }
}
