import XCTest
@testable import RareImageryAPI

final class JWTDecoderTests: XCTestCase {

    /// Builds a fake unsigned JWT (header.payload.signature) with the given payload dictionary.
    private func makeToken(payload: [String: Any]) -> String {
        let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return "\(headerData.base64URLEncodedString()).\(payloadData.base64URLEncodedString()).fake-signature"
    }

    func testDecodesValidToken() throws {
        let exp = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let token = makeToken(payload: [
            "sub": "user-uuid",
            "storeUuid": "store-uuid",
            "slug": "test",
            "handle": "tester",
            "role": "x_creator",
            "aud": "mobile-access",
            "exp": exp,
            "iat": Int(Date().timeIntervalSince1970)
        ])
        let claims = try JWTDecoder.decode(token)
        XCTAssertEqual(claims.sub, "user-uuid")
        XCTAssertEqual(claims.storeUuid, "store-uuid")
        XCTAssertEqual(claims.handle, "tester")
        XCTAssertEqual(claims.role, "x_creator")
        XCTAssertEqual(claims.aud, "mobile-access")
        XCTAssertFalse(claims.isExpired)
    }

    func testDecodePayloadAcceptsDrupalAudience() throws {
        let exp = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let token = makeToken(payload: [
            "sub": "drupal-user-uuid",
            "aud": "11111111-2222-3333-4444-555555555555",
            "exp": exp
        ])
        let claims = try JWTDecoder.decodePayload(token)
        XCTAssertEqual(claims.sub, "drupal-user-uuid")
        XCTAssertEqual(claims.aud, "11111111-2222-3333-4444-555555555555")
        XCTAssertThrowsError(try JWTDecoder.decode(token)) { error in
            guard case JWTDecoder.Failure.wrongAudience = error else {
                return XCTFail("Expected wrongAudience, got \(error)")
            }
        }
    }

    func testRejectsWrongAudience() {
        let exp = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let token = makeToken(payload: [
            "sub": "u",
            "aud": "web-access",
            "exp": exp
        ])
        XCTAssertThrowsError(try JWTDecoder.decode(token)) { error in
            guard case JWTDecoder.Failure.wrongAudience = error else {
                return XCTFail("Expected wrongAudience, got \(error)")
            }
        }
    }

    func testRejectsExpiredToken() {
        let exp = Int(Date().addingTimeInterval(-60).timeIntervalSince1970)
        let token = makeToken(payload: [
            "sub": "u",
            "aud": "mobile-access",
            "exp": exp
        ])
        XCTAssertThrowsError(try JWTDecoder.decode(token)) { error in
            XCTAssertEqual(error as? JWTDecoder.Failure, .expired)
        }
    }

    func testRejectsMalformed() {
        XCTAssertThrowsError(try JWTDecoder.decode("not.a.jwt.with.too.many.parts")) { error in
            XCTAssertEqual(error as? JWTDecoder.Failure, .malformed)
        }
    }
}
