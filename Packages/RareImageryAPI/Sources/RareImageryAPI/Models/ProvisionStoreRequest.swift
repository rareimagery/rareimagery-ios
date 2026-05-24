import Foundation

/// Body for `POST /api/v1/creator/provision-store` (the BFF wrapper for
/// the `provisionCreatorAction` Server Action on the web side).
///
/// Idempotent on the Drupal side — `CreatorProvisioner` either creates
/// the user/store/profile/subdomain atomically OR returns the existing
/// entities (status: "existing"). Either way iOS gets the same response
/// shape back so the call is safe to retry.
///
/// All fields are optional; the BFF accepts partial payloads (every
/// field omitted = "provision with all defaults from the X session
/// data NextAuth already captured"). iOS's TweakSheetView sends only
/// the fields the user actually changed.
///
/// Two notable nuances:
///   - `subdomain` is the iOS naming for what web calls `slug`; the BFF
///     accepts EITHER key and normalizes to slug internally. Sending
///     `subdomain` is the iOS-canonical choice for clarity.
///   - The matching Zod schema on the BFF side requires `subdomain OR
///     slug` to be present even though they're both individually
///     optional — pass `subdomain` if you want the BFF to consider the
///     request as containing a slug change.
public struct ProvisionStoreRequest: Encodable, Sendable {
    /// iOS naming for the storefront slug. Send when the user renamed
    /// their slug in the Tweak sheet; omit to keep the default
    /// (X username lowercased).
    public let subdomain: String?

    /// Display name override. Defaults to X display name if omitted.
    public let displayName: String?

    /// Bio override. Defaults to X bio if omitted.
    public let bio: String?

    /// Avatar URL override. Rarely sent from iOS — defaults to X avatar.
    public let avatarUrl: String?

    /// Banner URL override. Rarely sent from iOS — defaults to X banner.
    public let bannerUrl: String?

    /// Featured creator references. Up to 10. From the Tweak sheet's
    /// FavoriteFriendsPicker equivalent (once iOS adds that surface).
    public let favorites: [FavoriteRef]?

    /// Template ID. Currently only `"modern-cart"` works for v1 mobile
    /// onboarding; future templates will be choosable here.
    public let templateId: String?

    /// One of the 10 color-scheme IDs. See `LiveStorePreview.ColorSchemeOption.all`
    /// for the iOS-canonical list — mirrors Drupal's
    /// `field_color_scheme` allowed_values + Next.js's `COLOR_SCHEMES`.
    public let colorScheme: String?

    /// When true (default), first Console visit fires the Grok background
    /// + accent tuner via `/api/stores/auto-generate`. Defaults to true
    /// on Drupal side if omitted.
    public let matchXVibe: Bool?

    /// Up to 4 X post IDs to feature on the storefront. iOS doesn't pick
    /// these in the Tweak sheet v1 — typically omitted.
    public let featuredPostIds: [String]?

    public init(
        subdomain: String? = nil,
        displayName: String? = nil,
        bio: String? = nil,
        avatarUrl: String? = nil,
        bannerUrl: String? = nil,
        favorites: [FavoriteRef]? = nil,
        templateId: String? = nil,
        colorScheme: String? = nil,
        matchXVibe: Bool? = nil,
        featuredPostIds: [String]? = nil
    ) {
        self.subdomain = subdomain
        self.displayName = displayName
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.bannerUrl = bannerUrl
        self.favorites = favorites
        self.templateId = templateId
        self.colorScheme = colorScheme
        self.matchXVibe = matchXVibe
        self.featuredPostIds = featuredPostIds
    }

    /// Shape per the BFF's ProvisionStoreSchema FavoriteSchema:
    /// `{ username, displayName?, profileImageUrl?, followerCount?, verified? }`
    /// All fields optional except `username`.
    public struct FavoriteRef: Encodable, Sendable {
        public let username: String
        public let displayName: String?
        public let profileImageUrl: String?
        public let followerCount: Int?
        public let verified: Bool?

        public init(
            username: String,
            displayName: String? = nil,
            profileImageUrl: String? = nil,
            followerCount: Int? = nil,
            verified: Bool? = nil
        ) {
            self.username = username
            self.displayName = displayName
            self.profileImageUrl = profileImageUrl
            self.followerCount = followerCount
            self.verified = verified
        }
    }
}

/// Response from `POST /api/v1/creator/provision-store` on success.
/// The BFF returns 200 with this shape; 4xx errors come through as
/// thrown `APIError`s (handled by the APIClient's response decoder).
public struct ProvisionStoreResponse: Decodable, Sendable {
    public let ok: Bool
    public let slug: String
    public let url: String
    public let profileNid: Int?
}
