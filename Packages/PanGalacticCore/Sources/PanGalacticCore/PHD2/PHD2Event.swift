import Foundation

/// PHD2 application state as documented in the EventMonitoring wiki.
public enum PHD2AppState: Hashable, Sendable {
    case stopped, selected, calibrating, guiding, lostLock, paused, looping
    case other(String)

    init(wire: String) {
        switch wire {
        case "Stopped": self = .stopped
        case "Selected": self = .selected
        case "Calibrating": self = .calibrating
        case "Guiding": self = .guiding
        case "LostLock": self = .lostLock
        case "Paused": self = .paused
        case "Looping": self = .looping
        default: self = .other(wire)
        }
    }
}

public struct PHD2GuideStep: Hashable, Sendable {
    public let frame: Int?
    /// Seconds since guiding started.
    public let time: Double?
    public let mount: String?
    public let dx: Double?
    public let dy: Double?
    /// RA/Dec distance of the guide offset in pixels (before algorithm modification).
    public let raDistanceRaw: Double
    public let decDistanceRaw: Double
    public let raDurationMs: Double?
    public let raDirection: String?
    public let decDurationMs: Double?
    public let decDirection: String?
    public let starMass: Double?
    public let snr: Double?
    public let hfd: Double?
    public let avgDist: Double?
    public let raLimited: Bool
    public let decLimited: Bool
    public let errorCode: Int?
}

public struct PHD2StarLost: Hashable, Sendable {
    public let frame: Int?
    public let time: Double?
    public let starMass: Double?
    public let snr: Double?
    public let avgDist: Double?
    public let errorCode: Int?
    public let status: String?
}

public struct PHD2Settling: Hashable, Sendable {
    public let distance: Double?
    public let time: Double?
    public let settleTime: Double?
    public let starLocked: Bool?
}

public struct PHD2SettleDone: Hashable, Sendable {
    /// 0 on success, non-zero on failure.
    public let status: Int?
    public let error: String?
    public let totalFrames: Int?
    public let droppedFrames: Int?

    public var succeeded: Bool? { status.map { $0 == 0 } }
}

public enum PHD2Event: Hashable, Sendable {
    case version(phdVersion: String?, subversion: String?, messageVersion: Int?)
    case appState(PHD2AppState)
    case guideStep(PHD2GuideStep)
    case starLost(PHD2StarLost)
    case startGuiding
    case guidingStopped
    case paused
    case resumed
    case startCalibration(mount: String?)
    case calibrationComplete(mount: String?)
    case calibrationFailed(reason: String?)
    case loopingExposures(frame: Int?)
    case loopingExposuresStopped
    case settleBegin
    case settling(PHD2Settling)
    case settleDone(PHD2SettleDone)
    case guidingDithered(dx: Double?, dy: Double?)
    case lockPositionLost
    case alert(message: String?, type: String?)
    /// Documented or future event this app does not interpret.
    case other(name: String)
}

/// An event plus the attributes common to all PHD2 notifications.
public struct PHD2Message: Hashable, Sendable {
    public let event: PHD2Event
    /// Event time from PHD2 (seconds since epoch), `nil` if absent.
    public let timestamp: Date?
    /// PHD2 instance number (1-based).
    public let instance: Int?
}

public enum PHD2EventDecoder {
    public enum DecodingError: Error, Equatable, Sendable {
        case notJSONObject
        case missingField(String)
    }

