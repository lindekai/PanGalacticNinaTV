import PanGalacticCore
import SwiftUI

/// Shown when more than one instance is configured (or after leaving a dashboard).
struct InstancePickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(model.store.instances) { instance in
                    Button {
                        model.activate(instance.id)
                    } label: {
                        InstanceRow(instance: instance)
                    }
                }
            }
            Section {
                NavigationLink(value: Destination.addInstance(host: nil)) {
                    Label("Add Instance", systemImage: "plus")
                }
                NavigationLink(value: Destination.scan) {
                    Label("Search Local Network", systemImage: "antenna.radiowaves.left.and.right")
                }
                NavigationLink(value: Destination.settings) {
                    Label("Manage Instances", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Choose an Observatory")
    }
}

struct InstanceRow: View {
    let instance: DeviceInstance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: instance.displayName).font(.headline)
            Text(verbatim: "\(instance.host):\(instance.apiPort)")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let lastSeen = instance.lastSeen {
                Text("Last seen \(lastSeen, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Never connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
