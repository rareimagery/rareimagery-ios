import XCTest
@testable import RareImageryAPI

final class CaptureAPITests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeClient() async throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let keychain = KeychainStore(service: "com.rareimagery.tests.capture.\(UUID().uuidString)")
        try await keychain.clearAll()
        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: URL(string: "https://rareimagery.net")!,
                xClientID: "test"
            ),
            keychain: keychain,
            urlSession: session
        )
        await client.setTokenProvider { "test-token" }
        return client
    }

    func testAnalyzeDecodesDataEnvelope() async throws {
        let client = try await makeClient()
        let repo = CaptureRepository(client: client)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/analyze-capture")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let body = Self.bodyString(from: request)
            XCTAssertTrue(body.contains("\"media_ids\""))
            XCTAssertTrue(body.contains("\"transcript\""))
            let data = Data("""
            {
              "data": {
                "itemType": "watch",
                "brandModel": "Rolex Submariner",
                "year": 1998,
                "condition": "good",
                "keyFeatures": ["steel", "black dial"],
                "estimatedValueUSD": 8500.0,
                "confidence": 0.82,
                "suggestedTitle": "1998 Rolex Submariner",
                "suggestedDescription": "Steel Submariner in good condition.",
                "spokenConfirmation": "Looks like a late-nineties Submariner around eighty-five hundred."
              }
            }
            """.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let result = try await repo.analyze(mediaIDs: [11, 12], transcript: "steel watch")
        XCTAssertEqual(result.itemType, "watch")
        XCTAssertFalse(result.spokenConfirmation.isEmpty)
        XCTAssertEqual(result.estimatedValueUSD, 8500.0)
    }

    func testCreateListingDecodesSnakeCaseFields() async throws {
        let client = try await makeClient()
        let repo = CaptureRepository(client: client)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/listings")
            let body = Self.bodyString(from: request)
            XCTAssertTrue(body.contains("\"media_ids\""))
            XCTAssertTrue(body.contains("\"status\":\"draft\""))
            let data = Data("""
            {
              "data": {
                "product_id": 42,
                "product_uuid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                "variation_id": 43,
                "status": "draft",
                "store_id": 7
              }
            }
            """.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let listing = try await repo.createListing(
            title: "Test",
            description: "Desc",
            price: "25.00",
            status: "draft",
            analysis: nil,
            mediaIDs: [11, 12]
        )
        XCTAssertEqual(listing.productId, 42)
        XCTAssertEqual(listing.status, "draft")
        XCTAssertEqual(listing.productUuid, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    }

    func testVoiceTokenMint() async throws {
        let client = try await makeClient()
        let voice = VoiceTokenClient(client: client)
        let future = Int(Date().addingTimeInterval(300).timeIntervalSince1970)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/realtime-token")
            XCTAssertEqual(request.httpMethod, "POST")
            let data = Data("""
            {
              "data": {
                "token": "ephemeral-secret",
                "expires_at": \(future),
                "realtime_url": "wss://api.x.ai/v1/realtime?model=grok-voice"
              }
            }
            """.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let token = try await voice.mint()
        XCTAssertEqual(token.token, "ephemeral-secret")
        XCTAssertFalse(token.isExpired)
        XCTAssertTrue(token.realtimeURL.contains("realtime"))
    }

    func testAnalyzeMaps422Validation() async throws {
        let client = try await makeClient()
        let repo = CaptureRepository(client: client)

        MockURLProtocol.requestHandler = { request in
            let data = Data("""
            {
              "errors": [
                { "status": "422", "code": "media_required", "detail": "media_ids required." }
              ]
            }
            """.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        do {
            _ = try await repo.analyze(mediaIDs: [1], transcript: "")
            XCTFail("Expected validation")
        } catch let error as APIError {
            XCTAssertEqual(error, .validation(code: "media_required", detail: "media_ids required."))
        }
    }

    private static func bodyString(from request: URLRequest) -> String {
        if let httpBody = request.httpBody {
            return String(data: httpBody, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 1024)
            if read > 0 { data.append(buffer, count: read) } else { break }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
