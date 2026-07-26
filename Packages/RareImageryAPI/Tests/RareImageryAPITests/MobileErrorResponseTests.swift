import XCTest
@testable import RareImageryAPI

final class MobileErrorResponseTests: XCTestCase {

    func testDecodesWrappedShape() throws {
        let json = #"{"error":{"code":"SLUG_TAKEN","message":"Your handle is in use."}}"#
        let envelope = try JSONDecoder().decode(MobileErrorResponse.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.code, "SLUG_TAKEN")
        XCTAssertEqual(envelope.displayMessage, "Your handle is in use.")
    }

    func testDecodesFlatShape() throws {
        // Some legacy endpoints (e.g. /api/products/from-images) return:
        //   {"error":"Unauthorized"}
        let json = #"{"error":"Unauthorized"}"#
        let envelope = try JSONDecoder().decode(MobileErrorResponse.self, from: Data(json.utf8))
        XCTAssertNil(envelope.code)
        XCTAssertEqual(envelope.displayMessage, "Unauthorized")
    }

    func testDecodesMissingErrorField() throws {
        let json = "{}"
        let envelope = try JSONDecoder().decode(MobileErrorResponse.self, from: Data(json.utf8))
        XCTAssertNil(envelope.error)
        XCTAssertEqual(envelope.displayMessage, "Something went wrong.")
    }

    func testNewCodesMapToFriendlyMessages() {
        let mobileAuth = APIError.badRequest(code: .mobileAuthFailed, message: "JWS Protected Header is invalid")
        XCTAssertEqual(mobileAuth.userFacingMessage, "Your session is invalid. Please sign in again.")

        let apple = APIError.serverError(status: 501, code: .appleAuthNotReady, message: "Apple Sign-In backend isn't deployed yet.")
        XCTAssertEqual(apple.userFacingMessage, "Apple Sign-In isn't ready yet. Use Continue with X.")

        let slug = APIError.badRequest(code: .slugTaken, message: "Slug is in use.")
        XCTAssertTrue(slug.requiresSupportContact)

        let network = APIError.network(URLError(.notConnectedToInternet))
        XCTAssertFalse(network.requiresSupportContact)

        let mint = APIError.serverError(status: 502, code: .drupalMintFailed, message: "mint-code returned 500")
        XCTAssertTrue(mint.userFacingMessage.contains("mint-code"))

        let unknownClient = APIError.badRequest(code: .unknownClient, message: "client_id is not registered with this broker.")
        XCTAssertTrue(unknownClient.userFacingMessage.contains("registered"))
    }
}
