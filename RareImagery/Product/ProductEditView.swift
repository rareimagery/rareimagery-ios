import SwiftUI
import RareImageryAPI

/// Edit a product — title, description, price — then publish it to the store.
/// Reached by tapping a row in the Products tab. Loads the full detail, lets
/// the creator refine Grok's draft, saves via PATCH, and publishes via POST
/// /publish.
struct ProductEditView: View {
    let productId: String
    var onChange: (() -> Void)? = nil

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var loaded: ProductDetail?
    @State private var title = ""
    @State private var description = ""
    @State private var priceText = ""
    @State private var loading = true
    @State private var saving = false
    @State private var publishing = false
    @State private var message: String?

    private var isPublished: Bool { loaded?.isPublished ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if loading {
                    ProgressView().tint(AppColor.gold)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    statusBadge

                    field("Title") {
                        TextField("Product title", text: $title, axis: .vertical)
                            .textFieldStyle(.plain)
                    }
                    field("Description") {
                        TextField("Describe your item", text: $description, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(4...10)
                    }
                    field("Price (USD)") {
                        HStack(spacing: 4) {
                            Text("$").foregroundStyle(AppColor.gold)
                            TextField("0.00", text: $priceText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.plain)
                        }
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Text(saving ? "Saving…" : "Save changes")
                            .font(AppFont.buttonLabel).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(AppColor.surfaceSecondary, in: Capsule())
                    }
                    .disabled(saving || publishing)

                    if !isPublished {
                        Button {
                            Task { await saveThenPublish() }
                        } label: {
                            Text(publishing ? "Publishing…" : "Publish to store")
                                .font(AppFont.buttonLabel).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(AppColor.cta, in: Capsule())
                        }
                        .disabled(saving || publishing)
                    }

                    if let message {
                        Text(message).font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .padding(20)
        }
        .background(AppColor.background)
        .navigationTitle("Edit product")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var statusBadge: some View {
        Text(isPublished ? "LIVE ON STORE" : "UNPUBLISHED")
            .font(AppFont.mono(10, .semibold)).tracking(1.4)
            .foregroundStyle(isPublished ? AppColor.success : AppColor.gold)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(AppFont.mono(10, .semibold)).tracking(1.2)
                .foregroundStyle(AppColor.textSecondary)
            content()
                .font(AppFont.body).foregroundStyle(AppColor.textPrimary)
                .padding(12)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColor.border, lineWidth: 1))
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let detail = try await state.productRepository.get(uuid: productId)
            loaded = detail
            title = detail.title ?? ""
            description = detail.description ?? ""
            if let price = detail.price { priceText = "\(price as NSDecimalNumber)" }
        } catch {
            message = "Couldn't load this product."
        }
    }

    private func patchRequest() -> ProductPatchRequest {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = Decimal(string: priceText.replacingOccurrences(of: ",", with: ""))
        return ProductPatchRequest(
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            description: description,
            price: price
        )
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            loaded = try await state.productRepository.patch(uuid: productId, fields: patchRequest())
            message = "Saved."
            onChange?()
        } catch {
            message = "Save failed. Check the price and try again."
        }
    }

    private func saveThenPublish() async {
        publishing = true
        defer { publishing = false }
        do {
            _ = try await state.productRepository.patch(uuid: productId, fields: patchRequest())
            loaded = try await state.productRepository.publish(uuid: productId)
            message = "Published — it's live on your store."
            onChange?()
        } catch {
            message = "Couldn't publish. Make sure the price is set."
        }
    }
}
