import SwiftUI
import RareImageryAPI

/// Products tab — browse + search every published product across all approved
/// creator stores (GET /api/discover/products). Took Friends' slot in the tab
/// bar. Distinct from "My Products" (the creator's own listings). Tap a card
/// for a read-only detail with a Buy hand-off and a link into the store.
struct BrowseProductsView: View {
    @Environment(AppState.self) private var state

    @State private var products: [StoreProduct] = []
    @State private var loading = false
    @State private var message: String?
    @State private var query = ""

    private var filtered: [StoreProduct] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return products }
        return products.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(q)
                || ($0.description ?? "").localizedCaseInsensitiveContains(q)
                || ($0.storeName ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if loading && products.isEmpty {
                    ProgressView().tint(AppColor.gold).padding(.top, 60)
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        products.isEmpty ? "No products yet" : "No matches",
                        systemImage: "square.grid.2x2",
                        description: Text(
                            products.isEmpty
                                ? (message ?? "Products from creators show up here as they go live.")
                                : "Nothing matches “\(query)”."
                        )
                    )
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(filtered) { product in
                            NavigationLink {
                                BrowseProductDetailView(product: product)
                                    .environment(state)
                            } label: {
                                card(product)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .background(AppColor.background)
            .navigationTitle("Products")
            .searchable(text: $query, prompt: "Search products")
            .refreshable { await load() }
            .task { await load() }
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
            if let store = product.storeName {
                Text("@\(store)")
                    .font(AppFont.mono(11)).foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
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
            products = try await state.storeDiscoveryRepository.listProducts()
            message = nil
        } catch {
            message = "Couldn't load products. Pull to retry."
        }
    }
}

/// Read-only detail for a browsed product, rendered from the list row we
/// already have — GET /api/products/{uuid} is owner-scoped, so cross-store
/// browse never refetches. Buy links to the web storefront; the store row
/// pushes the creator's native store page.
struct BrowseProductDetailView: View {
    let product: StoreProduct

    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AsyncImage(url: product.imageUrl.flatMap { URL(string: $0) }) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default:
                        AppColor.surface.overlay(
                            Image(systemName: "photo").font(.system(size: 34))
                                .foregroundStyle(AppColor.textSecondary)
                        )
                    }
                }
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipped()

                VStack(alignment: .leading, spacing: 14) {
                    Text(product.title ?? "Untitled item")
                        .font(AppFont.largeTitle).foregroundStyle(AppColor.textPrimary)

                    if let priceDisplay = product.priceDisplay {
                        Text(priceDisplay).font(AppFont.mono(22, .bold)).foregroundStyle(AppColor.gold)
                    }

                    if let slug = product.storeSlug {
                        NavigationLink {
                            StoreDetailView(slug: slug)
                                .environment(state)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "storefront")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("@\(product.storeName ?? slug)")
                                    .font(AppFont.mono(13, .semibold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(AppColor.gold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColor.goldSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if let description = product.description, !description.isEmpty {
                        Text(description).font(AppFont.body).foregroundStyle(AppColor.textSecondary)
                    }

                    if let urlString = product.storefrontUrl, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Text("Buy")
                                .font(AppFont.buttonLabel).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(AppColor.cta, in: Capsule())
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .padding(.bottom, 32)
        }
        .background(AppColor.background)
        .navigationTitle("Product")
        .navigationBarTitleDisplayMode(.inline)
    }
}
