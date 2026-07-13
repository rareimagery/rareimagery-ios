import Foundation

/// Two-step Drupal JSON:API media upload (core file upload + media create).
///
/// Verified field names (2026-07-13):
/// - image → `field_media_image`
/// - video → `field_media_video_file` + `field_media_poster`
///
/// Returns Drupal internal media IDs (`drupal_internal__mid`) for
/// `POST /api/v1/listings` `media_ids`.
public actor MediaUploadRepository {
    public struct Frame: Sendable {
        public let jpegData: Data
        public let filename: String

        public init(jpegData: Data, filename: String = "frame.jpg") {
            self.jpegData = jpegData
            self.filename = filename
        }
    }

    private let client: APIClient
    private let logger = APILogger(category: "MediaUpload")
    private let maxAttempts = 3
    private let videoSession: URLSession

    public init(client: APIClient, videoSession: URLSession? = nil) {
        self.client = client
        if let videoSession {
            self.videoSession = videoSession
        } else {
            let config = URLSessionConfiguration.background(
                withIdentifier: "net.rareimagery.ios.media-upload"
            )
            config.isDiscretionary = false
            config.sessionSendsLaunchEvents = true
            config.timeoutIntervalForResource = 600
            self.videoSession = URLSession(configuration: config)
        }
    }

    // MARK: - Public API

    /// Uploads 1…N JPEG frames as `media--image`. Returns media mids in order.
    public func uploadFrames(_ frames: [Frame]) async throws -> [Int] {
        guard !frames.isEmpty else {
            throw APIError.badRequest(code: nil, message: "uploadFrames called with zero frames")
        }
        var mids: [Int] = []
        for (index, frame) in frames.enumerated() {
            let name = frame.filename.isEmpty ? "frame\(index + 1).jpg" : frame.filename
            let mid = try await uploadImage(jpeg: frame.jpegData, filename: name)
            mids.append(mid)
        }
        return mids
    }

    /// Convenience for raw JPEG Data arrays.
    public func uploadFrames(_ jpegFrames: [Data]) async throws -> [Int] {
        let frames = jpegFrames.enumerated().map { i, data in
            Frame(jpegData: data, filename: "frame\(i + 1).jpg")
        }
        return try await uploadFrames(frames)
    }

    /// Uploads a local video + on-device poster into one `media--video`.
    /// Poster is extracted at ~0.5s when `posterJPEG` is nil.
    public func uploadVideo(at fileURL: URL, posterJPEG: Data? = nil) async throws -> Int {
        let poster: Data
        if let posterJPEG {
            poster = posterJPEG
        } else {
            poster = try await VideoPosterExtractor.jpegPoster(from: fileURL)
        }

        let videoFileID = try await uploadBinaryFile(
            data: try Data(contentsOf: fileURL),
            filename: fileURL.lastPathComponent.isEmpty ? "clip.mov" : fileURL.lastPathComponent,
            mediaBundle: "video",
            fieldName: "field_media_video_file",
            useBackgroundSession: true,
            fromFile: fileURL
        )

        let posterFileID = try await uploadBinaryFile(
            data: poster,
            filename: "poster.jpg",
            mediaBundle: "video",
            fieldName: "field_media_poster",
            useBackgroundSession: false,
            fromFile: nil
        )

        return try await createMediaEntity(
            type: "media--video",
            name: fileURL.deletingPathExtension().lastPathComponent,
            relationships: [
                "field_media_video_file": .init(type: "file--file", id: videoFileID),
                "field_media_poster": .init(type: "file--file", id: posterFileID, alt: "Video poster"),
            ]
        )
    }

    /// Capture helper: frames first, optional video last. Returns all mids
    /// (video mid last when present).
    public func uploadCapture(frames: [Data], videoURL: URL?) async throws -> [Int] {
        var ids = try await uploadFrames(frames)
        if let videoURL {
            let videoMid = try await uploadVideo(at: videoURL)
            ids.append(videoMid)
        }
        return ids
    }

    // MARK: - Image path

    private func uploadImage(jpeg: Data, filename: String) async throws -> Int {
        let fileID = try await uploadBinaryFile(
            data: jpeg,
            filename: filename,
            mediaBundle: "image",
            fieldName: "field_media_image",
            useBackgroundSession: false,
            fromFile: nil
        )
        return try await createMediaEntity(
            type: "media--image",
            name: filename,
            relationships: [
                "field_media_image": .init(type: "file--file", id: fileID, alt: filename),
            ]
        )
    }

    // MARK: - Shared steps

    private func uploadBinaryFile(
        data: Data,
        filename: String,
        mediaBundle: String,
        fieldName: String,
        useBackgroundSession: Bool,
        fromFile: URL?
    ) async throws -> String {
        let endpoints = await client.endpoints
        let url = endpoints.jsonAPI.appending(path: "media/\(mediaBundle)/\(fieldName)")
        let disposition = #"file; filename="\#(filename.replacingOccurrences(of: "\"", with: ""))""#
        let headers = ["Content-Disposition": disposition]

        logger.info("upload file → \(mediaBundle)/\(fieldName) (\(data.count) bytes)")

        let responseData = try await withRetry {
            if useBackgroundSession, let fromFile {
                return try await client.uploadFile(
                    fromFile: fromFile,
                    to: url,
                    contentType: "application/octet-stream",
                    accept: "application/vnd.api+json",
                    headers: headers,
                    sessionOverride: videoSession
                )
            }
            return try await client.performRawRequest(
                url: url,
                method: "POST",
                body: data,
                contentType: "application/octet-stream",
                accept: "application/vnd.api+json",
                headers: headers
            )
        }

        let doc = try JSONDecoder.rareImagery.decode(
            JSONAPISingleDocument<JSONAPIFileAttributes>.self,
            from: responseData
        )
        return doc.data.id
    }

    private func createMediaEntity(
        type: String,
        name: String,
        relationships: [String: JSONAPIMediaCreateBody.DataObject.ResourceIdentifier]
    ) async throws -> Int {
        let endpoints = await client.endpoints
        let bundle = type.split(separator: "--").last.map(String.init) ?? "image"
        let url = endpoints.jsonAPI.appending(path: "media/\(bundle)")

        let body = JSONAPIMediaCreateBody(
            data: .init(
                type: type,
                attributes: .init(name: name),
                relationships: relationships.mapValues {
                    .init(data: $0)
                }
            )
        )
        let encoded = try JSONEncoder().encode(body)

        logger.info("create media \(type)")
        let responseData = try await withRetry {
            try await client.performRawRequest(
                url: url,
                method: "POST",
                body: encoded,
                contentType: "application/vnd.api+json",
                accept: "application/vnd.api+json"
            )
        }

        let doc = try JSONDecoder.rareImagery.decode(
            JSONAPISingleDocument<JSONAPIMediaAttributes>.self,
            from: responseData
        )
        return doc.data.attributes.drupalInternalMid
    }

    /// Exponential backoff on transport errors only (max 3 attempts).
    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 0
        var lastError: Error?
        while attempt < maxAttempts {
            attempt += 1
            do {
                return try await operation()
            } catch let error as APIError {
                lastError = error
                guard case .network = error, attempt < maxAttempts else { throw error }
                let delay = UInt64(pow(2.0, Double(attempt - 1)) * 250_000_000) // 0.25s, 0.5s, 1s
                logger.warning("transport error — retry \(attempt)/\(maxAttempts)")
                try await Task.sleep(nanoseconds: delay)
            } catch {
                throw error
            }
        }
        throw lastError ?? APIError.network(URLError(.unknown))
    }
}
