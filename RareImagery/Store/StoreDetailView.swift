import SwiftUI
import RareImageryAPI

/// A creator's public store, browsed from Friends (and later the Shop tab):
/// their X hero over a grid of published products, each tapping into the
/// read-only ProductDetailView → Buy. Data: GET /api/discover/stores/{slug}.
struct StoreDetailView: View {
    let slug: String

    @Environment(AppState.self) private var state

    @State private var detail: StoreDetail?
    @State private var loading = true
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if loading {
                    ProgressView().tint(AppColor.gold).padding(.top, 80)
                } else if let detail {
                    LiveStorePreview(
                        displayName: detail.profile.displayName ?? detail.profile.handle,
                        handle: detail.profile.handle,
                        bio: detail.profile.bio ?? "",
                        avatarURL: detail.profile.avatarURL,
                        bannerURL: detail.profile.bannerURL,
                        colorScheme: .default,
                        slug: detail.profile.slug
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    productsSection(detail.products)
                } else {
                    Text(message ?? "Couldn't load this store.")
                        .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                        .padding(.top, 80)
                }
            }
            .padding(.bottom, 24)
        }
        .background(AppColor.background)
        .navigationTitle("Store")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder private func productsSection(_ products: [StoreProduct]) -> some View {
        if products.isEmpty {
            ContentUnavailableView(
                "Nothing for sale yet",
                systemImage: "storefront",
                description: Text("This store hasn't published any products.")
            )
            .padding(.top, 12)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(products) { product in
                    NavigationLink {
                        ProductDetailView(productId: product.id)
                            .environment(state)
                    } label: {
                        card(product)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func card(_ product: StoreProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: product.imageUrl.flatMap { URL(string: $0) }) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: AppColor.surface.overlay(
                    Image(systemName: "photo").foregroundStyle(AppColor.textSecondary)
                )
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(product.title ?? "Untitled item")
                .font(AppFont.bodyText(14)).foregroundStyle(AppColor.textPrimary)
                .lineLimit(2)
            if let priceDisplay = product.priceDisplay {
                Text(priceDisplay).font(AppFont.mono(14)).foregroundStyle(AppColor.gold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColor.border, lineWidth: 1))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            detail = try await state.storeDiscoveryRepository.store(slug: slug)
        } catch {
            message = "Couldn't load this store. Go back and retry."
        }
    }
}
