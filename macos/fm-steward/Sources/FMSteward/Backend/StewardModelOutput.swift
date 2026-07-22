#if canImport(FoundationModels)
import FoundationModels

/// Structured generation target for the on-device System Language Model.
///
/// Constrained via guided generation so the model cannot invent free-form
/// verdict strings outside the product enum.
@Generable(description: "Orca FM steward classify decision for a structured risk card")
struct StewardModelOutput {
    @Guide(
        description: "Security soft-interrupt decision",
        .anyOf(["continue", "ask", "ask_sticky_candidate"])
    )
    var verdict: String

    @Guide(description: "One short sentence why this verdict was chosen (no secrets)")
    var why: String

    @Guide(
        description:
            "Plain-language user explanation when verdict is ask or ask_sticky_candidate; empty string when continue"
    )
    var explain: String

    @Guide(
        description:
            "Sticky allow scope only when verdict is ask_sticky_candidate; otherwise empty. One of: once, session, effect_class, or empty",
        .anyOf(["", "once", "session", "effect_class"])
    )
    var suggestedStickyScope: String

    @Guide(
        description:
            "Effect class for sticky when suggestedStickyScope is effect_class; otherwise empty. Prefer external-message, shell, file, network, pay, browser",
        .anyOf(["", "external-message", "shell", "file", "network", "pay", "browser"])
    )
    var suggestedEffectClass: String
}
#endif
