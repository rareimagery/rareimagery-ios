import SwiftUI

/// iOS-side product kind for OnePageCreator chips.
/// Raw values map 1:1 to Drupal's `field_product_kind` enum and the BFF's
/// `ProductType` in `x-store-next/src/lib/product-specs.ts`.
///
/// Per decision 2026-05-24 ("Match Drupal's existing enum"), v1 ships
/// the 3 chips that fit the "merch with my face on it" framing.
/// `tote_bag`, `sticker_pack`, `pet_bandana`, `pet_hoodie`, `digital_drop`,
/// etc. exist in Drupal but are deferred.
enum MerchProductKind: String, CaseIterable, Identifiable, Hashable {
    case tShirt = "t_shirt"
    case hoodie = "hoodie"
    case ballcap = "ballcap"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tShirt:  return "T-Shirt"
        case .hoodie:  return "Hoodie"
        case .ballcap: return "Cap"
        }
    }

    /// SF Symbol — picks a vaguely on-brand glyph per type. Apparel
    /// symbols are sparse in SF Symbols; tshirt.fill is the cleanest hit
    /// and works for the others as a thematic placeholder until custom
    /// icons land.
    var symbol: String {
        switch self {
        case .tShirt:  return "tshirt.fill"
        case .hoodie:  return "tshirt.fill"
        case .ballcap: return "graduationcap.fill"
        }
    }
}
