import Foundation

/// Test / demo backend that sleeps before returning a canned response.
///
/// Used to prove steward timeout races: even if this would eventually return
/// `ask`, the session must surface `continue` + `timed_out` + `fallback` when
/// the sleep exceeds `timeout_ms` — never the late ask.
public struct SlowBackend: FoundationModelBackend {
    public let delayMs: Int
    public let response: ClassifyResponse

    /// - Parameters:
    ///   - delayMs: Sleep duration before returning `response`.
    ///   - response: Canned classify result (defaults to a late **ask** so
    ///     timeout tests can assert the ask never surfaces).
    public init(delayMs: Int = 2000, response: ClassifyResponse? = nil) {
        self.delayMs = max(0, delayMs)
        self.response = response ?? ClassifyResponse(
            verdict: .ask,
            why: "SlowBackend late response (must not surface after steward timeout).",
            explain: "This late ask must never be returned when the steward times out.",
            timedOut: false,
            fallback: false,
            modelAvailable: true
        )
    }

    public func classify(_ card: RiskCard) async -> ClassifyResponse {
        let ns = UInt64(delayMs) * 1_000_000
        do {
            try await Task.sleep(nanoseconds: ns)
        } catch {
            // Cancelled by StewardSession timeout race — parent ignores this result.
            return response
        }
        return response
    }
}
