import Foundation

public enum APIError: Error, Sendable, Equatable, LocalizedError {
    case unauthorized
    case forbidden
    case validation(code: String, detail: String)
    case conflict(code: String, detail: String)
    case aiUnavailable
    case rateLimited(retryAfter: TimeInterval?)
    case quotaExceeded(QuotaInfo)
    case badRequest(code: MobileErrorCode?, message: String)
    case notFound
    case serverError(status: Int, code: MobileErrorCode?, message: String?)
    case network(URLError)
    case decode(String)
    case invalidConfiguration(String)
    case authCancelled
    case authFailed(String)

    public var isRetryable: Bool {
        switch self {
        case .network, .serverError, .rateLimited, .aiUnavailable:
            return true
        default:
            return false
        }
    }

    public var code: MobileErrorCode? {
        switch self {
        case .badRequest(let code, _): return code
        case .serverError(_, let code, _): return code
        default: return nil
        }
    }

    public var errorDescription: String? { userFacingMessage }

    /// Best-effort human-readable message for the UI layer.
    /// CLAUDE.md §4.2 mandates the SLUG_TAKEN / RESERVED_SLUG copy.
    public var userFacingMessage: String {
        switch self {
        case .authCancelled:
            return "Sign-in cancelled."
        case .authFailed(let m):
            return m
        case .invalidConfiguration(let m):
            return "Configuration error: \(m)"
        case .network(let urlError):
            return Self.networkMessage(for: urlError)
        case .decode(let m):
            return "Couldn't read the server's response. (\(m))"
        case .notFound:
            return "Not found."
        case .forbidden:
            return "You don't have access to that."
        case .validation(_, let detail), .conflict(_, let detail):
            return detail
        case .aiUnavailable:
            return "Voice service is temporarily unavailable."
        case .rateLimited(let retry):
            if let r = retry { return "Too many requests. Try again in \(Int(r))s." }
            return "Too many requests. Please wait a moment."
        case .quotaExceeded(let info):
            let formatter = RelativeDateTimeFormatter()
            let resetText = formatter.localizedString(for: info.resetsAtDate, relativeTo: .now)
            return "You've used \(info.used) of \(info.limit) AI calls on the \(info.tier) tier. Resets \(resetText)."
        case .unauthorized:
            return "Please sign in again."
        case .badRequest(let code, let message),
             .serverError(_, let code, .some(let message)) where !message.isEmpty:
            return Self.localizedMessage(forCode: code, fallback: message)
        case .serverError(let status, let code, _):
            return Self.localizedMessage(forCode: code, fallback: "Server error (\(status)).")
        }
    }

    /// True when the error is something a support contact (not a retry) is the right next step.
    public var requiresSupportContact: Bool {
        switch code {
        case .some(.slugTaken), .some(.reservedSlug), .some(.drupalProvisionFailed):
            return true
        default:
            return false
        }
    }

    private static func networkMessage(for urlError: URLError) -> String {
        switch urlError.code {
        case .cannotConnectToHost, .networkConnectionLost, .timedOut:
            return "Can't reach the RareImagery server. For local dev, run `npm run dev` in x-store-next " +
                "and confirm API_BASE_URL in Debug.xcconfig points at it."
        case .notConnectedToInternet:
            return "No internet connection. Check your network and try again."
        default:
            return "Network error: \(urlError.localizedDescription)"
        }
    }

    private static func localizedMessage(forCode code: MobileErrorCode?, fallback: String) -> String {
        guard let code = code else { return fallback }
        switch code {
        case .slugTaken:
            return "Your X handle is already in use or restricted. If this is your verified handle, contact support."
        case .reservedSlug:
            return "Your X handle conflicts with a reserved name. Pick a different X handle or contact support."
        case .drupalProvisionFailed:
            return "We couldn't finish setting up your store. Please try again — if it persists, contact support."
        case .xTokenExchangeFailed, .xUserFetchFailed:
            return "Couldn't reach X to verify your account. Please try again."
        case .serverMisconfigured:
            return "The server isn't configured for sign-in right now. Please try again later."
        case .internalError:
            return "Something went wrong on our end. Please try again."
        case .tokenExpired:
            return "Your session expired. Please sign in again."
        case .tokenMissing, .tokenInvalid, .wrongAudience, .mobileAuthFailed, .unauthorized:
            return "Your session is invalid. Please sign in again."
        case .appleAuthNotReady:
            return "Apple Sign-In isn't ready yet. Use Continue with X."
        case .unknownClient:
            return "This app build isn't registered for sign-in. Update the app or contact support."
        case .drupalMintFailed:
            return fallback.isEmpty
                ? "We couldn't finish signing you in. Please try again."
                : fallback
        case .drupalError:
            return fallback.isEmpty
                ? "We couldn't finish setting up your store. Please try again."
                : fallback
        case .grantNotEnabled:
            return "Sign-in isn't configured for this app yet. Contact support."
        case .validationFailed:
            return fallback.isEmpty
                ? "Sign-in request was invalid. Please try again."
                : fallback
        case .badRequest:
            return fallback
        }
    }
}
