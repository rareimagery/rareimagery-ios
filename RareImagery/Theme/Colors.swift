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
    /// #B8942A — deeper gold (design-system token gold-600) for text-on-light
    static let gold700 = Color(red: 184/255, green: 148/255, blue: 42/255)
    static let brandSoft = Color(red: 123/255, green: 45/255, blue: 142/255).opacity(0.16)

    // MARK: Vault gradient stops (#561F62 → #2C1033 → #160D1A)
    static let vaultTop = Color(red: 86/255, green: 31/255, blue: 98/255)
    static let vaultMid = Color(red: 44/255, green: 16/255, blue: 51/255)
    static let vaultBottom = Color(red: 22/255, green: 13/255, blue: 26/255)

    // MARK: Surfaces — violet-tinted inks per the vault theme tokens
    /// #100912 — base background (token ink-950 / vault --bg)
    static let background = Color(red: 16/255, green: 9/255, blue: 18/255)
    /// #1E1322 — elevated surfaces, cards, inputs (token ink-850 / vault --surface-raised)
    static let surface = Color(red: 30/255, green: 19/255, blue: 34/255)
    /// #261A2B — nested chips/search (token ink-800)
    static let surfaceSecondary = Color(red: 38/255, green: 26/255, blue: 43/255)

    // MARK: Text
    static let textPrimary = Color.white
    /// #B6A8C0 — violet-tinted muted text (vault --text-muted)
    static let textSecondary = Color(red: 182/255, green: 168/255, blue: 192/255)

    // MARK: Borders
    static let border = Color.white.opacity(0.08)
    static let borderGold = Color(red: 212/255, green: 175/255, blue: 55/255).opacity(0.35)

    // MARK: Semantic
    static let success = Color(red: 63/255, green: 185/255, blue: 80/255)

    // MARK: rare-app shell (Main App Kit handoff)
    /// #B15AD1 — active/selected purple (floating tab bar).
    static let brandActive = Color(red: 177/255, green: 90/255, blue: 209/255)
    /// #E2C159 — soft-gold Create-button fill on Home.
    static let createCircle = Color(red: 226/255, green: 193/255, blue: 89/255)
    /// #D8C4E2 — inactive tab label (canonical --color-text-secondary).
    static let tabInactive = Color(red: 216/255, green: 196/255, blue: 226/255)

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
    /// "Spotlight" surface — bright purple top → vault bottom
    /// (#4A1D57 → #2A0E33 → #0C060F). The Home/create-flow surface,
    /// distinct from the flat vault used by the rest of the app.
    static let spotlight = LinearGradient(
        stops: [
            .init(color: Color(red: 74/255, green: 29/255, blue: 87/255), location: 0),
            .init(color: Color(red: 42/255, green: 14/255, blue: 51/255), location: 0.55),
            .init(color: Color(red: 12/255, green: 6/255, blue: 15/255), location: 1),
        ],
        startPoint: .top, endPoint: .bottom
    )
}
