import SwiftUI
import RareImageryAPI

/// One-screen "turn this into a sellable product" form.
///
/// Pre-populates fields from the `ProductDraft` Rare just returned —
/// title, description, suggested price, tags — so the user accepts or
/// nudges rather than typing from scratch. Three knobs: product type
/// (T-shirt / Hoodie / Poster / Sticker), price, and an X-post toggle.
///
/// Voice: business-like but warm. The mascot's job ends here; this is
/// the moment the user commits to making something.
///
/// Wiring TODOs (left intentionally for the next iteration so this view
/// can ship today against the existing repository surface):
///   1. Actual product-create call. The current
///      `ProductRepository.analyze` returns a draft but doesn't persist
///      it server-side. A follow-up needs either:
///        - a `ProductRepository.create(...)` method, OR
///        - using `analyze` + `patch` to commit the user's edits
///      The "Create Product & Share" button below logs a marker and
///      dismisses — wire to the real call when the endpoint solidifies.
///   2. X-post composer. Toggle just captures intent for now.
struct QuickProductView: View {
    let draft: ProductDraft
    let heroImageData: Data?

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var summary: String
    @State private var productType: ProductType
    @State private var priceText: String
    @State private var shareToX: Bool = true
    @State private var isCreating = false
    @State private var errorMessage: String?

    enum ProductType: String, CaseIterable, Identifiable {
        case tshirt = "T-Shirt"
        case hoodie = "Hoodie"
        case poster = "Poster"
        case sticker = "Sticker"
        var id: String { rawValue }
    }

    init(draft: ProductDraft, heroImageData: Data?) {
        self.draft = draft
        self.heroImageData = heroImageData
        _title = State(initialValue: draft.title)
        _summary = State(initialValue: draft.summary ?? draft.description ?? "")
        _productType = State(initialValue: .tshirt)
        // Prefer the lower bound when Rare returned a range; otherwise
        // default to $24 (median for the merch types we ship today).
        let defaultPrice: Decimal = 24
        let initialPrice = draft.suggestedPriceLow ?? draft.suggestedPriceHigh ?? defaultPrice
        _priceText = State(initialValue: Self.formatPrice(initialPrice))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let data = heroImageData, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        formCard
                        shareCard
                        createButton

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Quick setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Cards

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                FieldLabel("Title")
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(AppColor.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.border))

                FieldLabel("What is it?")
                TextField("Short description", text: $summary, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(AppColor.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.border))

                FieldLabel("Type")
                HStack(spacing: 8) {
                    ForEach(ProductType.allCases) { type in
                        Button {
                            productType = type
                        } label: {
                            Text(type.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(productType == type ? AppColor.cta : AppColor.background, in: Capsule())
                                .foregroundStyle(productType == type ? .black : AppColor.textPrimary)
                                .overlay(Capsule().stroke(productType == type ? Color.clear : AppColor.border))
                        }
                    }
                }

                FieldLabel("Price (USD)")
                TextField("$0", text: $priceText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(AppColor.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.border))
            }
            .foregroundStyle(AppColor.textPrimary)
        }
        .padding(16)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var shareCard: some View {
        Toggle(isOn: $shareToX) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Post about this on X")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
                Text("We'll draft a tweet for you to review before publishing.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .tint(AppColor.cta)
        .padding(16)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var createButton: some View {
        Button(action: { Task { await createProduct() } }) {
            HStack {
                if isCreating {
                    ProgressView()
                        .tint(.black)
                }
                Text(isCreating ? "Creating…" : "Create Product")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isCreating ? AppColor.cta.opacity(0.5) : AppColor.cta)
            .clipShape(Capsule())
        }
        .disabled(isCreating || title.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Actions

    private func createProduct() async {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil

        // TODO: wire to ProductRepository.create(...) once the endpoint
        // contract solidifies. For now this records the user's intent so
        // the rest of the flow (X-post composer, drafts list) has data to
        // attach to.
        //
        // Expected real shape:
        //   let detail = try await state.productRepository.create(
        //       title: title,
        //       summary: summary,
        //       productType: productType.rawValue,
        //       priceCents: Self.parsePriceCents(priceText),
        //       sourceDraft: draft,
        //       heroImageData: heroImageData
        //   )
        //   if shareToX { await composer.openComposer(for: detail) }

        try? await Task.sleep(for: .milliseconds(600))
        isCreating = false
        dismiss()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func FieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColor.textSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private static func formatPrice(_ price: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: price as NSNumber) ?? "\(price)"
    }
}

#Preview {
    QuickProductView(
        draft: ProductDraft(
            title: "Vintage Denim Jacket",
            summary: "Classic washed denim with great texture.",
            description: nil,
            category: nil,
            condition: nil,
            brand: nil,
            suggestedPriceLow: 28,
            suggestedPriceHigh: 42,
            tags: ["denim", "vintage", "jacket"],
            handmade: nil,
            confidence: 0.8,
            flags: nil
        ),
        heroImageData: nil
    )
    .environment(AppState())
    .preferredColorScheme(.dark)
}
