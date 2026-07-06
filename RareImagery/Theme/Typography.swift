import SwiftUI

/// RareImagery type system — app-wide refresh (2026-06-25).
/// Display = Space Grotesk · Body = Hanken Grotesk · Mono = JetBrains Mono.
///
/// The OFL TTFs are bundled (RareImagery/Fonts + UIAppFonts in project.yml)
/// as of 2026-07-06; `.weight(_)` selects the matching static face. The family
/// strings must be the fonts' real family names (with spaces) — the earlier
/// no-space names never matched, so everything silently fell back to system.
enum AppFont {
    // Registered family names (from the TTFs' name tables).
    private static let displayFamily = "Space Grotesk"
    private static let bodyFamily = "Hanken Grotesk"
    private static let monoFamily = "JetBrains Mono"

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
