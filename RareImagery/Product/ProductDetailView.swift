import SwiftUI
import RareImageryAPI

/// Public, read-only product detail page — what a visitor sees when they tap a
/// product on the creator's store (Page tab). Distinct from `ProductEditView`,
/// which is the owner-only editor. Renders the capture-frame hero, title,
/// price, description, and a Buy button that hands off to the web storefront.
///
/// Data comes from the shared `GET /api/products/[uuid]` contract so the
/// eventual Android / Next.js clients render the same thing.
struct ProductDetailView: View {
    let productId: String

    @Environment(AppState.self) private var state

    @State private var detail: ProductDetail?
    @State private var loading = true
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if loading {
                    ProgressView().tint(AppColor.gold)
                        .frame(maxWidth: .infinity).padding(.top, 80)
                } else if let detail {
                    hero(detail)
                    content(detail)
                } else {
                    Text(message ?? "Couldn't load this product.")
                        .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(.bottom, 32)
        }
        .background(AppColor.background)
        .navigationTitle("Product")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Hero

    @ViewBuilder private func hero(_ detail: ProductDetail) -> some View {
        // Phase 2: when `detail.videoUrl` is populated, replace this AsyncImage
        // with an AVPlayer that plays the capture clip. Until then the hero is
        // the video frame the BFF saved onto the product.
        AsyncImage(url: detail.heroImageUrl.flatMap { URL(string: $0) }) { phase in
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
    }

    // MARK: - Content

    @ViewBuilder private func content(_ detail: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(detail.isPublished ? "LIVE" : "DRAFT")
                .font(AppFont.mono(10, .semibold)).tracking(1.4)
                .foregroundStyle(detail.isPublished ? AppColor.success : AppColor.gold)

            Text(detail.title ?? "Untitled item")
                .font(AppFont.largeTitle).foregroundStyle(AppColor.textPrimary)

            if let priceText = formattedPrice(detail.price) {
                Text(priceText).font(AppFont.mono(22, .bold)).foregroundStyle(AppColor.gold)
            }

            if let description = detail.description, !description.isEmpty {
                Text(description).font(AppFont.body).foregroundStyle(AppColor.textSecondary)
            }

            buyButton(detail)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    @ViewBuilder private func buyButton(_ detail: ProductDetail) -> some View {
        if let urlString = detail.storefrontUrl, let url = URL(string: urlString) {
            Link(destination: url) {
                Text("Buy")
                    .font(AppFont.buttonLabel).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(AppColor.cta, in: Capsule())
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Helpers

    /// `$12` / `$12.50` — drops trailing `.00`, matching StoreProduct.priceDisplay.
    private func formattedPrice(_ price: Decimal?) -> String? {
        guard let price else { return nil }
        let n = price as NSDecimalNumber
        let whole = n.doubleValue == n.rounding(accordingToBehavior: nil).doubleValue
            && n.doubleValue.truncatingRemainder(dividingBy: 1) == 0
        return whole ? "$\(n.intValue)" : "$" + String(format: "%.2f", n.doubleValue)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            detail = try await state.productRepository.get(uuid: productId)
        } catch {
            message = "Couldn't load this product. Pull back and retry."
        }
    }
}
