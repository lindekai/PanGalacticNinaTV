import SwiftUI

/// Shown when no instance is configured.
struct SetupView: View {
    var body: some View {
        VStack(spacing: 48) {
            VStack(spacing: 16) {
                Text("Pan Galactic N.I.N.A. TV")
                    .font(.largeTitle.bold())
                Text("Don't Panic. Your Telescope Is Probably Fine.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text("Connect to a N.I.N.A. computer with the Advanced API plugin enabled. This app only reads data – it never controls your equipment.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1100)
                .foregroundStyle(.secondary)

            HStack(spacing: 40) {
                NavigationLink(value: Destination.scan) {
                    Label("Search Local Network", systemImage: "antenna.radiowaves.left.and.right")
                }
                NavigationLink(value: Destination.addInstance(host: nil)) {
                    Label("Add Manually", systemImage: "plus")
                }
            }
        }
        .padding(80)
    }
}
