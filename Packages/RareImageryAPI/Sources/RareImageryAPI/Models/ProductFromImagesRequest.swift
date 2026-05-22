import Foundation

public struct ProductFromImagesRequest: Codable, Sendable, Equatable {
    public let heroUrl: String
    public let additionalUrls: [String]
    public let voiceTranscript: String?
    public let intent: ProductIntent
    public let storeUuid: String?

    public init(
        heroUrl: String,
        additionalUrls: [String] = [],
        voiceTranscript: String? = nil,
        intent: ProductIntent = .unknown,
        storeUuid: String? = nil
    ) {
        self.heroUrl = heroUrl
        self.additionalUrls = additionalUrls
        self.voiceTranscript = voiceTranscript
        self.intent = intent
        self.storeUuid = storeUuid
    }

    enum CodingKeys: String, CodingKey {
        case heroUrl = "hero_url"
        case additionalUrls = "additional_urls"
        case voiceTranscript = "voice_transcript"
        case intent
        case storeUuid = "store_uuid"
    }
}
