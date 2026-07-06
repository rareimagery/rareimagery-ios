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
/// Phase 4.2 swap: `record(_:)` now POSTs to the BFF
/// `/api/v1/telemetry/event` endpoint in addition to the console log.
/// Console output stays for dev/Xcode visibility; BFF dispatch is
/// fire-and-forget (the Task is detached; failures log but never throw).
///
/// Configuration:
///   - `Analytics.configure(client:sessionId:)` is called once from
///     `AppState.init()` after the APIClient is created.
///   - Before configure runs OR if it's skipped (tests, previews), the
///     BFF dispatch is silently no-op — only console output happens.
///
/// Thread safety: the configuration statics are set exactly once during
/// `AppState.init()` (MainActor) and read from arbitrary contexts
/// thereafter. `nonisolated(unsafe)` documents the post-init-immutable
/// invariant explicitly under Swift 6 strict concurrency.
public enum Analytics {

    nonisolated(unsafe) private static var client: APIClient?
    nonisolated(unsafe) private static var sessionId: String?

    /// One-time configuration from `AppState.init()`. Safe to call
    /// multiple times — last value wins — but in practice once per
    /// app launch. `sessionId` groups events from a single app
    /// launch in the Drupal telemetry table.
    public static func configure(client: APIClient, sessionId: String) {
        Self.client = client
        Self.sessionId = sessionId
    }

    public static func record(_ event: AnalyticsEvent) {
        consolePrint(event)

        // Fire-and-forget BFF dispatch. Detached so it can't block the
        // caller (most call sites are SwiftUI bodies / view modifiers
        // where blocking would jank the UI). Errors log to console
        // only — analytics failures must NEVER surface in the UX.
        guard let client = Self.client else { return }
        let sessionId = Self.sessionId
        let clientEventId = UUID().uuidString.lowercased()

        Task.detached(priority: .background) {
            do {
                try await dispatch(
                    client: client,
                    event: event,
                    sessionId: sessionId,
                    clientEventId: clientEventId,
                )
            } catch {
                // eslint-style: log without throwing. iOS analytics
                // failures should never bubble — they're just lost
                // data points. The Drupal dedup on client_event_id
                // means a retry queue is trivial to add later.
                print("[analytics] dispatch failed for \(event.name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Dispatch

    private static func dispatch(
        client: APIClient,
        event: AnalyticsEvent,
        sessionId: String?,
        clientEventId: String,
    ) async throws {
        let request = TelemetryIngestRequest(
            eventType: event.name,
            payload: event.properties.isEmpty ? nil : event.properties,
            clientEventId: clientEventId,
            sessionId: sessionId,
            subjectType: nil,
            subjectId: nil,
        )
        let data = try JSONEncoder().encode(request)
        let endpoint = APIEndpoint(
            path: "/api/v1/telemetry/event",
            method: .post,
            body: data,
            requiresAuth: true,
            contentType: "application/json",
            // Short — the Drupal insert is single-row + indexed. Longer
            // wouldn't help; iOS Analytics is fire-and-forget anyway.
            timeout: 8,
        )
        // sendRaw — we don't care about the response body, only that
        // the call landed. Throws on non-2xx; the catch logs.
        _ = try await client.sendRaw(endpoint)
    }

    // MARK: - Console output (unchanged from Phase 3.3)

    private static func consolePrint(_ event: AnalyticsEvent) {
        let props = event.properties
        if props.isEmpty {
            print("[analytics] \(event.name)")
        } else {
            let propString = props
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            print("[analytics] \(event.name) \(propString)")
        }
    }
}

/// Wire request shape — matches `TelemetryEventSchema` in
/// x-store-next/src/app/api/v1/telemetry/event/route.ts. Actor fields
/// are deliberately absent — the BFF derives them from auth and would
/// overwrite anything we sent.
private struct TelemetryIngestRequest: Encodable {
    let eventType: String
    let payload: [String: String]?
    let clientEventId: String
    let sessionId: String?
    let subjectType: String?
    let subjectId: String?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case payload
        case clientEventId = "client_event_id"
        case sessionId = "session_id"
        case subjectType = "subject_type"
        case subjectId = "subject_id"
    }
}
