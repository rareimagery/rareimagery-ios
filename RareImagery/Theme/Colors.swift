import SwiftUI

enum AppColor {
    /// #0a0a0a — main background
    static let background = Color(red: 10/255, green: 10/255, blue: 10/255)
    /// #171717 — elevated surfaces (cards, inputs)
    static let surface = Color(red: 23/255, green: 23/255, blue: 23/255)
    /// #7c3aed — brand accent (buttons, links, hero)
    static let accent = Color(red: 124/255, green: 58/255, blue: 237/255)
    /// #FF6B00 — primary CTA orange (Sign in, Continue, Make sellable).
    /// Warmer than the purple accent — fits onboarding + capture-result
    /// surfaces where Rare's mascot is in play. Promoted out of
    /// OnboardingView's private extension on 2026-05-23 so the welcome
    /// and capture-result views can share it.
    static let cta = Color(red: 255/255, green: 107/255, blue: 0/255)
    /// White, primary text
    static let textPrimary = Color.white
    /// Muted text for secondary lines
    static let textSecondary = Color(red: 0.65, green: 0.65, blue: 0.7)
    /// Subtle border lines
    static let border = Color.white.opacity(0.08)
}
