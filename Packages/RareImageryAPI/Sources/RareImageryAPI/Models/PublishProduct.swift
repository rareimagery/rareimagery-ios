import Foundation

/// Request body for POST /api/v1/design-studio/publish.
///
/// Phase 4.4 — closes the OnePageCreator stub. Sent from
/// OnePageCreatorViewModel.createProductAndStore() once the user has
/// a generated design preview AND has tapped "Create + Launch".
///
/// `imageUrl` is whatever came back in `previewImageURL` after
/// design-studio/generate completed — typically a data: URL with the
/// fitted mockup encoded as base64 (~1 MB), occasionally an https://
/// URL once Grok's task storage starts returning hosted URLs.
///
/// `creatorProfileUuid` is NOT in the request — the BFF derives it
/// server-side from the mobile JWT's `sub` claim. iOS only sends the
/// product-side fields.
public struct PublishProductRequest: Encodable, Sendable {
    public let productKind: String       // t_shirt | hoodie | ballcap (v1)
    public let title: String             // ≤80 chars
    public let description: String?      // long body, ≤2000 chars
    public let shortDescription: String? // ≤280 chars, falls back to title
    public let imageUrl: String          // data: or https:// URL
    public let priceLow: Double          // USD, used as variation price
    public let priceHigh: Double?        // USD, optional, analytics only
    public let designRecordUuid: String? // Phase 4.3 lineage threading
    public let tags: [String]?           // optional; taxonomy linkage is a follow-up

    public init(
        productKind: String,
        title: String,
        description: String? = nil,
        shortDescription: String? = nil,
        imageUrl: String,
        priceLow: Double,
        priceHigh: Double? = nil,
        designRecordUuid: String? = nil,
        tags: [String]? = nil
    ) {
        self.productKind = productKind
        self.title = title
        self.description = description
        self.shortDescription = shortDescription
        self.imageUrl = imageUrl
        self.priceLow = priceLow
        self.priceHigh = priceHigh
        self.designRecordUuid = designRecordUuid
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case productKind = "product_kind"
        case title
        case description
        case shortDescription = "short_description"
        case imageUrl = "image_url"
        case priceLow = "price_low"
        case priceHigh = "price_high"
        case designRecordUuid = "design_record_uuid"
        case tags
    }
}

/// Response from POST /api/v1/design-studio/publish.
/// Forwarded straight from Drupal's `/api/sales-telemetry/publish-product`
/// — the BFF doesn't reshape it.
public struct PublishProductResponse: Decodable, Sendable {
    public let ok: Bool
    public let productId: Int
    public let productUuid: String
    public let variationId: Int
    public let sku: String
    public let imageFileId: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case productId = "product_id"
        case productUuid = "product_uuid"
        case variationId = "variation_id"
        case sku
        case imageFileId = "image_file_id"
    }
}
