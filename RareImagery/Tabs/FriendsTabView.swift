import SwiftUI
import RareImageryAPI

/// Friends tab — everyone you follow on X (pfp + name). Friends with a
/// RareImagery store show a store chip and tap into their native store page.
/// Replaces the old three-segment Circle tab with one list.
struct FriendsTabView: View {
    @Environment(AppState.self) private var state

    @State private var friends: [FriendSummary] = []
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if loading && friends.isEmpty {
                        ProgressView().tint(AppColor.gold).padding(.top, 60)
                    } else if friends.isEmpty {
                        ContentUnavailableView(
                            "No friends yet",
                            systemImage: "person.2",
                            description: Text(message ?? "People you follow on X show up here — with their store when they have one.")
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(friends) { friend in
                            if let slug = friend.storeSlug, !slug.isEmpty {
                                NavigationLink {
                                    StoreDetailView(slug: slug)
                                        .environment(state)
                                } label: {
                                    row(friend)
                                }
                                .buttonStyle(.plain)
                            } else {
                                row(friend)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(AppColor.background)
            .navigationTitle("Friends")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func row(_ friend: FriendSummary) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: friend.avatarURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default:
                    Circle().fill(AppColor.surfaceSecondary).overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(AppColor.textSecondary)
                    )
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())
            .overlay(Circle().stroke(friend.hasStore ? AppColor.borderGold : AppColor.border, lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(AppFont.bodyText(16, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text("@\(friend.handle)")
                    .font(AppFont.mono(12))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if friend.hasStore {
                HStack(spacing: 5) {
                    Image(systemName: "storefront")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Store")
                        .font(AppFont.mono(11, .semibold))
                }
                .foregroundStyle(AppColor.gold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColor.goldSoft, in: Capsule())
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(12)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColor.border, lineWidth: 1))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            friends = try await state.circleRepository.fetchFriends()
            message = nil
        } catch {
            message = "Couldn't load your friends. Pull to retry."
        }
    }
}
