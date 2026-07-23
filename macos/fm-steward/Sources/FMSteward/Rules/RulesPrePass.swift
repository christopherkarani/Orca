import Foundation

/// Deterministic first-hit rules so CI/demo machines without Foundation Models
/// still get correct fixture verdicts. Order is fixed (first hit wins).
///
/// **v1 focus:** shell / command safety short-circuits only.
/// 1. `executed == false` → continue
/// 2. `same_intent == test_loop` → continue
/// 3. `CommandShape.skipFM` (echo/search/comment/print/var+echo/safe-clean) → continue
/// 4. `HardDangerRules` → ask (clear catastrophe / exfil / RCE)
/// 5. else → FM backend (residual gray)
///
/// Email bulk/VIP are out of v1 steward rules (ignored here; may still appear on cards).
///
/// Feature flags are **host-authoritative**. Do not feed agent-claimed
/// `executed` / `same_intent` without host recompute (Phase 4).
public enum RulesPrePass {
    /// Known sticky effect-class allowlist (shell-first for v1).
    public static let allowedEffectClasses: Set<String> = [
        "shell",
        "file",
        "network",
        "external-message",
        "pay",
        "browser",
    ]

    /// Default sticky effect class for shell steward v1.
    public static let defaultEffectClass = "shell"

    /// Floor/ceiling retained for schema/host thresholds (not used by v1 rules).
    public static let minBulkRecipientMin = 1
    public static let maxBulkRecipientMin = 1_000_000

    /// Returns a response when a rule matches; `nil` means fall through to the FM backend.
    public static func evaluate(_ card: RiskCard) -> ClassifyResponse? {
        // 1. executed == false → continue (grep / data / inspection, not execution)
        if card.features.executed == false {
            return .rulesContinue(why: "executed=false; command is data/inspection, not execution.")
        }

        // 2. same_intent == "test_loop" → continue (repeated safe test intent)
        if card.features.sameIntent == "test_loop" {
            return .rulesContinue(why: "same_intent=test_loop; repeated safe test intent.")
        }

        // 3. Command shape: echo/grep/comment of dangerous strings, print-only, var+echo, safe dev clean.
        // Only when a command string is present (nil command e.g. email cards must not match).
        if let command = card.command {
            let shape = CommandShape.analyze(command: command, executed: card.features.executed)
            if shape.skipFM {
                return .rulesContinue(why: shape.reason)
            }
        }

        // 4. Deterministic soft-ask for clear catastrophe / exfil / RCE patterns (do not wait on FM).
        if let hardAsk = HardDangerRules.evaluate(card) {
            return hardAsk
        }

        // 5. else → on-device FM (residual semantic gray)
        // v1 deliberately does not short-circuit on email bulk/VIP features.
        return nil
    }

    /// Map card effect hints through the allowlist; unknown → default shell.
    public static func stickyEffectClass(for card: RiskCard) -> String {
        guard let first = card.features.effectHints?.first, !first.isEmpty else {
            return defaultEffectClass
        }
        if allowedEffectClasses.contains(first) {
            return first
        }
        return defaultEffectClass
    }

    /// Clamp a caller bulk threshold into a sane range (host field; unused by v1 rules).
    public static func clampBulkRecipientMin(_ raw: Int?) -> Int {
        guard let raw else { return RiskCard.defaultBulkRecipientMin }
        if raw < minBulkRecipientMin || raw > maxBulkRecipientMin {
            return RiskCard.defaultBulkRecipientMin
        }
        return raw
    }
}
