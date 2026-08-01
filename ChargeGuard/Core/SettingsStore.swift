import Foundation

/// Single source of truth for the saved Tuya configuration.
/// The whole config lives in the Keychain because it contains the access secret.
enum SettingsStore {
    private static let keychainKey = "com.bluehawana.chargeguard.tuyaConfig"

    static func load() -> TuyaConfig? {
        guard let data = Keychain.read(keychainKey) else { return nil }
        return try? JSONDecoder().decode(TuyaConfig.self, from: data)
    }

    @discardableResult
    static func save(_ config: TuyaConfig) -> Bool {
        guard let data = try? JSONEncoder().encode(config) else { return false }
        return Keychain.save(keychainKey, data)
    }

    static func clear() {
        Keychain.delete(keychainKey)
    }
}

/// Convenience used by both the App Intents and the UI test buttons.
enum ChargerController {
    static func makeBackend() throws -> TuyaCloudBackend {
        guard let config = SettingsStore.load(), config.isComplete else {
            throw ChargeGuardError.notConfigured
        }
        return TuyaCloudBackend(config: config)
    }

    static func setCharger(on: Bool) async throws {
        try await makeBackend().setPower(on: on)
    }

    static func isOn() async throws -> Bool {
        try await makeBackend().isOn()
    }
}
