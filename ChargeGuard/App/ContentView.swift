import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var config: TuyaConfig
    @Published var statusMessage: String?
    @Published var isError = false
    @Published var isBusy = false

    init() {
        self.config = SettingsStore.load() ?? .empty
    }

    func save() {
        let trimmed = TuyaConfig(
            region: config.region,
            accessId: config.accessId.trimmingCharacters(in: .whitespacesAndNewlines),
            accessSecret: config.accessSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceId: config.deviceId.trimmingCharacters(in: .whitespacesAndNewlines),
            switchCode: config.switchCode.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        config = trimmed
        if SettingsStore.save(trimmed) {
            show("Saved.", error: false)
        } else {
            show("Couldn't save to Keychain.", error: true)
        }
    }

    func test(turnOn: Bool) {
        run { backend in
            try await backend.setPower(on: turnOn)
            return turnOn ? "Plug turned ON. ⚡️" : "Plug turned OFF — this is what happens at 80%. 🔋"
        }
    }

    func checkStatus() {
        run { backend in
            let on = try await backend.isOn()
            return on ? "Plug is currently ON." : "Plug is currently OFF."
        }
    }

    func detectSwitchCode() {
        run { backend in
            let codes = try await backend.detectSwitchCodes()
            if let first = codes.first {
                self.config.switchCode = first
                _ = SettingsStore.save(self.config)
                return "Found switch code(s): \(codes.joined(separator: ", ")). Using \"\(first)\"."
            }
            return "No on/off switch found on this device — double-check the Device ID."
        }
    }

    private func run(_ action: @escaping (TuyaCloudBackend) async throws -> String) {
        save()
        guard config.isComplete else {
            show("Fill in every field first.", error: true)
            return
        }
        isBusy = true
        statusMessage = nil
        let backend = TuyaCloudBackend(config: config)
        Task {
            do {
                let message = try await action(backend)
                show(message, error: false)
            } catch {
                show(error.localizedDescription, error: true)
            }
            isBusy = false
        }
    }

    private func show(_ message: String, error: Bool) {
        statusMessage = message
        isError = error
    }
}

struct ContentView: View {
    @StateObject private var vm = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Charge Guard stops your old iPhone charging past ~80% overnight by switching off the smart plug that powers the charger. Set up your Tuya credentials here, then wire the App Intent to a Battery Level automation (see the README).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Tuya Cloud project") {
                    Picker("Region", selection: $vm.config.region) {
                        ForEach(TuyaRegion.allCases) { region in
                            Text(region.label).tag(region)
                        }
                    }
                    LabeledField("Access ID", text: $vm.config.accessId)
                    SecureField("Access Secret", text: $vm.config.accessSecret)
                }

                Section("Plug") {
                    LabeledField("Device ID", text: $vm.config.deviceId)
                    HStack {
                        LabeledField("Switch code", text: $vm.config.switchCode)
                        Button("Detect") { vm.detectSwitchCode() }
                            .buttonStyle(.bordered)
                            .disabled(vm.isBusy)
                    }
                }

                Section {
                    Button {
                        vm.save()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        vm.test(turnOn: false)
                    } label: {
                        Label("Test: turn plug OFF", systemImage: "bolt.slash.fill")
                    }
                    Button {
                        vm.test(turnOn: true)
                    } label: {
                        Label("Test: turn plug ON", systemImage: "bolt.fill")
                    }
                    Button {
                        vm.checkStatus()
                    } label: {
                        Label("Check plug status", systemImage: "powerplug.fill")
                    }
                }
                .disabled(vm.isBusy)

                if let message = vm.statusMessage {
                    Section {
                        Label(message, systemImage: vm.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(vm.isError ? .red : .green)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Charge Guard")
            .overlay {
                if vm.isBusy { ProgressView().controlSize(.large) }
            }
        }
    }
}

/// A label + text field that behaves well on both iOS and macOS.
private struct LabeledField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.automatic)
            #if os(iOS)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            #endif
    }
}

#Preview {
    ContentView()
}
