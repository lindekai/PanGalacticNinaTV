import Foundation

/// What a device's detail page shows, built from its `/equipment/info` object.
/// Semantics follow the source review of 2026-11-16 (capability matrix, "Device
/// details"): a disconnected device is a default-constructed object whose values
/// (0, -1, `pierEast`, `IsSafe = false` …) mean nothing, so only a connected device
/// gets sections; `"NaN"` is a missing reading; localized UI strings in the payload
/// (`FollowingType`, `LocalizedCoverState`, `LocalizedLightOnState`) are never shown,
/// the machine-readable fields next to them are.
public struct DeviceDetail: Hashable, Sendable {
    public enum Label: Hashable, Sendable {
        /// English key, localized by the app.
        case key(String)
        /// User- or driver-defined text such as a filter or switch name.
        case verbatim(String)
    }

    public enum Value: Hashable, Sendable {
        case missing
        /// Shown as sent, e.g. N.I.N.A.'s own "13:01:13" or a Bayer pattern.
        case text(String)
        /// English key, localized by the app.
        case word(String)
        case yesNo(Bool)
        case onOff(Bool)
        case number(Double, digits: Int, unit: String)
        case time(Date)
        /// A value within its range, e.g. the flat panel's brightness.
        case level(Double, min: Double, max: Double)
        /// Raw guider state; the app localizes the PHD2 values and shows others as sent.
        case guiderState(String)
    }

    public struct Row: Hashable, Sendable {
        public let label: Label
        public let value: Value
        /// Stands out, e.g. the active filter or an unsafe safety monitor.
        public let highlighted: Bool

        init(_ label: Label, _ value: Value, highlighted: Bool = false) {
            self.label = label
            self.value = value
            self.highlighted = highlighted
        }

        init(_ key: String, _ value: Value, highlighted: Bool = false) {
            self.init(.key(key), value, highlighted: highlighted)
        }
    }

    public struct Section: Hashable, Sendable {
        /// English key, localized by the app.
        public let title: String
        public let rows: [Row]
    }

    public let kind: NINAEquipmentSummary.DeviceKind
    /// `nil` is unknown (no object, or one without `Connected`).
    public let connected: Bool?
    /// Empty unless connected; empty sections are left out.
    public let sections: [Section]

    public init(kind: NINAEquipmentSummary.DeviceKind, object: JSONValue?) {
        self.kind = kind
        connected = object?["Connected"]?.bool
        guard connected == true, let object else {
            sections = []
            return
        }
        let builder = Builder(object)
        sections = (builder.sections(for: kind) + [builder.driver]).filter { !$0.rows.isEmpty }
    }
}

private struct Builder {
    typealias Row = DeviceDetail.Row
    typealias Section = DeviceDetail.Section

    let o: JSONValue

    init(_ object: JSONValue) { o = object }

    func sections(for kind: NINAEquipmentSummary.DeviceKind) -> [Section] {
        switch kind {
        case .camera: camera
        case .mount: mount
        case .focuser: focuser
        case .filterWheel: filterWheel
        case .rotator: rotator
        case .flatDevice: flatDevice
        case .switchHub: switchHub
        case .weather: weather
        case .safetyMonitor: safetyMonitor
        case .guider: guider
        case .dome: dome
        }
    }

    // MARK: Values

    func number(_ key: String, digits: Int, unit: String = "") -> DeviceDetail.Value {
        o[key]?.double.map { .number($0, digits: digits, unit: unit) } ?? .missing
    }

    func text(_ key: String) -> DeviceDetail.Value {
        o[key]?.string.flatMap { $0.isEmpty ? nil : .text($0) } ?? .missing
    }

    func yesNo(_ key: String) -> DeviceDetail.Value { o[key]?.bool.map { .yesNo($0) } ?? .missing }
    func onOff(_ key: String) -> DeviceDetail.Value { o[key]?.bool.map { .onOff($0) } ?? .missing }
    func flag(_ key: String) -> Bool { o[key]?.bool == true }

    /// An enum sent as its C# member name, mapped to an English display key; unknown
    /// members are shown as sent.
    func word(_ key: String, _ words: [String: String]) -> DeviceDetail.Value {
        guard let raw = o[key]?.string, !raw.isEmpty else { return .missing }
        return words[raw].map { .word($0) } ?? .text(raw)
    }

    /// Rows whose value is missing are left out: the device does not report it.
    func present(_ rows: [Row]) -> [Row] { rows.filter { $0.value != .missing } }

    // MARK: Devices

