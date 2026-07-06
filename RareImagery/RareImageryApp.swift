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
                // OAuth callbacks are handled by AuthCoordinator's ASWebAuthenticationSession
                // (which threads draftUuid/draftToken/deviceId for the value-first claim).
                // Do not duplicate completeXAuth here — it races and clears PKCE state.
        }
        .modelContainer(for: [CircleMember.self, FavoriteItem.self])
    }
}
