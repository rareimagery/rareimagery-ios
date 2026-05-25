import Foundation
import Observation
import SwiftData
import RareImageryAPI

typealias XUserSearchResult = XUserSummary

@Observable
@MainActor
final class CircleService {
    private let modelContext: ModelContext
    private let repository: CircleRepository

    var circleMembers: [CircleMember] = []
    var favorites: [FavoriteItem] = []
    var searchResults: [XUserSearchResult] = []
    var suggestions: [XUserSearchResult] = []
    var isSearching = false
    var isLoadingSuggestions = false
    var errorMessage: String?
    var selectedProfile: XUserSearchResult?

    static let maxCircleSize = 24

    private var searchTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?

    init(modelContext: ModelContext, repository: CircleRepository) {
        self.modelContext = modelContext
        self.repository = repository
        loadLocalData()
    }

    func loadLocalData() {
        let memberDescriptor = FetchDescriptor<CircleMember>(
            sortBy: [SortDescriptor(\.addedDate, order: .reverse)]
        )
        circleMembers = (try? modelContext.fetch(memberDescriptor)) ?? []

        let favDescriptor = FetchDescriptor<FavoriteItem>(
            sortBy: [SortDescriptor(\.addedDate, order: .reverse)]
        )
        favorites = (try? modelContext.fetch(favDescriptor)) ?? []
    }

    func loadSuggestionsIfNeeded() async {
        guard suggestions.isEmpty, !isLoadingSuggestions else { return }
        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }
        do {
            suggestions = try await repository.fetchSuggestions()
        } catch {
            suggestions = []
        }
    }

    func searchUsers(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self else { return }
            do {
                let users = try await self.repository.searchUsers(query: trimmed)
                guard !Task.isCancelled else { return }
                self.searchResults = users
                self.errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.searchResults = []
                self.errorMessage = "Search failed. Try an exact @handle."
            }
            self.isSearching = false
        }
    }

    func addToCircle(_ user: XUserSearchResult, circleType: CircleType = .closeFriends) {
        if let existing = circleMembers.first(where: { $0.xUserID == user.id }) {
            existing.circleType = circleType
            existing.displayName = user.name
            existing.username = user.handle
            existing.profileImageURL = user.avatar
        } else {
            guard circleMembers.count < Self.maxCircleSize else {
                errorMessage = "Rare Circle is full (max \(Self.maxCircleSize))."
                return
            }
            let member = CircleMember(
                xUserID: user.id,
                username: user.handle,
                displayName: user.name,
                profileImageURL: user.avatar,
                circleType: circleType
            )
            modelContext.insert(member)
        }
        persistAndReload()
        scheduleSyncToServer()
    }

    func toggleFavorite(_ user: XUserSearchResult) {
        let favoriteID = favoriteReferenceID(for: user.id)
        if let existing = favorites.first(where: { $0.referenceID == favoriteID }) {
            modelContext.delete(existing)
            circleMembers.first(where: { $0.xUserID == user.id })?.isFavorite = false
        } else {
            let fav = FavoriteItem(
                itemType: .creator,
                referenceID: favoriteID,
                title: user.name,
                imageURL: user.avatar
            )
            modelContext.insert(fav)
            if let member = circleMembers.first(where: { $0.xUserID == user.id }) {
                member.isFavorite = true
            } else {
                addToCircle(user)
                circleMembers.first(where: { $0.xUserID == user.id })?.isFavorite = true
            }
        }
        persistAndReload()
        scheduleSyncToServer()
    }

    func removeMember(_ member: CircleMember) {
        if member.isFavorite {
            let favoriteID = favoriteReferenceID(for: member.xUserID)
            if let favorite = favorites.first(where: { $0.referenceID == favoriteID }) {
                modelContext.delete(favorite)
            }
        }
        modelContext.delete(member)
        persistAndReload()
        scheduleSyncToServer()
    }

    func isInCircle(_ userID: String) -> Bool {
        circleMembers.contains { $0.xUserID == userID }
    }

    func isFavorite(_ userID: String) -> Bool {
        favorites.contains { $0.referenceID == favoriteReferenceID(for: userID) }
    }

    private func favoriteReferenceID(for userID: String) -> String {
        "creator:\(userID)"
    }

    private func persistAndReload() {
        try? modelContext.save()
        loadLocalData()
    }

    private func scheduleSyncToServer() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            await self.syncCircleToServer()
        }
    }

    func syncCircleToServer() async {
        let handles = circleMembers.map(\.username)
        do {
            _ = try await repository.updateCircle(handles: handles)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't sync circle to server."
        }
    }
}
