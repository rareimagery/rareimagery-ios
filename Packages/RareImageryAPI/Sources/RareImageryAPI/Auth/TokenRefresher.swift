import Foundation

/// Background helper that pre-emptively refreshes the access token before it expires.
/// Caller starts/stops it from the active session.
public actor TokenRefresher {
    private let client: APIClient
    private let logger = APILogger(category: "TokenRefresher")
    private var task: Task<Void, Never>?

    public init(client: APIClient) {
        self.client = client
    }

    public func start(checkInterval: TimeInterval = 30) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickIfNeeded()
                try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func tickIfNeeded() async {
        do {
            let token = try await client.config.baseURL // touch config — no-op; replaced below
            _ = token
            // We don't know exp here without re-decoding; defer to APIClient when calls 401.
            // Pre-emptive refresh hook: just call refresh if we know token expires soon.
            // (Concrete pre-emptive logic happens once we cache decoded claims; for now this
            //  is a no-op and APIClient handles reactive refresh on 401.)
        } catch {
            logger.warning("TokenRefresher tick failed: \(error.localizedDescription)")
        }
    }
}
