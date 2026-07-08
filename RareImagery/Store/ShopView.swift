import SwiftUI
import RareImageryAPI

/// Shop — the tab bar's center button: browse every approved creator store,
/// tap into a native store page. Powered by GET /api/discover/stores.
struct ShopView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var stores: [StoreSummary] = []
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if loading && stores.isEmpty {
                        ProgressView().tint(AppColor.gold).padding(.top, 60)
                    } else if stores.isEmpty {
                        ContentUnavailableView(
                            "No stores yet",
                            systemImage: "bag",
                            description: Text(message ?? "Creator stores show up here as they go live.")
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(stores) { store in
                            NavigationLink {
                                StoreDetailView(slug: store.slug)
                                    .environment(state)
                            } label: {
                                row(store)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(AppColor.background)
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColor.gold)
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func row(_ store: StoreSummary) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: store.avatarURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default:
                    Circle().fill(AppColor.surfaceSecondary).overlay(
                        Image(systemName: "storefront")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColor.textSecondary)
                    )
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())
            .overlay(Circle().stroke(AppColor.borderGold, lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(store.displayName ?? store.handle)
                    .font(AppFont.bodyText(16, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text("@\(store.handle)")
                    .font(AppFont.mono(12))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(12)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColor.border, lineWidth: 1))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            stores = try await state.storeDiscoveryRepository.listStores()
            message = nil
        } catch {
            message = "Couldn't load stores. Pull to retry."
        }
    }
}
