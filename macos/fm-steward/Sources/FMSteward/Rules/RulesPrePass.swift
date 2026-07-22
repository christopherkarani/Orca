import Foundation

/// Deterministic first-hit rules so CI/demo machines without Foundation Models
/// still get correct fixture verdicts. Order is fixed (first hit wins).
///
/// Feature flags and thresholds are **host-authoritative**. Do not feed agent-claimed
/// `executed` / `same_intent` / `vip` / bulk fields without host recompute (Phase 4).
public enum RulesPrePass {
    /// Known sticky effect-class allowlist (plan ontology subset). Unknown hints ignored.
    public static let allowedEffectClasses: Set<String> = [
        "external-message",
        "shell",
        "file",
        "network",
        "pay",
        "browser",
    ]

    /// Default sticky effect class when hints are missing or not allowlisted.
    public static let defaultEffectClass = "external-message"

    /// Floor/ceiling for caller `bulk_recipient_min` (absurd overrides demoted to default).
    public static let minBulkRecipientMin = 1
    public static let maxBulkRecipientMin = 1_000_000

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
        // VIP list files: steward does not read `thresholds.vip_list_path` in Phase 3;
        // host must set `features.vip` (path is host-only metadata).
        if card.features.vip == true {
            return ask(
                verdict: .askStickyCandidate,
                why: "Recipient is flagged VIP.",
                explain: "This message targets a VIP recipient. Confirm the send is intentional before proceeding.",
                stickyScope: "effect_class",
                effectClass: stickyEffectClass(for: card)
            )
        }

        // 4. bulk_outbound == true OR recipient_count >= bulk_recipient_min → ask + explain
        // Plain ask: sticky suggestion fields stay null (schema: null when not sticky-candidate).
        let bulkFlag = card.features.bulkOutbound == true
        let count = card.features.recipientCount
        let bulkByCount = count.map { $0 >= card.bulkRecipientMin } ?? false
        if bulkFlag || bulkByCount {
            let recipients = count.map(String.init) ?? "many"
            return ask(
                verdict: .ask,
                why: "Bulk outbound (\(recipients) recipients) exceeds policy nuance threshold.",
                explain: "The agent is about to send a very large number of external messages. Confirm this bulk send is intentional.",
                stickyScope: nil,
                effectClass: nil
            )
        }

        // 5. else → backend
        return nil
    }

    /// Map card effect hints through the allowlist; unknown → default.
    public static func stickyEffectClass(for card: RiskCard) -> String {
        guard let first = card.features.effectHints?.first, !first.isEmpty else {
            return defaultEffectClass
        }
        if allowedEffectClasses.contains(first) {
            return first
        }
        return defaultEffectClass
    }

    /// Clamp a caller bulk threshold into a sane range (host may still set any value in-card;
    /// absurd values are treated as the product default).
    public static func clampBulkRecipientMin(_ raw: Int?) -> Int {
        guard let raw else { return RiskCard.defaultBulkRecipientMin }
        if raw < minBulkRecipientMin || raw > maxBulkRecipientMin {
            return RiskCard.defaultBulkRecipientMin
        }
        return raw
    }

    /// Rules always pass non-empty explain literals; `make` cannot fail for these call sites.
    private static func ask(
        verdict: Verdict,
        why: String,
        explain: String,
        stickyScope: String?,
        effectClass: String?
    ) -> ClassifyResponse {
        // modelAvailable=false: pure rules path (not live FM generation).
        try! ClassifyResponse.make(
            verdict: verdict,
            why: why,
            explain: explain,
            suggestedStickyScope: stickyScope,
            suggestedEffectClass: effectClass,
            timedOut: false,
            fallback: false,
            modelAvailable: false
        )
    }
}
