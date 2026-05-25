import SwiftUI

struct DiscoverView: View {
    @Bindable var service: CircleService
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            CircleSearchBar(text: $searchText)
                .padding(.bottom, 12)
                .onChange(of: searchText) { _, newValue in
                    service.searchUsers(query: newValue)
                }

            if service.isSearching {
                ProgressView("Searching X…")
                    .tint(AppColor.accent)
                    .padding(.top, 24)
            } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                userList(service.searchResults, emptyMessage: "No users found. Try an exact @handle.")
            } else {
                suggestionsSection
            }
        }
        .task {
            await service.loadSuggestionsIfNeeded()
        }
        .sheet(item: $service.selectedProfile) { user in
            CircleProfileSheet(
                user: user,
                isInCircle: service.isInCircle(user.id),
                isFavorited: service.isFavorite(user.id),
                onAddToCircle: { service.addToCircle(user) },
                onToggleFavorite: { service.toggleFavorite(user) },
                onDismiss: { service.selectedProfile = nil }
            )
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        if service.isLoadingSuggestions {
            ProgressView()
                .tint(AppColor.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if service.suggestions.isEmpty {
            ContentUnavailableView(
                "Search for creators",
                systemImage: "magnifyingglass",
                description: Text("Try searching an exact @handle")
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Suggested from your X network")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                userList(service.suggestions, emptyMessage: "")
            }
        }
    }

    @ViewBuilder
    private func userList(_ users: [XUserSearchResult], emptyMessage: String) -> some View {
        if users.isEmpty, !emptyMessage.isEmpty {
            Text(emptyMessage)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 24)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            List(users) { user in
                CircleMemberRow(
                    member: user.toCircleMemberDisplay(),
                    isInCircle: service.isInCircle(user.id),
                    isFavorited: service.isFavorite(user.id),
                    onAdd: { service.addToCircle(user) },
                    onToggleFavorite: { service.toggleFavorite(user) },
                    onTap: { service.selectedProfile = user }
                )
                .listRowBackground(AppColor.background)
                .listRowSeparatorTint(AppColor.border)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

struct CircleSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.textSecondary)
            TextField("Search @handle or name", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(AppColor.textPrimary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColor.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}
