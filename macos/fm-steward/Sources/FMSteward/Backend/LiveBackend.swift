import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Live on-device Apple Foundation Models backend (`SystemLanguageModel`).
///
/// Uses guided generation (`@Generable` `StewardModelOutput`) so gray-area cards
/// that miss the rules pre-pass get a real semantic verdict. Rules still win first
/// for fixture demos / CI without waiting on the model.
///
/// When the framework is missing, Apple Intelligence is off, or generation fails,
/// returns fallback **continue** (never invents ask; never unlocks hard fence).
public actor LiveBackend: FoundationModelBackend {
    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    public init() {}

    /// Prefer live FM when the on-device model is available; otherwise unavailable stub.
    public static func preferredDefault() -> any FoundationModelBackend {
        if isFoundationModelsFrameworkPresent && isOnDeviceModelAvailable {
            return LiveBackend()
        }
        return UnavailableBackend()
    }

    /// Whether the Apple FoundationModels module is linked/importable in this build.
    public nonisolated static var isFoundationModelsFrameworkPresent: Bool {
        #if canImport(FoundationModels)
        true
        #else
        false
        #endif
    }

    /// Runtime: on-device model assets ready and Apple Intelligence enabled.
    public nonisolated static var isOnDeviceModelAvailable: Bool {
        #if canImport(FoundationModels)
        SystemLanguageModel.default.isAvailable
        #else
        false
        #endif
    }

    public nonisolated static var availabilityDescription: String {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "unavailable(deviceNotEligible)"
            case .appleIntelligenceNotEnabled:
                return "unavailable(appleIntelligenceNotEnabled)"
            case .modelNotReady:
                return "unavailable(modelNotReady)"
            @unknown default:
                return "unavailable(unknown)"
            }
        @unknown default:
            return "unknown"
        }
        #else
        return "framework_not_linked"
        #endif
    }

    public func prepareWarm() async {
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return }
        let session = ensureSession()
        session.prewarm()
        #endif
    }

    public func classify(_ card: RiskCard) async -> ClassifyResponse {
        #if canImport(FoundationModels)
        if Task.isCancelled {
            return cancelFallback()
        }

        guard SystemLanguageModel.default.isAvailable else {
            return .fallbackContinue(
                why:
                    "On-device Foundation Model unavailable (\(Self.availabilityDescription)); continuing under policy and hard fence only.",
                modelAvailable: false,
                timedOut: false
            )
        }

        let session = ensureSession()
        let prompt = Self.prompt(for: card)
        let options = GenerationOptions(
            sampling: .greedy,
            temperature: 0.2,
            maximumResponseTokens: 256
        )

        do {
            try Task.checkCancellation()
            let response = try await session.respond(
                to: prompt,
                generating: StewardModelOutput.self,
                options: options
            )
            if Task.isCancelled {
                return cancelFallback()
            }
            return Self.mapOutput(response.content)
        } catch is CancellationError {
            return cancelFallback()
        } catch {
            if Task.isCancelled {
                return cancelFallback()
            }
            return .fallbackContinue(
                why:
                    "Foundation Model generation failed (\(error.localizedDescription)); continuing under policy and hard fence only.",
                modelAvailable: true,
                timedOut: false
            )
        }
        #else
        return .fallbackContinue(
            why: "FoundationModels framework not linked; continuing under policy and hard fence only.",
            modelAvailable: false,
            timedOut: false
        )
        #endif
    }

    #if canImport(FoundationModels)
    private func ensureSession() -> LanguageModelSession {
        if let session {
            return session
        }
        let created = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: Self.systemInstructions
        )
        session = created
        return created
    }

    private func cancelFallback() -> ClassifyResponse {
        .fallbackContinue(
            why: "Live Foundation Model classify cancelled; continuing under policy and hard fence only.",
            modelAvailable: true,
            timedOut: true
        )
    }

    /// Compact risk-card prompt — features only, never full agent transcripts.
    nonisolated static func prompt(for card: RiskCard) -> String {
        let f = card.features
        var lines: [String] = [
            "Classify this agent tool risk card.",
            "tool: \(card.tool)",
        ]
        if let command = card.command, !command.isEmpty {
            // Cap command length so we never dump huge shells into the model.
            let clipped = command.count > 400 ? String(command.prefix(400)) + "…" : command
            lines.append("command: \(clipped)")
        }
        lines.append("features.executed: \(stringify(f.executed))")
        lines.append("features.bulk_outbound: \(stringify(f.bulkOutbound))")
        lines.append("features.vip: \(stringify(f.vip))")
        lines.append("features.same_intent: \(stringify(f.sameIntent))")
        lines.append("features.recipient_count: \(stringify(f.recipientCount))")
        lines.append("features.recipient_class: \(stringify(f.recipientClass))")
        lines.append("features.amount: \(stringify(f.amount))")
        lines.append("features.currency: \(stringify(f.currency))")
        if let hints = f.effectHints, !hints.isEmpty {
            lines.append("features.effect_hints: \(hints.joined(separator: ","))")
        }
        lines.append("thresholds.bulk_recipient_min: \(card.bulkRecipientMin)")
        lines.append(
            "Return structured verdict. Prefer continue for safe/gray-low; ask for bulk/VIP/high-risk outbound."
        )
        return lines.joined(separator: "\n")
    }

    nonisolated static let systemInstructions = """
        You are Orca's Mac on-device semantic steward (Apple Foundation Model).
        You classify structured agent risk cards AFTER policy and hard-fence checks.
        You never authorize catastrophic shell; hard deny is decided elsewhere.
        Your only job is soft-interrupt: continue vs ask.

        Verdict rules:
        - continue: low risk / safe inspection / repeated safe test intent / no meaningful user interrupt needed.
        - ask: user should confirm (bulk outbound, ambiguous external side effects).
        - ask_sticky_candidate: ask AND sticky allow may be appropriate (VIP recipients, repeated trusted pattern candidates).

        Output constraints:
        - why: one short sentence, no secrets, no PII dumps.
        - explain: required non-empty prose when verdict is ask or ask_sticky_candidate; empty when continue.
        - suggestedStickyScope / suggestedEffectClass: only populate for ask_sticky_candidate; empty strings otherwise.
        - Prefer continue when features are incomplete rather than inventing risk.
        - Never invent deny/allow; only continue|ask|ask_sticky_candidate.
        """

    nonisolated static func mapOutput(_ out: StewardModelOutput) -> ClassifyResponse {
        let verdict: Verdict
        switch out.verdict {
        case "ask":
            verdict = .ask
        case "ask_sticky_candidate":
            verdict = .askStickyCandidate
        default:
            verdict = .continue
        }

        let explainRaw = out.explain.trimmingCharacters(in: .whitespacesAndNewlines)
        let explain: String? = explainRaw.isEmpty ? nil : explainRaw

        var stickyScope: String? = nil
        var effectClass: String? = nil
        if verdict == .askStickyCandidate {
            let scope = out.suggestedStickyScope.trimmingCharacters(in: .whitespacesAndNewlines)
            if !scope.isEmpty {
                stickyScope = scope
            } else {
                stickyScope = "effect_class"
            }
            let ec = out.suggestedEffectClass.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ec.isEmpty, RulesPrePass.allowedEffectClasses.contains(ec) {
                effectClass = ec
            } else {
                effectClass = RulesPrePass.defaultEffectClass
            }
        }

        // Validating factory demotes broken ask* at Classifier/Session boundary too.
        if let made = try? ClassifyResponse.make(
            verdict: verdict,
            why: out.why.isEmpty ? "On-device model classified risk card." : out.why,
            explain: explain,
            suggestedStickyScope: stickyScope,
            suggestedEffectClass: effectClass,
            timedOut: false,
            fallback: false,
            modelAvailable: true
        ) {
            return made
        }

        // Model returned ask* without usable explain — soft residual continue.
        return .fallbackContinue(
            why: "On-device model returned ask without explain; demoting to continue under policy and hard fence only.",
            modelAvailable: true,
            timedOut: false
        )
    }

    nonisolated private static func stringify<T>(_ value: T?) -> String {
        guard let value else { return "null" }
        return String(describing: value)
    }
    #endif
}
