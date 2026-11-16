import PanGalacticCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDeletion: DeviceInstance?
    @AppStorage(AmbientController.enabledKey) private var ambientEnabled = true
    @AppStorage(AmbientController.delayKey) private var ambientDelay = AmbientPolicy.defaultDelayMinutes

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
            Section {
                Toggle("Ambient Mode", isOn: $ambientEnabled)
                if ambientEnabled {
                    Picker("Start After", selection: $ambientDelay) {
                        ForEach(AmbientPolicy.delayChoices, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                }
            } header: {
                Text("Ambient Mode")
            } footer: {
                Text("Without remote input, the newest frame fills the screen with a slim status strip. Any button returns to the overview; an alarm returns at once. While it is on, the screensaver does not start on the overview.")
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
