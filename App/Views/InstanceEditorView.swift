import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// Add or edit an instance, with a read-only connection test.
struct InstanceEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var instance: DeviceInstance
    @State private var hostInput: String
    @State private var phd2Enabled: Bool
    @State private var phd2Port: Int
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false
    @State private var validationMessage: LocalizedStringKey?
    let isNew: Bool

    init(instance: DeviceInstance, isNew: Bool) {
        _instance = State(initialValue: instance)
        _hostInput = State(initialValue: instance.host)
        _phd2Enabled = State(initialValue: instance.phd2Port != nil)
        _phd2Port = State(initialValue: instance.phd2Port ?? DeviceInstance.defaultPHD2Port)
        self.isNew = isNew
    }

    var body: some View {
        Form {
            Section {
                TextField("Name (optional)", text: $instance.name)
                TextField("Host or IP address", text: $hostInput)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Advanced API port", value: $instance.apiPort, format: .number.grouping(.never))
            } header: {
                Text("N.I.N.A. Advanced API")
            } footer: {
                Text("Default port 1888. The Advanced API plugin must be enabled in N.I.N.A.")
            }

            Section {
                Toggle("Monitor PHD2", isOn: $phd2Enabled)
                if phd2Enabled {
                    TextField("PHD2 port", value: $phd2Port, format: .number.grouping(.never))
                }
            } header: {
                Text("PHD2")
            } footer: {
                Text("Default port 4400. PHD2's server must be enabled (Tools → Enable Server).")
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(isTesting)
                if let testResult {
                    TestResultLabel(result: testResult)
                }
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button(isNew ? "Save Instance" : "Save Changes") { save() }
            } footer: {
                Text("You can save an instance that is currently offline; the app keeps retrying.")
            }
        }
        .navigationTitle(isNew ? "Add Instance" : "Edit Instance")
    }

    private func validated() -> DeviceInstance? {
        do throws(InstanceValidationError) {
            var result = instance
            result.host = try InstanceValidation.normalizedHost(hostInput)
            try InstanceValidation.validatePort(result.apiPort)
            if phd2Enabled { try InstanceValidation.validatePort(phd2Port) }
            result.phd2Port = phd2Enabled ? phd2Port : nil
            validationMessage = nil
            return result
        } catch {
            switch error {
            case .emptyHost: validationMessage = "Enter a host name or IP address."
            case .invalidHost: validationMessage = "This is not a valid host name or IP address."
            case .invalidPort: validationMessage = "Ports must be between 1 and 65535."
            }
            return nil
        }
    }

    private func test() async {
        guard let candidate = validated() else { return }
        isTesting = true
        testResult = await ConnectionTester().test(host: candidate.host, port: candidate.apiPort)
        isTesting = false
    }

    private func save() {
        guard let candidate = validated() else { return }
        if isNew, model.store.contains(host: candidate.host, port: candidate.apiPort) {
            validationMessage = "An instance with this host and port already exists."
            return
        }
        model.save(candidate)
        dismiss()
    }
}

struct TestResultLabel: View {
    let result: ConnectionTestResult

    var body: some View {
        switch result {
        case .found(let plugin, let nina):
            Label("N.I.N.A. \(nina ?? "?") with Advanced API \(plugin) found", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unsupportedPlugin(let version):
            Label("Advanced API \(version) is not supported yet (supported: 2.x)", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.orange)
        case .notNINA:
            Label("Something answered, but it is not the N.I.N.A. Advanced API", systemImage: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        case .unreachable(let message):
            Label("Not reachable: \(message)", systemImage: "wifi.exclamationmark")
                .foregroundStyle(.red)
        }
    }
}
