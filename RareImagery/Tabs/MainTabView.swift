import SwiftUI
import RareImageryAPI

/// Home — the rare-create Intro screen (ui_kits/rare-create): spotlight
/// gradient, the Rare / Bud / Imagery lockup inside gold viewfinder brackets,
/// the pitch card, and the gold "Start Sniffing" circle that launches the
/// video → Grok create flow.
struct HomeTabView: View {
    /// Called after "Add to store" so MainTabView can switch to the Products
    /// tab, where the fresh draft shows as UNPUBLISHED.
    var onProductCreated: (() -> Void)? = nil

    @Environment(AppState.self) private var state
    @State private var showVideoCreate = false

    var body: some View {
        ZStack {
            AppColor.spotlight.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Text("Ready to sniff something Rare? 🐾")
                        .font(AppFont.display(20, .bold))
                        .italic()
                        .foregroundStyle(AppColor.gold)
                        .padding(.top, 18)

                    Text("Rare")
                        .font(AppFont.display(38, .bold))
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.top, 18)

                    Image("BudHound")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                        .overlay(ViewfinderBrackets())
                        .padding(.top, 22)

                    Text("Imagery")
                        .font(AppFont.display(40, .bold))
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.top, 6)

                    // Pitch card — gold hairline + wash
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 22))
                            .foregroundStyle(AppColor.gold)
                        Text("Film your product and talk about it — Rare builds the whole listing from your video and voice.")
                            .font(AppFont.bodyText(15))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(AppColor.gold.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppColor.gold.opacity(0.5), lineWidth: 1))
                    .padding(.top, 22)

                    // The create CTA — same video → Grok Vision flow as sign-up;
                    // authenticated, so the draft lands owned in their store.
                    Button {
                        showVideoCreate = true
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 28, weight: .semibold))
                            Text("Start Sniffing")
                                .font(AppFont.display(15, .bold))
                        }
                        .foregroundStyle(Color(red: 22/255, green: 13/255, blue: 26/255))
                        .frame(width: 128, height: 128)
                        .background(AppColor.createCircle, in: Circle())
                        .shadow(color: AppColor.createCircle.opacity(0.25), radius: 20, y: 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start filming your product")
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .fullScreenCover(isPresented: $showVideoCreate) {
            VideoSubmissionFunnelView(
                onExit: { showVideoCreate = false },
                productMode: true,
                onProductAdded: {
                    showVideoCreate = false
                    onProductCreated?()
                }
            )
            .environment(state)
        }
    }
}

/// Gold viewfinder corner brackets (26pt arms, 3pt stroke) framing Bud.
private struct ViewfinderBrackets: View {
    var body: some View {
        GeometryReader { geo in
            let L: CGFloat = 26, T: CGFloat = 3, r: CGFloat = 6
            let w = geo.size.width, h = geo.size.height
            Path { p in
                // tl
                p.move(to: CGPoint(x: 0, y: L)); p.addLine(to: CGPoint(x: 0, y: r))
                p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
                p.addLine(to: CGPoint(x: L, y: 0))
                // tr
                p.move(to: CGPoint(x: w - L, y: 0)); p.addLine(to: CGPoint(x: w - r, y: 0))
                p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: L))
                // bl
                p.move(to: CGPoint(x: 0, y: h - L)); p.addLine(to: CGPoint(x: 0, y: h - r))
                p.addQuadCurve(to: CGPoint(x: r, y: h), control: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: L, y: h))
                // br
                p.move(to: CGPoint(x: w - L, y: h)); p.addLine(to: CGPoint(x: w - r, y: h))
                p.addQuadCurve(to: CGPoint(x: w, y: h - r), control: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w, y: h - L))
            }
            .stroke(AppColor.gold, lineWidth: T)
        }
    }
}

/// Products tab — every product the signed-in creator has made (drafts +
/// live), from GET /api/stores/products. Tap a row to edit title/description/
/// price and publish. Back on the tab bar in Page's old slot.
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
            Text(product.isPublished ? "LIVE" : "UNPUBLISHED")
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
            var list = try await state.productRepository.listMine()
            // A just-created draft can be missing from the server list (e.g.
            // its creator claim failed or the index lags). The funnel stashes
            // its uuid — surface that draft here anyway so it's never lost.
            if let pending = try? await state.keychain.get(.pendingDraftUuid), !pending.isEmpty {
                if list.contains(where: { $0.id == pending }) {
                    // Visible through the normal list now — stop tracking it.
                    try? await state.keychain.remove(.pendingDraftUuid)
                } else if let detail = try? await state.productRepository.get(uuid: pending) {
                    list.insert(StoreProduct(
                        id: detail.uuid,
                        title: detail.title,
                        description: detail.description,
                        price: detail.price.map { "\($0 as NSDecimalNumber)" },
                        currency: "USD",
                        imageUrl: detail.heroImageUrl,
                        productType: nil,
                        status: detail.isPublished ? 1 : 0
                    ), at: 0)
                }
            }
            products = list
            message = nil
        } catch {
            message = "Couldn't load your products. Pull to retry."
        }
    }

}

