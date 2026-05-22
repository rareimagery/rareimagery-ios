import Foundation

public enum JWTDecoder {
    public enum Failure: Error, Equatable {
        case malformed
        case base64Decode
        case jsonDecode
        case wrongAudience(found: String, expected: String)
        case expired
    }

    /// Decodes the payload segment of a JWT without verifying its signature.
    /// Verifies `aud` matches the expected audience and that `exp` is in the future.
    public static func decode(_ token: String, expectedAudience: String = MobileClaims.expectedAudience) throws -> MobileClaims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw Failure.malformed }

        guard let payloadData = Data(base64URLEncoded: String(parts[1])) else {
            throw Failure.base64Decode
        }

        let decoder = JSONDecoder()
        let claims: MobileClaims
        do {
            claims = try decoder.decode(MobileClaims.self, from: payloadData)
        } catch {
            throw Failure.jsonDecode
        }

        guard claims.aud == expectedAudience else {
            throw Failure.wrongAudience(found: claims.aud, expected: expectedAudience)
        }

        guard !claims.isExpired else { throw Failure.expired }

        return claims
    }
}
