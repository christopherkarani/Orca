import Foundation

/// Verdict enum matching `Schemas/classify-response-v1.json` exactly.
public enum Verdict: String, Codable, Sendable, Equatable {
    case `continue` = "continue"
    case ask = "ask"
    case askStickyCandidate = "ask_sticky_candidate"

    public var requiresExplain: Bool {
        switch self {
        case .ask, .askStickyCandidate:
            return true
        case .continue:
            return false
        }
    }
}

public enum ClassifyResponseError: Error, Equatable, Sendable {
    /// Ask / ask_sticky_candidate verdicts must carry a non-empty explain string.
    case explainRequired
}

/// Classify response matching `Schemas/classify-response-v1.json`.
public struct ClassifyResponse: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var verdict: Verdict
    public var why: String
    public var explain: String?
    public var suggestedStickyScope: String?
    public var suggestedEffectClass: String?
    public var timedOut: Bool
    public var fallback: Bool
    public var modelAvailable: Bool
    public var latencyMs: Int?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case verdict
        case why
        case explain
        case suggestedStickyScope = "suggested_sticky_scope"
        case suggestedEffectClass = "suggested_effect_class"
        case timedOut = "timed_out"
        case fallback
        case modelAvailable = "model_available"
        case latencyMs = "latency_ms"
    }

    /// Validating factory: enforces non-empty `explain` for ask / ask_sticky_candidate.
    public static func make(
        schemaVersion: Int = 1,
        verdict: Verdict,
        why: String,
        explain: String? = nil,
        suggestedStickyScope: String? = nil,
        suggestedEffectClass: String? = nil,
        timedOut: Bool = false,
        fallback: Bool = false,
        modelAvailable: Bool,
        latencyMs: Int? = nil
    ) throws -> ClassifyResponse {
        try requireExplain(verdict: verdict, explain: explain)
        return ClassifyResponse(
            schemaVersion: schemaVersion,
            verdict: verdict,
            why: why,
            explain: explain,
            suggestedStickyScope: suggestedStickyScope,
            suggestedEffectClass: suggestedEffectClass,
            timedOut: timedOut,
            fallback: fallback,
            modelAvailable: modelAvailable,
            latencyMs: latencyMs
        )
    }

    /// Unchecked memberwise for same-module stubs/tests. Prefer `make` for ask*.
    init(
        schemaVersion: Int = 1,
        verdict: Verdict,
        why: String,
        explain: String? = nil,
        suggestedStickyScope: String? = nil,
        suggestedEffectClass: String? = nil,
        timedOut: Bool = false,
        fallback: Bool = false,
        modelAvailable: Bool,
        latencyMs: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.verdict = verdict
        self.why = why
        self.explain = explain
        self.suggestedStickyScope = suggestedStickyScope
        self.suggestedEffectClass = suggestedEffectClass
        self.timedOut = timedOut
        self.fallback = fallback
        self.modelAvailable = modelAvailable
        self.latencyMs = latencyMs
    }

    /// Continue under rules pre-pass (not a model fallback; `modelAvailable=false`).
    public static func rulesContinue(why: String, latencyMs: Int? = nil) -> ClassifyResponse {
        ClassifyResponse(
            verdict: .continue,
            why: why,
            explain: nil,
            timedOut: false,
            fallback: false,
            modelAvailable: false,
            latencyMs: latencyMs
        )
    }

    /// Fallback continue when backend/model is unavailable or timed out.
    public static func fallbackContinue(
        why: String,
        modelAvailable: Bool,
        timedOut: Bool = false,
        latencyMs: Int? = nil
    ) -> ClassifyResponse {
        ClassifyResponse(
            verdict: .continue,
            why: why,
            explain: nil,
            timedOut: timedOut,
            fallback: true,
            modelAvailable: modelAvailable,
            latencyMs: latencyMs
        )
    }

    /// Ensure ask* responses never leave with empty explain (last-line defense).
    public func enforcingExplain() throws -> ClassifyResponse {
        try Self.requireExplain(verdict: verdict, explain: explain)
        return self
    }

    private static func requireExplain(verdict: Verdict, explain: String?) throws {
        if verdict.requiresExplain {
            guard let explain, !explain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ClassifyResponseError.explainRequired
            }
        }
    }
}
