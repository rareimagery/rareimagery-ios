import Foundation
import Observation
import RareImageryAPI

// MARK: - Models

struct FollowedUser: Identifiable, Hashable, Decodable {
    let id: String
    let username: String
    let name: String
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, username, name
        case avatarURL = "avatar"
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class OnboardingViewModel {

    enum Step { case name, building }

    enum HandleState: Equatable {
        case idle
        case checking
        case available
        case taken
        case invalid(reason: String)

        var isReady: Bool { self == .available }
    }

    enum StoreCreation: Equatable {
        case idle
        case creating
        case ready
        case failed(message: String)
    }

    // MARK: Inputs / step
    var name: String = ""
    var step: Step = .name

    // MARK: Derived
    var slug: String { Self.slugify(name) }
    var storeURL: String {
        slug.isEmpty ? "yourname.rareimagery.net" : "\(slug).rareimagery.net"
    }
    var canContinue: Bool {
        handleState.isReady && storeCreation != .creating
    }

    // MARK: Async state
    var handleState: HandleState = .idle
    var storeCreation: StoreCreation = .idle
    var followedUsers: [FollowedUser] = []
    var circleSelection: Set<FollowedUser.ID> = []

    // MARK: Dependencies
    private let api: OnboardingAPI
    private var availabilityTask: Task<Void, Never>?
    private var circlePersistTask: Task<Void, Never>?

    init(api: OnboardingAPI = .live()) {
        self.api = api
    }

    // MARK: - Intents

    func onNameChanged(_ newValue: String) {
        name = newValue
        availabilityTask?.cancel()

        let candidate = slug
        guard !candidate.isEmpty else {
            handleState = .idle
            return
        }

        if case .invalid(let reason) = Self.validateSlug(candidate) {
            handleState = .invalid(reason: reason)
            return
        }

        handleState = .checking
        availabilityTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            do {
                let result = try await self.api.isHandleAvailable(candidate)
                guard !Task.isCancelled else { return }
                if result.available {
                    self.handleState = .available
                } else {
                    self.handleState = Self.mapUnavailable(reason: result.reason)
                }
            } catch {
                // Network error: don't block the user; let them try Continue.
                self.handleState = .idle
            }
        }
    }

    private static func mapUnavailable(reason: String?) -> HandleState {
        switch reason {
        case "reserved":       return .invalid(reason: "Reserved name")
        case "invalid":        return .invalid(reason: "Invalid format")
        case "taken", nil:     return .taken
        default:               return .taken
        }
    }

    func submitName() {
        guard canContinue else { return }
        step = .building
        Task { await loadCircleSuggestions() }
        Task { await provisionStore() }
    }

    func toggleCircleMember(_ user: FollowedUser) {
        if circleSelection.contains(user.id) {
            circleSelection.remove(user.id)
        } else if circleSelection.count < 24 {
            circleSelection.insert(user.id)
        }
        // else: hit the 24-pin cap; UI shows the count
    }

    func retryProvisioning() {
        Task { await provisionStore() }
    }

