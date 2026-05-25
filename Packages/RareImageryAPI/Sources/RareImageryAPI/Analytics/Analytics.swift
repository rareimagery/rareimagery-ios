import Foundation

/// Centralized event enum for product analytics.
///
/// **v1 implementation: console print only.** When a real analytics
/// service lands (PostHog, Mixpanel, Amplitude, or a homegrown collector
/// on the BFF), swap the body of `Analytics.record(_:)` and every emit
/// point in the codebase starts shipping events with zero call-site
/// changes. The names + properties are stable contracts.
///
/// Naming convention (per Phase 3 spec): `snake_case` event names so
/// downstream tooling (warehouse, dashboards) doesn't have to renormalize.
/// Properties are `[String: String]` for v1 — sufficient for the trial
/// funnel and trivially Sendable. Upgrade to a typed-value sum type
/// (`AnalyticsValue.string | .int | .double | .bool`) when a real
/// service requires richer payloads.
public enum AnalyticsEvent: Sendable, Equatable {
    /// Fired once per app launch when bootstrap mints (or revives) an
    /// anonymous JWT. Top-of-funnel marker.
    case anonymousSessionStarted(deviceId: String)

    /// Fired after every successful `merch-ideas` call from an anonymous
    /// user (including graceful-fail vendor responses — they spent the
    /// rate-limit budget). `remaining` is the post-decrement count, so
    /// the sequence is 2 → 1 → 0 over the trial life.
    case freeMerchIdeasUsed(remaining: Int)

    /// Fired the FIRST time the persistent SignUpReminderBanner becomes
    /// visible (transition from `false → true` on
    /// `session.shouldShowSignUpReminder`). NOT fired on subsequent
    /// re-renders. Funnel signal: "trial budget exhausted, soft nudge
    /// surfaced."
    case signUpReminderShown

    /// Fired when an anonymous user taps an idea card and the ViewModel
    /// short-circuits before spending a generation call. Hard-wall
    /// trigger event — the dopamine moment.
    case generationGatedByAnonymous

    /// Fired when the sign-up sheet (SignInView) is presented from the
    /// trial flow — either from the banner CTA, the Create+Launch
    /// button while anonymous, or the gated idea tap. Conversion
    /// funnel: "user is now looking at the X auth screen."
    case xAuthInitiatedFromReminder

    public var name: String {
        switch self {
        case .anonymousSessionStarted:      return "anonymous_session_started"
        case .freeMerchIdeasUsed:           return "free_merch_ideas_used"
        case .signUpReminderShown:          return "sign_up_reminder_shown"
        case .generationGatedByAnonymous:   return "generation_gated_by_anonymous"
        case .xAuthInitiatedFromReminder:   return "x_auth_initiated_from_reminder"
        }
    }

    public var properties: [String: String] {
        switch self {
        case .anonymousSessionStarted(let deviceId):
            return ["device_id": deviceId]
        case .freeMerchIdeasUsed(let remaining):
            return ["remaining": String(remaining)]
        case .signUpReminderShown,
             .generationGatedByAnonymous,
             .xAuthInitiatedFromReminder:
            return [:]
        }
    }
}

/// Single emit point. Call sites stay stable across implementation swaps.
///
/// To wire a real service later, replace the body — add a SDK init in
/// `AppState.init()` (or `RareImageryApp`'s `init`) and have `record(_:)`
/// forward to the SDK. No call-site changes required.
public enum Analytics {
    public static func record(_ event: AnalyticsEvent) {
        let props = event.properties
        if props.isEmpty {
            print("[analytics] \(event.name)")
        } else {
            // Sort props for stable log output — easier to grep + diff
            // when manually tailing the simulator console.
            let propString = props
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            print("[analytics] \(event.name) \(propString)")
        }
    }
}
