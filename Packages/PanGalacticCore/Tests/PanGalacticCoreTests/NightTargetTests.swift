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

    @Test func ofDatePrecessesOnlyJ2000() {
        let date = ISO8601DateFormatter().date(from: "2026-11-19T20:00:00Z")!
        let j2000 = NightTarget(name: nil, coordinates: Equatorial(ra: 10.683333, dec: 41.268611), epoch: .j2000, source: .sequence)
        #expect(abs(j2000.ofDate(date).ra - 11.058) < 0.02)
        let jnow = NightTarget(name: nil, coordinates: Equatorial(ra: 11.0, dec: 41.4), epoch: .ofDate, source: .mount)
        #expect(jnow.ofDate(date) == jnow.coordinates)
    }
}
