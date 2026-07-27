import SwiftUI
import RareImageryAPI

/// Onboarding slug picker shown when Apple/Google exchange returns NEEDS_SLUG.
struct SlugPickerView: View {
    let suggestedSlug: String?
    let onSubmit: (String) async -> Void
    let onCancel: () -> Void

    @State private var slug: String
    @State private var isSubmitting = false
    @State private var localError: String?
    @FocusState private var slugFocused: Bool

    init(
        suggestedSlug: String?,
        onSubmit: @escaping (String) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.suggestedSlug = suggestedSlug
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _slug = State(initialValue: suggestedSlug ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.vaultGradient.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    Text("Choose your storefront")
                        .font(AppFont.display(28, .bold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("This becomes your RareImagery URL — e.g. \(previewHost)")
                        .font(AppFont.bodyText(15))
                        .foregroundStyle(AppColor.textSecondary)

                    TextField("your-name", text: $slug)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($slugFocused)
                        .padding(14)
                        .background(AppColor.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColor.borderGold, lineWidth: 1)
                        )
                        .onChange(of: slug) { _, newValue in
                            slug = newValue
                                .lowercased()
                                .replacingOccurrences(of: " ", with: "-")
                                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                            localError = nil
                        }

                    if let localError {
                        Text(localError)
                            .font(AppFont.bodyText(14))
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            }
                            Text(isSubmitting ? "Creating…" : "Continue")
                                .font(AppFont.buttonLabel)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColor.gold, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isSubmitting || !isValidSlug)

                    Spacer()
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .onAppear { slugFocused = true }
        }
    }

    private var previewHost: String {
        let s = slug.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "your-name.rareimagery.net" : "\(s).rareimagery.net"
    }

    private var isValidSlug: Bool {
        let trimmed = slug.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, trimmed.count <= 30 else { return false }
        return trimmed.range(of: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", options: .regularExpression) != nil
    }

    private func submit() async {
        let trimmed = slug.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.count >= 3 else {
            localError = "Slug must be at least 3 characters."
            return
        }
        guard trimmed.count <= 30 else {
            localError = "Slug must be 30 characters or fewer."
            return
        }
        guard trimmed.range(of: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", options: .regularExpression) != nil else {
            localError = "Use lowercase letters, numbers, and hyphens — not at the start or end."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        await onSubmit(trimmed)
    }
}
