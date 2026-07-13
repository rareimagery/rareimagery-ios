import SwiftUI
import RareImageryAPI

/// DEBUG: lists products from Drupal JSON:API (`commerce_product/{type}`).
/// Default type is the ruled `capture` bundle; DEBUG picker can probe
/// live `default` / `physical` until Task 4a lands.
struct JSONAPIProductsDebugView: View {
    @Environment(AppState.self) private var state

    @State private var products: [Product] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var productType = "capture"

    private let types = ["capture", "default", "physical"]

    var body: some View {
        List {
            Section {
                Picker("Bundle", selection: $productType) {
                    ForEach(types, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: productType) { _, _ in
                    Task { await load() }
                }
            }

            if loading && products.isEmpty {
                Section {
                    ProgressView()
                }
            } else if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .font(AppFont.caption)
                        .foregroundStyle(.red)
                }
            } else if products.isEmpty {
                Section {
                    Text("No products in `\(productType)`.")
                        .foregroundStyle(AppColor.textSecondary)
                }
            } else {
                Section("\(products.count) products") {
                    ForEach(products) { product in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(product.title)
                                    .font(AppFont.bodyText(15, .semibold))
                                Spacer()
                                Text(product.isLive ? "LIVE" : "DRAFT")
                                    .font(AppFont.mono(10, .semibold))
                                    .foregroundStyle(product.isLive ? AppColor.success : AppColor.gold)
                            }
                            if !product.descriptionText.isEmpty {
                                Text(product.descriptionText)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                                    .lineLimit(2)
                            }
                            Text(product.id)
                                .font(AppFont.mono(10))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("JSON:API products")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            products = try await state.productRepository.myProducts(productType: productType)
            errorMessage = nil
        } catch let error as APIError {
            products = []
            if case .notFound = error {
                errorMessage = "Bundle `\(productType)` not found (404). Capture lands with Drupal Task 4a — try `default`."
            } else {
                errorMessage = error.userFacingMessage
            }
        } catch {
            products = []
            errorMessage = error.localizedDescription
        }
    }
}
