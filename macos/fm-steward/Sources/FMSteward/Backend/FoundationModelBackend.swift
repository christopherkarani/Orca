import Foundation

/// Pluggable Foundation Models (or stub) classify path used after rules pre-pass.
///
/// - Important: `StewardSession` races this call against `timeoutMs` using a task
///   group and cancels the losing child. Implementations **must** honor task
///   cancellation promptly (poll `Task.checkCancellation()` / use cancelable
///   awaits). Structured concurrency joins children before `classify` returns to
///   the caller — a cancellation-blind hang blocks the session past the timeout
///   even when the logical outcome is already `timed_out`.
/// - Note: Late results after cancel are discarded by the session. On cancel,
///   prefer returning a cheap fallback continue (or exiting promptly) rather
///   than a late `ask`.
public protocol FoundationModelBackend: Sendable {
    /// Optional warm / preload. Default: no-op.
    func prepareWarm() async

    /// Classify a risk card after rules pre-pass missed.
    func classify(_ card: RiskCard) async -> ClassifyResponse
}

extension FoundationModelBackend {
    public func prepareWarm() async {}
}
