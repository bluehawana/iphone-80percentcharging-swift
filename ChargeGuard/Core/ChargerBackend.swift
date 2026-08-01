import Foundation

/// Abstraction over "the thing that switches the charger's power".
///
/// Today the only implementation is `TuyaCloudBackend` (WiFi Tuya / Deltaco Smart Home).
/// Later we can add an `MqttBackend` (zigbee2mqtt) or `LocalTuyaBackend` (LAN) without
/// touching the UI or the App Intents — they only ever talk to this protocol.
protocol ChargerBackend: Sendable {
    /// Turn the plug on (charging allowed) or off (charging stopped).
    func setPower(on: Bool) async throws

    /// Current plug state: `true` == powered on.
    func isOn() async throws -> Bool
}

enum ChargeGuardError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Charge Guard isn't set up yet. Open the app and enter your Tuya credentials and plug device ID."
        }
    }
}
