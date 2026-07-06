import SwiftUI
import RareImageryAPI

struct HomeTabView: View {
    @Environment(AppState.self) private var state
    @State private var showVideoCreate = false
    @State private var showPhotoCapture = false
    @State private var showOnePageCreator = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    VStack(spacing: 10) {
                        Text("Add a product")
                            .font(AppFont.largeTitle)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Film it — Grok drafts the whole listing.")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    // Primary = the SAME video → Grok Vision flow as sign-up.
                    // Authenticated, so the BFF binds the resulting draft to
                    // this creator (owned, editable product in their store).
                    Button {
                        showVideoCreate = true
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 34, weight: .semibold))
                            Text("Create")
                                .font(.system(size: 22, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .frame(width: 180, height: 180)
                        .background(AppColor.cta, in: Circle())
                        .shadow(color: AppColor.cta.opacity(0.35), radius: 24, y: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create product from video")

                    VStack(spacing: 6) {
                        Button {
                            showPhotoCapture = true
                        } label: {
                            Text("Use photos instead")
                                .font(AppFont.bodyText(14))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        Button {
                            showOnePageCreator = true
                        } label: {
                            Text("Design merch instead")
                                .font(AppFont.bodyText(14))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    Spacer()
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showVideoCreate) {
                VideoSubmissionFunnelView(onExit: { showVideoCreate = false }, productMode: true)
                    .environment(state)
            }
            .fullScreenCover(isPresented: $showPhotoCapture) {
                FirstProductFlowView()
                    .environment(state)
            }
            .fullScreenCover(isPresented: $showOnePageCreator) {
                OnePageCreatorHostView()
                    .environment(state)
            }
        }
    }
}

/// Products tab — every product the signed-in creator has made (drafts +
/// live), from GET /api/stores/products. Unpublished drafts get a Publish
/// action inline; this is where the pre-sign-in funnel video also lands.
struct ProductsTabView: View {
    @Environment(AppState.self) private var state
    @State private var products: [StoreProduct] = []
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if loading && products.isEmpty {
                        ProgressView().tint(AppColor.gold).padding(.top, 60)
                    } else if products.isEmpty {
                        ContentUnavailableView(
                            "No products yet",
                            systemImage: "bag",
                            description: Text("Tap Create on the Home tab, film an item, and Grok drafts the listing.")
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(products) { product in
                            NavigationLink {
                                ProductEditView(productId: product.id, onChange: { Task { await load() } })
                                    .environment(state)
                            } label: {
                                productCard(product)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let message {
                        Text(message).font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary).padding(.top, 4)
                    }
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
            }
            .background(AppColor.background)
            .navigationTitle("Products")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func productCard(_ product: StoreProduct) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(product.isPublished ? "LIVE" : "DRAFT")
                .font(AppFont.mono(10, .semibold)).tracking(1.4)
                .foregroundStyle(product.isPublished ? AppColor.success : AppColor.gold)
            Text(product.title ?? "Untitled item")
                .font(AppFont.headline).foregroundStyle(AppColor.textPrimary)
            if let description = product.description, !description.isEmpty {
                Text(description).font(AppFont.bodyText(13))
                    .foregroundStyle(AppColor.textSecondary).lineLimit(3)
            }
            HStack {
                if let priceDisplay = product.priceDisplay {
                    Text(priceDisplay).font(AppFont.mono(15)).foregroundStyle(AppColor.gold)
                } else if !product.isPublished {
                    Text("Set a price →").font(AppFont.bodyText(13)).foregroundStyle(AppColor.gold)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(product.isPublished ? AppColor.border : AppColor.borderGold, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            products = try await state.productRepository.listMine()
            message = nil
        } catch {
            message = "Couldn't load your products. Pull to retry."
        }
    }

}

/// Page tab — the creator's public-facing storefront as visitors see it:
/// X avatar + banner (captured at account creation) over the grid of
/// products they've published. Read-only preview; editing lives in Products.
struct PageTabView: View {
    @Environment(AppState.self) private var state
    @State private var profile: StoreProfile?
    @State private var published: [StoreProduct] = []
    @State private var loading = false

    private var handle: String { state.session.claims?.handle ?? "yourname" }
    private var slug: String { profile?.storeSlug ?? state.session.claims?.slug ?? handle }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    LiveStorePreview(
                        displayName: profile?.displayName ?? state.session.displayHandle ?? "Your name",
                        handle: handle,
                        bio: profile?.bio ?? "",
                        avatarURL: profile?.avatarURL,
                        bannerURL: profile?.bannerURL,
                        colorScheme: .default,
                        slug: slug
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    publishedSection
                }
            }
            .background(AppColor.background)
            .navigationTitle("Page")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    @ViewBuilder private var publishedSection: some View {
        if loading && published.isEmpty {
            ProgressView().tint(AppColor.gold).padding(.top, 30)
        } else if published.isEmpty {
            ContentUnavailableView(
                "No live products yet",
                systemImage: "storefront",
                description: Text("Publish a product from the Products tab and it shows up here on your store page.")
            )
            .padding(.top, 20)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(published) { product in
                    storeCard(product)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func storeCard(_ product: StoreProduct) -> some View {
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
        async let profileResult = try? await state.productRepository.myProfile()
        async let productsResult = (try? await state.productRepository.listMine()) ?? []
        profile = await profileResult
        published = await productsResult.filter { $0.isPublished }
    }
}

struct ProfileTabView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            List {
                if let handle = state.session.displayHandle {
                    Section {
                        LabeledContent("Handle", value: "@\(handle)")
                        if let slug = state.session.claims?.slug {
                            LabeledContent("Store", value: "\(slug).rareimagery.net")
                        }
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await state.signOut() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColor.background)
            .navigationTitle("Profile")
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeTabView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            CircleTabView()
                .tabItem { Label("Circle", systemImage: "person.3.fill") }

            ProductsTabView()
                .tabItem { Label("Products", systemImage: "bag.fill") }

            PageTabView()
                .tabItem { Label("Page", systemImage: "storefront.fill") }

            ProfileTabView()
                .tabItem { Label("Profile", systemImage: "person.circle.fill") }
        }
        .tint(AppColor.accent)
    }
}
