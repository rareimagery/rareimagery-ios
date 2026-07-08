import Foundation

/// A creator's public store: profile hero + their published products.
/// From `GET /api/discover/stores/{slug}` — powers the Shop → native store page.
public struct StoreDetail: Decodable, Sendable {
    public let profile: StoreSummary
    public let products: [StoreProduct]
}
