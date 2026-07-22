import Foundation

/// Pluggable Foundation Models (or stub) classify path used after rules pre-pass.
public protocol FoundationModelBackend: Sendable {
    func classify(_ card: RiskCard) async -> ClassifyResponse
}
