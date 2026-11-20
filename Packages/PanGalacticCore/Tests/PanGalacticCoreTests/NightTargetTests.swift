import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Night target")
struct NightTargetTests {
    @Test func runningTargetFromTheStateFixture() throws {
        let target = try #require(NightTarget.fromSequence(state: try SequenceProgressTests.tree("sequence-state-running-1")))
        #expect(target.name == "Coma Cluster")
        #expect(target.source == .sequence && target.epoch == .j2000)
        #expect(abs(target.coordinates.ra - 194.952917) < 1e-5) // 12h59m48.7s
        #expect(abs(target.coordinates.dec - 27.980556) < 1e-5) // +27°58′50″
    }

    static func state(_ status: String, negative: Bool = false, decDegrees: Int = 41, name: String = "M 31") throws -> JSONValue {
        try SequenceProgressTests.decode(#"""
            [{"Name":"Ziele_Container","Status":"RUNNING","Items":[
               {"Name":"Done_Container","Status":"FINISHED","Items":[],
                "Target":{"TargetName":"Old","InputCoordinates":{"RAHours":1,"RAMinutes":0,"RASeconds":0,"NegativeDec":false,"DecDegrees":10,"DecMinutes":0,"DecSeconds":0}}},
               {"Name":"M 31_Container","Status":"\#(status)","Items":[],
                "Target":{"TargetName":"\#(name)","PositionAngle":0,"InputCoordinates":{"RAHours":0,"RAMinutes":42,"RASeconds":44.0,"NegativeDec":\#(negative),"DecDegrees":\#(decDegrees),"DecMinutes":16,"DecSeconds":7.0}}}]}]
            """#)
    }

    @Test func createdTargetWhenNothingRuns() throws {
        let target = try #require(NightTarget.fromSequence(state: try Self.state("CREATED")))
        #expect(target.name == "M 31")
        #expect(abs(target.coordinates.ra - 10.683333) < 1e-5)
    }

    @Test func finishedTargetsAreNotUsed() throws {
        #expect(NightTarget.fromSequence(state: try Self.state("FINISHED")) == nil)
    }

    @Test func negativeDeclination() throws {
        let flag = try #require(NightTarget.fromSequence(state: try Self.state("RUNNING", negative: true, decDegrees: 0)))
        #expect(abs(flag.coordinates.dec - -(16.0 / 60 + 7.0 / 3600)) < 1e-6)
        let signed = try #require(NightTarget.fromSequence(state: try Self.state("RUNNING", decDegrees: -41)))
        #expect(abs(signed.coordinates.dec - -41.268611) < 1e-5)
    }

    @Test func emptyNameFallsBackToTheContainer() throws {
        let target = try #require(NightTarget.fromSequence(state: try Self.state("RUNNING", name: "")))
        #expect(target.name == "M 31")
    }

    @Test func noTargetInTheIdleFixture() throws {
        #expect(NightTarget.fromSequence(state: try SequenceProgressTests.tree("sequence-state-idle")) == nil)
    }

    static func idleSummary() throws -> NINAEquipmentSummary {
        let data = try LiveFixtureTests.fixture("nina/equipment-info-idle.json")
        return try JSONDecoder().decode(NINAEnvelope<NINAEquipmentSummary>.self, from: data).payload()
    }

    @Test func mountNumbersAndSiteAreDecoded() throws {
        let mount = try #require(try Self.idleSummary().mount)
        #expect(mount.rightAscensionHours != nil && mount.declinationDegrees != nil && mount.azimuthDegrees != nil)
        #expect(mount.site == nil, "the sanitised fixture has site 0, 0, 0")
    }

    @Test func mountTargetOnlyWhileTracking() throws {
        #expect(NightTarget.fromMount(try Self.idleSummary().mount, name: "M 31") == nil, "fixture mount is not tracking")
    }

    @Test func sequenceWinsOverTheMount() throws {
        let sequence = try #require(NightTarget.fromSequence(state: try Self.state("RUNNING")))
        #expect(NightTarget.resolve(sequence: sequence, mount: nil, imageTarget: nil) == sequence)
        #expect(NightTarget.resolve(sequence: nil, mount: nil, imageTarget: "X") == nil)
    }

    /// The idle fixture's mount, switched to tracking (unparked, tracking on).
    static func trackingMount() throws -> NINAEquipmentSummary.Mount {
        let data = try LiveFixtureTests.fixture("nina/equipment-info-idle.json")
        var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var response = try #require(root["Response"] as? [String: Any])
        var mount = try #require(response["Mount"] as? [String: Any])
        mount["Connected"] = true
        mount["AtPark"] = false
        mount["Slewing"] = false
        mount["TrackingEnabled"] = true
        mount["RightAscension"] = 0.75
        mount["Declination"] = 41.5
        response["Mount"] = mount
        root["Response"] = response
        let patched = try JSONSerialization.data(withJSONObject: root)
        let summary = try JSONDecoder().decode(NINAEnvelope<NINAEquipmentSummary>.self, from: patched).payload()
        return try #require(summary.mount)
    }

    @Test func trackingMountIsATargetOfDate() throws {
        let mount = try Self.trackingMount()
        #expect(mount.activity == .tracking)
        let target = try #require(NightTarget.fromMount(mount, name: "M 31"))
        #expect(target.name == "M 31")
        #expect(target.source == .mount && target.epoch == .ofDate)
        #expect(abs(target.coordinates.ra - 11.25) < 1e-9, "0.75 h × 15")
        #expect(abs(target.coordinates.dec - 41.5) < 1e-9)
        #expect(NightTarget.fromMount(mount, name: nil)?.name == nil)
    }

    @Test func resolveFallsBackToTheTrackingMount() throws {
        let mount = try Self.trackingMount()
        let resolved = try #require(NightTarget.resolve(sequence: nil, mount: mount, imageTarget: "NGC 7000"))
        #expect(resolved.source == .mount && resolved.name == "NGC 7000")
        let sequence = try #require(NightTarget.fromSequence(state: try Self.state("RUNNING")))
        #expect(NightTarget.resolve(sequence: sequence, mount: mount, imageTarget: "NGC 7000") == sequence)
    }

    /// Spec: the target is dimmed with "As of" when stale and "—" while unknown; unknown,
    /// stale and empty stay distinct (AGENTS.md).
    @Test func targetStateFollowsTheConnection() throws {
        let mount = try #require(NightTarget.fromMount(try Self.trackingMount(), name: nil))
        let sequence = try #require(NightTarget.fromSequence(state: try Self.state("RUNNING")))
        #expect(NightTargetState(target: sequence, phase: .live) == .live(sequence))
        #expect(NightTargetState(target: nil, phase: .live) == .none)
        for target in [sequence, mount] {
            #expect(NightTargetState(target: target, phase: .stale) == .stale(target))
            #expect(NightTargetState(target: target, phase: .offline) == .stale(target), "the mount target is kept while offline")
            #expect(NightTargetState(target: target, phase: .connecting) == .stale(target))
        }
        #expect(NightTargetState(target: nil, phase: .stale) == .none, "last known: no target")
        #expect(NightTargetState(target: nil, phase: .offline) == .unknown)
        #expect(NightTargetState(target: nil, phase: .connecting) == .unknown)
        #expect(NightTargetState.stale(mount).isStale && !NightTargetState.live(mount).isStale)
        #expect(NightTargetState.unknown.isUnknown && !NightTargetState.none.isUnknown)
    }

    @Test func ofDatePrecessesOnlyJ2000() {
        let date = ISO8601DateFormatter().date(from: "2026-11-19T20:00:00Z")!
        let j2000 = NightTarget(name: nil, coordinates: Equatorial(ra: 10.683333, dec: 41.268611), epoch: .j2000, source: .sequence)
        #expect(abs(j2000.ofDate(date).ra - 11.058) < 0.02)
        let jnow = NightTarget(name: nil, coordinates: Equatorial(ra: 11.0, dec: 41.4), epoch: .ofDate, source: .mount)
        #expect(jnow.ofDate(date) == jnow.coordinates)
    }
}
