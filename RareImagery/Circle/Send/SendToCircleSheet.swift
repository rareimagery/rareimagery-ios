import SwiftUI
import SwiftData
import RareImageryAPI

/// "Send to Circle" bottom sheet presented after the user finishes the
/// first-product flow. Mixed-theme — light mode, while the rest of the
/// app stays dark. Matches the mock3/mock4 visual direction.
///
/// State machine inside the sheet:
///
///   composing → sending → succeeded   (happy path, auto-dismisses)
///                       ↘ failed       (F2 — all recipients failed; retry preserves selection)
///                       ↘ partial      (F3 — some sent, some failed; retry-failed only)
///
///   empty                                (F1 — circle has 0 members; gated at body level)
///
/// The sheet is self-contained: it reads members + favorites via
/// SwiftData @Query (no shared CircleService needed) and dispatches
/// through `state.circleShareRepository`. Closing the sheet
/// discards all in-flight state.
struct SendToCircleSheet: View {
    let draft: ProductDraft

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CircleMember.addedDate, order: .reverse)
    private var members: [CircleMember]

    @Query(sort: \FavoriteItem.addedDate, order: .reverse)
    private var favorites: [FavoriteItem]

    @State private var selectedIDs: Set<String> = []
    @State private var note: String = ""
    @State private var phase: Phase = .composing
    @State private var lastResults: [RecipientResult] = []
    @State private var lastErrorMessage: String?

    /// Fresh UUID per share — used as the BFF correlation ID. ProductDraft
    /// has no persistent id yet; when it does, swap in the real value.
    private let correlationId = UUID().uuidString

    private enum Phase: Equatable {
        case composing
        case sending
        case succeeded(count: Int)
        case failed
        case partial
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if members.isEmpty {
                    emptyState                          // F1
                } else {
                    switch phase {
                    case .succeeded(let count):
                        succeededView(count: count)
                    case .partial:
                        partialView                     // F3
                    default:
                        composingView                   // composing + sending + failed overlay
                    }
                }
            }
            .navigationTitle("Send to Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty state (F1)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppColor.accent)
            Text("Your Circle is empty")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(.label))
            Text("Add 2–3 friends to share drops with for feedback or co-promotion. Your Circle is private — only you see who's in it.")
                .font(.system(size: 15))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                // Bounce to Circle tab → Discover. The simplest path is to
                // dismiss the sheet and let the user navigate. A deep-link
                // hook can come later if friction matters.
                dismiss()
            } label: {
                Text("Find friends to add")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)

            Button("Share on X instead") { dismiss() }
                .font(.system(size: 15))
                .foregroundStyle(Color(.secondaryLabel))

            Spacer()
        }
    }

    // MARK: - Composing (mock3) + sending + failed overlay

    private var composingView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    draftPreview
                    Divider().padding(.horizontal, 16)
                    quickActions
                    Divider().padding(.horizontal, 16)
                    pickListSectionHeader
                    pickList
                }
                .padding(.vertical, 16)
            }

            sendBar
        }
        .overlay(alignment: .top) {
            if phase == .failed, let message = lastErrorMessage {
                failureToast(message: message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    private var draftPreview: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(
                    colors: [Color(.tertiarySystemFill), Color(.quaternarySystemFill)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "tshirt.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(.tertiaryLabel))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(2)
                Text(draft.priceDisplay ?? "Ready to share with your circle?")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK ACTIONS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color(.secondaryLabel))

            HStack(spacing: 12) {
                QuickActionCard(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Ask my whole Circle",
                    subtitle: subtitle(count: members.count, label: "member"),
                    isHighlighted: selectedIDs.count == members.count && !members.isEmpty
                ) {
                    selectedIDs = Set(members.map(\.xUserID))
                }

                QuickActionCard(
                    icon: "heart.fill",
                    title: "Co-promote with Favorites",
                    subtitle: subtitle(count: favoritedMembers.count, label: "favorite"),
                    isHighlighted: !favoritedMembers.isEmpty
                        && selectedIDs == Set(favoritedMembers.map(\.xUserID))
                ) {
                    selectedIDs = Set(favoritedMembers.map(\.xUserID))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var pickListSectionHeader: some View {
        HStack {
            Text("OR PICK SPECIFIC PEOPLE")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color(.secondaryLabel))
            Spacer()
            if !selectedIDs.isEmpty {
                Button("Clear") { selectedIDs.removeAll() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.accent)
            }
        }
        .padding(.horizontal, 16)
    }

    private var pickList: some View {
        VStack(spacing: 0) {
            ForEach(members) { member in
                MemberPickRow(
                    member: member,
                    isSelected: selectedIDs.contains(member.xUserID),
                    isFavorite: member.isFavorite
                ) {
                    toggle(member)
                }
            }
        }
    }

    private var sendBar: some View {
        VStack(spacing: 10) {
            TextField("Add a note (optional)", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .disabled(phase == .sending)

            Button(action: send) {
                HStack(spacing: 8) {
                    if phase == .sending {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(sendButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(sendButtonBackground, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedIDs.isEmpty || phase == .sending)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(.thinMaterial)
    }

    private var sendButtonTitle: String {
        switch phase {
        case .sending: return "Sending…"
        case .failed:  return "Retry — Send to \(selectedIDs.count)"
        default:
            let people = selectedIDs.count == 1 ? "person" : "people"
            return "Send to \(selectedIDs.count) \(people)"
        }
    }

    private var sendButtonBackground: Color {
        if phase == .failed { return Color.red.opacity(0.85) }
        if selectedIDs.isEmpty { return AppColor.accent.opacity(0.35) }
        return AppColor.accent
    }

    private func failureToast(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't send")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.label))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Retry") { send() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .padding(.horizontal, 16)
    }

    // MARK: - Partial success (F3)

    private var partialView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.green)
                        Text("Sent to \(sentCount) of \(lastResults.count)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color(.label))
                        if failedCount > 0 {
                            Text(failedCount == 1
                                ? "One recipient couldn't receive this drop."
                                : "\(failedCount) recipients couldn't receive this drop.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(.secondaryLabel))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 12)

                    VStack(spacing: 0) {
                        ForEach(lastResults) { result in
                            ResultRow(
                                result: result,
                                member: memberByXUserID[result.recipientId]
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }

            VStack(spacing: 10) {
                if failedCount > 0 {
                    Button("Retry the \(failedCount) that failed") { retryFailed() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColor.accent, lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                }
                Button("Done") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.accent, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .background(.thinMaterial)
        }
    }

    // MARK: - Succeeded (all clear)

    private func succeededView(count: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.green)
            Text("Sent to \(count) \(count == 1 ? "person" : "people")")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(.label))
            Text("They'll see it in their Circle feed.")
                .font(.system(size: 14))
                .foregroundStyle(Color(.secondaryLabel))
            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismiss() }
        }
    }

    // MARK: - Send + Retry

    private func send() {
        guard !selectedIDs.isEmpty else { return }
        dispatch(recipientIds: Array(selectedIDs))
    }

    private func retryFailed() {
        let failedIds = lastResults
            .filter { $0.status == .failed }
            .map(\.recipientId)
        guard !failedIds.isEmpty else { return }
        dispatch(recipientIds: failedIds)
    }

    private func dispatch(recipientIds: [String]) {
        phase = .sending
        lastErrorMessage = nil

        let request = CircleShareRequest(
            draftId: correlationId,
            recipientIds: recipientIds,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
            intent: .feedback
        )

        Task {
            do {
                let response = try await state.circleShareRepository.send(request)
                await MainActor.run {
                    self.lastResults = response.results
                    if response.failed == 0 {
                        self.phase = .succeeded(count: response.sent)
                    } else {
                        self.phase = .partial
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = describe(error)
                    self.phase = .failed
                }
            }
        }
    }

    // MARK: - Helpers

    private var favoritedMembers: [CircleMember] {
        members.filter(\.isFavorite)
    }

    private var memberByXUserID: [String: CircleMember] {
        Dictionary(uniqueKeysWithValues: members.map { ($0.xUserID, $0) })
    }

    private var sentCount: Int {
        lastResults.filter { $0.status == .sent }.count
    }

    private var failedCount: Int {
        lastResults.count - sentCount
    }

    private func subtitle(count: Int, label: String) -> String {
        switch count {
        case 0:  return "No \(label)s yet"
        case 1:  return "1 \(label)"
        default: return "\(count) \(label)s"
        }
    }

    private func toggle(_ member: CircleMember) {
        if selectedIDs.contains(member.xUserID) {
            selectedIDs.remove(member.xUserID)
        } else {
            selectedIDs.insert(member.xUserID)
        }
    }

    private func describe(_ error: Error) -> String {
        // APIClient throws localized error descriptions; surface as-is.
        // Network failures get a friendlier nudge.
        let raw = (error as NSError).localizedDescription
        if raw.lowercased().contains("internet") || raw.lowercased().contains("offline") {
            return "You're offline. We'll retry when you're back online."
        }
        return raw.isEmpty ? "Network error — please try again." : raw
    }
}

// MARK: - QuickActionCard

private struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColor.accent)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isHighlighted ? AppColor.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MemberPickRow

private struct MemberPickRow: View {
    let member: CircleMember
    let isSelected: Bool
    let isFavorite: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    avatar
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white, AppColor.accent)
                            .background(Circle().fill(Color(.systemBackground)).frame(width: 18, height: 18))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(.label))
                    HStack(spacing: 6) {
                        Text("@\(member.username)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(.secondaryLabel))
                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColor.cta)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = member.profileImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(AppColor.accent.opacity(0.85))
            .frame(width: 44, height: 44)
            .overlay {
                Text(String(member.displayName.prefix(1)).uppercased())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

// MARK: - ResultRow (F3 partial-success per-recipient line)

private struct ResultRow: View {
    let result: RecipientResult
    let member: CircleMember?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.status == .sent ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(result.status == .sent ? Color.green : Color.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(member?.displayName ?? "Recipient")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(.label))
                if result.status == .failed, let reason = result.reason {
                    Text(failureCopy(for: reason))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.red.opacity(0.85))
                } else if let username = member?.username {
                    Text("@\(username)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }

            Spacer()

            Text(result.status == .sent ? "Sent" : "Failed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(result.status == .sent ? Color.green : Color.red)
        }
        .padding(.vertical, 8)
    }

    private func failureCopy(for reason: RecipientResult.FailureReason) -> String {
        switch reason {
        case .recipientBlocked:  return "They may have removed you on X"
        case .recipientUnknown:  return "Account no longer exists"
        case .rateLimited:       return "Rate-limited — try again later"
        case .network:           return "Couldn't reach — tap retry"
        case .internal:          return "Something went wrong — tap retry"
        }
    }
}
