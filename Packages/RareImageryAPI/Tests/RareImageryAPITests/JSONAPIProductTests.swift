import XCTest
@testable import RareImageryAPI

final class JSONAPIProductTests: XCTestCase {

    /// Fixture shaped like live `GET /jsonapi/commerce_product/default` (2026-07-13),
    /// including unknown attribute keys that must not break decoding.
    private let sampleDocument = """
    {
      "jsonapi": { "version": "1.1" },
      "data": [
        {
          "type": "commerce_product--default",
          "id": "123923da-e3dc-403a-a07e-4478501fb068",
          "attributes": {
            "drupal_internal__product_id": 7,
            "langcode": "en",
            "status": true,
            "title": "RareImagery — Signature Print",
            "path": { "alias": null, "pid": null, "langcode": "en" },
            "created": "2026-06-26T12:14:03+00:00",
            "changed": "2026-06-26T12:46:04+00:00",
            "default_langcode": true,
            "body": {
              "value": "A signature archival giclée print from the @RareImagery collection.",
              "format": "basic_html",
              "processed": "A signature archival giclée print from the @RareImagery collection.",
              "summary": null
            },
            "field_display_weight": 999
          }
        },
        {
          "type": "commerce_product--default",
          "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          "attributes": {
            "status": 0,
            "title": "Stoned Dog Poster",
            "created": "2026-06-20T10:00:00+00:00",
            "body": null
          }
        }
      ]
    }
    """

    func testDecodesLiveShapedDocumentIgnoringUnknownFields() throws {
        let doc = try JSONDecoder.rareImagery.decode(
            JSONAPIDocument<ProductAttributes>.self,
            from: Data(sampleDocument.utf8)
        )
        XCTAssertEqual(doc.data.count, 2)

        let signature = Product(resource: doc.data[0])
        XCTAssertEqual(signature.id, "123923da-e3dc-403a-a07e-4478501fb068")
        XCTAssertEqual(signature.title, "RareImagery — Signature Print")
        XCTAssertTrue(signature.isLive)
        XCTAssertTrue(signature.descriptionText.contains("giclée"))

        let poster = Product(resource: doc.data[1])
        XCTAssertEqual(poster.title, "Stoned Dog Poster")
        XCTAssertFalse(poster.isLive)
        XCTAssertEqual(poster.descriptionText, "")
    }

    func testMyProductsHitsJSONAPICapturePath() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let keychain = KeychainStore(service: "com.rareimagery.tests.jsonapi.\(UUID().uuidString)")
        try await keychain.clearAll()
        try await keychain.set("test-token", for: .accessToken)

        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: URL(string: "https://rareimagery.net")!,
                xClientID: "test"
            ),
            keychain: keychain,
            urlSession: session
        )
        await client.setTokenProvider { "test-token" }

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/jsonapi/commerce_product/capture")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(self.sampleDocument.utf8))
        }

        let repo = ProductRepository(client: client)
        let products = try await repo.myProducts()
        XCTAssertEqual(products.count, 2)
        XCTAssertEqual(products.first?.title, "RareImagery — Signature Print")
    }

    func testMyProductsMaps404ToNotFound() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let keychain = KeychainStore(service: "com.rareimagery.tests.jsonapi404.\(UUID().uuidString)")
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

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Not Found".utf8))
        }

        let repo = ProductRepository(client: client)
        do {
            _ = try await repo.myProducts()
            XCTFail("Expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound)
        }
    }
}
