import XCTest
@testable import RareImageryAPI

final class AuthManagerTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeManager(
        clientID: String = "11111111-2222-3333-4444-555555555555"
    ) async throws -> (AuthManager, KeychainStore) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let keychain = KeychainStore(service: "com.rareimagery.tests.authmanager.\(UUID().uuidString)")
        try await keychain.clearAll()
        let manager = AuthManager(
            configuration: APIConfiguration(
                baseURL: URL(string: "https://rareimagery.net")!,
                xClientID: "unused",
                oauthClientID: clientID
            ),
            keychain: keychain,
            urlSession: session
        )
        return (manager, keychain)
    }

    func testStartSignInBuildsPKCEAuthorizeURL() async throws {
        let (manager, _) = try await makeManager()
        let request = try await manager.startSignIn()
        XCTAssertEqual(request.callbackScheme, "rareimagery")
        let items = URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(byName["response_type"], "code")
        XCTAssertEqual(byName["client_id"], "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(byName["redirect_uri"], "rareimagery://oauth/callback")
        XCTAssertEqual(byName["code_challenge_method"], "S256")
        XCTAssertFalse(byName["code_challenge"]?.isEmpty ?? true)
        XCTAssertFalse(byName["state"]?.isEmpty ?? true)
    }

    func testCompleteSignInExchangesCodeAndPersistsTokens() async throws {
        let (manager, keychain) = try await makeManager()
        let started = try await manager.startSignIn()
        let state = URLComponents(url: started.authorizationURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "state" })?.value ?? ""

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/oauth/token")
            XCTAssertEqual(request.httpMethod, "POST")
            let bodyData: Data
            if let httpBody = request.httpBody {
                bodyData = httpBody
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                let bufferSize = 1024
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: bufferSize)
                    if read > 0 { data.append(buffer, count: read) }
                    else { break }
                }
                bodyData = data
            } else {
                bodyData = Data()
            }
            let body = String(data: bodyData, encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("grant_type=authorization_code"), "body=\(body)")
            XCTAssertTrue(body.contains("code=auth-code-1"), "body=\(body)")
            let data = Data("""
            {
              "access_token": "access-aaa",
              "refresh_token": "refresh-bbb",
              "expires_in": 3600,
              "token_type": "Bearer"
            }
            """.utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        var callback = URLComponents(string: "rareimagery://oauth/callback")!
        callback.queryItems = [
            URLQueryItem(name: "code", value: "auth-code-1"),
            URLQueryItem(name: "state", value: state),
        ]
        let set = try await manager.completeSignIn(callbackURL: callback.url!)
        XCTAssertEqual(set.accessToken, "access-aaa")
        let storedAccess = try await keychain.get(.accessToken)
        let storedRefresh = try await keychain.get(.refreshToken)
        let storedExpiry = try await keychain.get(.accessTokenExpiry)
        XCTAssertEqual(storedAccess, "access-aaa")
        XCTAssertEqual(storedRefresh, "refresh-bbb")
        XCTAssertNotNil(storedExpiry)
    }

    func testValidAccessTokenRefreshesWhenExpired() async throws {
        let (manager, keychain) = try await makeManager()
        try await keychain.set("stale-access", for: .accessToken)
        try await keychain.set("refresh-old", for: .refreshToken)
        try await keychain.set(
            ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10)),
            for: .accessTokenExpiry
        )
        _ = await manager.restoreFromKeychain()

        var refreshCalls = 0
        MockURLProtocol.requestHandler = { request in
            refreshCalls += 1
            let bodyData: Data
            if let httpBody = request.httpBody {
                bodyData = httpBody
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                let bufferSize = 1024
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: bufferSize)
                    if read > 0 { data.append(buffer, count: read) }
                    else { break }
                }
                bodyData = data
            } else {
                bodyData = Data()
            }
            let body = String(data: bodyData, encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("grant_type=refresh_token"), "body=\(body)")
            XCTAssertTrue(body.contains("refresh_token=refresh-old"), "body=\(body)")
            let data = Data("""
            {
              "access_token": "access-fresh",
              "refresh_token": "refresh-new",
              "expires_in": 3600,
              "token_type": "Bearer"
            }
            """.utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let token = try await manager.validAccessToken()
        XCTAssertEqual(token, "access-fresh")
        XCTAssertEqual(refreshCalls, 1)
        let storedRefresh = try await keychain.get(.refreshToken)
        XCTAssertEqual(storedRefresh, "refresh-new")
    }

    func testFormEncodingPercentEncodesReservedCharacters() {
        let data = AuthManager.form([
            "grant_type": "refresh_token",
            "client_id": "abc",
            "refresh_token": "a&b=c",
        ])
        let body = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("refresh_token=a%26b%3Dc"))
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
    }
}
