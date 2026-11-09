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
    }

    public struct Mount: Hashable, Sendable {
        public let device: Device
        public let trackingEnabled: Bool?
        public let atPark: Bool?
        public let slewing: Bool?
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
                       .flatMap { NINADate.parse($0) })
        }
        mount = device(.mount).map { d, dev in
            Mount(device: dev,
                  trackingEnabled: try? d.decodeIfPresent(Bool.self, forKey: .trackingEnabled),
                  atPark: try? d.decodeIfPresent(Bool.self, forKey: .atPark),
                  slewing: try? d.decodeIfPresent(Bool.self, forKey: .slewing))
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