/// My page — the creator's public-facing storefront as visitors see it:
/// X avatar + banner over the grid of published products. Read-only preview;
/// editing lives in the Products tab. Left the tab bar (Products took its
/// slot); pushed from Profile → "My page" inside that stack.
struct PageTabView: View {
    @Environment(AppState.self) private var state
    @State private var profile: StoreProfile?
    @State private var published: [StoreProduct] = []
    @State private var loading = false

    private var handle: String { state.session.claims?.handle ?? "yourname" }
    private var slug: String { profile?.storeSlug ?? state.session.claims?.slug ?? handle }

    var body: some View {
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
            .navigationTitle("My page")
            .refreshable { await load() }
            .task { await load() }
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
                    NavigationLink {
                        ProductDetailView(productId: product.id)
                            .environment(state)
                    } label: {
                        storeCard(product)
                    }
                    .buttonStyle(.plain)
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

                // Store sales system — orders, revenue, shipping (read-only,
                // from Drupal Commerce via /api/sales/*).
                Section {
                    NavigationLink {
                        SalesDashboardView()
                            .environment(state)
                    } label: {
                        Label("Sales", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    // The public storefront preview left the tab bar (Products
                    // took its slot); it stays reachable from here.
                    NavigationLink {
                        PageTabView()
                            .environment(state)
                    } label: {
                        Label("My page", systemImage: "storefront")
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

/// The four capsule tabs: the branded Bud "RareImagery" home tab, Friends,
/// Products (edit + publish the creator's listings), Profile — with the Shop
/// button in the center. The public store preview (Page) lives under
/// Profile → "My page".
enum RareTab: CaseIterable {
    case home, friends, products, profile

    var label: String {
        switch self {
        case .home: "RareImagery"
        case .friends: "Friends"
        case .products: "Products"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"           // fallback only — home renders Bud
        case .friends: "person.2"
        case .products: "shippingbox"
        case .profile: "person.crop.circle"
        }
    }
}

/// Floating rounded-capsule bottom nav (rare-create kit): #2C1033 fill,
/// hairline border, active tab bright purple with a subtle highlight pill.
/// Home renders the Bud mascot; Profile renders the creator's X avatar; the
/// center slot is the transparent Shop button (bag icon, lowercase label).
struct RareTabBar: View {
    @Binding var selected: RareTab
    var avatarURL: URL?
    var onShop: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.home)
            tabButton(.friends)


            // Center — Shop (transparent variant: 34pt icon, muted label)
            Button(action: onShop) {
                VStack(spacing: 3) {
                    Image(systemName: "bag")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(AppColor.tabInactive)
                        .frame(width: 34, height: 34)
                    Text("shop")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.tabInactive)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shop creator stores")

            tabButton(.products)
            tabButton(.profile)
        }
        .padding(8)
        .background(AppColor.vaultMid, in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: Color(red: 5/255, green: 3/255, blue: 8/255).opacity(0.5), radius: 15, y: 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
    }

    private func tabButton(_ tab: RareTab) -> some View {
        let isOn = selected == tab
        return Button {
            selected = tab
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isOn {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 52, height: 30)
                    }
                    tabIcon(tab, isOn: isOn)
                }
                .frame(height: 32)
                Text(tab.label)
                    .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? AppColor.brandActive : AppColor.tabInactive)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
    }

    @ViewBuilder private func tabIcon(_ tab: RareTab, isOn: Bool) -> some View {
        switch tab {
        case .home:
            Image("BudHound")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
        case .profile:
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default:
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(isOn ? AppColor.brandActive : .white)
                    }
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())
                .overlay(Circle().stroke(isOn ? AppColor.brandActive : Color.white.opacity(0.25), lineWidth: isOn ? 2 : 1))
            } else {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isOn ? AppColor.brandActive : .white)
            }
        default:
            Image(systemName: tab.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isOn ? AppColor.brandActive : .white)
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var state
    @State private var tab: RareTab = .home
    @State private var avatarURL: URL?
    @State private var showShop = false

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()
            // Lazy: each tab mounts on first visit (loads its own data) rather
            // than all at launch. The floating bar insets each tab's safe area
            // so scroll content clears it.
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    RareTabBar(selected: $tab, avatarURL: avatarURL, onShop: { showShop = true })
                }
        }
        .sheet(isPresented: $showShop) {
            ShopView()
                .environment(state)
        }
        .task {
            // Pfp for the Profile tab button — best-effort; falls back to the
            // person icon until the profile loads.
            avatarURL = (try? await state.productRepository.myProfile())?.avatarURL
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .home: HomeTabView(onProductCreated: { tab = .products })
        case .friends: FriendsTabView()
        case .products: ProductsTabView()
        case .profile: ProfileTabView()
        }
    }
}
