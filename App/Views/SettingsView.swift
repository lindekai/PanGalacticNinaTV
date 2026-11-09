import PanGalacticCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDeletion: DeviceInstance?

    var body: some View {
        List {
            Section("Instances") {
                ForEach(model.store.instances) { instance in
                    HStack {
                        NavigationLink(value: Destination.editInstance(instance)) {
                            InstanceRow(instance: instance)
                        }
                        Button(role: .destructive) {
                            pendingDeletion = instance
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                NavigationLink(value: Destination.addInstance(host: nil)) {
                    Label("Add Instance", systemImage: "plus")
                }
            }
            Section("About") {
                Text("Pan Galactic N.I.N.A. TV is an independent, unofficial companion app. It only reads data from N.I.N.A. and PHD2 and never controls equipment.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Remove \(pendingDeletion?.displayName ?? "")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let pendingDeletion { model.delete(pendingDeletion.id) }
                pendingDeletion = nil
            }
        }
    }
}
