import SwiftUI
import RareImageryAPI

struct HomeTabView: View {
    @Environment(AppState.self) private var state
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    VStack(spacing: 10) {
                        Text("RareVision")
                            .font(AppFont.largeTitle)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Capture something worth selling.")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    Button {
                        showCapture = true
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 36, weight: .semibold))
                            Text("Create")
                                .font(.system(size: 22, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .frame(width: 180, height: 180)
                        .background(AppColor.cta, in: Circle())
                        .shadow(color: AppColor.cta.opacity(0.35), radius: 24, y: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create a product")

                    Spacer()
                    Spacer()
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showCapture) {
                NavigationStack {
                    CaptureFlowView()
                }
                .environment(state)
                .environment(state.capture)
                .tint(AppColor.accent)
            }
        }
    }
}

struct CreationsTabView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch state.capture.phase {
                case .ready(let draft):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest draft")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        Text(draft.title)
                            .font(AppFont.headline)
                        if let description = draft.description, !description.isEmpty {
                            Text(description)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                default:
                    ContentUnavailableView(
                        "No drafts yet",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Your in-progress captures will show up here.")
                    )
                }
                Spacer()
            }
            .padding(.top, 16)
            .background(AppColor.background)
            .navigationTitle("Creations")
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
