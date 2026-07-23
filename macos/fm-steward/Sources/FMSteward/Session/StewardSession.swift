import Foundation

/// Warm, reusable FM steward session with a hard classify timeout.
///
/// Rules pre-pass runs first (no backend wait). Residual path races
/// **retrieve + backend** against `timeoutMs` (default 3000). On timeout, parent
/// cancel, or broken backend ask*, returns fallback **continue** — never ask-spam.
///
/// ## Concurrency / single-flight
///
/// This type is an `actor`, so method entry is serialized. Callers **must not**
/// expect concurrent `classify` calls on the same session (especially with a
/// shared `LiveBackend`) to run parallel Foundation Model generation. Prefer
/// sequential awaits from one owner; multi-call stress should be serial.
///
/// `raceResidual` spawns only **one** residual child task (few-shot retrieve then
/// backend classify) plus a timer — not multiple FM classifies. Overlapping
/// `classify` invocations can re-enter at `await` points after suspension, but
/// session state (`warmed`) is still actor-protected. `LiveBackend` uses a
/// **fresh** `LanguageModelSession` per classify so multi-card transcripts never
/// accumulate on the session object.
///
/// - Note: Timeout is **cooperative** under structured concurrency: the session
///   cancels the residual child when the timer wins, but `withTaskGroup` still
///   joins children. Retrievers and backends **must** honor task cancellation
///   promptly (see `FoundationModelBackend`). Phase 3 stubs do; real FM
///   generation / Wax open must poll cancel or the caller can block past
///   `timeoutMs` while still returning `timed_out=true` after the late work ends.
/// - Note: Prefer fail-open **empty** few-shots over hanging past `timeoutMs`
///   when retrieve is slow or cancelled.
public actor StewardSession {
    /// Product default: 3s hard timeout for residual (retrieve + backend) work.
    /// Residual on-device FM is typically ~1–2.5s; 500ms systematically timed out residual asks.
    public static let defaultTimeoutMs: Int = 3000

    /// Upper bound for `timeoutMs` so `UInt64(ms) * 1_000_000` cannot trap.
    public static let maxTimeoutMs: Int = 60_000

    /// Default few-shot k for residual path (matches LiveBackend prompt cap).
    public static let defaultFewShotLimit: Int = 3

    /// Effective default timeout for this session (overridable per `classify` call).
    /// Always clamped to `1...maxTimeoutMs` (0 / negative → `defaultTimeoutMs`).
    public nonisolated let timeoutMs: Int

    private let backend: any FoundationModelBackend
    private let fewShotRetriever: any FewShotRetriever
    private let fewShotLimit: Int
    private var warmed: Bool = false
    /// Last residual few-shot hit count (0 when rules short-circuit, timeout, or retriever empty).
    private var lastFewShotHitCount: Int = 0

    public init(
        backend: any FoundationModelBackend = LiveBackend.preferredDefault(),
        timeoutMs: Int = StewardSession.defaultTimeoutMs,
        fewShotRetriever: any FewShotRetriever = NullFewShotRetriever(),
        fewShotLimit: Int = StewardSession.defaultFewShotLimit
    ) {
        self.backend = backend
        self.timeoutMs = Self.clampTimeoutMs(timeoutMs)
        self.fewShotRetriever = fewShotRetriever
        self.fewShotLimit = max(0, min(fewShotLimit, 8))
    }

    /// Few-shot hits from the most recent residual classify (0 on rules path / timeout).
    public var lastFewShotHits: Int { lastFewShotHitCount }

    /// Clamp `ms` into a safe sleep range: `≤0` → default; otherwise `1...maxTimeoutMs`.
    public nonisolated static func clampTimeoutMs(_ ms: Int) -> Int {
        if ms <= 0 { return defaultTimeoutMs }
        return min(ms, maxTimeoutMs)
    }

    /// Whether the session has been warmed (`warm()` or first `classify`).
    public var isWarmed: Bool { warmed }

    /// Mark the session warm and preload the backend (on-device model prewarm when live).
    ///
    /// LiveBackend `prepareWarm` uses a disposable session and does not retain
    /// transcript state for later classifies.
    public func warm() async {
        warmed = true
        await backend.prepareWarm()
    }

    /// Classify `card`. Rules short-circuit without backend; otherwise race
    /// residual retrieve + backend against `timeoutMs` (session default when nil).
    ///
    /// Safe under serial multi-call. Do not fan out concurrent classifies on the
    /// same session expecting parallel FM work — actor entry is serialized and
    /// residual FM latency stacks.
    public func classify(_ card: RiskCard, timeoutMs: Int? = nil) async -> ClassifyResponse {
        markWarmed()

        // Rules path: never consult few-shot retriever (hard rules own clear danger).
        if let hit = ClassifyPipeline.rulesHit(card) {
            lastFewShotHitCount = 0
            return hit
        }

        // Residual path: retrieve + backend share the hard timeout budget.
        let bound = Self.clampTimeoutMs(timeoutMs ?? self.timeoutMs)
        return await raceResidual(card: card, timeoutMs: bound)
    }

    // MARK: - Internals

    private func markWarmed() {
        if !warmed {
            warmed = true
        }
    }

    private enum RaceOutcome: Sendable {
        case response(ClassifyResponse, fewShotHits: Int)
        case timedOut
    }

    /// Race residual few-shot retrieve **then** backend classify against the hard
    /// timeout. First-win latency is measured when either the residual child or
    /// the timer wins — not after draining cancelled children.
    ///
    /// On cancel/timeout during retrieve, few-shots fail-open to empty (product
    /// law: assist only; never hang past `timeoutMs` for RAG).
    private func raceResidual(
        card: RiskCard,
        timeoutMs: Int
    ) async -> ClassifyResponse {
        let start = ContinuousClock.now
        let backend = self.backend
        let retriever = self.fewShotRetriever
        let limit = self.fewShotLimit

        // Single-flight residual race: one (retrieve→classify) child + one timer.
        // Actor entry is serialized; overlapping callers re-enter only at await points.
        let (outcome, firstWinMs): (RaceOutcome, Int) = await withTaskGroup(of: RaceOutcome.self) { group in
            group.addTask {
                // Fail-open empty few-shots when already cancelled or retrieve is slow.
                let fewShots: [FewShotExample]
                if Task.isCancelled {
                    fewShots = []
                } else {
                    fewShots = await retriever.retrieve(for: card, limit: limit)
                }
                // Do not start backend work after the timer has won.
                if Task.isCancelled {
                    return .timedOut
                }
                let raw = await backend.classify(card, fewShots: fewShots)
                if Task.isCancelled {
                    return .timedOut
                }
                return .response(raw, fewShotHits: fewShots.count)
            }
            group.addTask {
                let ns = UInt64(timeoutMs) * 1_000_000
                do {
                    try await Task.sleep(nanoseconds: ns)
                    return .timedOut
                } catch {
                    // Cancelled because residual already won (or parent cancelled).
                    return .timedOut
                }
            }

            let first = await group.next() ?? .timedOut
            // First-win latency (before drain).
            let winMs = Self.elapsedMilliseconds(since: start)
            group.cancelAll()
            // Drain so cancelled children do not leak into later work.
            // Note: this joins cooperative-cancel backends/retrievers; non-cooperative
            // work can still block until completion (document residual; see type docs).
            for await _ in group {}
            return (first, winMs)
        }

        // Parent cancel while racing → always soft fallback continue (never ask-spam).
        if Task.isCancelled {
            lastFewShotHitCount = 0
            return .fallbackContinue(
                why: "FM steward classify cancelled; continuing under policy and hard fence only.",
                modelAvailable: false,
                timedOut: true,
                latencyMs: firstWinMs
            )
        }

        switch outcome {
        case .timedOut:
            lastFewShotHitCount = 0
            return .fallbackContinue(
                why: "FM steward timed out; continuing under policy and hard fence only.",
                modelAvailable: false,
                timedOut: true,
                latencyMs: firstWinMs
            )
        case .response(let raw, let fewShotHits):
            lastFewShotHitCount = fewShotHits
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
