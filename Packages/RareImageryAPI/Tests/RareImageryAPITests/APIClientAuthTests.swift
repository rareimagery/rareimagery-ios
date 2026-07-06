import XCTest
@testable import RareImageryAPI

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test helpers

private enum AuthTestFixtures {
    static func makeToken(payload: [String: Any]) -> String {
        let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return "\(headerData.base64URLEncodedString()).\(payloadData.base64URLEncodedString()).fake-signature"
    }

    static func accessToken(expiringIn seconds: TimeInterval) -> String {
        let exp = Int(Date().addingTimeInterval(seconds).timeIntervalSince1970)
        return makeToken(payload: [
            "sub": "user-uuid",
            "store_uuid": "store-uuid",
            "slug": "tester",
            "handle": "tester",
            "role": "CREATOR",
            "aud": "mobile-access",
            "exp": exp
        ])
    }

    static func refreshResponse(accessToken: String, refreshToken: String = "new-refresh") -> Data {
        let body: [String: Any] = [
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "expires_in": 604800,
            "token_type": "Bearer"
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func mockURLSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static let configuration = APIConfiguration(
        baseURL: URL(string: "https://test.rareimagery.net")!,
        xClientID: "test-client"
    )
}

// MARK: - Tests

final class APIClientAuthTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testProactiveRefreshBeforeAuthenticatedRequest() async throws {
        let keychain = KeychainStore(service: "com.rareimagery.tests.proactive")
        try await keychain.clearAll()
        try await keychain.set("old-refresh", for: .refreshToken)
        let nearExpiryToken = AuthTestFixtures.accessToken(expiringIn: 30)
        try await keychain.set(nearExpiryToken, for: .accessToken)

        let refreshedToken = AuthTestFixtures.accessToken(expiringIn: 3600)
        var refreshCallCount = 0

        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/mobile/auth/refresh" {
                refreshCallCount += 1
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, AuthTestFixtures.refreshResponse(accessToken: refreshedToken))
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let client = APIClient(
            configuration: AuthTestFixtures.configuration,
            keychain: keychain,
            urlSession: AuthTestFixtures.mockURLSession()
        )

        struct Empty: Decodable {}
        let endpoint = APIEndpoint(
            path: "/api/test",
            method: .get,
            requiresAuth: true
        )
        _ = try await client.send(endpoint, as: Empty.self)

        XCTAssertEqual(refreshCallCount, 1)
        let storedAccess = try await keychain.get(.accessToken)
        XCTAssertEqual(storedAccess, refreshedToken)
    }

    func test401AfterFailedRefreshInvalidatesSession() async throws {
        let keychain = KeychainStore(service: "com.rareimagery.tests.invalidate")
        try await keychain.clearAll()
        try await keychain.set("stale-refresh", for: .refreshToken)
        let validToken = AuthTestFixtures.accessToken(expiringIn: 3600)
        try await keychain.set(validToken, for: .accessToken)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = Data("{\"error\":{\"code\":\"TOKEN_EXPIRED\",\"message\":\"Expired\"}}".utf8)
            return (response, body)
        }

        let client = APIClient(
            configuration: AuthTestFixtures.configuration,
            keychain: keychain,
            urlSession: AuthTestFixtures.mockURLSession()
        )

        let invalidated = LockedBool()
        await client.setAuthEventHandlers(AuthEventHandlers(
            onSessionInvalidated: {
                invalidated.set(true)
            }
        ))

        struct Empty: Decodable {}
        let endpoint = APIEndpoint(
            path: "/api/test",
            method: .get,
            requiresAuth: true
        )

        do {
            _ = try await client.send(endpoint, as: Empty.self)
            XCTFail("Expected unauthorized")
        } catch APIError.unauthorized {
            // expected
        }

        let wasInvalidated = invalidated.value
        XCTAssertTrue(wasInvalidated)
    }

    func testRefreshSuccessInvokesOnTokensRefreshed() async throws {
        let keychain = KeychainStore(service: "com.rareimagery.tests.refreshed")
        try await keychain.clearAll()
        try await keychain.set("old-refresh", for: .refreshToken)

        let refreshedToken = AuthTestFixtures.accessToken(expiringIn: 3600)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/mobile/auth/refresh")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, AuthTestFixtures.refreshResponse(accessToken: refreshedToken))
        }

        let client = APIClient(
            configuration: AuthTestFixtures.configuration,
            keychain: keychain,
            urlSession: AuthTestFixtures.mockURLSession()
        )

        let received = LockedString()
        await client.setAuthEventHandlers(AuthEventHandlers(
            onTokensRefreshed: { tokens in
                received.set(tokens.accessToken)
            }
        ))

        _ = try await client.refreshTokens()

        XCTAssertEqual(received.value, refreshedToken)
    }
}

// MARK: - Thread-safe test capture helpers

private final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func set(_ newValue: Bool) {
        lock.lock()
        _value = newValue
        lock.unlock()
    }
}

private final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func set(_ newValue: String?) {
        lock.lock()
        _value = newValue
        lock.unlock()
    }
}
