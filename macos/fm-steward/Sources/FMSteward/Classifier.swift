import Foundation

/// Classifies a risk card: rules pre-pass first, then injectable Foundation Models backend.
///
/// - Important: This path does **not** enforce the product default timeout (3s). Hosts and the CLI
///   should use `StewardSession` for timeout + cancel. `Classifier` is the pure pipeline
///   (rules + normalize) for tests and composition.
///
/// ## Residual few-shot / RAG — not on this type
///
/// `Classifier` has **no** few-shot retriever, no Wax store, and no residual RAG path.
/// It never accepts or injects neighbor examples. Residual few-shot assist is **only**
/// composed on `StewardSession` after the host builds a retriever via
/// `FewShotRuntime.makeRetriever` (see README **Host attach**). Do not bolt a
/// retriever onto `Classifier` for product hosts.
public struct Classifier: Sendable {
    private let backend: any FoundationModelBackend

    public init(backend: any FoundationModelBackend = LiveBackend.preferredDefault()) {
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
