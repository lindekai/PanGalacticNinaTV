import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// M1 placeholder dashboard: connection health and an equipment overview.
/// The full Overview layout follows in M2.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    let connection: InstanceConnection

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 40) {
                header(now: context.date)
                if let version = connection.incompatibility {
                    Label("Advanced API \(version) is not supported yet (supported: 2.x). Monitoring stopped.",
                          systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.orange)
                } else {
                    equipmentGrid(now: context.date)
                }
                Spacer()
                footer
            }
            .padding(60)
            .onChange(of: context.date) { connection.refreshPhase() }
        }
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: connection.instance.displayName)
                .font(.largeTitle.bold())
            Spacer()
            ConnectionBadge(connection: connection, now: now)
        }
    }

    private func equipmentGrid(now: Date) -> some View {
        let equipment = connection.equipment
        let dimmed = connection.phase != .live
        return Grid(horizontalSpacing: 40, verticalSpacing: 40) {
            GridRow {
                EquipmentCard(title: "Camera", systemImage: "camera", device: equipment?.camera?.device) {
                    if let camera = equipment?.camera, camera.device.connected {
                        ValueRow("Sensor", camera.temperature.map { $0.formatted(.number.precision(.fractionLength(1))) + " °C" })
                        ValueRow("Cooler", camera.coolerOn.map { $0 ? String(localized: "On") : String(localized: "Off") })
                        ValueRow("Exposing", camera.isExposing.map { $0 ? String(localized: "Yes") : String(localized: "No") })
                        if camera.isOverdue(now: now) {
                            Label("Exposure overdue – camera may be stuck", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                EquipmentCard(title: "Mount", systemImage: "scope", device: equipment?.mount?.device) {
                    if let mount = equipment?.mount, mount.device.connected {
                        ValueRow("Tracking", mount.trackingEnabled.map { $0 ? String(localized: "On") : String(localized: "Off") })
                        ValueRow("Parked", mount.atPark.map { $0 ? String(localized: "Yes") : String(localized: "No") })
                        ValueRow("Slewing", mount.slewing.map { $0 ? String(localized: "Yes") : String(localized: "No") })
                    }
                }
            }
            GridRow {
                EquipmentCard(title: "Filter Wheel", systemImage: "circle.grid.cross", device: equipment?.filterWheel?.device) {
                    if let wheel = equipment?.filterWheel, wheel.device.connected {
                        ValueRow("Filter", wheel.selectedFilter)
                    }
                }
                EquipmentCard(title: "Guider", systemImage: "target", device: equipment?.guider?.device) {
                    if let guider = equipment?.guider, guider.device.connected {
                        ValueRow("State", guider.state)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(dimmed && equipment != nil ? 0.55 : 1)
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
    let systemImage: String
    let device: NINAEquipmentSummary.Device?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(title, systemImage: systemImage).font(.title3.bold())
                Spacer()
                Text(status).font(.callout).foregroundStyle(device?.connected == true ? .green : .secondary)
            }
            if let name = device?.name, device?.connected == true {
                Text(verbatim: name).font(.callout).foregroundStyle(.secondary)
            }
            content
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    private var status: LocalizedStringKey {
        switch device?.connected {
        case true: "Connected"
        case false: "Not connected"
        case nil: "Unknown"
        }
    }
}

/// A labelled value; `nil` is shown as an explicit dash, never as zero.
struct ValueRow: View {
    let label: LocalizedStringKey
    let value: String?

    init(_ label: LocalizedStringKey, _ value: String?) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value ?? "—")
        }
        .font(.body)
    }
}
