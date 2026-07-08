import Foundation

/// Optional callbacks wired from the app layer so `APIClient` can notify
/// `AuthSession` after refresh or force sign-out on unrecoverable auth failure.
public struct AuthEventHandlers: Sendable {
    public var onTokensRefreshed: (@Sendable (AuthTokenResponse) async -> Void)?
    public var onSessionInvalidated: (@Sendable () async -> Void)?

    public init(
        onTokensRefreshed: (@Sendable (AuthTokenResponse) async -> Void)? = nil,
        onSessionInvalidated: (@Sendable () async -> Void)? = nil
    ) {
        self.onTokensRefreshed = onTokensRefreshed
        self.onSessionInvalidated = onSessionInvalidated
    }
}
