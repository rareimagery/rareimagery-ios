import XCTest
@testable import RareImageryAPI

final class PKCETests: XCTestCase {
    func testVerifierLengthRange() {
        let v = PKCE.generateVerifier()
        XCTAssertGreaterThanOrEqual(v.count, 43)
        XCTAssertLessThanOrEqual(v.count, 128)
    }

    func testVerifierUsesUnreservedCharactersOnly() {
        let allowed: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let v = PKCE.generateVerifier(length: 96)
        for ch in v { XCTAssertTrue(allowed.contains(ch), "disallowed char: \(ch)") }
    }

    func testChallengeIsBase64URLOfSHA256() {
        // Test vector from RFC 7636 §4.2
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertEqual(PKCE.challenge(for: verifier), expectedChallenge)
    }

    func testBase64URLRoundTrip() {
        let original = Data([0xFA, 0x12, 0x00, 0xCC, 0xFF])
        let encoded = original.base64URLEncodedString()
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        let decoded = Data(base64URLEncoded: encoded)
        XCTAssertEqual(decoded, original)
    }
}
