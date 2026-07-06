import Foundation

/// Wraps POST /api/design-studio/generate + GET /api/design-studio/task/{key}
/// for the OnePageCreator visual generation flow.
///
/// ⚠ The generate route currently uses `getToken` (NextAuth cookie) only.
/// The BFF patch landing alongside this Phase 2 work adds mobile-Bearer
/// fallback via `requireSessionOrMobile`. If you see 401s on iOS, that
/// patch hasn't landed yet — see Plan Amendment 2026-05-24 in the plan
/// file for context.
///
/// Two response modes:
///   - `.fast` — stickers, embroidery, pet items (~10-15s) → `imageUrl` is
///     populated immediately on the POST response.
///   - `.background` — apparel, posters, canvas (~30-90s) → POST returns
///     a `taskKey` + `pollUrl`; call `pollUntilDone` to wait for completion.
public actor DesignGenerationRepository {
    private let client: APIClient
    private let logger = APILogger(category: "DesignGenerationRepository")

    /// Hard cap on background polling so a stuck task doesn't loop forever.
    /// 120s = 2 minutes ≈ p95 ceiling on Grok Imagine pro per the route's
    /// 30-90s observed range.
    private let maxPollingDuration: TimeInterval = 120

    public init(client: APIClient) {
        self.client = client
    }

    /// Kick off generation. Returns the raw response — caller decides
    /// whether to poll (background mode) or render immediately (fast).
    public func generate(_ request: DesignGenerationRequest) async throws -> DesignGenerationResponse {
        let body = try JSONEncoder().encode(request)
        let endpoint = APIEndpoint(
            path: "/api/design-studio/generate",
            method: .post,
            body: body,
            requiresAuth: true,
            contentType: "application/json",
            timeout: 60
        )
        return try await client.send(endpoint, as: DesignGenerationResponse.self)
    }

    /// Convenience: kick off + poll if background, return final image URL
    /// + the design_record UUID (Phase 4.3 lineage).
    ///
    /// Throws if the task ends in `.failed`, if polling times out, or if
    /// the response is malformed (background mode without a poll_url).
    ///
    /// `designRecordId` on the result is `nil` when the BFF telemetry
    /// write failed for this generation or when the BFF predates 4.3.
    /// Callers should still publish — lineage is best-effort, not required.
    public func generateAndWait(_ request: DesignGenerationRequest) async throws -> GeneratedDesignResult {
        let initial = try await generate(request)

        switch initial.mode {
        case .fast:
            guard let urlString = initial.imageUrl, let url = URL(string: urlString) else {
                throw DesignGenerationError.malformedResponse("fast mode missing image_url")
            }
            return GeneratedDesignResult(imageURL: url, designRecordId: initial.designRecordId)

        case .background:
            guard let taskKey = initial.taskKey else {
                throw DesignGenerationError.malformedResponse("background mode missing task_key")
            }
            let intervalMs = initial.pollIntervalMs ?? 5000
            return try await pollUntilDone(taskKey: taskKey, intervalMs: intervalMs)
        }
    }

    /// Poll the task endpoint until status moves off `.pending`.
    /// Returns the final image URL + design_record UUID on `.completed`;
    /// throws on `.failed` or if `maxPollingDuration` is exceeded.
    public func pollUntilDone(taskKey: String, intervalMs: Int) async throws -> GeneratedDesignResult {
        let deadline = Date().addingTimeInterval(maxPollingDuration)
        let interval = max(1, intervalMs) // never poll faster than 1Hz

        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(interval))

            let endpoint = APIEndpoint(
                path: "/api/design-studio/task/\(taskKey)",
                method: .get,
                requiresAuth: true,
                contentType: nil,
                timeout: 15
            )
            let status = try await client.send(endpoint, as: DesignTaskStatus.self)

            switch status.status {
            case .pending:
                continue
            case .completed:
                guard let urlString = status.imageUrl, let url = URL(string: urlString) else {
                    throw DesignGenerationError.malformedResponse("completed task missing image_url")
                }
                return GeneratedDesignResult(imageURL: url, designRecordId: status.designRecordId)
            case .failed:
                throw DesignGenerationError.taskFailed(status.error ?? "Image generation failed")
            }
        }
        throw DesignGenerationError.timeout
    }
}

public enum DesignGenerationError: LocalizedError, Sendable {
    case malformedResponse(String)
    case taskFailed(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .malformedResponse(let reason): return "Generation response invalid: \(reason)"
        case .taskFailed(let reason):        return reason
        case .timeout:                       return "Generation timed out — please try again."
        }
    }
}
