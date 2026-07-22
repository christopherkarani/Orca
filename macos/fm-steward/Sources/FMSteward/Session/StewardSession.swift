import Foundation

/// Warm, reusable FM steward session with a hard classify timeout.
///
/// Rules pre-pass runs first (no backend wait). Backend-bound work is raced
/// against `timeoutMs` (default 500). On timeout, parent cancel, or broken backend
/// ask*, returns fallback **continue** — never ask-spam.
///
/// - Note: Timeout is **cooperative** under structured concurrency: the session
///   cancels the backend child when the timer wins, but `withTaskGroup` still
///   joins children. Backends **must** honor task cancellation promptly (see
///   `FoundationModelBackend`). Phase 3 stubs do; real FM generation must poll
///   cancel or the caller can block past `timeoutMs` while still returning
///   `timed_out=true` after the late work ends.
public actor StewardSession {
    /// Product default: 500ms hard timeout for backend-bound classify work.
    public static let defaultTimeoutMs: Int = 500

    /// Upper bound for `timeoutMs` so `UInt64(ms) * 1_000_000` cannot trap.
    public static let maxTimeoutMs: Int = 60_000

    /// Effective default timeout for this session (overridable per `classify` call).
    /// Always clamped to `1...maxTimeoutMs` (0 / negative → `defaultTimeoutMs`).
    public nonisolated let timeoutMs: Int

    private let backend: any FoundationModelBackend
    private var warmed: Bool = false

    public init(
        backend: any FoundationModelBackend = UnavailableBackend(),
        timeoutMs: Int = StewardSession.defaultTimeoutMs
    ) {
        self.backend = backend
        self.timeoutMs = Self.clampTimeoutMs(timeoutMs)
    }

    /// Clamp `ms` into a safe sleep range: `≤0` → default; otherwise `1...maxTimeoutMs`.
    public nonisolated static func clampTimeoutMs(_ ms: Int) -> Int {
        if ms <= 0 { return defaultTimeoutMs }
        return min(ms, maxTimeoutMs)
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

        if let hit = ClassifyPipeline.rulesHit(card) {
            return hit
        }

        let bound = Self.clampTimeoutMs(timeoutMs ?? self.timeoutMs)
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

        let (outcome, firstWinMs): (RaceOutcome, Int) = await withTaskGroup(of: RaceOutcome.self) { group in
            group.addTask {
                let raw = await backend.classify(card)
                // Defense in depth: if cancelled after return, do not treat as a win.
                if Task.isCancelled {
                    return .timedOut
                }
                return .response(raw)
            }
            group.addTask {
                let ns = UInt64(timeoutMs) * 1_000_000
                do {
                    try await Task.sleep(nanoseconds: ns)
                    return .timedOut
                } catch {
                    // Cancelled because backend already won (or parent cancelled).
                    return .timedOut
                }
            }

            let first = await group.next() ?? .timedOut
            let winMs = Self.elapsedMilliseconds(since: start)
            group.cancelAll()
            // Drain so cancelled children do not leak into later work.
            // Note: this joins cooperative-cancel backends; non-cooperative work can
            // still block until completion (document residual; see type docs).
            for await _ in group {}
            return (first, winMs)
        }

        // Parent cancel while racing → always soft fallback continue (never ask-spam).
        if Task.isCancelled {
            return .fallbackContinue(
                why: "FM steward classify cancelled; continuing under policy and hard fence only.",
                modelAvailable: false,
                timedOut: true,
                latencyMs: firstWinMs
            )
        }

        switch outcome {
        case .timedOut:
            return .fallbackContinue(
                why: "FM steward timed out; continuing under policy and hard fence only.",
                modelAvailable: false,
                timedOut: true,
                latencyMs: firstWinMs
            )
        case .response(let raw):
            return ClassifyPipeline.normalizeBackend(raw, latencyMs: firstWinMs)
        }
    }

    private static func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Int {
        let duration = ContinuousClock.now - start
        let seconds = duration.components.seconds
        let attoseconds = duration.components.attoseconds
        let ms = (seconds * 1000) + (attoseconds / 1_000_000_000_000_000)
        return Int(max(0, ms))
    }
}
