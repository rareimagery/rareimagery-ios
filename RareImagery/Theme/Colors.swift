import SwiftUI

enum AppColor {
    /// #0a0a0a — main background
    static let background = Color(red: 10/255, green: 10/255, blue: 10/255)
    /// #171717 — elevated surfaces (cards, inputs)
    static let surface = Color(red: 23/255, green: 23/255, blue: 23/255)
    /// #7c3aed — brand accent (buttons, links, hero)
    static let accent = Color(red: 124/255, green: 58/255, blue: 237/255)
    /// White, primary text
    static let textPrimary = Color.white
    /// Muted text for secondary lines
    static let textSecondary = Color(red: 0.65, green: 0.65, blue: 0.7)
    /// Subtle border lines
    static let border = Color.white.opacity(0.08)
}
