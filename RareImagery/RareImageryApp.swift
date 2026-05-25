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
                        if url.scheme == "rareimagery", url.host == "auth" {
                            do {
                                let tokens = try await state.authService.completeXAuth(callbackURL: url)
                                state.session.apply(tokens: tokens)
                            } catch {
                                state.session.setError("Deep-link auth failed: \(error)")
                            }
                        }
                    }
                }
        }
        .modelContainer(for: [CircleMember.self, FavoriteItem.self])
    }
}
