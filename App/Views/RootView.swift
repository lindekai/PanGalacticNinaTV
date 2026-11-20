import PanGalacticCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let connection = model.connection {
                    #if DEBUG
                    // Simulator gate tests have no remote: `-debug.screen devices` opens the device page.
                    if UserDefaults.standard.string(forKey: "debug.screen") == "devices" {
                        DevicesView(connection: connection)
                    } else if let kind = UserDefaults.standard.string(forKey: "debug.screen")
                        .flatMap(NINAEquipmentSummary.DeviceKind.init(rawValue:)) {
                        // `-debug.screen Camera` (any `/equipment/info` key) opens that device's details.
                        DeviceDetailView(connection: connection, kind: kind)
                    } else {
                        DashboardView(connection: connection)
                    }
                    #else
                    DashboardView(connection: connection)
                    #endif
                } else if model.store.instances.isEmpty {
                    SetupView()
                } else {
                    InstancePickerView()
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .addInstance(let host):
                    InstanceEditorView(instance: DeviceInstance(name: "", host: host ?? ""), isNew: true)
                case .editInstance(let instance):
                    InstanceEditorView(instance: instance, isNew: false)
                case .scan:
                    NetworkScanView()
                case .settings:
                    SettingsView()
                case .devices:
                    if let connection = model.connection { DevicesView(connection: connection) }
                case .device(let kind):
                    if let connection = model.connection { DeviceDetailView(connection: connection, kind: kind) }
                case .sequence:
                    if let connection = model.connection { SequenceView(connection: connection) }
                case .night:
                    if let connection = model.connection, let night = model.night {
                        NightView(model: night, connection: connection)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let error = model.store.persistenceError {
                Label("Could not save settings: \(error)", systemImage: "exclamationmark.triangle.fill")
                    .padding()
                    .background(.red.opacity(0.8), in: .rect(cornerRadius: 12))
                    .padding()
            }
        }
    }
}

enum Destination: Hashable {
    case addInstance(host: String?)
    case editInstance(DeviceInstance)
    case scan
    case settings
    case devices
    case sequence
    case night
    case device(NINAEquipmentSummary.DeviceKind)
}
