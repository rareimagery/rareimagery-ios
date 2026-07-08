import SwiftUI

/// "Your Rare Circle is full" card shown above the My Circle grid when
/// `circleMembers.count >= CircleService.maxCircleSize` (F6 in the
/// mockup set).
///
/// Framed as a curation principle, not a paywall — the cap keeps the
/// circle tight; bigger isn't better.
struct AtCapWarningCard: View {
    let count: Int
    let cap: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your Rare Circle is full")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.orange)

                Text("Remove someone to add a new face. The \(cap)-person cap keeps your circle tight — bigger isn't better here.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}

#Preview {
    VStack(spacing: 16) {
        AtCapWarningCard(count: 24, cap: 24)
        Spacer()
    }
    .padding(.top, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
