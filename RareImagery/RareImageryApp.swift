import SwiftUI
import SwiftData
import RareImageryAPI

@main
struct RareImageryApp: App {
    @State private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

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
                .onChange(of: scenePhase) { _, phase in
                    // Bootstrap runs once at launch; if the BFF was briefly
                    // unreachable (e.g. Docker Desktop idle-resume in local
                    // dev), the app would otherwise be stuck on the sign-in
                    // fallback forever. Retry the anonymous trial mint on
                    // each foreground — but only for that specific failure,
                    // never after a deliberate sign-out or session expiry.
                    guard phase == .active,
                          case .signedOut = state.session.status,
                          let err = state.session.lastError,
                          err.hasPrefix("Couldn't start free trial")
                              || err.hasPrefix("Couldn't prepare trial session")
                    else { return }
                    Task { await state.bootstrap() }
                }
        }
        .modelContainer(for: [CircleMember.self, FavoriteItem.self])
    }
}
