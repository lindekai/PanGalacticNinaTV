import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// Opt-in, bounded search for Advanced API servers on the local /24 network.
struct NetworkScanView: View {
    @Environment(AppModel.self) private var model
    @State private var hosts: [String] = []
    @State private var checked = 0
    @State private var results: [DiscoveredInstance] = []
    @State private var scanTask: Task<Void, Never>?
    @State private var finished = false

    private var isScanning: Bool { scanTask != nil }

    var body: some View {
        List {
            Section {
                Text("The app checks port 1888 on every address of your local network (at most 254 addresses) and then asks each open port for its Advanced API version. Nothing else is sent.")
                    .foregroundStyle(.secondary)
                if isScanning {
                    Button("Stop Search", role: .cancel) { stop() }
                    ProgressView(value: Double(checked), total: Double(max(hosts.count, 1))) {
                        Text("Checked \(checked) of \(hosts.count) addresses")
                    }
                } else {
                    Button(finished ? "Search Again" : "Start Search") { start() }
                }
            }

            if finished && results.isEmpty {
                Section {
                    Label("No Advanced API found. Check that N.I.N.A. is running, the plugin is enabled and the Windows firewall allows port 1888 – or add the computer manually.",
                          systemImage: "magnifyingglass")
                }
            }

            if !results.isEmpty {
                Section("Found") {
                    ForEach(results, id: \.host) { item in
                        if item.result.isUsable {
                            NavigationLink(value: Destination.addInstance(host: item.host)) {
                                row(item)
                            }
                        } else {
                            row(item)
                        }
                    }
                }
            }
        }
        .navigationTitle("Search Local Network")
        .onDisappear { stop() }
    }

    private func row(_ item: DiscoveredInstance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: item.host).font(.headline)
            TestResultLabel(result: item.result).font(.callout)
            if model.store.contains(host: item.host, port: item.port) {
                Text("Already added").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func start() {
        stop()
        hosts = NetworkScanner.defaultHosts()
        checked = 0
        results = []
        finished = false
        let hosts = hosts
        scanTask = Task {
            await NetworkScanner().scan(hosts: hosts, progress: { count in
                await MainActor.run { checked = count }
            }, found: { item in
                await MainActor.run { results.append(item) }
            })
            await MainActor.run {
                finished = true
                scanTask = nil
            }
        }
    }

    private func stop() {
        scanTask?.cancel()
        scanTask = nil
    }
}
