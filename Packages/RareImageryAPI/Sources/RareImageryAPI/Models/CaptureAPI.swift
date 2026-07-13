import Foundation

/// Phase-1 capture analysis from `POST /api/v1/analyze-capture`.
public struct AnalysisResult: Codable, Sendable, Equatable {
    public let itemType: String
    public let brandModel: String?
    public let year: Int?
    public let condition: String
    public let keyFeatures: [String]
    public let estimatedValueUSD: Double
    public let confidence: Double
    public let suggestedTitle: String
    public let suggestedDescription: String
    public let spokenConfirmation: String

    public init(
        itemType: String,
        brandModel: String? = nil,
        year: Int? = nil,
        condition: String,
        keyFeatures: [String],
        estimatedValueUSD: Double,
        confidence: Double,
        suggestedTitle: String,
        suggestedDescription: String,
        spokenConfirmation: String
    ) {
        self.itemType = itemType
        self.brandModel = brandModel
        self.year = year
        self.condition = condition
        self.keyFeatures = keyFeatures
        self.estimatedValueUSD = estimatedValueUSD
        self.confidence = confidence
        self.suggestedTitle = suggestedTitle
        self.suggestedDescription = suggestedDescription
        self.spokenConfirmation = spokenConfirmation
    }
}

/// Created listing from `POST /api/v1/listings`.
public struct ListingResult: Decodable, Sendable, Equatable {
    public let productId: Int
    public let productUuid: String
    public let variationId: Int
    public let status: String
    public let storeId: Int

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case productUuid = "product_uuid"
        case variationId = "variation_id"
        case status
        case storeId = "store_id"
    }

    public init(
        productId: Int,
        productUuid: String,
        variationId: Int,
        status: String,
        storeId: Int
    ) {
        self.productId = productId
        self.productUuid = productUuid
        self.variationId = variationId
        self.status = status
        self.storeId = storeId
    }
}

/// Ephemeral xAI Realtime credentials from `POST /api/v1/realtime-token`.
public struct RealtimeToken: Decodable, Sendable, Equatable {
    public let token: String
    public let expiresAt: Int
    public let realtimeURL: String

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case realtimeURL = "realtime_url"
    }

    public init(token: String, expiresAt: Int, realtimeURL: String) {
        self.token = token
        self.expiresAt = expiresAt
        self.realtimeURL = realtimeURL
    }

    public var expiresAtDate: Date {
        Date(timeIntervalSince1970: TimeInterval(expiresAt))
    }

    public var isExpired: Bool {
        expiresAtDate <= Date()
    }
}

/// `{ "data": T }` envelope used by rareimagery_api success responses.
public struct DataEnvelope<T: Decodable>: Decodable, Sendable where T: Sendable {
    public let data: T

    public init(data: T) {
        self.data = data
    }
}
