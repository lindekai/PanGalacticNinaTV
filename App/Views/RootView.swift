import PanGalacticCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let connection = model.connection {
                    DashboardView(connection: connection)
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
}
