import SwiftUI
import AVFoundation

/// Pre-permission education screen. Shows up before iOS fires its native
/// camera-access dialog so the user knows WHY we need the camera. Reduces
/// the rate of "Don't Allow" — once a user denies camera in the system
/// prompt, the only recovery is Settings → Privacy → Camera.
///
/// Voice: Rare-as-mascot, friendly, no jargon. The user just met Rare on
/// the welcome screen; we keep the warmth.
///
/// Wiring:
///   - Calls `AVCaptureDevice.requestAccess(for: .video)` directly.
///     System dialog fires on first invocation; subsequent invocations
///     return the cached decision without re-prompting.
///   - On grant: `onContinue()` lets the parent navigate forward.
///   - On deny: shows a deep-link button to iOS Settings.
struct PermissionsView: View {
    let onContinue: () -> Void

    @State private var status: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isRequesting = false

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "camera.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(AppColor.cta)

                VStack(spacing: 14) {
                    Text("Show Rare what you've got")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Rare uses your camera to analyze one thing at a time. Your photos stay private until you decide to turn them into something sellable.")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button(action: { Task { await primaryAction() } }) {
                    HStack {
                        if isRequesting {
                            ProgressView()
                                .tint(.black)
                        }
                        Text(primaryButtonTitle)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColor.cta)
                    .clipShape(Capsule())
                }
                .disabled(isRequesting)
                .padding(.horizontal, 24)

                if status == .denied || status == .restricted {
                    Text("Camera is currently disabled for Rare Imagery. Open Settings to enable it.")
                        .font(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                Spacer().frame(height: 32)
            }
        }
    }

    private var primaryButtonTitle: String {
        switch status {
        case .authorized:
            return "Continue"
        case .denied, .restricted:
            return "Open Settings"
        case .notDetermined:
            return isRequesting ? "Asking iOS…" : "Enable Camera"
        @unknown default:
            return "Enable Camera"
        }
    }

    private func primaryAction() async {
        switch status {
        case .authorized:
            onContinue()
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        case .notDetermined:
            isRequesting = true
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            // Re-read instead of inferring — covers the "restricted" edge case
            // (parental controls / MDM) that ignores the user's choice.
            status = AVCaptureDevice.authorizationStatus(for: .video)
            isRequesting = false
            if granted {
                onContinue()
            }
        @unknown default:
            break
        }
    }
}

#Preview {
    PermissionsView(onContinue: {})
        .preferredColorScheme(.dark)
}
