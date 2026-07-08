import SwiftUI
import RareImageryAPI

/// Lightweight display model so Discover + My Circle share one avatar-first row.
struct CircleMemberDisplay: Identifiable {
    let xUserID: String
    let username: String
    let displayName: String
    let profileImageURL: String?

    var id: String { xUserID }
}

extension CircleMember {
    var display: CircleMemberDisplay {
        CircleMemberDisplay(
            xUserID: xUserID,
            username: username,
            displayName: displayName,
            profileImageURL: profileImageURL
        )
    }
}

extension XUserSummary {
    func toCircleMemberDisplay() -> CircleMemberDisplay {
        CircleMemberDisplay(
            xUserID: id,
            username: handle,
            displayName: name,
            profileImageURL: avatar
        )
    }
}

struct CircleMemberRow: View {
    let member: CircleMemberDisplay
    let isInCircle: Bool
    let isFavorited: Bool
    let onAdd: () -> Void
    let onToggleFavorite: () -> Void
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 16) {
                avatar

                VStack(alignment: .leading, spacing: 4) {
                    Text(member.displayName)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)

                    Text("@\(member.username)")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    if !isInCircle {
                        Button(action: onAdd) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppColor.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add to circle")
                    }

                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorited ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(isFavorited ? .pink : AppColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFavorited ? "Remove favorite" : "Favorite")
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    @ViewBuilder
    private var avatar: some View {
        AsyncImage(url: member.profileImageURL.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Circle()
                    .fill(AppColor.surfaceSecondary)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(AppColor.textSecondary)
                    }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(AppColor.border, lineWidth: 1)
        }
    }
}

struct CircleProfileSheet: View {
    let user: XUserSummary
    let isInCircle: Bool
    let isFavorited: Bool
    let onAddToCircle: () -> Void
    let onToggleFavorite: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                AsyncImage(url: user.avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Circle()
                            .fill(AppColor.surfaceSecondary)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(AppColor.border, lineWidth: 1)
                }

                VStack(spacing: 6) {
                    Text(user.name)
                        .font(AppFont.title)
                    Text("@\(user.handle)")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                HStack(spacing: 20) {
                    if !isInCircle {
                        Button {
                            onAddToCircle()
                        } label: {
                            Label("Add to Circle", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColor.accent)
                    }

                    Button(action: onToggleFavorite) {
                        Label(
                            isFavorited ? "Favorited" : "Favorite",
                            systemImage: isFavorited ? "heart.fill" : "heart"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(isFavorited ? .pink : AppColor.accent)
                }

                Text("Ask for feedback on my next drop")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary.opacity(0.7))

                Spacer()
            }
            .padding(24)
            .background(AppColor.background)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
