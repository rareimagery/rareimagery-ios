import SwiftUI

/// Horizontal scroll of product-kind chips. v1 = T-Shirt / Hoodie / Cap.
/// Adding new kinds = add to `MerchProductKind.allCases` (no UI change).
struct ProductTypeChips: View {
    @Binding var selected: MerchProductKind

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(MerchProductKind.allCases) { kind in
                    ChipButton(
                        kind: kind,
                        isSelected: selected == kind,
                        onTap: { selected = kind }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct ChipButton: View {
    let kind: MerchProductKind
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(kind.label)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? AppColor.accent : AppColor.surface)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : AppColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    struct Host: View {
        @State var sel: MerchProductKind = .tShirt
        var body: some View {
            VStack {
                ProductTypeChips(selected: $sel)
                Text("Selected: \(sel.label)").foregroundStyle(.white).padding()
                Spacer()
            }
        }
    }
    return Host()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
        .preferredColorScheme(.dark)
}
