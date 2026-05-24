import SwiftUI
import RareImageryAPI

/// Compact visual preview of a creator's storefront, rendered from the
/// data we already have at sign-in: X banner + avatar + display name +
/// handle + bio + a color-scheme accent strip.
///
/// Used by `LivePreviewView` (the "You're live" onboarding screen) and
/// by `TweakSheetView` (where the preview updates live as the user
/// changes color/slug/bio). Keep it pure — no API calls, no state of
/// its own. All inputs come from the parent's bindings.
///
/// Visual hierarchy mirrors the web storefront's hero section:
///   ┌───────────────────────────┐
///   │  [banner image]           │
///   │   [avatar]                │
///   │   Display Name            │
///   │   @handle                 │
///   │   bio first sentence …    │
///   │   ▓▓▓ accent strip ▓▓▓    │
///   └───────────────────────────┘
struct LiveStorePreview: View {
    let displayName: String
    let handle: String
    let bio: String
    let avatarURL: URL?
    let bannerURL: URL?
    let colorScheme: ColorSchemeOption
    let slug: String

    /// Each color option carries both a hex value (for the accent strip)
    /// and a display label (for the swatch grid in TweakSheetView).
    struct ColorSchemeOption: Identifiable, Equatable {
        let id: String        // "midnight" | "ocean" | "forest" | …
        let label: String     // "Midnight" | "Ocean" | …
        let accentHex: String // "#7c3aed" | …

        var accentColor: Color {
            Color(hex: accentHex) ?? AppColor.accent
        }

        /// The 10 swatches matching `field_color_scheme` allowed values
        /// on Drupal + COLOR_SCHEMES in Next.js src/lib/color-schemes.ts.
        /// Keep this list in sync with both.
        static let all: [ColorSchemeOption] = [
            .init(id: "midnight", label: "Midnight", accentHex: "#7c3aed"),
            .init(id: "ocean",    label: "Ocean",    accentHex: "#0ea5e9"),
            .init(id: "forest",   label: "Forest",   accentHex: "#10b981"),
            .init(id: "sunset",   label: "Sunset",   accentHex: "#f97316"),
            .init(id: "royal",    label: "Royal",    accentHex: "#6366f1"),
            .init(id: "cherry",   label: "Cherry",   accentHex: "#ef4444"),
            .init(id: "arctic",   label: "Arctic",   accentHex: "#38bdf8"),
            .init(id: "ember",    label: "Ember",    accentHex: "#dc2626"),
            .init(id: "slate",    label: "Slate",    accentHex: "#64748b"),
            .init(id: "neon",     label: "Neon",     accentHex: "#a3e635"),
        ]

        static let `default` = all[0] // midnight
    }

    var body: some View {
        VStack(spacing: 0) {
            // Banner — clip in a rounded top
            bannerSection
                .frame(height: 100)
                .clipShape(UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 18, topTrailing: 18)
                ))

            VStack(spacing: 12) {
                // Avatar overlaps the banner edge
                avatarSection
                    .offset(y: -40)
                    .padding(.bottom, -32) // claw back space the offset added

                VStack(spacing: 4) {
                    Text(displayName.isEmpty ? "Your name" : displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)

                    Text("@\(handle)")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textSecondary)
                }

                if !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textSecondary.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 16)
                }

                // Accent strip — the visual signature of the chosen color
                Rectangle()
                    .fill(colorScheme.accentColor)
                    .frame(height: 4)
                    .clipShape(Capsule())
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                // URL chip — drives home "this is YOUR website"
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                    Text("\(slug).rareimagery.net")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColor.background, in: Capsule())
                .overlay(Capsule().stroke(AppColor.border, lineWidth: 1))
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppColor.border, lineWidth: 1)
        )
    }

    // MARK: Section views

    @ViewBuilder private var bannerSection: some View {
        if let bannerURL {
            AsyncImage(url: bannerURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    bannerFallback
                @unknown default:
                    bannerFallback
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
        } else {
            bannerFallback
        }
    }

    private var bannerFallback: some View {
        LinearGradient(
            colors: [
                colorScheme.accentColor.opacity(0.6),
                colorScheme.accentColor.opacity(0.2),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var avatarSection: some View {
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        avatarFallback
                    @unknown default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().stroke(AppColor.surface, lineWidth: 3))
    }

    private var avatarFallback: some View {
        Circle()
            .fill(AppColor.background)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppColor.textSecondary)
            }
    }
}

// MARK: - Color hex helper

private extension Color {
    /// Parse a hex string like "#7c3aed" or "7c3aed" into a SwiftUI Color.
    /// Returns nil on parse failure (caller falls back to AppColor.accent).
    init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6,
              let value = UInt32(trimmed, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    VStack(spacing: 16) {
        LiveStorePreview(
            displayName: "Rare Imagery",
            handle: "rareimagery",
            bio: "Photography that hits different. Building stores for creators on Rare.",
            avatarURL: URL(string: "https://i.pravatar.cc/150?img=12"),
            bannerURL: nil,
            colorScheme: .all[0],
            slug: "rareimagery"
        )

        LiveStorePreview(
            displayName: "Bud Hound",
            handle: "budhound",
            bio: "Bandanas, vibes, and very good boys.",
            avatarURL: nil,
            bannerURL: nil,
            colorScheme: .all[5], // cherry
            slug: "budhound"
        )
    }
    .padding(20)
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
