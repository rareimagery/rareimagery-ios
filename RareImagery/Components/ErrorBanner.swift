import SwiftUI

/// Dismissable error banner used across Circle surfaces.
///
/// Replaces the inline orange `Text(errorMessage)` pattern in
/// `CircleTabView` (F4) and is reusable from the Send sheet's error
/// states and elsewhere. Single component = single visual language for
/// failures.
struct ErrorBanner: View {
    let message: String
    var retryTitle: String = "Retry"
    /// Tap-Retry action. Nil to hide the retry button (e.g. info-only banners).
    var onRetry: (() -> Void)? = nil
    /// Optional dismiss action. Nil to make the banner persistent (caller
    /// controls visibility).
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.red)

            Text(message)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)

            if let onRetry {
                Button(retryTitle, action: onRetry)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .buttonStyle(.plain)
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}

#Preview {
    VStack(spacing: 16) {
        ErrorBanner(message: "Couldn't sync circle to server", onRetry: {})
        ErrorBanner(message: "Couldn't sync circle to server", onRetry: {}, onDismiss: {})
        ErrorBanner(message: "Offline — changes saved locally")
    }
    .padding(.vertical, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
