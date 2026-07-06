import SwiftUI
import SwiftData
import RareImageryAPI

@main
struct RareImageryApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(state)
                .environment(state.capture)
                .preferredColorScheme(.dark)
                .task { await state.bootstrap() }
                .onOpenURL { url in
                    Task {
                        guard url.scheme == "rareimagery", url.host == "auth" else { return }
                        do {
                            let draftToken = try? await state.keychain.get(.pendingDraftToken)
                            let draftUuid = try? await state.keychain.get(.pendingDraftUuid)
                            let deviceId = try? await state.keychain.stableDeviceId()
                            let tokens = try await state.authService.completeXAuth(
                                callbackURL: url,
                                draftToken: draftToken,
                                draftUuid: draftUuid,
                                deviceId: deviceId
                            )
                            state.session.apply(tokens: tokens)
                            try? await state.keychain.remove(.pendingDraftToken)
                            try? await state.keychain.remove(.pendingDraftUuid)
                        } catch {
                            state.session.setError("Deep-link auth failed: \(error)")
                        }
                    }
                }
        }
        .modelContainer(for: [CircleMember.self, FavoriteItem.self])
    }
}
