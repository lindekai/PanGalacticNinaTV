import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Instances and connection lifecycle")
struct InstanceTests {
    @Test func launchRouting() {
        let a = DeviceInstance(name: "A", host: "10.0.0.2")
        let b = DeviceInstance(name: "B", host: "10.0.0.3")
        #expect(LaunchRoute(instances: []) == .setup)
        #expect(LaunchRoute(instances: [a]) == .dashboard(a.id))
        #expect(LaunchRoute(instances: [a, b]) == .picker)
    }

    @Test func defaultsAndDisplayName() {
        let instance = DeviceInstance(name: "  ", host: "nina.local")
        #expect(instance.apiPort == 1888)
        #expect(instance.phd2Port == 4400)
        #expect(instance.displayName == "nina.local")
    }

    @Test("host input is normalised", arguments: [
        ("192.168.1.20", "192.168.1.20"),
        (" nina.local ", "nina.local"),
        ("http://nina.local:1888/v2/api", "nina.local"),
        ("DESKTOP-ABC123", "DESKTOP-ABC123"),
        ("observatory_pc", "observatory_pc"),
        ("10.0.0.5:1888", "10.0.0.5"),
        ("[fe80::1%en0]:1888", "fe80::1%en0"),
        ("fe80::1", "fe80::1"),
    ])
    func normalisesHost(input: String, expected: String) throws {
        #expect(try InstanceValidation.normalizedHost(input) == expected)
    }

    @Test("invalid hosts are rejected", arguments: ["", "   ", "256.1.1.1", "1.2.3", "bad host", "-bad.example", "a..b", "http://"])
    func rejectsHost(input: String) {
        #expect(throws: InstanceValidationError.self) { try InstanceValidation.normalizedHost(input) }
    }

    @Test func validatesPort() throws {
        try InstanceValidation.validatePort(1888)
        #expect(throws: InstanceValidationError.invalidPort) { try InstanceValidation.validatePort(0) }
        #expect(throws: InstanceValidationError.invalidPort) { try InstanceValidation.validatePort(70000) }
    }

    @Test func codableRoundTrip() throws {
        let instance = DeviceInstance(name: "Obs", host: "10.0.0.9", apiPort: 1999, phd2Port: nil,
                                      lastSeen: Date(timeIntervalSince1970: 1_700_000_000))
        let decoded = try JSONDecoder().decode(DeviceInstance.self, from: JSONEncoder().encode(instance))
        #expect(decoded == instance)
    }

    @Test func backoffGrowsAndCaps() {
        let backoff = ReconnectBackoff(base: 2, maximum: 60, jitter: 0.2)
        #expect(backoff.delay(attempt: 0, unitRandom: 0.5) == 2)
        #expect(backoff.delay(attempt: 3, unitRandom: 0.5) == 16)
        #expect(backoff.delay(attempt: 10, unitRandom: 0.5) == 60)
        #expect(backoff.delay(attempt: 1000, unitRandom: 0.5) == 60)
        #expect(backoff.delay(attempt: 0, unitRandom: 0) == 1.6)
        #expect(backoff.delay(attempt: 0, unitRandom: 1) == 2.4)
    }

    @Test func stateMachineLifecycle() {
        let t0 = Date(timeIntervalSince1970: 0)
        var machine = ConnectionStateMachine(policy: ConnectionPolicy(pollInterval: 5, staleAfter: 15,
                                                                      offlineAfterFailures: 3,
                                                                      backoff: ReconnectBackoff(base: 2, maximum: 60, jitter: 0)))
        #expect(machine.phase(at: t0) == .connecting)

        #expect(machine.recordSuccess(at: t0) == 5)
        #expect(machine.phase(at: t0) == .live)
        #expect(machine.phase(at: t0 + 16) == .stale, "no fresh data for longer than staleAfter")

        #expect(machine.recordFailure(at: t0 + 5, error: "timeout", unitRandom: 0.5) == 5)
        #expect(machine.phase(at: t0 + 5) == .stale)
        machine.recordFailure(at: t0 + 10, error: "timeout", unitRandom: 0.5)
        #expect(machine.recordFailure(at: t0 + 15, error: "timeout", unitRandom: 0.5) == 2)
        #expect(machine.phase(at: t0 + 15) == .offline)
        #expect(machine.recordFailure(at: t0 + 17, error: "timeout", unitRandom: 0.5) == 4)
        #expect(machine.lastError == "timeout")
        #expect(machine.lastSuccess == t0, "last fresh timestamp is kept for display")

        machine.recordSuccess(at: t0 + 30)
        #expect(machine.phase(at: t0 + 30) == .live)
        #expect(machine.lastError == nil)
    }

    @Test func neverConnectedGoesOfflineWithoutStale() {
        let t0 = Date(timeIntervalSince1970: 0)
        var machine = ConnectionStateMachine()
        machine.recordFailure(at: t0, error: "refused", unitRandom: 0.5)
        #expect(machine.phase(at: t0) == .connecting)
        machine.recordFailure(at: t0, error: "refused", unitRandom: 0.5)
        machine.recordFailure(at: t0, error: "refused", unitRandom: 0.5)
        #expect(machine.phase(at: t0) == .offline)
    }

    @Test func equipmentSummaryFromLiveFixture() throws {
        let data = try LiveFixtureTests.fixture("nina/equipment-info-idle.json")
        let summary = try JSONDecoder().decode(NINAEnvelope<NINAEquipmentSummary>.self, from: data).payload()
        #expect(summary.camera?.device.connected == true)
        #expect(summary.camera?.device.name == "ATR2600C")
        #expect(summary.camera?.isExposing == false)
        #expect(summary.mount?.atPark == true)
        #expect(summary.mount?.trackingEnabled == false)
        #expect(summary.filterWheel?.selectedFilter == "UV/IR")
        #expect(summary.guider?.device.name == "PHD2")
        #expect(summary.guider?.state == "Stopped")
        #expect(summary.focuser == nil, "live /equipment/info sends \"Focuser\": {} – unknown, not disconnected")
    }

    @Test func equipmentSummaryToleratesMissingDevices() throws {
        let json = #"{"Response":{"Camera":{"Connected":false},"Mount":"garbage"},"Success":true}"#
        let summary = try JSONDecoder().decode(NINAEnvelope<NINAEquipmentSummary>.self, from: Data(json.utf8)).payload()
        #expect(summary.camera?.device.connected == false)
        #expect(summary.camera?.temperature == nil)
        #expect(summary.mount == nil)
        #expect(summary.guider == nil)
    }

    @Test func overdueExposure() throws {
        let end = Date(timeIntervalSince1970: 1000)
        let json = #"{"Response":{"Camera":{"Connected":true,"IsExposing":true,"ExposureEndTime":"1970-01-01T00:16:40Z"}},"Success":true}"#
        let camera = try #require(try JSONDecoder().decode(NINAEnvelope<NINAEquipmentSummary>.self, from: Data(json.utf8))
            .payload().camera)
        #expect(camera.exposureEndTime == end)
        #expect(!camera.isOverdue(now: end + 30))
        #expect(camera.isOverdue(now: end + 61))
    }
}
