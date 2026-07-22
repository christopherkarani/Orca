import Foundation

/// Backend used when Foundation Models are not available (CI, Linux skip path, demos).
/// Always returns fallback continue — never invents ask verdicts.
public struct UnavailableBackend: FoundationModelBackend {
    public init() {}

    public func classify(_ card: RiskCard) async -> ClassifyResponse {
        .fallbackContinue(
            why: "FM steward unavailable; continuing under policy and hard fence only.",
            modelAvailable: false,
            timedOut: false
        )
    }
}
