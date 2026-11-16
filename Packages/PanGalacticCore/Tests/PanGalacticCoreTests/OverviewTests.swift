import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Overview data")
struct OverviewTests {
    func equipment() throws -> NINAEquipmentSummary {
        let envelope = try JSONDecoder().decode(NINAEnvelope<NINAEquipmentSummary>.self,
                                                from: LiveFixtureTests.fixture("nina/equipment-info-idle.json"))
        return try #require(envelope.response)
    }

    @Test func cameraSetpointUsesDriverValueOnlyWhileCooling() throws {
        let camera = try #require(try equipment().camera)
        // Live: TargetTemp -10 (panel value) vs. TemperatureSetPoint 10 (driver) with the cooler off.
        #expect(camera.driverSetpoint == 10)
        #expect(camera.coolerOn == false)
        #expect(camera.activeSetpoint == nil)
        #expect(camera.gain == 100)
        #expect(camera.offset == 180)

        let json = #"{"Camera":{"Connected":true,"CoolerOn":true,"TemperatureSetPoint":-10,"TargetTemp":5}}"#
        let cooling = try JSONDecoder().decode(NINAEquipmentSummary.self, from: Data(json.utf8)).camera
        #expect(cooling?.activeSetpoint == -10)
    }

    @Test func mountPosition() throws {
        let mount = try #require(try equipment().mount)
        #expect(mount.rightAscension == "04:41:15")
        #expect(mount.declination == #"90° 00' 00""#)
        #expect(mount.sideOfPier == .east)
        #expect(abs((mount.altitudeDegrees ?? 0) - 52.32) < 0.01)

        let unknown = #"{"Mount":{"Connected":true,"SideOfPier":"pierUnknown"}}"#
        #expect(try JSONDecoder().decode(NINAEquipmentSummary.self, from: Data(unknown.utf8)).mount?.sideOfPier == nil)
        let disconnected = #"{"Mount":{"Connected":false,"RightAscensionString":"00:00:00","Altitude":0}}"#
        let off = try JSONDecoder().decode(NINAEquipmentSummary.self, from: Data(disconnected.utf8)).mount
        #expect(off?.rightAscension == nil && off?.altitudeDegrees == nil, "stale coordinates of a disconnected mount are hidden")
    }

    @Test func trackerFetchesOnlyWhenNewestImageChanges() {
        var tracker = LatestImageTracker()
        #expect(!tracker.needsMetadata && !tracker.needsThumbnail)

        var changed = tracker.update(count: 0)
        #expect(changed)
        #expect(tracker.latestIndex == nil && !tracker.needsMetadata)

        changed = tracker.update(count: 3)
        #expect(changed)
        #expect(tracker.latestIndex == 2 && tracker.needsMetadata && tracker.needsThumbnail)
        tracker.metadataFetched()
        tracker.thumbnailFetched(success: true)
        #expect(!tracker.needsMetadata && !tracker.needsThumbnail)
        changed = tracker.update(count: 3)
        #expect(!changed, "unchanged count fetches nothing")

        changed = tracker.update(count: 1)
        #expect(changed, "shrinking history = N.I.N.A. restarted")
        #expect(tracker.latestIndex == 0 && tracker.needsMetadata)
    }

    @Test func thumbnailRetriesAreBounded() {
        var tracker = LatestImageTracker()
        tracker.update(count: 1)
        tracker.metadataFetched()
        for _ in 0..<LatestImageTracker.maxThumbnailAttempts {
            #expect(tracker.needsThumbnail)
            tracker.thumbnailFetched(success: false)
        }
        #expect(!tracker.needsThumbnail)
        tracker.update(count: 2)
        #expect(tracker.needsThumbnail, "a new image gets fresh attempts")
    }

    @Test func jpegDetection() {
        #expect(ImageFormat.isJPEG(Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])))
        #expect(!ImageFormat.isJPEG(Data(#"{"Response":"","Error":"No thumbnails available"}"#.utf8)))
        #expect(!ImageFormat.isJPEG(Data()))
    }
}

@Suite("Device overview")
struct DeviceOverviewTests {
    @Test func everyDeviceTypeInEquipmentTabOrder() throws {
        let envelope = try JSONDecoder().decode(NINAEnvelope<NINAEquipmentSummary>.self,
                                                from: LiveFixtureTests.fixture("nina/equipment-info-idle.json"))
        let devices = try #require(envelope.response).devices
        #expect(devices.map(\.kind) == NINAEquipmentSummary.DeviceKind.allCases)
        let byKind = Dictionary(uniqueKeysWithValues: devices.map { ($0.kind, $0) })
        #expect(byKind[.camera]?.connected == true)
        #expect(byKind[.camera]?.name == "ATR2600C")
        #expect(byKind[.dome]?.connected == false, "idle default: known to be not connected")
        #expect(byKind[.dome]?.name == nil)
        #expect(byKind[.focuser]?.connected == nil, "live quirk: an empty object is unknown, not disconnected")
        #expect(byKind[.weather]?.connected == true, "key is WeatherData")
    }

    @Test func missingNullAndEmptyNamesAreUnknown() throws {
        let json = #"{"Camera":null,"Mount":{"Connected":true,"Name":"","DisplayName":"EQ6 (ASCOM)"}}"#
        let devices = try JSONDecoder().decode(NINAEquipmentSummary.self, from: Data(json.utf8)).devices
        #expect(devices.first { $0.kind == .camera }?.connected == nil)
        #expect(devices.first { $0.kind == .rotator }?.connected == nil)
        #expect(devices.first { $0.kind == .mount }?.name == "EQ6 (ASCOM)", "empty Name falls back to DisplayName")
    }
}

@Suite("Device connection state")
struct DeviceConnectionStateTests {
    func device(_ connected: Bool?) -> NINAEquipmentSummary.DeviceStatus {
        NINAEquipmentSummary.DeviceStatus(kind: .camera, connected: connected, name: nil)
    }

    @Test func liveAndStale() {
        #expect(DeviceConnectionState.of(device(true), phase: .live) == .connected(.normal))
        #expect(DeviceConnectionState.of(device(true), phase: .stale) == .connected(.warning))
        #expect(DeviceConnectionState.of(device(false), phase: .live) == .notConnected)
        #expect(DeviceConnectionState.of(device(nil), phase: .live) == .unknown)
    }

    @Test func withoutConnectionNothingIsKnown() {
        #expect(DeviceConnectionState.of(device(true), phase: .offline) == .unknown)
        #expect(DeviceConnectionState.of(device(false), phase: .connecting) == .unknown)
    }
}