    /// Debounced trigger; the view calls this from `.onChange(of:)` for
    /// both `storeCreation` and `circleSelection`. Only persists when
    /// the store is ready AND there's a non-empty selection. Internal
    /// debounce avoids PUT-per-tap.
    func schedulePersistCircle() {
        guard case .ready = storeCreation else { return }
        circlePersistTask?.cancel()
        circlePersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            await self.persistCircle()
        }
    }

    // MARK: - Async work

    private func loadCircleSuggestions() async {
        do {
            followedUsers = try await api.fetchCircleSuggestions()
        } catch {
            // Non-blocking: empty list is acceptable during onboarding.
            followedUsers = []
        }
    }

    private func provisionStore() async {
        storeCreation = .creating
        do {
            try await api.provisionStore(slug, name)
            storeCreation = .ready
            // Circle PUT is now driven by view-side onChange via
            // schedulePersistCircle(). This avoids the stale-closure trap
            // where `circleSelection` captured at call time is always
            // empty because the user picks pins AFTER pressing Continue.
        } catch {
            storeCreation = .failed(message: error.localizedDescription)
        }
    }

    private func persistCircle() async {
        guard !circleSelection.isEmpty else { return }
        let pins = followedUsers
            .filter { circleSelection.contains($0.id) }
            .map(\.username)
        do {
            try await api.putCircle(pins)
        } catch {
            // Non-blocking for onboarding: log and move on. Surface in
            // profile settings if persistent failure becomes a UX issue.
            print("Circle persist failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Slug helpers (mirror the JS slugify from the web flow)

    static func slugify(_ raw: String) -> String {
        let folded = raw
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        var result = ""
        for char in folded {
            if char.isLetter || char.isNumber {
                result.append(char)
            } else if char.isWhitespace || char == "-" || char == "_" {
                if result.last != "-" { result.append("-") }
            }
        }
        while result.first == "-" { result.removeFirst() }
        while result.last == "-" { result.removeLast() }
        if result.count > 30 { result = String(result.prefix(30)) }
        return result
    }

    /// Local validation result. `String` doesn't conform to `Error`, so the
    /// chat-paste's `Result<Void, String>` shape needs a wrapper — using a
    /// plain enum here is clearer than introducing a `struct: Error` wrapper.
    enum Validation: Equatable {
        case valid
        case invalid(reason: String)
    }

    static func validateSlug(_ slug: String) -> Validation {
        guard slug.count >= 3 else { return .invalid(reason: "At least 3 characters") }
        guard slug.count <= 30 else { return .invalid(reason: "Too long") }
        let blocked: Set<String> = [
            "admin", "api", "app", "auth", "create",
            "rare", "rareimagery", "store", "www", "support", "help"
        ]
        guard !blocked.contains(slug) else { return .invalid(reason: "Reserved name") }
        return .valid
    }
}

// MARK: - API client

/// Function-based API client — easy to swap for previews/tests.
struct OnboardingAPI {
    /// `reason` is one of "invalid" | "reserved" | "taken" when `available == false`
    /// (or nil for legacy responses). Surfaced to the UI as a more helpful label.
    struct HandleAvailability: Sendable, Equatable {
        let available: Bool
        let reason: String?
    }

    var isHandleAvailable: (String) async throws -> HandleAvailability
    var fetchCircleSuggestions: () async throws -> [FollowedUser]
    var provisionStore: (_ slug: String, _ displayName: String) async throws -> Void
    var putCircle: (_ pins: [String]) async throws -> Void

    // Same base URL the rest of the app uses (Debug → local stack, Release
    // → production). This was hardcoded to production, so the wizard's
    // slug checks silently hit the live site from local/dev builds and
    // every name read as unavailable.
    static let baseURL = APIConfiguration.fromBundle.baseURL

    /// Production wiring. Pass the app's `KeychainStore` for Bearer-auth on
    /// the three endpoints that require it. `nil` keychain falls back to
    /// session-cookie auth (HTTPCookieStorage).
    static func live(keychain: KeychainStore? = nil) -> OnboardingAPI {
        // Resolve bearer at request-time, not at factory-time, so the token
        // can rotate during a long-running flow (AuthCoordinator owns refresh).
        let bearerResolver: () async -> String? = {
            guard let keychain else { return nil }
            return try? await keychain.get(.accessToken)
        }

        return OnboardingAPI(
            isHandleAvailable: { handle in
                // BFF route is `/api/stores/check-slug?slug=...` (the spec-doc's
                // `/api/stores/handle-available` doesn't exist). After PR #20 +
                // Round 6 deploy, this returns deterministic `reason` field.
                var components = URLComponents(
                    url: baseURL.appendingPathComponent("/api/stores/check-slug"),
                    resolvingAgainstBaseURL: false
                )!
                components.queryItems = [.init(name: "slug", value: handle)]
                var req = URLRequest(url: components.url!)
                await Self.addAuth(&req, bearerResolver: bearerResolver)
                let (data, response) = try await URLSession.shared.data(for: req)
                try Self.assertOK(response)
                struct Body: Decodable { let available: Bool; let reason: String? }
                let body = try JSONDecoder().decode(Body.self, from: data)
                return OnboardingAPI.HandleAvailability(available: body.available, reason: body.reason)
            },
            fetchCircleSuggestions: {
                let url = baseURL.appendingPathComponent("/api/social/circle/suggestions")
                var req = URLRequest(url: url)
                await Self.addAuth(&req, bearerResolver: bearerResolver)
                let (data, response) = try await URLSession.shared.data(for: req)
                try Self.assertOK(response)
                struct Body: Decodable { let users: [FollowedUser] }
                return try JSONDecoder().decode(Body.self, from: data).users
            },
            provisionStore: { slug, displayName in
                let url = baseURL.appendingPathComponent("/api/creator/provision-store")
                let body = ["subdomain": slug, "displayName": displayName]
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                await Self.addAuth(&req, bearerResolver: bearerResolver)
                req.httpBody = try JSONEncoder().encode(body)
                let (_, response) = try await URLSession.shared.data(for: req)
                try Self.assertOK(response)
            },
            putCircle: { pins in
                let url = baseURL.appendingPathComponent("/api/social/circle")
                let body = ["pins": pins.map { ["xUsername": $0] }]
                var req = URLRequest(url: url)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                await Self.addAuth(&req, bearerResolver: bearerResolver)
                req.httpBody = try JSONEncoder().encode(body)
                let (_, response) = try await URLSession.shared.data(for: req)
                try Self.assertOK(response)
            }
        )
    }

    /// Stub for SwiftUI previews and unit tests.
    static let preview = OnboardingAPI(
        isHandleAvailable: { _ in HandleAvailability(available: true, reason: nil) },
        fetchCircleSuggestions: {
            try? await Task.sleep(for: .milliseconds(400))
            return [
                .init(id: "1", username: "budhound", name: "Bud Hound",
                      avatarURL: URL(string: "https://i.pravatar.cc/150?img=12")),
                .init(id: "2", username: "alicecreates", name: "Alice Chen",
                      avatarURL: URL(string: "https://i.pravatar.cc/150?img=47")),
                .init(id: "3", username: "genxskater", name: "Mike Torres",
                      avatarURL: URL(string: "https://i.pravatar.cc/150?img=28"))
            ]
        },
        provisionStore: { _, _ in
            try? await Task.sleep(for: .seconds(1))
        },
        putCircle: { _ in }
    )

    // MARK: HTTP helpers

    private static func addAuth(_ req: inout URLRequest, bearerResolver: () async -> String?) async {
        guard let token = await bearerResolver() else { return }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private static func assertOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.init(rawValue: http.statusCode))
        }
    }
}
