import Foundation

/// The subset of `GET /equipment/info` shown on the dashboard. Every device is
/// optional and every field lenient: missing devices and unknown values decode to
/// `nil` instead of failing the whole response.
///
/// Live 2.2.15.3 quirks: a device may be an empty object (`"Focuser": {}`), which
/// means "unknown", not "disconnected"; `DisplayName` can carry a driver ID suffix,
/// so `Name` is preferred.
public struct NINAEquipmentSummary: Decodable, Hashable, Sendable {
    public struct Device: Hashable, Sendable {
        public let connected: Bool
        public let name: String?
    }

    public struct Camera: Hashable, Sendable {
        public let device: Device
        public let temperature: Double?
        public let coolerOn: Bool?
        public let coolerPower: Double?
        public let isExposing: Bool?
        public let exposureEndTime: Date?
        /// `TemperatureSetPoint`: the setpoint reported by the camera driver.
        /// `TargetTemp` (the value typed into N.I.N.A.'s camera panel, not necessarily
        /// applied) and `AtTargetTemp` (exact float equality) are deliberately ignored (#5).
        public let driverSetpoint: Double?
        public let gain: Int?
        public let offset: Int?

        /// The setpoint the cooler is regulating to; `nil` while the cooler is off or unknown.
        public var activeSetpoint: Double? { coolerOn == true ? driverSetpoint : nil }
    }

    public struct Mount: Hashable, Sendable {
        public let device: Device
        public let trackingEnabled: Bool?
        public let atPark: Bool?
        public let slewing: Bool?
        /// Formatted by N.I.N.A.; epoch is JNOW (M0 finding).
        public let rightAscension: String?
        public let declination: String?
        public let altitudeDegrees: Double?
        public let sideOfPier: SideOfPier?
    }

    public enum SideOfPier: String, Hashable, Sendable {
        case east = "pierEast", west = "pierWest"
    }

    public struct FilterWheel: Hashable, Sendable {
        public let device: Device
        public let selectedFilter: String?
    }

    public struct Guider: Hashable, Sendable {
        public let device: Device
        public let state: String?
    }

    public struct Focuser: Hashable, Sendable {
        public let device: Device
        public let position: Int?
        public let temperature: Double?
    }

    public let camera: Camera?
    public let mount: Mount?
    public let filterWheel: FilterWheel?
    public let guider: Guider?
    public let focuser: Focuser?

    enum Keys: String, CodingKey {
        case camera = "Camera", mount = "Mount", filterWheel = "FilterWheel", guider = "Guider", focuser = "Focuser"
    }

    enum Field: String, CodingKey {
        case connected = "Connected", name = "Name", displayName = "DisplayName"
        case temperature = "Temperature", coolerOn = "CoolerOn", coolerPower = "CoolerPower"
        case isExposing = "IsExposing", exposureEndTime = "ExposureEndTime"
        case trackingEnabled = "TrackingEnabled", atPark = "AtPark", slewing = "Slewing"
        case selectedFilter = "SelectedFilter", state = "State", position = "Position"
        case temperatureSetPoint = "TemperatureSetPoint", gain = "Gain", offset = "Offset"
        case rightAscensionString = "RightAscensionString", declinationString = "DeclinationString"
        case altitude = "Altitude", sideOfPier = "SideOfPier"
    }

    enum FilterField: String, CodingKey { case name = "Name" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)

        func device(_ key: Keys) -> (KeyedDecodingContainer<Field>, Device)? {
            guard let d = try? c.nestedContainer(keyedBy: Field.self, forKey: key),
                  let connected = (try? d.decodeIfPresent(Bool.self, forKey: .connected)) ?? nil
            else { return nil }
            let name = (try? d.decodeIfPresent(String.self, forKey: .name)) ?? nil
                ?? (try? d.decodeIfPresent(String.self, forKey: .displayName)) ?? nil
            return (d, Device(connected: connected, name: name))
        }

        camera = device(.camera).map { d, dev in
            Camera(device: dev,
                   temperature: dev.connected ? d.lenientDouble(.temperature) : nil,
                   coolerOn: try? d.decodeIfPresent(Bool.self, forKey: .coolerOn),
                   coolerPower: d.lenientDouble(.coolerPower),
                   isExposing: try? d.decodeIfPresent(Bool.self, forKey: .isExposing),
                   exposureEndTime: ((try? d.decodeIfPresent(String.self, forKey: .exposureEndTime)) ?? nil)
                       .flatMap { NINADate.parse($0) },
                   driverSetpoint: d.lenientDouble(.temperatureSetPoint),
                   gain: d.lenientInt(.gain),
                   offset: d.lenientInt(.offset))
        }
        mount = device(.mount).map { d, dev in
            Mount(device: dev,
                  trackingEnabled: try? d.decodeIfPresent(Bool.self, forKey: .trackingEnabled),
                  atPark: try? d.decodeIfPresent(Bool.self, forKey: .atPark),
                  slewing: try? d.decodeIfPresent(Bool.self, forKey: .slewing),
                  rightAscension: dev.connected ? (try? d.decodeIfPresent(String.self, forKey: .rightAscensionString)) ?? nil : nil,
                  declination: dev.connected ? (try? d.decodeIfPresent(String.self, forKey: .declinationString)) ?? nil : nil,
                  altitudeDegrees: dev.connected ? d.lenientDouble(.altitude) : nil,
                  sideOfPier: ((try? d.decodeIfPresent(String.self, forKey: .sideOfPier)) ?? nil).flatMap(SideOfPier.init))
        }
        filterWheel = device(.filterWheel).map { d, dev in
            let filter = try? d.nestedContainer(keyedBy: FilterField.self, forKey: .selectedFilter)
            return FilterWheel(device: dev, selectedFilter: (try? filter?.decodeIfPresent(String.self, forKey: .name)) ?? nil)
        }
        guider = device(.guider).map { d, dev in
            Guider(device: dev, state: try? d.decodeIfPresent(String.self, forKey: .state))
        }
        focuser = device(.focuser).map { d, dev in
            Focuser(device: dev, position: d.lenientInt(.position), temperature: d.lenientDouble(.temperature))
        }
    }
}

extension NINAEquipmentSummary.Camera {
    /// An exposure that should have ended more than `grace` ago but is still reported
    /// as running – observed in M0 when a camera driver hung.
    public func isOverdue(now: Date, grace: TimeInterval = 60) -> Bool {
        guard isExposing == true, let end = exposureEndTime else { return false }
        return now.timeIntervalSince(end) > grace
    }
}
