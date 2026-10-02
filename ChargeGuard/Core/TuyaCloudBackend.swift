import Foundation

enum TuyaError: LocalizedError {
    case http(status: Int)
    case api(message: String, code: Int)
    case badResponse
    case switchCodeNotFound(String)

    var errorDescription: String? {
        switch self {
        case .http(let status):
            return "Network error from Tuya (HTTP \(status))."
        case .api(let message, let code):
            if let hint = Self.hint(forCode: code) {
                return "Tuya API error \(code): \(message)\n\(hint)"
            }
            return "Tuya API error \(code): \(message)"
        case .badResponse:
            return "Unexpected response from Tuya."
        case .switchCodeNotFound(let code):
            return "The plug didn't report a switch named \"\(code)\". Tap \"Detect switch code\" to find the right one."
        }
    }

    /// True when retrying shortly afterwards has a real chance of succeeding
    /// (plug briefly dropped off WiFi, transient network/server hiccup).
    var isTransient: Bool {
        switch self {
        case .http(let status): return status >= 500 || status == 429
        case .api(_, let code): return code == 2001
        default: return false
        }
    }

    /// Plain-language fix for the Tuya error codes people actually hit.
    static func hint(forCode code: Int) -> String? {
        switch code {
        case 1004:
            return "Signature rejected: wrong Access Secret or wrong Region (data center)."
        case 1010, 1011:
            return "Access token invalid/expired: re-check Access ID, Access Secret and Region."
        case 1106:
            return "Permission denied: the plug isn't linked to your Tuya cloud project. If you removed and re-added it in the Smart Life/Deltaco app (e.g. after moving), re-link the app account under Devices and check the Device ID."
        case 2001:
            return "The plug is OFFLINE in Tuya's cloud: it isn't connected to WiFi/internet. Re-pair it with your new WiFi (2.4 GHz) and check it works in the Smart Life/Deltaco app."
        case 28841002:
            return "Your Tuya IoT Core trial/subscription has expired. Renew it at iot.tuya.com → Cloud → Cloud Services → IoT Core (free extension)."
        default:
            return nil
        }
    }
}

