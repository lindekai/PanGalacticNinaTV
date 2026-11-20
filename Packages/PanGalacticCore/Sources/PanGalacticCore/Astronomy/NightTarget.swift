import Foundation

/// What the altitude curve follows: the sequence's target container (J2000, from
/// `/sequence/state` `Target.InputCoordinates`), else the tracking mount (JNOW).
public struct NightTarget: Equatable, Sendable {
    public enum Source: Equatable, Sendable { case sequence, mount }
    public enum Epoch: Equatable, Sendable { case j2000, ofDate }

    public let name: String?
    public let coordinates: Equatorial
    public let epoch: Epoch
    public let source: Source

    public init(name: String?, coordinates: Equatorial, epoch: Epoch, source: Source) {
        self.name = name
        self.coordinates = coordinates
        self.epoch = epoch
        self.source = source
    }

    /// Coordinates for the equinox of `date`.
    public func ofDate(_ date: Date) -> Equatorial {
        epoch == .j2000 ? Sky.precessFromJ2000(coordinates, to: date) : coordinates
    }

    public static func fromSequence(state: JSONValue) -> NightTarget? {
        var running: NightTarget?
        var children = state.array ?? []
        while let node = children.first(where: { $0["Status"]?.string == "RUNNING" && $0["Items"]?.array != nil }) {
            if let target = target(of: node) { running = target }
            children = node["Items"]?.array ?? []
        }
        if let running { return running }
        return firstCreated(in: state.array ?? [])
    }

    private static func firstCreated(in nodes: [JSONValue]) -> NightTarget? {
        for node in nodes {
            if node["Status"]?.string == "CREATED", let target = target(of: node) { return target }
            if let items = node["Items"]?.array, let found = firstCreated(in: items) { return found }
        }
        return nil
    }

    private static func target(of container: JSONValue) -> NightTarget? {
        guard let input = container["Target"]?["InputCoordinates"],
              let rh = input["RAHours"]?.double, let rm = input["RAMinutes"]?.double, let rs = input["RASeconds"]?.double,
              let dd = input["DecDegrees"]?.double, let dm = input["DecMinutes"]?.double, let ds = input["DecSeconds"]?.double
        else { return nil }
        let negative = input["NegativeDec"]?.bool == true || dd < 0
        let dec = (abs(dd) + dm / 60 + ds / 3600) * (negative ? -1 : 1)
        let containerName = container["Name"]?.string.map { $0.hasSuffix("_Container") ? String($0.dropLast(10)) : $0 }
        let name = [container["Target"]?["TargetName"]?.string, containerName].compactMap { $0 }.first { !$0.isEmpty }
        return NightTarget(name: name, coordinates: Equatorial(ra: (rh + rm / 60 + rs / 3600) * 15, dec: dec),
                           epoch: .j2000, source: .sequence)
    }

    public static func fromMount(_ mount: NINAEquipmentSummary.Mount?, name: String?) -> NightTarget? {
        guard let mount, mount.activity == .tracking,
              let ra = mount.rightAscensionHours, let dec = mount.declinationDegrees else { return nil }
        return NightTarget(name: name, coordinates: Equatorial(ra: ra * 15, dec: dec), epoch: .ofDate, source: .mount)
    }

    public static func resolve(sequence: NightTarget?, mount: NINAEquipmentSummary.Mount?, imageTarget: String?) -> NightTarget? {
        sequence ?? fromMount(mount, name: imageTarget)
    }
}
