import SwiftUI
import RareImageryAPI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        switch state.session.status {
        case .checking:
            ProgressView()
                .tint(AppColor.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.background)
                .ignoresSafeArea()
        case .signedOut:
            SignInView()
        case .signedIn:
            NavigationStack {
                CaptureFlowView()
            }
            .tint(AppColor.accent)
        }
    }
}