    /// Decodes one line. Returns `nil` for lines that are not event notifications
    /// (e.g. JSON-RPC responses, which this read-only client never solicits).
    public static func decode(line: Data) throws -> PHD2Message? {
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw DecodingError.notJSONObject
        }
        guard let name = object["Event"] as? String else { return nil }
        let f = Fields(object)
        let event: PHD2Event
        switch name {
        case "Version":
            event = .version(phdVersion: f.string("PHDVersion"), subversion: f.string("PHDSubver"),
                             messageVersion: f.int("MsgVersion"))
        case "AppState":
            guard let state = f.string("State") else { throw DecodingError.missingField("State") }
            event = .appState(PHD2AppState(wire: state))
        case "GuideStep":
            guard let ra = f.double("RADistanceRaw") else { throw DecodingError.missingField("RADistanceRaw") }
            guard let dec = f.double("DECDistanceRaw") else { throw DecodingError.missingField("DECDistanceRaw") }
            event = .guideStep(PHD2GuideStep(
                frame: f.int("Frame"), time: f.double("Time"), mount: f.string("Mount"),
                dx: f.double("dx"), dy: f.double("dy"), raDistanceRaw: ra, decDistanceRaw: dec,
                raDurationMs: f.double("RADuration"), raDirection: f.string("RADirection"),
                decDurationMs: f.double("DECDuration"), decDirection: f.string("DECDirection"),
                starMass: f.double("StarMass"), snr: f.double("SNR"), hfd: f.double("HFD"),
                avgDist: f.double("AvgDist"), raLimited: f.bool("RALimited") ?? false,
                decLimited: f.bool("DecLimited") ?? false, errorCode: f.int("ErrorCode")))
        case "StarLost":
            event = .starLost(PHD2StarLost(
                frame: f.int("Frame"), time: f.double("Time"), starMass: f.double("StarMass"),
                snr: f.double("SNR"), avgDist: f.double("AvgDist"), errorCode: f.int("ErrorCode"),
                status: f.string("Status")))
        case "StartGuiding": event = .startGuiding
        case "GuidingStopped": event = .guidingStopped
        case "Paused": event = .paused
        case "Resumed": event = .resumed
        case "StartCalibration": event = .startCalibration(mount: f.string("Mount"))
        case "CalibrationComplete": event = .calibrationComplete(mount: f.string("Mount"))
        case "CalibrationFailed": event = .calibrationFailed(reason: f.string("Reason"))
        case "LoopingExposures": event = .loopingExposures(frame: f.int("Frame"))
        case "LoopingExposuresStopped": event = .loopingExposuresStopped
        case "SettleBegin": event = .settleBegin
        case "Settling":
            event = .settling(PHD2Settling(distance: f.double("Distance"), time: f.double("Time"),
                                           settleTime: f.double("SettleTime"), starLocked: f.bool("StarLocked")))
        case "SettleDone":
            event = .settleDone(PHD2SettleDone(status: f.int("Status"), error: f.string("Error"),
                                               totalFrames: f.int("TotalFrames"),
                                               droppedFrames: f.int("DroppedFrames")))
        case "GuidingDithered": event = .guidingDithered(dx: f.double("dx"), dy: f.double("dy"))
        case "LockPositionLost": event = .lockPositionLost
        case "Alert": event = .alert(message: f.string("Msg"), type: f.string("Type"))
        default: event = .other(name: name)
        }
        return PHD2Message(event: event, timestamp: f.double("Timestamp").map(Date.init(timeIntervalSince1970:)),
                           instance: f.int("Inst"))
    }

    /// Typed, lenient accessors over a JSON object. JSONSerialization yields NSNumber
    /// for both numbers and booleans, so they are told apart explicitly.
    private struct Fields {
        let object: [String: Any]
        init(_ object: [String: Any]) { self.object = object }

        func string(_ key: String) -> String? { object[key] as? String }

        func double(_ key: String) -> Double? {
            guard let n = object[key] as? NSNumber, !n.isBool else { return nil }
            let value = n.doubleValue
            return value.isFinite ? value : nil
        }

        func int(_ key: String) -> Int? {
            guard let value = double(key), value.rounded() == value, abs(value) < 1e15 else { return nil }
            return Int(value)
        }

        func bool(_ key: String) -> Bool? {
            guard let n = object[key] as? NSNumber, n.isBool else { return nil }
            return n.boolValue
        }
    }
}

private extension NSNumber {
    var isBool: Bool { CFGetTypeID(self) == CFBooleanGetTypeID() }
}
