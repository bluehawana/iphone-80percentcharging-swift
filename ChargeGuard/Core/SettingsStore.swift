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

    /// Retries transient failures (plug briefly off WiFi, network blip) a few times,
    /// because the battery automation only fires once per 79→80% crossing — a single
    /// failed request would otherwise let the phone charge to 100%.
    /// Total wait stays well inside the background budget iOS gives an App Intent.
    static func setCharger(on: Bool) async throws {
        let backend = try makeBackend()
        let delays: [UInt64] = [3, 7]
        for delay in delays {
            do {
                try await backend.setPower(on: on)
                return
            } catch let error as TuyaError where error.isTransient {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            } catch let error as URLError where error.code != .cancelled {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
        try await backend.setPower(on: on)
    }

    static func isOn() async throws -> Bool {
        try await makeBackend().isOn()
    }
}
