import Foundation

/// Single rules + explain-normalization path shared by `Classifier` and `StewardSession`.
///
/// Keeps fail-closed demotion (broken ask* → fallback continue) in one place so
/// the public entry points cannot drift.
enum ClassifyPipeline {
    /// Why string when rules return ask* without a usable explain (soft residual).
    static let rulesBrokenAskWhy =
        "Rules returned ask without explain; demoting to continue under policy and hard fence only (soft residual, not hard-fence fail-closed)."

    /// Why string when backend returns ask* without a usable explain (soft residual).
    static let backendBrokenAskWhy =
        "Backend returned ask without explain; demoting to continue under policy and hard fence only (soft residual, not hard-fence fail-closed)."

    /// Rules pre-pass short-circuit, with explain re-check on ask*.
    static func rulesHit(_ card: RiskCard) -> ClassifyResponse? {
        guard let hit = RulesPrePass.evaluate(card) else { return nil }
        if let valid = try? hit.enforcingExplain() {
            return valid
        }
        return .fallbackContinue(
            why: rulesBrokenAskWhy,
            modelAvailable: hit.modelAvailable,
            timedOut: hit.timedOut,
            latencyMs: hit.latencyMs
        )
    }

    /// Normalize a backend response: ask* without explain → fallback continue.
    static func normalizeBackend(
        _ response: ClassifyResponse,
        latencyMs: Int? = nil
    ) -> ClassifyResponse {
        let stamped = withLatency(response, latencyMs: latencyMs)
        if stamped.verdict.requiresExplain {
            if let valid = try? stamped.enforcingExplain() {
                return valid
            }
            return .fallbackContinue(
                why: backendBrokenAskWhy,
                modelAvailable: stamped.modelAvailable,
                timedOut: stamped.timedOut,
                latencyMs: stamped.latencyMs
            )
        }
        return stamped
    }

    private static func withLatency(_ response: ClassifyResponse, latencyMs: Int?) -> ClassifyResponse {
        guard let latencyMs else { return response }
        var copy = response
        if copy.latencyMs == nil {
            copy.latencyMs = latencyMs
        }
        return copy
    }
}
