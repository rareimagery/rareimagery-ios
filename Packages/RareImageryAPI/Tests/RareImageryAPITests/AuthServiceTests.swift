import XCTest
@testable import RareImageryAPI

final class AuthServiceTests: XCTestCase {
    private func makeService(xClientID: String) -> AuthService {
        let config = APIConfiguration(
            baseURL: URL(string: "http://localhost:3000")!,
            xClientID: xClientID,
            environment: "development"
        )
        let keychain = KeychainStore(service: "com.rareimagery.studio.tests.\(UUID().uuidString)")
        let client = APIClient(configuration: config, keychain: keychain)
        let repository = AuthRepository(client: client)
        return AuthService(configuration: config, repository: repository, client: client)
    }

    func testPlaceholderClientIDRejected() async {
        let service = makeService(xClientID: "REPLACE_ME_WITH_X_CLIENT_ID")
        do {
            _ = try await service.startXAuth()
            XCTFail("Expected invalidConfiguration for placeholder client ID")
        } catch let error as APIError {
            guard case .invalidConfiguration(let message) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
            XCTAssertTrue(message.contains("Debug.local.xcconfig"))
            XCTAssertTrue(message.contains("Client ID"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStartXAuthBuildsAuthorizeURL() async throws {
        let clientID = "Wm9hUHI2UVllT3BMUi1IdjJPaEE6MTpjaQ"
        let service = makeService(xClientID: clientID)
        let request = try await service.startXAuth()

        XCTAssertEqual(request.callbackScheme, "rareimagery")
        XCTAssertEqual(request.authorizationURL.host, "x.com")
        XCTAssertTrue(request.authorizationURL.path.contains("oauth2/authorize"))

        let items = URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let byName = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(byName["response_type"], "code")
        XCTAssertEqual(byName["client_id"], clientID)
        XCTAssertEqual(byName["redirect_uri"], "rareimagery://auth/callback")
        XCTAssertEqual(byName["code_challenge_method"], "S256")
        XCTAssertNotNil(byName["code_challenge"])
        XCTAssertNotNil(byName["state"])
        XCTAssertTrue(byName["scope"]?.contains("tweet.read") == true)
    }

    func testCompleteXAuthRejectsStateMismatch() async throws {
        let service = makeService(xClientID: "Wm9hUHI2UVllT3BMUi1IdjJPaEE6MTpjaQ")
        _ = try await service.startXAuth()

        var components = URLComponents()
        components.scheme = "rareimagery"
        components.host = "auth"
        components.path = "/callback"
        components.queryItems = [
            URLQueryItem(name: "code", value: "test-code"),
            URLQueryItem(name: "state", value: "wrong-state")
        ]
        let callbackURL = try XCTUnwrap(components.url)

        do {
            _ = try await service.completeXAuth(callbackURL: callbackURL)
            XCTFail("Expected state mismatch")
        } catch let error as APIError {
            guard case .authFailed(let message) = error else {
                return XCTFail("Expected authFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("State mismatch"))
        }
    }
}