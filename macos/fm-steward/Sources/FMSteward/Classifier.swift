import Foundation

/// Classifies a risk card: rules pre-pass first, then injectable Foundation Models backend.
///
/// - Important: This path does **not** enforce the product ≤500ms timeout. Hosts and the CLI
///   should use `StewardSession` for timeout + cancel. `Classifier` is the pure pipeline
///   (rules + normalize) for tests and composition.
public struct Classifier: Sendable {
    private let backend: any FoundationModelBackend

    public init(backend: any FoundationModelBackend = UnavailableBackend()) {
        self.backend = backend
    }

    /// Classify `card` without a wall-clock timeout.
    ///
    /// Ask* without non-empty explain demotes to fallback **continue** (anti-ask-spam soft residual).
    public func classify(_ card: RiskCard) async -> ClassifyResponse {
        if let hit = ClassifyPipeline.rulesHit(card) {
            return hit
        }
        let backendResponse = await backend.classify(card)
        return ClassifyPipeline.normalizeBackend(backendResponse)
    }
}
