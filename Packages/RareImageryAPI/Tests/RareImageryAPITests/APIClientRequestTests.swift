import XCTest
@testable import RareImageryAPI

final class APIClientRequestTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeClient(tokenProvider: (@Sendable () async throws -> String)? = nil) async -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let keychain = KeychainStore(service: "com.rareimagery.tests.request.\(UUID().uuidString)")
        try? await keychain.clearAll()
        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: URL(string: "https://rareimagery.net")!,
                xClientID: "test-client"
            ),
            keychain: keychain,
            urlSession: session
        )
        if let tokenProvider {
            await client.setTokenProvider(tokenProvider)
        }
        return client
    }

    func testRequestDecodesSampleBody() async throws {
        struct Sample: Decodable, Equatable {
            let id: String
            let title: String
        }

        let url = URL(string: "https://rareimagery.net/jsonapi/commerce_product/capture")!
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, url)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let data = Data(#"{"id":"abc","title":"Signature Print"}"#.utf8)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = await makeClient { "test-token" }
        let sample = try await client.request(Sample.self, url: url)
        XCTAssertEqual(sample, Sample(id: "abc", title: "Signature Print"))
    }

    func testRequestMaps422EnvelopeToValidation() async throws {
        let url = URL(string: "https://rareimagery.net/api/v1/listings")!
        let body = Data("""
        {
          "errors": [
            {
              "status": "422",
              "code": "invalid_price",
              "detail": "Price must be a positive number."
            }
          ]
        }
        """.utf8)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: url, statusCode: 422, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let client = await makeClient { "test-token" }
        do {
            struct Unused: Decodable { let ok: Bool }
            _ = try await client.request(
                Unused.self,
                url: url,
                method: "POST",
                body: Data("{}".utf8)
            )
            XCTFail("Expected validation error")
        } catch let error as APIError {
            XCTAssertEqual(
                error,
                .validation(code: "invalid_price", detail: "Price must be a positive number.")
            )
            XCTAssertEqual(error.errorDescription, "Price must be a positive number.")
        }
    }

    func testRequestMaps502ToAIUnavailable() async throws {
        let url = URL(string: "https://rareimagery.net/api/v1/realtime-token")!
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: url, statusCode: 502, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"errors":[{"status":"502","code":"ai_provider_unavailable","detail":"down"}]}"#.utf8))
        }

        let client = await makeClient { "test-token" }
        do {
            struct Unused: Decodable { let token: String }
            _ = try await client.request(Unused.self, url: url, method: "POST")
            XCTFail("Expected aiUnavailable")
        } catch let error as APIError {
            XCTAssertEqual(error, .aiUnavailable)
        }
    }

    func testAPIEnvironmentPaths() {
        let endpoints = APIEnvironment.urls(for: URL(string: "https://rareimagery.net")!)
        XCTAssertEqual(endpoints.jsonAPI.absoluteString, "https://rareimagery.net/jsonapi")
        XCTAssertEqual(endpoints.apiV1.absoluteString, "https://rareimagery.net/api/v1")
        XCTAssertEqual(endpoints.oauthToken.absoluteString, "https://rareimagery.net/oauth/token")
        XCTAssertEqual(endpoints.oauthAuthorize.absoluteString, "https://rareimagery.net/oauth/authorize")
    }
}
