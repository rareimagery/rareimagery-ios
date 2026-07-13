import XCTest
@testable import RareImageryAPI

final class MediaUploadRepositoryTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeRepo() async throws -> MediaUploadRepository {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let keychain = KeychainStore(service: "com.rareimagery.tests.media.\(UUID().uuidString)")
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
        // Use the same mock session for video path (avoid real background session in tests).
        return MediaUploadRepository(client: client, videoSession: session)
    }

    private func fileUploadResponse(id: String, filename: String) -> Data {
        Data("""
        {
          "data": {
            "type": "file--file",
            "id": "\(id)",
            "attributes": {
              "filename": "\(filename)",
              "filemime": "image/jpeg",
              "filesize": 12,
              "drupal_internal__fid": 99
            }
          }
        }
        """.utf8)
    }

    private func mediaCreateResponse(mid: Int, id: String = UUID().uuidString) -> Data {
        Data("""
        {
          "data": {
            "type": "media--image",
            "id": "\(id)",
            "attributes": {
              "name": "frame",
              "status": true,
              "drupal_internal__mid": \(mid)
            }
          }
        }
        """.utf8)
    }

    func testUploadFramesTwoStepCreatesMediaIDs() async throws {
        let repo = try await makeRepo()
        var fileUploadCount = 0
        var mediaCreateCount = 0
        var paths: [String] = []

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            paths.append(path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")

            if path.hasSuffix("/field_media_image") {
                fileUploadCount += 1
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
                let disposition = request.value(forHTTPHeaderField: "Content-Disposition") ?? ""
                XCTAssertTrue(disposition.contains("filename="), disposition)
                let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
                let fileID = "file-uuid-\(fileUploadCount)"
                return (response, self.fileUploadResponse(id: fileID, filename: "frame.jpg"))
            }

            if path == "/jsonapi/media/image" {
                mediaCreateCount += 1
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/vnd.api+json")
                let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
                return (response, self.mediaCreateResponse(mid: 100 + mediaCreateCount))
            }

            XCTFail("Unexpected path \(path)")
            throw URLError(.badURL)
        }

        let mids = try await repo.uploadFrames([
            Data(repeating: 0xFF, count: 16),
            Data(repeating: 0xAA, count: 16),
        ])
        XCTAssertEqual(mids, [101, 102])
        XCTAssertEqual(fileUploadCount, 2)
        XCTAssertEqual(mediaCreateCount, 2)
        XCTAssertEqual(paths.filter { $0.hasSuffix("/field_media_image") }.count, 2)
        XCTAssertEqual(paths.filter { $0 == "/jsonapi/media/image" }.count, 2)
    }

    func testTransportRetryThenSuccess() async throws {
        let repo = try await makeRepo()
        var attempts = 0

        MockURLProtocol.requestHandler = { request in
            attempts += 1
            if attempts == 1 {
                throw URLError(.networkConnectionLost)
            }
            let path = request.url?.path ?? ""
            if path.hasSuffix("/field_media_image") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
                return (response, self.fileUploadResponse(id: "file-r", filename: "frame1.jpg"))
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, self.mediaCreateResponse(mid: 55))
        }

        let mids = try await repo.uploadFrames([Data("jpeg".utf8)])
        XCTAssertEqual(mids, [55])
        XCTAssertEqual(attempts, 3) // 1 fail on file + 1 success file + 1 media create
    }

    func testTransportFailureExhaustsRetriesWithoutCrash() async throws {
        let repo = try await makeRepo()
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        do {
            _ = try await repo.uploadFrames([Data("jpeg".utf8)])
            XCTFail("Expected network error")
        } catch let error as APIError {
            guard case .network = error else {
                return XCTFail("Expected network, got \(error)")
            }
        }
    }
}
