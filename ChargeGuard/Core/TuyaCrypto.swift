import Foundation
import CryptoKit

/// Tuya Cloud request signing primitives.
///
/// Tuya's OpenAPI uses an HMAC-SHA256 signature over a canonical request string.
/// See: https://developer.tuya.com/en/docs/iot/new-singnature
enum TuyaCrypto {
    /// Lowercase hex SHA-256 of the request body (Tuya "Content-SHA256").
    static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Uppercase hex HMAC-SHA256 — Tuya expects the `sign` header uppercased.
    static func hmacSHA256Hex(secret: String, message: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return mac.map { String(format: "%02X", $0) }.joined()
    }
}
