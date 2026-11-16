import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// Every device N.I.N.A. reports, connected or not, from the same `/equipment/info`
/// poll as the overview. The endpoint cannot tell "no device chosen" from
/// "disconnected", so both read "Not connected".
struct DevicesView: View {
    let connection: InstanceConnection

    private let columns = [GridItem(.flexible(), spacing: Theme.moduleGap), GridItem(.flexible(), spacing: Theme.moduleGap)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Devices").font(.pgDisplay).foregroundStyle(Theme.text)
                    Text(verbatim: connection.instance.displayName).font(.pgLabel).foregroundStyle(Theme.text2)
                }
                LazyVGrid(columns: columns, spacing: Theme.moduleGap) {
                    ForEach(devices, id: \.kind) { device in
                        DeviceRow(device: device, state: DeviceConnectionState.of(device, phase: connection.phase))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, Theme.marginVertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
            .ignoresSafeArea()
            .onChange(of: context.date) { connection.refreshPhase() }
        }
    }

    /// Before the first poll every type is listed as unknown, so the page never looks empty.
    private var devices: [NINAEquipmentSummary.DeviceStatus] {
        connection.equipment?.devices
            ?? NINAEquipmentSummary.DeviceKind.allCases.map { .init(kind: $0, connected: nil, name: nil) }
    }
}

private struct DeviceRow: View {
    let device: NINAEquipmentSummary.DeviceStatus
    let state: DeviceConnectionState

    var body: some View {
        HStack(spacing: 20) {
            icon.resizable().scaledToFit().frame(width: 34, height: 34).foregroundStyle(Theme.text2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.pgValue).foregroundStyle(Theme.text).lineLimit(1)
                Text(verbatim: device.name ?? "—").font(.pgLabel)
                    .foregroundStyle(device.name == nil ? Theme.text3 : Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 16)
            HStack(spacing: 12) {
                Text(word).font(.pgLabel).foregroundStyle(wordColor)
                StatusLED(light)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 96)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
    }

    private var light: StatusLight {
        if case .connected(let light) = state { light } else { .unknown }
    }

    private var word: LocalizedStringKey {
        switch state {
        case .connected: "Connected"
        case .notConnected: "Not connected"
        case .unknown: "Unknown"
        }
    }

    private var wordColor: Color {
        if case .connected = state { Theme.text2 } else { Theme.text3 }
    }

    private var title: LocalizedStringKey {
        switch device.kind {
        case .camera: "Camera"
        case .filterWheel: "Filter Wheel"
        case .focuser: "Focuser"
        case .rotator: "Rotator"
        case .mount: "Mount"
        case .guider: "Guider"
        case .switchHub: "Switch"
        case .flatDevice: "Flat Panel"
        case .weather: "Weather"
        case .dome: "Dome"
        case .safetyMonitor: "Safety Monitor"
        }
    }

    private var icon: Image {
        switch device.kind {
        case .camera: Image(systemName: "camera")
        case .filterWheel: Image(systemName: "circle.grid.cross")
        case .focuser: Image(systemName: "scope")
        case .rotator: Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
        case .mount: Image("TelescopeMount")
        case .guider: Image(systemName: "target")
        case .switchHub: Image(systemName: "switch.2")
        case .flatDevice: Image(systemName: "light.panel")
        case .weather: Image(systemName: "cloud.sun")
        case .dome: Image(systemName: "building.columns")
        case .safetyMonitor: Image(systemName: "checkmark.shield")
        }
    }
}