/// Talks to the Tuya Cloud OpenAPI to switch a WiFi plug (Deltaco Smart Home / Smart Life).
///
/// An `actor` so the cached token is accessed safely; each App Intent invocation makes a
/// fresh instance, so the token is fetched once per invocation (one extra lightweight request).
actor TuyaCloudBackend: ChargerBackend {
    private let config: TuyaConfig
    private let session: URLSession

    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast

    init(config: TuyaConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - ChargerBackend

    func setPower(on: Bool) async throws {
        let path = "/v1.0/devices/\(config.deviceId)/commands"
        let payload: [String: Any] = ["commands": [["code": config.switchCode, "value": on]]]
        let body = try Self.jsonString(payload)
        let response = try await request(method: "POST", path: path, body: body, authenticated: true)
        try Self.assertSuccess(response)
    }

    func isOn() async throws -> Bool {
        let path = "/v1.0/devices/\(config.deviceId)/status"
        let response = try await request(method: "GET", path: path, body: "", authenticated: true)
        try Self.assertSuccess(response)
        guard let result = response["result"] as? [[String: Any]] else { throw TuyaError.badResponse }
        for dp in result where (dp["code"] as? String) == config.switchCode {
            return (dp["value"] as? Bool) ?? false
        }
        throw TuyaError.switchCodeNotFound(config.switchCode)
    }

    // MARK: - Discovery helpers (used by the setup UI)

    /// Walks the full chain — credentials/region, device link, online state, switch code —
    /// and reports the first broken link, so "it stopped working" can be pinned down.
    func diagnose() async throws -> String {
        var lines: [String] = []

        _ = try await token()
        lines.append("✅ Credentials & region (\(config.region.label)) accepted.")

        let info = try await request(
            method: "GET",
            path: "/v1.0/devices/\(config.deviceId)",
            body: "",
            authenticated: true
        )
        try Self.assertSuccess(info)
        guard let device = info["result"] as? [String: Any] else { throw TuyaError.badResponse }
        let name = (device["name"] as? String) ?? config.deviceId
        lines.append("✅ Plug \"\(name)\" is linked to your cloud project.")

        guard (device["online"] as? Bool) == true else {
            lines.append("❌ Plug is OFFLINE — Tuya can't reach it, so it can't be switched off at 80%. Re-pair it with your current WiFi (2.4 GHz) in the Smart Life/Deltaco app and make sure it has a strong signal where the charger is.")
            return lines.joined(separator: "\n")
        }
        lines.append("✅ Plug is online.")

        let codes = try await detectSwitchCodes()
        if codes.contains(config.switchCode) {
            lines.append("✅ Switch code \"\(config.switchCode)\" found. Cloud side is healthy — if it still doesn't stop at 80%, check the Shortcuts battery automation.")
        } else {
            lines.append("❌ Switch code \"\(config.switchCode)\" not found (device reports: \(codes.joined(separator: ", "))). Tap Detect.")
        }
        return lines.joined(separator: "\n")
    }

    /// Returns the boolean DP codes the device exposes, so the user can pick the right one
    /// if it isn't the default "switch_1" (some plugs use "switch").
    func detectSwitchCodes() async throws -> [String] {
        let path = "/v1.0/devices/\(config.deviceId)/status"
        let response = try await request(method: "GET", path: path, body: "", authenticated: true)
        try Self.assertSuccess(response)
        guard let result = response["result"] as? [[String: Any]] else { throw TuyaError.badResponse }
        return result.compactMap { dp -> String? in
            guard let code = dp["code"] as? String, dp["value"] is Bool else { return nil }
            return code
        }
    }

    // MARK: - Signing & transport

    private func token() async throws -> String {
        if let cachedToken, Date() < tokenExpiry.addingTimeInterval(-60) {
            return cachedToken
        }
        let response = try await request(
            method: "GET",
            path: "/v1.0/token?grant_type=1",
            body: "",
            authenticated: false
        )
        try Self.assertSuccess(response)
        guard
            let result = response["result"] as? [String: Any],
            let access = result["access_token"] as? String,
            let expire = result["expire_time"] as? Int
        else { throw TuyaError.badResponse }

        cachedToken = access
        tokenExpiry = Date().addingTimeInterval(TimeInterval(expire))
        return access
    }

    private func request(
        method: String,
        path: String,
        body: String,
        authenticated: Bool
    ) async throws -> [String: Any] {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let accessToken = authenticated ? try await token() : ""

        // Canonical string to sign: METHOD \n SHA256(body) \n <signed headers> \n path
        let contentHash = TuyaCrypto.sha256Hex(body)
        let stringToSign = "\(method)\n\(contentHash)\n\n\(path)"
        let signSource = config.accessId + accessToken + timestamp + stringToSign
        let sign = TuyaCrypto.hmacSHA256Hex(secret: config.accessSecret, message: signSource)

        guard let url = URL(string: config.region.baseURL + path) else { throw TuyaError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(config.accessId, forHTTPHeaderField: "client_id")
        req.setValue(sign, forHTTPHeaderField: "sign")
        req.setValue(timestamp, forHTTPHeaderField: "t")
        req.setValue("HMAC-SHA256", forHTTPHeaderField: "sign_method")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated { req.setValue(accessToken, forHTTPHeaderField: "access_token") }
        if method != "GET", !body.isEmpty { req.httpBody = Data(body.utf8) }

        let (data, urlResponse) = try await session.data(for: req)
        if let http = urlResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TuyaError.http(status: http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TuyaError.badResponse
        }
        return json
    }

    private static func assertSuccess(_ response: [String: Any]) throws {
        if (response["success"] as? Bool) == true { return }
        let message = (response["msg"] as? String) ?? "unknown error"
        let code = (response["code"] as? Int) ?? -1
        throw TuyaError.api(message: message, code: code)
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else { throw TuyaError.badResponse }
        return string
    }
}