    var camera: [Section] {
        var cooling: [Row] = [Row("Sensor temperature", number("Temperature", digits: 1, unit: "°C"))]
        if flag("CanSetTemperature") {
            cooling.append(Row("Cooler", onOff("CoolerOn")))
            // The driver's setpoint applies only while the cooler runs (#5); `AtTargetTemp`
            // is an exact float comparison and not shown.
            if flag("CoolerOn") { cooling.append(Row("Setpoint", number("TemperatureSetPoint", digits: 1, unit: "°C"))) }
            cooling.append(Row("Cooler power", number("CoolerPower", digits: 0, unit: "%")))
        }
        if flag("HasDewHeater") { cooling.append(Row("Dew heater", onOff("DewHeaterOn"))) }

        var exposure: [Row] = [
            Row("State", word("CameraState", [
                "NoState": "Unknown", "Idle": "Idle", "Waiting": "Waiting", "Exposing": "Exposing",
                "Reading": "Reading out", "Download": "Downloading", "Error": "Error", "LoadingFile": "Loading file",
            ])),
        ]
        if flag("IsExposing"), let end = o["ExposureEndTime"]?.string.flatMap({ NINADate.parse($0) }) {
            exposure.append(Row("Exposure ends", .time(end)))
        }
        if flag("CanGetGain") { exposure.append(Row("Gain", number("Gain", digits: 0))) }
        if flag("CanSetOffset") { exposure.append(Row("Offset", number("Offset", digits: 0))) }
        if let x = o["BinX"]?.int, let y = o["BinY"]?.int { exposure.append(Row("Binning", .text("\(x)×\(y)"))) }
        exposure.append(Row("Readout mode", number("ReadoutMode", digits: 0)))
        if flag("CanSetUSBLimit") { exposure.append(Row("USB limit", number("USBLimit", digits: 0))) }
        // -1: no download yet.
        if let download = o["LastDownloadTime"]?.double, download >= 0 {
            exposure.append(Row("Last download", .number(download, digits: 2, unit: "s")))
        }
        if flag("CanSubSample") { exposure.append(Row("Subframe", onOff("IsSubSampleEnabled"))) }
        if flag("CanShowLiveView") { exposure.append(Row("Live view", onOff("LiveViewEnabled"))) }
        // `HasBattery` is never filled in by the plugin; -1 means no battery.
        if let battery = o["Battery"]?.double, battery >= 0 {
            exposure.append(Row("Battery", .number(battery, digits: 0, unit: "%")))
        }

        var sensor: [Row] = []
        if let x = o["XSize"]?.int, let y = o["YSize"]?.int, x > 0, y > 0 {
            sensor.append(Row("Resolution", .text("\(x) × \(y) px")))
        }
        sensor.append(Row("Pixel size", number("PixelSize", digits: 2, unit: "µm")))
        sensor.append(Row("Sensor type", word("SensorType", ["Monochrome": "Monochrome", "Color": "Color"])))
        sensor.append(Row("Bit depth", number("BitDepth", digits: 0, unit: "bit")))
        if flag("CanGetGain"), let min = o["GainMin"]?.int, let max = o["GainMax"]?.int {
            sensor.append(Row("Gain range", .text("\(min)–\(max)")))
        }
        if let max = o["ExposureMax"]?.double {
            sensor.append(Row("Longest exposure", .number(max, digits: 0, unit: "s")))
        }
        return [
            Section(title: "Cooling", rows: present(cooling)),
            Section(title: "Exposure", rows: present(exposure)),
            Section(title: "Sensor", rows: present(sensor)),
        ]
    }

