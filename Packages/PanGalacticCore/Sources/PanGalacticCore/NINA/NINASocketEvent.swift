import Foundation

/// Event name from the Advanced API WebSocket (`/v2/socket`).
/// Unknown names are preserved so that new plugin versions do not break decoding.
public struct NINAEventName: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    // Names from websocket_spec.yaml at plugin 2.2.15.3.
    public static let imageSave = Self(rawValue: "IMAGE-SAVE")
    public static let imagePrepared = Self(rawValue: "IMAGE-PREPARED")
    public static let sequenceStarting = Self(rawValue: "SEQUENCE-STARTING")
    public static let sequenceFinished = Self(rawValue: "SEQUENCE-FINISHED")
    public static let sequenceEntityFailed = Self(rawValue: "SEQUENCE-ENTITY-FAILED")
    public static let filterwheelChanged = Self(rawValue: "FILTERWHEEL-CHANGED")
    public static let guiderStart = Self(rawValue: "GUIDER-START")
    public static let guiderStop = Self(rawValue: "GUIDER-STOP")
    public static let guiderDither = Self(rawValue: "GUIDER-DITHER")
    public static let autofocusStarting = Self(rawValue: "AUTOFOCUS-STARTING")
    public static let autofocusFinished = Self(rawValue: "AUTOFOCUS-FINISHED")
    public static let errorAutofocus = Self(rawValue: "ERROR-AF")
    public static let errorPlatesolve = Self(rawValue: "ERROR-PLATESOLVE")
    public static let cameraConnected = Self(rawValue: "CAMERA-CONNECTED")
    public static let cameraDisconnected = Self(rawValue: "CAMERA-DISCONNECTED")
    public static let cameraDownloadTimeout = Self(rawValue: "CAMERA-DOWNLOAD-TIMEOUT")
    public static let mountConnected = Self(rawValue: "MOUNT-CONNECTED")
    public static let mountDisconnected = Self(rawValue: "MOUNT-DISCONNECTED")
    public static let mountParked = Self(rawValue: "MOUNT-PARKED")
    public static let mountBeforeFlip = Self(rawValue: "MOUNT-BEFORE-FLIP")
    public static let mountAfterFlip = Self(rawValue: "MOUNT-AFTER-FLIP")
    public static let guiderConnected = Self(rawValue: "GUIDER-CONNECTED")
    public static let guiderDisconnected = Self(rawValue: "GUIDER-DISCONNECTED")
    public static let safetyChanged = Self(rawValue: "SAFETY-CHANGED")
}

/// `ImageStatistics` payload of `IMAGE-SAVE` as documented in websocket_spec.yaml.
/// All fields optional until confirmed by live fixtures.
public struct NINAImageSaveStatistics: Decodable, Hashable, Sendable {
    public let index: Int?
    public let exposureTime: Double?
    public let filter: String?
    public let temperature: Double?
    public let cameraName: String?
    public let gain: Double?
    public let offset: Double?
    /// Raw date string; format to be pinned from a live fixture.
    public let date: String?
    public let telescopeName: String?
    public let focalLength: Double?
    public let targetName: String?
    public let hfr: Double?
    public let hfrStDev: Double?
    public let stars: Int?
    public let mean: Double?
    public let median: Double?
    public let stDev: Double?
    public let min: Double?
    public let max: Double?
    public let isBayered: Bool?
    public let rmsText: String?

    enum CodingKeys: String, CodingKey {
        case index = "Index", exposureTime = "ExposureTime", filter = "Filter", temperature = "Temperature"
        case cameraName = "CameraName", gain = "Gain", offset = "Offset", date = "Date"
        case telescopeName = "TelescopeName", focalLength = "FocalLength", targetName = "TargetName"
        case hfr = "HFR", hfrStDev = "HFRStDev", stars = "Stars", mean = "Mean", median = "Median"
        case stDev = "StDev", min = "Min", max = "Max", isBayered = "IsBayered", rmsText = "RmsText"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = c.lenientInt(.index)
        exposureTime = c.lenientDouble(.exposureTime)
        filter = try? c.decodeIfPresent(String.self, forKey: .filter)
        temperature = c.lenientDouble(.temperature)
        cameraName = try? c.decodeIfPresent(String.self, forKey: .cameraName)
        gain = c.lenientDouble(.gain)
        offset = c.lenientDouble(.offset)
        date = try? c.decodeIfPresent(String.self, forKey: .date)
        telescopeName = try? c.decodeIfPresent(String.self, forKey: .telescopeName)
        focalLength = c.lenientDouble(.focalLength)
        targetName = try? c.decodeIfPresent(String.self, forKey: .targetName)
        hfr = c.lenientDouble(.hfr)
        hfrStDev = c.lenientDouble(.hfrStDev)
        stars = c.lenientInt(.stars)
        mean = c.lenientDouble(.mean)
        median = c.lenientDouble(.median)
        stDev = c.lenientDouble(.stDev)
        min = c.lenientDouble(.min)
        max = c.lenientDouble(.max)
        isBayered = try? c.decodeIfPresent(Bool.self, forKey: .isBayered)
        rmsText = try? c.decodeIfPresent(String.self, forKey: .rmsText)
    }
}

/// One message from `/v2/socket`.
public struct NINASocketEvent: Sendable {
    public let name: NINAEventName
    public let imageStatistics: NINAImageSaveStatistics?
    /// Arrival time on this device. The plugin does not include a timestamp in live
    /// socket messages (only in `/event-history`).
    public let receivedAt: Date

    public static func decode(_ data: Data, receivedAt: Date = Date()) throws -> NINASocketEvent {
        let message = try JSONDecoder().decode(Message.self, from: data)
        return NINASocketEvent(name: message.name, imageStatistics: message.imageStatistics, receivedAt: receivedAt)
    }

    private struct Message: Decodable {
        let name: NINAEventName
        let imageStatistics: NINAImageSaveStatistics?

        enum CodingKeys: String, CodingKey { case response = "Response" }
        enum PayloadKeys: String, CodingKey { case event = "Event", imageStatistics = "ImageStatistics" }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Plain-string responses (e.g. "<DEVICE>-INFO-UPDATED") carry only a name.
            if let plain = try? c.decode(String.self, forKey: .response) {
                name = NINAEventName(rawValue: plain)
                imageStatistics = nil
                return
            }
            let payload = try c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .response)
            name = NINAEventName(rawValue: try payload.decode(String.self, forKey: .event))
            imageStatistics = try? payload.decodeIfPresent(NINAImageSaveStatistics.self, forKey: .imageStatistics)
        }
    }
}
