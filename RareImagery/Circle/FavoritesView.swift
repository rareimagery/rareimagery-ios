import SwiftUI

struct FavoritesView: View {
    let favorites: [FavoriteItem]
    let onDiscover: () -> Void

    var body: some View {
        if favorites.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "heart.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColor.cta)
                Text("No favorites yet")
                    .font(AppFont.headline)
                Text("Heart creators while discovering to save them here.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Discover creators", action: onDiscover)
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.accent)
                Spacer()
            }
        } else {
            List(favorites) { item in
                HStack(spacing: 12) {
                    if let urlString = item.imageURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(AppColor.surface)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(AppColor.surface)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: icon(for: item.itemType))
                                    .foregroundStyle(AppColor.accent)
                            }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(AppFont.headline)
                        Text(item.itemType.label)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .listRowBackground(AppColor.background)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func icon(for type: FavoriteType) -> String {
        switch type {
        case .creator: return "person.fill"
        case .productDraft: return "doc.fill"
        case .design: return "paintbrush.fill"
        }
    }
}
