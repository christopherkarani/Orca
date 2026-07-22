import Foundation

/// Live Foundation Models backend.
///
/// Phase 3 ships a stub/protocol path: demos and CI must succeed via rules pre-pass
/// without requiring on-device model generation. When the FoundationModels framework
/// is importable this reports `model_available=true` but still falls back to continue
/// rather than inventing free-form verdicts without a structured generation path.
///
/// Real generation can be filled in later without changing the classifier surface.
public struct LiveBackend: FoundationModelBackend {
    public init() {}

    public func classify(_ card: RiskCard) async -> ClassifyResponse {
        let available = Self.isFoundationModelsFrameworkPresent
        if available {
            // Structured FM generation not wired in Phase 3 unit u2; fail open to continue.
            return .fallbackContinue(
                why: "Live Foundation Models path present but structured generation is not enabled; continuing under policy and hard fence only.",
                modelAvailable: true,
                timedOut: false
            )
        }
        return .fallbackContinue(
            why: "Foundation Models framework unavailable; continuing under policy and hard fence only.",
            modelAvailable: false,
            timedOut: false
        )
    }

    /// Whether the Apple FoundationModels module is linked/importable in this build.
    public static var isFoundationModelsFrameworkPresent: Bool {
        #if canImport(FoundationModels)
        true
        #else
        false
        #endif
    }
}