    var mount: [Section] {
        let position = [
            Row("Right ascension", text("RightAscensionString")),
            Row("Declination", text("DeclinationString")),
            Row("Altitude", text("AltitudeString")),
            Row("Azimuth", text("AzimuthString")),
            Row("Side of pier", word("SideOfPier", ["pierEast": "East", "pierWest": "West", "pierUnknown": "Unknown"])),
            Row("Sidereal time", text("SiderealTimeString")),
            Row("Epoch", text("EquatorialSystem")),
        ]
        var motion = [
            Row("Tracking", onOff("TrackingEnabled")),
            Row("Tracking rate", word("TrackingMode", [
                "Sidereal": "Sidereal", "Lunar": "Lunar", "Solar": "Solar", "King": "King",
                "Custom": "Custom", "Stopped": "Stopped",
            ])),
            Row("Slewing", yesNo("Slewing")),
            Row("Parked", yesNo("AtPark")),
            Row("At home", yesNo("AtHome")),
        ]
        if flag("CanPulseGuide") {
            motion.append(Row("Pulse guiding", yesNo("IsPulseGuiding")))
            motion.append(Row("Guide rate RA", number("GuideRateRightAscensionArcsecPerSec", digits: 2, unit: "″/s")))
            motion.append(Row("Guide rate Dec", number("GuideRateDeclinationArcsecPerSec", digits: 2, unit: "″/s")))
        }
        var meridian = [Row("Time to meridian", text("HoursToMeridianString"))]
        // 24 h stands for "not applicable" (not tracking, or no flip due).
        if flag("TrackingEnabled"), let hours = o["TimeToMeridianFlip"]?.double, hours < 24 {
            meridian.append(Row("Time to flip", text("TimeToMeridianFlipString")))
        }
        let site = [
            Row("Latitude", number("SiteLatitude", digits: 4, unit: "°")),
            Row("Longitude", number("SiteLongitude", digits: 4, unit: "°")),
            Row("Elevation", number("SiteElevation", digits: 0, unit: "m")),
            Row("Alignment", word("AlignmentMode", [
                "AltAz": "Alt-azimuth", "Polar": "Equatorial", "GermanPolar": "German equatorial",
            ])),
        ]
        return [
            Section(title: "Position", rows: present(position)),
            Section(title: "Motion", rows: present(motion)),
            Section(title: "Meridian", rows: present(meridian)),
            Section(title: "Site", rows: present(site)),
        ]
    }

    var focuser: [Section] {
        var rows = [
            Row("Position (steps)", number("Position", digits: 0)),
            Row("Temperature", number("Temperature", digits: 1, unit: "°C")),
            Row("Moving", yesNo("IsMoving")),
            Row("Settling", yesNo("IsSettling")),
        ]
        if flag("TempCompAvailable") { rows.append(Row("Temperature compensation", onOff("TempComp"))) }
        if let step = o["StepSize"]?.double, step > 0 { rows.append(Row("Step size", .number(step, digits: 2, unit: "µm"))) }
        return [Section(title: "Status", rows: present(rows))]
    }

    var filterWheel: [Section] {
        let selected = o["SelectedFilter"]?["Id"]?.int
        let status = [
            Row("Active filter", o["SelectedFilter"]?["Name"]?.string.map { .text($0) } ?? .missing),
            Row("Moving", yesNo("IsMoving")),
        ]
        // From the active profile; `Id` is the 0-based slot.
        let filters = (o["AvailableFilters"]?.array ?? []).compactMap { filter -> Row? in
            guard let name = filter["Name"]?.string, let id = filter["Id"]?.int else { return nil }
            return Row(.verbatim(name), .text("#\(id + 1)"), highlighted: id == selected)
        }
        return [Section(title: "Status", rows: present(status)), Section(title: "Filters", rows: filters)]
    }

    var rotator: [Section] {
        var rows = [
            Row("Sky angle", number("Position", digits: 1, unit: "°")),
            Row("Mechanical angle", number("MechanicalPosition", digits: 1, unit: "°")),
            Row("Moving", yesNo("IsMoving")),
            Row("Synced", yesNo("Synced")),
        ]
        if flag("CanReverse") { rows.append(Row("Reversed", yesNo("Reverse"))) }
        return [Section(title: "Status", rows: present(rows))]
    }

    var flatDevice: [Section] {
        var rows: [Row] = []
        if flag("SupportsOpenClose") {
            rows.append(Row("Cover", word("CoverState", [
                "Unknown": "Unknown", "NeitherOpenNorClosed": "Neither open nor closed", "Closed": "Closed",
                "Open": "Open", "Error": "Error", "NotPresent": "Not present",
            ])))
        }
        if flag("SupportsOnOff") { rows.append(Row("Light", onOff("LightOn"))) }
        if let value = o["Brightness"]?.double, let min = o["MinBrightness"]?.double, let max = o["MaxBrightness"]?.double,
           max > min {
            rows.append(Row("Brightness", .level(value, min: min, max: max)))
        }
        return [Section(title: "Status", rows: present(rows))]
    }

