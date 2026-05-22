import Foundation
import CryptoKit

public enum PKCE {
    /// Generates an unreserved-character verifier per RFC 7636 §4.1.
    /// Length is between 43 and 128 characters (default 64) using [A-Z][a-z][0-9]-._~.
    public static func generateVerifier(length: Int = 64) -> String {
        precondition(length >= 43 && length <= 128, "verifier length must be 43..128")
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    /// Returns code_challenge = base64url( SHA256(verifier) ), no padding.
    public static func challenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - s.count % 4) % 4
        s += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: s) else { return nil }
        self = data
    }
}
