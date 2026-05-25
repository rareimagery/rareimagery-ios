import Foundation

/// Request body for POST /api/design-studio/generate.
/// Source: `x-store-next/src/app/api/design-studio/generate/route.ts`.
///
/// `productType` values are the Drupal `field_product_kind` enum:
/// `t_shirt | hoodie | ballcap | pet_bandana | pet_hoodie | digital_drop |
/// skateboard_deck | vintage_poster | sticker_pack | canvas_art | tote_bag`.
/// OnePageCreator v1 uses the first three.
///
/// `referenceImage` is a data URL OR https URL (the route accepts both).
/// For PFP integration, pass the user's avatar URL directly + set
/// `useCreatorContext=true` to trigger `generateDesignWithContext`.
public struct DesignGenerationRequest: Encodable, Sendable {
    public let prompt: String
    public let productType: String
    public let referenceImage: String?
    public let variants: Int?
    public let useCreatorContext: Bool?
    public let placementId: String?

    public init(
        prompt: String,
        productType: String,
        referenceImage: String? = nil,
        variants: Int? = 4,
        useCreatorContext: Bool? = true,
        placementId: String? = nil
    ) {
        self.prompt = prompt
        self.productType = productType
        self.referenceImage = referenceImage
        self.variants = variants
        self.useCreatorContext = useCreatorContext
        self.placementId = placementId
    }

    enum CodingKeys: String, CodingKey {
        case prompt
        case productType = "product_type"
        case referenceImage = "reference_image"
        case variants
        case useCreatorContext = "use_creator_context"
        case placementId = "placement_id"
    }
}

/// Response from POST /api/design-studio/generate.
/// Two distinct shapes depending on `mode` — apparel triggers `.background`
/// (poll the task endpoint); stickers/embroidery return `.fast` with
/// `imageUrl` populated immediately.
///
/// Decoded as a unified envelope so callers don't have to switch decode
/// paths — check `.mode` and read the appropriate fields.
public struct DesignGenerationResponse: Decodable, Sendable {
    public let success: Bool
    public let mode: Mode
    public let productType: String?
    public let originalPrompt: String?

    // Fast-mode fields (mode == .fast)
    public let imageUrl: String?
    public let imageUrls: [String]?
    public let usedPfp: Bool?
    public let usedUpload: Bool?
    public let pfpUsername: String?

    // Background-mode fields (mode == .background)
    public let taskKey: String?
    public let pollUrl: String?
    public let pollIntervalMs: Int?

    public enum Mode: String, Decodable, Sendable {
        case fast
        case background
    }

    enum CodingKeys: String, CodingKey {
        case success, mode
        case productType = "product_type"
        case originalPrompt = "original_prompt"
        case imageUrl = "image_url"
        case imageUrls = "image_urls"
        case usedPfp = "used_pfp"
        case usedUpload = "used_upload"
        case pfpUsername = "pfp_username"
        case taskKey = "task_key"
        case pollUrl = "poll_url"
        case pollIntervalMs = "poll_interval_ms"
    }
}

/// Polling response from GET /api/design-studio/task/{taskKey}.
/// `status` transitions: `pending → completed | failed`. On completion,
/// `imageUrl` is populated (typically a data URL after print-area fitting).
public struct DesignTaskStatus: Decodable, Sendable {
    public let taskKey: String
    public let status: Status
    public let productType: String?
    public let prompt: String?
    public let imageUrl: String?
    public let imageUrls: [String]?
    public let error: String?
    public let createdAt: String?
    public let completedAt: String?

    public enum Status: String, Decodable, Sendable {
        case pending
        case completed
        case failed
    }

    enum CodingKeys: String, CodingKey {
        case taskKey = "task_key"
        case status
        case productType = "product_type"
        case prompt
        case imageUrl = "image_url"
        case imageUrls = "image_urls"
        case error
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}
