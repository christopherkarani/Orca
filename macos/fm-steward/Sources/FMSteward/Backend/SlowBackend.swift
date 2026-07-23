import Foundation

/// Test / demo backend that sleeps before returning a canned response.
///
/// Used to prove steward timeout races: even if this would eventually return
/// `ask`, the session must surface `continue` + `timed_out` + `fallback` when
/// the sleep exceeds `timeout_ms` — never the late ask.
///
/// Honors task cancellation promptly (cooperative). For the cancellation-blind
/// residual (non-cooperative FM drain), see `CancellationBlindBackend`.
public struct SlowBackend: FoundationModelBackend {
    public let delayMs: Int
    public let response: ClassifyResponse

    /// - Parameters:
    ///   - delayMs: Sleep duration before returning `response` (clamped to session max).
    ///   - response: Canned classify result (defaults to a late **ask** so
    ///     timeout tests can assert the ask never surfaces).
    public init(delayMs: Int = 2000, response: ClassifyResponse? = nil) {
        self.delayMs = min(max(0, delayMs), StewardSession.maxTimeoutMs)
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
            // Cancelled by StewardSession timeout race — return soft fallback, never late ask.
            return .fallbackContinue(
                why: "SlowBackend cancelled; fallback continue (must not surface late ask).",
                modelAvailable: true,
                timedOut: true,
                latencyMs: nil
            )
        }
        return response
    }
}

/// Test double: sleeps **without** honoring `Task.isCancelled` (unlike `SlowBackend`).
///
/// Documents the residual that `StewardSession` timeout is cooperative under
/// structured concurrency: when the timer wins, the residual child is cancelled
/// and the group still **drains** it before `classify` returns. A cancellation-blind
/// backend (or real non-cooperative on-device FM) can therefore make wall-clock
/// on classify return exceed `timeoutMs` by the remaining work — even though the
/// logical outcome is already `timed_out` + `continue`. Do **not** claim a hard
/// wall-clock kill of non-cooperative Foundation Models.
public struct CancellationBlindBackend: FoundationModelBackend {
    public let delayMs: Int
    public let response: ClassifyResponse

    /// - Parameters:
    ///   - delayMs: Wall sleep before returning `response` (clamped to session max).
    ///   - response: Canned classify result (defaults to a late **ask** that must
    ///     not surface after steward timeout — same product law as `SlowBackend`).
    public init(delayMs: Int = 2000, response: ClassifyResponse? = nil) {
        self.delayMs = min(max(0, delayMs), StewardSession.maxTimeoutMs)
        self.response = response ?? ClassifyResponse(
            verdict: .ask,
            why: "CancellationBlindBackend late response (must not surface after steward timeout).",
            explain: "This late ask must never be returned when the steward times out.",
            timedOut: false,
            fallback: false,
            modelAvailable: true
        )
    }

    public func classify(_ card: RiskCard) async -> ClassifyResponse {
        _ = card
        // Non-cooperative sleep: DispatchQueue.asyncAfter is not cancelled by
        // Task cancellation, so the child keeps running until delayMs elapses.
        let remaining = max(0, delayMs)
        if remaining > 0 {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(remaining)) {
                    cont.resume()
                }
            }
        }
        return response
    }
}
