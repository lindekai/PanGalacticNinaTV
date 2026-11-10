import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// Overview of one N.I.N.A. instance: newest frame, camera, mount, filter and guider.
/// Values that are unknown are shown as "—"; data that is not live is labelled with its age.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    let connection: InstanceConnection
    @State private var viewerItem: ViewerItem?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 32) {
                header(now: context.date)
                if let version = connection.incompatibility {
                    Label("Advanced API \(version) is not supported yet (supported: 2.x). Monitoring stopped.",
                          systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                } else {
                    overview(now: context.date)
                }
                footer
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
            .onChange(of: context.date) { connection.refreshPhase() }
        }
        #if DEBUG
        // Simulator gate tests have no remote: `-debug.openViewer YES` opens the viewer once an image is known.
        .onChange(of: connection.latestImageIndex) { _, index in
            if let index, UserDefaults.standard.bool(forKey: "debug.openViewer"), viewerItem == nil {
                viewerItem = ViewerItem(index: index)
            }
        }
        #endif
        .fullScreenCover(item: $viewerItem) { item in
            ImageViewer(index: item.index, image: connection.latestImage, thumbnail: connection.latestThumbnail,
                        service: model.renderService)
        }
    }

    private var asOf: Date? {
        connection.phase == .live ? nil : connection.lastSuccess
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: connection.instance.displayName)
                .font(.largeTitle.bold())
            Spacer()
            ConnectionBadge(connection: connection, now: now)
        }
    }

    private func overview(now: Date) -> some View {
        let equipment = connection.equipment
        return HStack(alignment: .top, spacing: 40) {
            LatestImageCard(image: connection.latestImage, thumbnail: connection.latestThumbnail,
                            asOf: asOf, now: now) {
                if let index = connection.latestImageIndex { viewerItem = ViewerItem(index: index) }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 24) {
                CameraCard(camera: equipment?.camera, now: now)
                MountCard(mount: equipment?.mount)
                HStack(spacing: 24) {
                    EquipmentCard(title: "Filter", icon: Image(systemName: "circle.grid.cross"), device: equipment?.filterWheel?.device) {
                        if let wheel = equipment?.filterWheel, wheel.device.connected {
                            Text(verbatim: wheel.selectedFilter ?? "—").font(.title3)
                        }
                    }
                    EquipmentCard(title: "Guider", icon: Image(systemName: "target"), device: equipment?.guider?.device) {
                        if let guider = equipment?.guider, guider.device.connected {
                            Text(verbatim: guider.state ?? "—").font(.title3)
                        }
                    }
                }
            }
            .frame(width: 800)
            .opacity(asOf != nil && equipment != nil ? 0.55 : 1)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 40) {
            if connection.phase == .offline {
                Button("Retry Now", systemImage: "arrow.clockwise") { connection.retryNow() }
            }
            if model.store.instances.count > 1 {
                Button("Switch Observatory", systemImage: "rectangle.2.swap") { model.deactivate() }
            }
            NavigationLink(value: Destination.settings) {
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
            if let plugin = connection.pluginVersion {
                Text("N.I.N.A. \(connection.ninaVersion ?? "?") · Advanced API \(plugin)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ViewerItem: Identifiable {
    let index: Int
    var id: Int { index }
}

struct CameraCard: View {
    let camera: NINAEquipmentSummary.Camera?
    let now: Date

    var body: some View {
        EquipmentCard(title: "Camera", icon: Image(systemName: "camera"), device: camera?.device) {
            if let camera, camera.device.connected {
                HStack(spacing: 28) {
                    Stat("Sensor", camera.temperature.map(Self.celsius))
                    // Setpoint only while the cooler runs (#5: driver value, not the panel value).
                    Stat("Setpoint", camera.activeSetpoint.map(Self.celsius))
                    Stat("Cooler", camera.coolerOn.map { on in
                        on ? camera.coolerPower.map { "\(Int($0.rounded())) %" } ?? String(localized: "On")
                           : String(localized: "Off")
                    })
                    Stat("Gain", camera.gain.map(String.init))
                }
                exposure(camera)
            }
        }
    }

    @ViewBuilder private func exposure(_ camera: NINAEquipmentSummary.Camera) -> some View {
        if camera.isOverdue(now: now) {
            Label("Exposure overdue – camera may be stuck", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if camera.isExposing == true, let end = camera.exposureEndTime, end > now {
            Label("Exposing – \(Int(end.timeIntervalSince(now).rounded(.up))) s left", systemImage: "camera.aperture")
                .foregroundStyle(.secondary)
        } else if camera.isExposing == true {
            Label("Exposing", systemImage: "camera.aperture")
                .foregroundStyle(.secondary)
        }
    }

    static func celsius(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " °C"
    }
}

struct MountCard: View {
    let mount: NINAEquipmentSummary.Mount?

    var body: some View {
        // No SF Symbol for a telescope on a mount exists on tvOS 26; custom template vector.
        EquipmentCard(title: "Mount", icon: Image("TelescopeMount"), device: mount?.device) {
            if let mount, mount.device.connected {
                HStack(spacing: 28) {
                    Stat("RA", mount.rightAscension)
                    Stat("Dec", mount.declination)
                    Stat("Altitude", mount.altitudeDegrees.map { $0.formatted(.number.precision(.fractionLength(1))) + "°" })
                    Stat("Pier", mount.sideOfPier.map { $0 == .east ? String(localized: "East") : String(localized: "West") })
                }
                Text(verbatim: status(mount)).foregroundStyle(.secondary)
            }
        }
    }

    private func status(_ mount: NINAEquipmentSummary.Mount) -> String {
        if mount.slewing == true { return String(localized: "Slewing") }
        if mount.atPark == true { return String(localized: "Parked") }
        switch mount.trackingEnabled {
        case true: return String(localized: "Tracking")
        case false: return String(localized: "Not tracking")
        case nil: return "—"
        }
    }
}

struct ConnectionBadge: View {
    let connection: InstanceConnection
    let now: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 18, height: 18)
                Text(title).font(.headline)
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch connection.phase {
        case .live: .green
        case .stale: .yellow
        case .offline: .red
        case .connecting: .gray
        }
    }

    private var title: LocalizedStringKey {
        switch connection.phase {
        case .live: "Live"
        case .stale: "Stale"
        case .offline: "Offline"
        case .connecting: "Connecting…"
        }
    }

    private var detail: String? {
        switch connection.phase {
        case .live, .connecting:
            return nil
        case .stale:
            return connection.lastSuccess.map {
                String(localized: "Last update \($0.formatted(date: .omitted, time: .standard))")
            }
        case .offline:
            let retry = connection.nextAttempt.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) }
            // Service messages are stable English sentences used as catalog keys.
            let error = connection.lastError.map { String(localized: String.LocalizationValue($0)) } ?? ""
            return retry.map { String(localized: "Retry in \($0) s · \(error)") } ?? error
        }
    }
}

struct EquipmentCard<Content: View>: View {
    let title: LocalizedStringKey
    let icon: Image
    let device: NINAEquipmentSummary.Device?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label { Text(title) } icon: { icon.resizable().scaledToFit().frame(width: 40, height: 40) }
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if device?.connected == true {
                    // A dot instead of text keeps narrow cards readable.
                    Circle().fill(.green).frame(width: 14, height: 14)
                        .accessibilityLabel(Text(status))
                } else {
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let name = device?.name, device?.connected == true {
                Text(verbatim: name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }

    private var status: LocalizedStringKey {
        switch device?.connected {
        case true: "Connected"
        case false: "Not connected"
        case nil: "Unknown"
        }
    }
}