    /// Values have driver-defined units; channels with a 0…1 range in steps of 1 are switches.
    var switchHub: [Section] {
        func rows(_ key: String) -> [Row] {
            (o[key]?.array ?? []).compactMap { item in
                guard let name = item["Name"]?.string, let value = item["Value"]?.double else { return nil }
                let isSwitch = item["Minimum"]?.double == 0 && item["Maximum"]?.double == 1 && item["StepSize"]?.double == 1
                return Row(.verbatim(name), isSwitch ? .onOff(value >= 0.5) : .number(value, digits: value.rounded() == value ? 0 : 2, unit: ""))
            }
        }
        return [Section(title: "Readings", rows: rows("ReadonlySwitches")), Section(title: "Outputs", rows: rows("WritableSwitches"))]
    }

    /// Sensors a station does not have report `"NaN"`; their rows are left out.
    var weather: [Section] {
        var conditions = [
            Row("Temperature", number("Temperature", digits: 1, unit: "°C")),
            Row("Dew point", number("DewPoint", digits: 1, unit: "°C")),
            Row("Humidity", number("Humidity", digits: 0, unit: "%")),
            Row("Pressure", number("Pressure", digits: 0, unit: "hPa")),
            Row("Cloud cover", number("CloudCover", digits: 0, unit: "%")),
            Row("Wind speed", number("WindSpeed", digits: 1, unit: "m/s")),
            Row("Wind gusts", number("WindGust", digits: 1, unit: "m/s")),
            Row("Wind direction", number("WindDirection", digits: 0, unit: "°")),
            Row("Rain rate", number("RainRate", digits: 1, unit: "mm/h")),
        ]
        if let period = o["AveragePeriod"]?.double, period > 0 {
            conditions.append(Row("Averaging period", .number(period, digits: 1, unit: "h")))
        }
        let sky = [
            Row("Sky quality", number("SkyQuality", digits: 2, unit: "mag/arcsec²")),
            Row("Sky brightness", number("SkyBrightness", digits: 1, unit: "lx")),
            Row("Sky temperature", number("SkyTemperature", digits: 1, unit: "°C")),
            Row("Star FWHM", number("StarFWHM", digits: 2, unit: "″")),
        ]
        return [Section(title: "Conditions", rows: present(conditions)), Section(title: "Sky", rows: present(sky))]
    }

    var safetyMonitor: [Section] {
        guard let safe = o["IsSafe"]?.bool else { return [] }
        return [Section(title: "Status", rows: [Row("Conditions", .word(safe ? "Safe" : "Unsafe"), highlighted: !safe)])]
    }

    /// RMS in arcseconds when the pixel scale is known, else in guide-camera pixels.
    /// `LastGuideStep` is not shown: the plugin never clears it, so it outlives guiding.
    var guider: [Section] {
        let scale = o["PixelScale"]?.double ?? 0
        var status: [Row] = []
        if let state = o["State"]?.string, !state.isEmpty { status.append(Row("State", .guiderState(state))) }
        if scale > 0 { status.append(Row("Pixel scale", .number(scale, digits: 2, unit: "″/px"))) }
        let rms = [("RA", "RMS RA"), ("Dec", "RMS Dec"), ("Total", "RMS total"), ("PeakRA", "Peak RA"), ("PeakDec", "Peak Dec")]
            .map { key, label -> Row in
                let error = o["RMSError"]?[key]
                if scale > 0, let arcseconds = error?["Arcseconds"]?.double {
                    return Row(label, .number(arcseconds, digits: 2, unit: "″"))
                }
                return Row(label, error?["Pixel"]?.double.map { .number($0, digits: 2, unit: "px") } ?? .missing)
            }
        return [Section(title: "Status", rows: status), Section(title: "Guiding error", rows: present(rms))]
    }

    /// `Altitude` is never filled in by the plugin and not shown.
    var dome: [Section] {
        let rows = [
            Row("Shutter", word("ShutterStatus", [
                "ShutterNone": "Unknown", "ShutterOpen": "Open", "ShutterClosed": "Closed",
                "ShutterOpening": "Opening", "ShutterClosing": "Closing", "ShutterError": "Error",
            ])),
            Row("Azimuth", number("Azimuth", digits: 1, unit: "°")),
            Row("Slewing", yesNo("Slewing")),
            Row("Parked", yesNo("AtPark")),
            Row("At home", yesNo("AtHome")),
            Row("Following", yesNo("IsFollowing")),
            Row("Synchronized", yesNo("IsSynchronized")),
        ]
        return [Section(title: "Status", rows: present(rows))]
    }

    /// `DeviceId` is technical and left out.
    var driver: Section {
        Section(title: "Driver", rows: present([
            Row("Device", text("DisplayName")),
            Row("Driver", text("DriverInfo")),
            Row("Version", text("DriverVersion")),
            Row("Description", text("Description")),
        ]))
    }
}
