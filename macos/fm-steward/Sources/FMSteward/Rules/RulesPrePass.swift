import Foundation

/// Deterministic first-hit rules so CI/demo machines without Foundation Models
/// still get correct fixture verdicts. Order is fixed (first hit wins).
public enum RulesPrePass {
    /// Returns a response when a rule matches; `nil` means fall through to the FM backend.
    public static func evaluate(_ card: RiskCard) -> ClassifyResponse? {
        // 1. executed == false → continue (grep / data, not execution)
        if card.features.executed == false {
            return .rulesContinue(why: "executed=false; action is data/inspection, not execution.")
        }

        // 2. same_intent == "test_loop" → continue
        if card.features.sameIntent == "test_loop" {
            return .rulesContinue(why: "same_intent=test_loop; repeated safe test intent.")
        }

        // 3. vip == true → ask_sticky_candidate + explain
        if card.features.vip == true {
            return askSticky(
                why: "Recipient is flagged VIP.",
                explain: "This message targets a VIP recipient. Confirm the send is intentional before proceeding.",
                effectClass: stickyEffectClass(for: card) ?? "external-message"
            )
        }

        // 4. bulk_outbound == true OR recipient_count >= bulk_recipient_min → ask* + explain
        let bulkFlag = card.features.bulkOutbound == true
        let count = card.features.recipientCount
        let bulkByCount = count.map { $0 >= card.bulkRecipientMin } ?? false
        if bulkFlag || bulkByCount {
            let recipients = count.map(String.init) ?? "many"
            return ask(
                why: "Bulk outbound (\(recipients) recipients) exceeds policy nuance threshold.",
                explain: "The agent is about to send a very large number of external messages. Confirm this bulk send is intentional.",
                effectClass: stickyEffectClass(for: card) ?? "external-message"
            )
        }

        // 5. else → backend
        return nil
    }

    private static func stickyEffectClass(for card: RiskCard) -> String? {
        card.features.effectHints?.first
    }

    /// Rules always pass non-empty explain literals; validation cannot fail.
    private static func ask(why: String, explain: String, effectClass: String) -> ClassifyResponse {
        (try? ClassifyResponse.make(
            verdict: .ask,
            why: why,
            explain: explain,
            suggestedStickyScope: "effect_class",
            suggestedEffectClass: effectClass,
            timedOut: false,
            fallback: false,
            modelAvailable: true
        )) ?? ClassifyResponse(
            verdict: .ask,
            why: why,
            explain: explain,
            suggestedStickyScope: "effect_class",
            suggestedEffectClass: effectClass,
            timedOut: false,
            fallback: false,
            modelAvailable: true
        )
    }

    private static func askSticky(why: String, explain: String, effectClass: String) -> ClassifyResponse {
        (try? ClassifyResponse.make(
            verdict: .askStickyCandidate,
            why: why,
            explain: explain,
            suggestedStickyScope: "effect_class",
            suggestedEffectClass: effectClass,
            timedOut: false,
            fallback: false,
            modelAvailable: true
        )) ?? ClassifyResponse(
            verdict: .askStickyCandidate,
            why: why,
            explain: explain,
            suggestedStickyScope: "effect_class",
            suggestedEffectClass: effectClass,
            timedOut: false,
            fallback: false,
            modelAvailable: true
        )
    }
}
