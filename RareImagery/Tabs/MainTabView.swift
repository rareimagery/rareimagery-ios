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

struct CreationsTabView: View {
    @Environment(AppState.self) private var state
    @State private var firstProduct: ProductDetail?
    @State private var loading = false
    @State private var publishing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // The pre-sign-in funnel video, claimed as the creator's
                    // first product — editable + publishable here.
                    if let product = firstProduct {
                        firstProductCard(product)
                    }

                    if let draft = latestDraft {
                        draftCard(draft)
                    }

                    if firstProduct == nil && latestDraft == nil && !loading {
                        ContentUnavailableView(
                            "No products yet",
                            systemImage: "square.stack.3d.up.slash",
                            description: Text("Film an item from the Home tab and Grok will draft the listing.")
                        )
                        .padding(.top, 60)
                    }

                    if loading { ProgressView().tint(AppColor.gold).padding(.top, 40) }
                    if let message { Text(message).font(AppFont.caption).foregroundStyle(AppColor.textSecondary) }
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
            }
            .background(AppColor.background)
            .navigationTitle("Creations")
            .task { await loadFirstProduct() }
        }
    }

    private var latestDraft: ProductDraft? {
        if case .ready(let draft) = state.capture.phase { return draft }
        return nil
    }

    private func firstProductCard(_ product: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(product.isPublished ? "YOUR FIRST PRODUCT · LIVE" : "YOUR FIRST PRODUCT · DRAFT")
                .font(AppFont.mono(10, .semibold)).tracking(1.4)
                .foregroundStyle(product.isPublished ? AppColor.success : AppColor.gold)
            Text(product.title ?? "Untitled item")
                .font(AppFont.headline).foregroundStyle(AppColor.textPrimary)
            if let description = product.description, !description.isEmpty {
                Text(description).font(AppFont.bodyText(13)).foregroundStyle(AppColor.textSecondary)
                    .lineLimit(3)
            }
            if let price = product.price {
                Text("$\(price as NSDecimalNumber)")
                    .font(AppFont.mono(15)).foregroundStyle(AppColor.gold)
            }
            if !product.isPublished {
                Button {
                    Task { await publish(product) }
                } label: {
                    Text(publishing ? "Publishing…" : "Publish to store")
                        .font(AppFont.buttonLabel).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(AppColor.cta, in: Capsule())
                }
                .disabled(publishing)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColor.borderGold, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func draftCard(_ draft: ProductDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LATEST DRAFT").font(AppFont.mono(10, .semibold)).tracking(1.4)
                .foregroundStyle(AppColor.textSecondary)
            Text(draft.title).font(AppFont.headline).foregroundStyle(AppColor.textPrimary)
            if let description = draft.description, !description.isEmpty {
                Text(description).font(AppFont.bodyText(13)).foregroundStyle(AppColor.textSecondary).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func loadFirstProduct() async {
        guard firstProduct == nil else { return }
        let stored = (try? await state.keychain.get(.firstProductUuid)) ?? nil
        guard let uuid = stored, !uuid.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            firstProduct = try await state.productRepository.get(uuid: uuid)
        } catch {
            // Non-fatal — the product still exists server-side; just not shown.
            message = "Couldn't load your first product yet."
        }
    }

    private func publish(_ product: ProductDetail) async {
        publishing = true
        defer { publishing = false }
        do {
            firstProduct = try await state.productRepository.publish(uuid: product.uuid)
            message = "Published — it's live on your store."
        } catch {
            message = "Publish failed. Try again."
        }
    }
}

struct PageTabView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            ScrollView {
                LiveStorePreview(
                    displayName: state.session.displayHandle ?? "Your name",
                    handle: state.session.claims?.handle ?? "yourname",
                    bio: "",
                    avatarURL: nil,
                    bannerURL: nil,
                    colorScheme: .default,
                    slug: state.session.claims?.slug ?? "yourname"
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Text("Full page editor coming soon — tweak colors, bio, and featured posts from here.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
            }
            .background(AppColor.background)
            .navigationTitle("Page")
        }
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

            CreationsTabView()
                .tabItem { Label("Creations", systemImage: "square.stack.fill") }

            PageTabView()
                .tabItem { Label("Page", systemImage: "storefront.fill") }

            ProfileTabView()
                .tabItem { Label("Profile", systemImage: "person.circle.fill") }
        }
        .tint(AppColor.accent)
    }
}
