import Foundation

/// Tuya data-center region. Pick the one matching the country you registered the
/// Deltaco / Smart Life app account in. Nordic/EU users almost always want `.eu`.
enum TuyaRegion: String, CaseIterable, Codable, Identifiable {
    case eu
    case us
    case cn
    case india

    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .eu:    return "https://openapi.tuyaeu.com"
        case .us:    return "https://openapi.tuyaus.com"
        case .cn:    return "https://openapi.tuyacn.com"
        case .india: return "https://openapi.tuyain.com"
        }
    }

    var label: String {
        switch self {
        case .eu:    return "Central Europe (EU)"
        case .us:    return "Western America (US)"
        case .cn:    return "China"
        case .india: return "India"
        }
    }
}

/// Everything needed to talk to one Tuya smart plug.
/// Persisted in the Keychain (see `SettingsStore`) — the access secret is sensitive.
struct TuyaConfig: Codable, Equatable {
    var region: TuyaRegion
    var accessId: String        // Tuya IoT project "Access ID / Client ID"
    var accessSecret: String    // Tuya IoT project "Access Secret / Client Secret"
    var deviceId: String        // The plug's device ID
    var switchCode: String      // DP code for the switch, usually "switch_1" or "switch"

    static let empty = TuyaConfig(
        region: .eu,
        accessId: "",
        accessSecret: "",
        deviceId: "",
        switchCode: "switch_1"
    )

    var isComplete: Bool {
        !accessId.isEmpty && !accessSecret.isEmpty && !deviceId.isEmpty && !switchCode.isEmpty
    }
}
