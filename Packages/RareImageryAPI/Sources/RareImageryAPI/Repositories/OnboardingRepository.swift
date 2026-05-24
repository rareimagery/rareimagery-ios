import Foundation

/// Persistence helper for the iOS onboarding flow's TweakSheetView.
///
/// One method today (`updateStore`) — calls the canonical BFF endpoint
/// at `POST /api/v1/creator/provision-store`. The endpoint is idempotent:
/// `CreatorProvisioner` on Drupal returns the existing entities if the
/// user is already provisioned (status: "existing"), or creates them
/// atomically if not (status: "created"). Either way iOS gets the same
/// `ProvisionStoreResponse` shape back, so this call is safe to retry.
///
/// Lives alongside `AuthRepository` and `ProductRepository` in the
/// canonical RareImageryAPI Swift package. Initialized once on
/// `AppState` startup with the shared `APIClient`.
///
/// Cross-platform parity: web invokes the same logic via the
/// `provisionCreatorAction` Server Action (`src/app/onboarding/actions.ts`
/// on x-store-next), which POSTs to the same Drupal endpoint. iOS goes
/// through the BFF wrapper `/api/v1/creator/provision-store` for Bearer
/// JWT support; web uses the cookie session. Both produce identical
/// Drupal-side state.
public actor OnboardingRepository {
    private let client: APIClient
    private let logger = APILogger(category: "OnboardingRepository")

    public init(client: APIClient) {
        self.client = client
    }

    /// Persist tweaks made in TweakSheetView.
    ///
    /// All parameters optional; omit fields the user didn't change. The
    /// BFF accepts the partial payload and `CreatorProvisioner` applies
    /// only what was sent (existing fields untouched).
    ///
    /// - Parameters:
    ///   - subdomain: Storefront slug. Send when the user renamed in the
    ///     sheet's URL field. Omit to keep the default (X username
    ///     lowercased).
    ///   - displayName: Display name override. Defaults to X display name.
    ///   - bio: Bio override. Defaults to X bio.
    ///   - colorScheme: One of the 10 color-scheme IDs
    ///     (`"midnight" | "ocean" | "forest" | …`). See
    ///     `LiveStorePreview.ColorSchemeOption.all` for the canonical
    ///     iOS list.
    ///   - matchXVibe: Whether to fire the post-launch Grok background
    ///     tuner on first Console visit. Defaults to true on Drupal.
    ///   - favorites: Up to 10 featured creator references. iOS doesn't
    ///     surface this in TweakSheetView v1; pass nil from the sheet.
    ///
    /// - Returns: `ProvisionStoreResponse` with the canonical slug + URL
    ///   the user can share. The slug in the response may differ from
    ///   what was passed in (e.g., normalization, conflict resolution
    ///   that returned an existing creator's stable slug).
    ///
    /// - Throws: `APIError` on auth failure (401), validation failure
    ///   (400 with Zod issues envelope per PR #15), slug conflict (409
    ///   with code `RESERVED_SLUG` or `SLUG_TAKEN`), or network/server
    ///   error (5xx with code `DRUPAL_ERROR` or `NETWORK_ERROR`).
    public func updateStore(
        subdomain: String? = nil,
        displayName: String? = nil,
        bio: String? = nil,
        colorScheme: String? = nil,
        matchXVibe: Bool? = nil,
        favorites: [ProvisionStoreRequest.FavoriteRef]? = nil
    ) async throws -> ProvisionStoreResponse {
        let body = ProvisionStoreRequest(
            subdomain: subdomain,
            displayName: displayName,
            bio: bio,
            avatarUrl: nil,
            bannerUrl: nil,
            favorites: favorites,
            templateId: nil,
            colorScheme: colorScheme,
            matchXVibe: matchXVibe,
            featuredPostIds: nil
        )

        // Force camelCase keys — APIEndpoint.json applies snake_case by
        // default and the BFF expects camelCase on this route (per the
        // ProvisionStoreSchema Zod definition in /api/v1/creator/provision-store/route.ts).
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        let data = try encoder.encode(body)

        let endpoint = APIEndpoint(
            path: "/api/v1/creator/provision-store",
            method: .post,
            body: data,
            requiresAuth: true,
            contentType: "application/json",
            // BFF enforces 90s — provision may touch Drupal + X API + run
            // follow-up patches. Allow the full budget.
            timeout: 90
        )
        logger.info(
            "updateStore: slug=\(subdomain ?? "<unchanged>") color=\(colorScheme ?? "<unchanged>") matchXVibe=\(matchXVibe.map(String.init) ?? "<unchanged>")"
        )
        return try await client.send(endpoint)
    }
}
