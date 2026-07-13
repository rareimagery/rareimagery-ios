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
        let claims = try decodePayload(token)
        guard claims.aud == expectedAudience else {
            throw Failure.wrongAudience(found: claims.aud, expected: expectedAudience)
        }
        guard !claims.isExpired else { throw Failure.expired }
        return claims
    }

    /// Decodes JWT payload without audience enforcement — used for Drupal simple_oauth
    /// access tokens whose `aud` is the consumer UUID (not `mobile-access`).
    public static func decodePayload(_ token: String) throws -> MobileClaims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw Failure.malformed }

        guard let payloadData = Data(base64URLEncoded: String(parts[1])) else {
            throw Failure.base64Decode
        }

        // Prefer MobileClaims shape; fall back to a loose payload for Drupal JWTs.
        if let claims = try? JSONDecoder().decode(MobileClaims.self, from: payloadData) {
            return claims
        }

        struct Loose: Decodable {
            let sub: String?
            let exp: Int?
            let iat: Int?
            let aud: FlexibleAudience?
        }

        let loose: Loose
        do {
            loose = try JSONDecoder().decode(Loose.self, from: payloadData)
        } catch {
            throw Failure.jsonDecode
        }

        guard let sub = loose.sub, let exp = loose.exp else {
            throw Failure.jsonDecode
        }

        return MobileClaims(
            sub: sub,
            storeUuid: nil,
            slug: nil,
            handle: nil,
            role: nil,
            aud: loose.aud?.value ?? "drupal",
            exp: exp,
            iat: loose.iat
        )
    }
}

/// OAuth `aud` may be a string or an array of strings.
private struct FlexibleAudience: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            value = s
        } else if let arr = try? container.decode([String].self), let first = arr.first {
            value = first
        } else {
            value = "drupal"
        }
    }
}
