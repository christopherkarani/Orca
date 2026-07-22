import Foundation

/// Warm, reusable FM steward session with a hard classify timeout.
///
/// Rules pre-pass runs first (no backend wait). Backend-bound work is raced
/// against `timeoutMs` (default 500). On timeout or broken backend ask*,
/// returns fallback **continue** — never ask-spam.
public actor StewardSession {
    /// Product default: 500ms hard timeout for backend-bound classify work.
    public static let defaultTimeoutMs: Int = 500

    /// Effective default timeout for this session (overridable per `classify` call).
    public nonisolated let timeoutMs: Int

    private let backend: any FoundationModelBackend
    private var warmed: Bool = false

    public init(
        backend: any FoundationModelBackend = UnavailableBackend(),
        timeoutMs: Int = StewardSession.defaultTimeoutMs
    ) {
        self.backend = backend
        self.timeoutMs = max(0, timeoutMs)
    }

    /// Whether the session has been warmed (`warm()` or first `classify`).
    public var isWarmed: Bool { warmed }

    /// Mark the session warm for reuse (no cold start required on later classify).
    /// Phase 3: no on-device model preload; presence of a live session is enough.
    public func warm() {
        warmed = true
    }

    /// Classify `card`. Rules short-circuit without backend; otherwise race backend
    /// against `timeoutMs` (session default when nil).
    public func classify(_ card: RiskCard, timeoutMs: Int? = nil) async -> ClassifyResponse {
        markWarmed()

        // Rules first — never block fixtures / obvious cases on FM latency.
        if let hit = RulesPrePass.evaluate(card) {
            return (try? hit.enforcingExplain()) ?? hit
        }

        let bound = max(0, timeoutMs ?? self.timeoutMs)
        return await raceBackend(card: card, timeoutMs: bound)
    }

    // MARK: - Internals

    private func markWarmed() {
        if !warmed {
            warmed = true
        }
    }

    private enum RaceOutcome: Sendable {
        case response(ClassifyResponse)
        case timedOut
    }

    private func raceBackend(card: RiskCard, timeoutMs: Int) async -> ClassifyResponse {
        let start = ContinuousClock.now
        let backend = self.backend

        let outcome: RaceOutcome = await withTaskGroup(of: RaceOutcome.self) { group in
            group.addTask {
                let raw = await backend.classify(card)
                return .response(raw)
            }
            group.addTask {
                let ns = UInt64(timeoutMs) * 1_000_000
                try? await Task.sleep(nanoseconds: ns)
                return .timedOut
            }

            let first = await group.next() ?? .timedOut
            group.cancelAll()
            // Drain so cancelled children do not leak into later work.
            for await _ in group {}
            return first
        }

        let elapsedMs = Self.elapsedMilliseconds(since: start)

        switch outcome {
        case .timedOut:
            return .fallbackContinue(
                why: "FM steward timed out; continuing under policy and hard fence only.",
                modelAvailable: false,
                timedOut: true,
                latencyMs: elapsedMs
            )
        case .response(let raw):
            return Self.normalizeBackendResponse(raw, latencyMs: elapsedMs)
        }
    }

    /// Mirror Classifier backend path: ask* without explain → fallback continue.
    private static func normalizeBackendResponse(
        _ response: ClassifyResponse,
        latencyMs: Int
    ) -> ClassifyResponse {
        if response.verdict.requiresExplain {
            if let valid = try? response.enforcingExplain() {
                return withLatency(valid, latencyMs: latencyMs)
            }
            return .fallbackContinue(
                why: "Backend returned ask without explain; falling back to continue under policy and hard fence only.",
                modelAvailable: response.modelAvailable,
                timedOut: response.timedOut,
                latencyMs: latencyMs
            )
        }
        return withLatency(response, latencyMs: latencyMs)
    }

    private static func withLatency(_ response: ClassifyResponse, latencyMs: Int) -> ClassifyResponse {
        var copy = response
        if copy.latencyMs == nil {
            copy.latencyMs = latencyMs
        }
        return copy
    }

    private static func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Int {
        let duration = ContinuousClock.now - start
        let seconds = duration.components.seconds
        let attoseconds = duration.components.attoseconds
        let ms = (seconds * 1000) + (attoseconds / 1_000_000_000_000_000)
        return Int(max(0, ms))
    }
}
