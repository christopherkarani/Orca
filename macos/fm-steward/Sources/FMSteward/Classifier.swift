import Foundation

/// Classifies a risk card: rules pre-pass first, then injectable Foundation Models backend.
public struct Classifier: Sendable {
    private let backend: any FoundationModelBackend

    public init(backend: any FoundationModelBackend = UnavailableBackend()) {
        self.backend = backend
    }

    /// Classify `card`. Ask* verdicts always leave with non-empty `explain`
    /// (rules construct via validating factory; backend responses are re-checked).
    /// Explain re-check failures fail closed to fallback continue (never surface broken ask*).
    public func classify(_ card: RiskCard) async -> ClassifyResponse {
        if let hit = RulesPrePass.evaluate(card) {
            // Rules path validates explain on ask*; fail closed if contract is broken.
            if let valid = try? hit.enforcingExplain() {
                return valid
            }
            return .fallbackContinue(
                why: "Rules returned ask without explain; falling back to continue under policy and hard fence only.",
                modelAvailable: hit.modelAvailable,
                timedOut: hit.timedOut,
                latencyMs: hit.latencyMs
            )
        }

        let backendResponse = await backend.classify(card)
        if backendResponse.verdict.requiresExplain {
            if let valid = try? backendResponse.enforcingExplain() {
                return valid
            }
            // Backend returned ask* without explain — fail closed to fallback continue.
            return .fallbackContinue(
                why: "Backend returned ask without explain; falling back to continue under policy and hard fence only.",
                modelAvailable: backendResponse.modelAvailable,
                timedOut: backendResponse.timedOut,
                latencyMs: backendResponse.latencyMs
            )
        }
        return backendResponse
    }
}
