import SwiftUI

/// RareImagery brand palette — app-wide refresh (2026-06-25) toward the
/// "Be Rare." vault identity: brand purple `#7B2D8E` + gold `#D4AF37`.
/// Source design: `~/rareimagery-brain/memory/design/video-submission-flow.dc.html`.
///
/// Legacy token names (`accent`, `cta`, `surface`, …) are kept so every existing
/// call-site compiles and adopts the refresh automatically.
enum AppColor {
    // MARK: Brand
    /// #7B2D8E — primary brand purple (was #7c3aed)
    static let brand = Color(red: 123/255, green: 45/255, blue: 142/255)
    /// #D4AF37 — brand gold (new)
    static let gold = Color(red: 212/255, green: 175/255, blue: 55/255)
    static let goldSoft = Color(red: 212/255, green: 175/255, blue: 55/255).opacity(0.16)
    /// #B8932B — deeper gold for text-on-light
    static let gold700 = Color(red: 184/255, green: 147/255, blue: 43/255)
    static let brandSoft = Color(red: 123/255, green: 45/255, blue: 142/255).opacity(0.16)

    // MARK: Vault gradient stops (#561F62 → #2C1033 → #160D1A)
    static let vaultTop = Color(red: 86/255, green: 31/255, blue: 98/255)
    static let vaultMid = Color(red: 44/255, green: 16/255, blue: 51/255)
    static let vaultBottom = Color(red: 22/255, green: 13/255, blue: 26/255)

    // MARK: Surfaces
    /// #0a0a0a — base background
    static let background = Color(red: 10/255, green: 10/255, blue: 10/255)
    /// #171717 — elevated surfaces (cards, inputs)
    static let surface = Color(red: 23/255, green: 23/255, blue: 23/255)
    /// #1a1a1a — nested chips/search
    static let surfaceSecondary = Color(red: 26/255, green: 26/255, blue: 26/255)

    // MARK: Text
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.65, green: 0.65, blue: 0.7)

    // MARK: Borders
    static let border = Color.white.opacity(0.08)
    static let borderGold = Color(red: 212/255, green: 175/255, blue: 55/255).opacity(0.35)

    // MARK: Semantic
    static let success = Color(red: 63/255, green: 185/255, blue: 80/255)

    // MARK: Legacy aliases (refresh-mapped)
    /// was accent #7c3aed → now brand purple
    static let accent = brand
    /// was cta #FF6B00 (orange) → now gold (the design's primary CTA is gold)
    static let cta = gold
}

extension AppColor {
    /// Vault background gradient — funnel + branded surfaces.
    static let vaultGradient = LinearGradient(
        colors: [vaultTop, vaultMid, vaultBottom],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Foil-gold gradient — the "." in "Rare." and gold accents.
    static let foil = LinearGradient(
        colors: [Color(red: 244/255, green: 229/255, blue: 166/255), gold, gold700],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}
