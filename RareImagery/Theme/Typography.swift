import SwiftUI

/// RareImagery type system — app-wide refresh (2026-06-25).
/// Display = Space Grotesk · Body = Hanken Grotesk · Mono = JetBrains Mono.
///
/// `Font.custom(family, size:)` falls back to the system font when the family
/// isn't registered, so this is safe to ship before the TTFs are bundled
/// (Phase 1b: add the OFL TTFs + `UIAppFonts`). Once bundled, `.weight(_)`
/// selects the matching face. Existing `AppFont.*` names are preserved so all
/// call-sites keep working.
enum AppFont {
    // Families (registered names). System fallback until TTFs are added.
    private static let displayFamily = "SpaceGrotesk"
    private static let bodyFamily = "HankenGrotesk"
    private static let monoFamily = "JetBrainsMono"

    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom(displayFamily, size: size).weight(weight)
    }
    static func bodyText(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(bodyFamily, size: size).weight(weight)
    }
    /// Mono — eyebrows, prices, catalog labels (new in the refresh).
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(monoFamily, size: size).weight(weight)
    }

    static let largeTitle = display(34, .bold)
    static let title = display(28, .bold)
    static let headline = display(20, .semibold)
    static let subheadline = bodyText(15)
    static let body = bodyText(17)
    static let callout = bodyText(16)
    static let caption = bodyText(13)
    static let buttonLabel = display(17, .semibold)
}
