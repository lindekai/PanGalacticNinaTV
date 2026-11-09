import Foundation
import Testing
@testable import PanGalacticCore

// Synthetic samples shaped after api_spec.yaml / websocket_spec.yaml at plugin
// 2.2.15.3. Replace or extend with sanitized live fixtures once captured (M0).
@Suite("N.I.N.A. decoding")
struct NINADecodingTests {
    @Test func decodesSuccessfulEnvelope() throws {
        let json = #"{"Response":"2.2.15.3","Error":"","StatusCode":200,"Success":true,"Type":"API"}"#
        let envelope = try JSONDecoder().decode(NINAEnvelope<String>.self, from: Data(json.utf8))
        #expect(try envelope.payload() == "2.2.15.3")
        #expect(envelope.type == "API")
    }

    @Test func errorEnvelopeWithMismatchedPayloadDecodes() throws {
        let json = #"{"Response":"","Error":"Sequence is not initialized","StatusCode":409,"Success":false,"Type":"API"}"#
        let envelope = try JSONDecoder().decode(NINAEnvelope<[String: Int]>.self, from: Data(json.utf8))
        #expect(envelope.response == nil)
        #expect(throws: NINAAPIError.server(statusCode: 409, message: "Sequence is not initialized")) {
            try envelope.payload()
        }
    }

    @Test func successEnvelopeWithWrongPayloadFails() {
        let json = #"{"Response":"oops","Error":"","StatusCode":200,"Success":true,"Type":"API"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(NINAEnvelope<Int>.self, from: Data(json.utf8))
        }
    }

    @Test func decodesImageSaveEvent() throws {
        let json = """
        {"Response":{"Event":"IMAGE-SAVE","ImageStatistics":{"ExposureTime":300,"Index":12,"Filter":"Ha",
        "RmsText":"","Temperature":-10.0,"CameraName":"Camera","Gain":100,"Offset":30,"Date":"2026-11-09T21:14:03",
        "TelescopeName":"Telescope","FocalLength":800,"StDev":12.5,"Mean":512.1,"Median":500,"Stars":874,
        "HFR":2.31,"IsBayered":false,"Min":0,"Max":65535,"HFRStDev":0.42,"TargetName":"M 31","Filename":"<redacted>"}},
        "Error":"","StatusCode":200,"Success":true,"Type":"Socket"}
        """
        let event = try NINASocketEvent.decode(Data(json.utf8))
        #expect(event.name == .imageSave)
        let stats = try #require(event.imageStatistics)
        #expect(stats.index == 12)
        #expect(stats.exposureTime == 300)
        #expect(stats.filter == "Ha")
        #expect(stats.hfr == 2.31)
        #expect(stats.stars == 874)
        #expect(stats.isBayered == false)
        #expect(stats.targetName == "M 31")
    }

    @Test func decodesEventWithoutPayloadAndUnknownNames() throws {
        let dither = try NINASocketEvent.decode(Data(#"{"Response":{"Event":"GUIDER-DITHER"},"Type":"Socket"}"#.utf8))
        #expect(dither.name == .guiderDither)
        #expect(dither.imageStatistics == nil)

        let future = try NINASocketEvent.decode(Data(#"{"Response":{"Event":"SOMETHING-NEW","X":1},"Type":"Socket"}"#.utf8))
        #expect(future.name.rawValue == "SOMETHING-NEW")

        let plain = try NINASocketEvent.decode(Data(#"{"Response":"CAMERA-INFO-UPDATED","Type":"Socket"}"#.utf8))
        #expect(plain.name.rawValue == "CAMERA-INFO-UPDATED")
    }

    @Test func malformedImageStatisticsDoNotDropTheEvent() throws {
        let json = #"{"Response":{"Event":"IMAGE-SAVE","ImageStatistics":{"Index":"twelve","HFR":"NaN","Stars":3.0}}}"#
        let event = try NINASocketEvent.decode(Data(json.utf8))
        #expect(event.name == .imageSave)
        let stats = try #require(event.imageStatistics)
        #expect(stats.index == nil)
        #expect(stats.hfr == nil)
        #expect(stats.stars == 3)
    }

    @Test func rejectsMessagesWithoutEvent() {
        #expect(throws: (any Error).self) { try NINASocketEvent.decode(Data(#"{"Response":{"Foo":1}}"#.utf8)) }
        #expect(throws: (any Error).self) { try NINASocketEvent.decode(Data("not json".utf8)) }
    }
}
