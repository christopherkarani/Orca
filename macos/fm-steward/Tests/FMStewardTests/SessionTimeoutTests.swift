import Foundation
import Testing
@testable import FMSteward

@Suite("StewardSession timeout + warm")
struct SessionTimeoutTests {
    /// Neutral card: no rules pre-pass hit → backend path.
    /// (echo/printf/grep/safe-clean shapes short-circuit via CommandShape; use residual shell.)
    private func neutralCard(sessionId: String = "sess-timeout") -> RiskCard {
        RiskCard(
            schemaVersion: 1,
            sessionId: sessionId,
            tool: "bash",
            // Residual shell that does not hit CommandShape or HardDangerRules.
            command: "make release",
            features: RiskCard.Features(executed: true, bulkOutbound: false, vip: false, sameIntent: nil),
            thresholds: nil,
            meta: nil
        )
    }

    @Test("default timeout_ms is 3000")
    func defaultTimeoutIs3000() {
        #expect(StewardSession.defaultTimeoutMs == 3000)
        let session = StewardSession(backend: UnavailableBackend())
        #expect(session.timeoutMs == 3000)
    }

    @Test("timeoutMs clamps: 0/negative → default; oversize → maxTimeoutMs")
    func timeoutMsClamp() {
        #expect(StewardSession.clampTimeoutMs(0) == StewardSession.defaultTimeoutMs)
        #expect(StewardSession.clampTimeoutMs(-1) == StewardSession.defaultTimeoutMs)
        #expect(StewardSession.clampTimeoutMs(100) == 100)
        #expect(StewardSession.clampTimeoutMs(60_000) == 60_000)
        #expect(StewardSession.clampTimeoutMs(60_001) == StewardSession.maxTimeoutMs)
        #expect(StewardSession.clampTimeoutMs(Int.max) == StewardSession.maxTimeoutMs)
        let zeroSession = StewardSession(backend: UnavailableBackend(), timeoutMs: 0)
        #expect(zeroSession.timeoutMs == StewardSession.defaultTimeoutMs)
        let hugeSession = StewardSession(backend: UnavailableBackend(), timeoutMs: Int.max)
        #expect(hugeSession.timeoutMs == StewardSession.maxTimeoutMs)
    }

    @Test("SlowBackend sleep > timeout → continue + timed_out + fallback; never ask; wall time ~timeout")
    func slowBackendTimesOutNearBound() async {
        // Sleep 2s but session timeout 100ms — must not wait for full sleep and must not surface late ask.
        let session = StewardSession(
            backend: SlowBackend(delayMs: 2000),
            timeoutMs: 100
        )
        let card = neutralCard()

        let start = ContinuousClock.now
        let response = await session.classify(card)
        let elapsed = ContinuousClock.now - start

        #expect(response.verdict == .continue)
        #expect(response.timedOut == true)
        #expect(response.fallback == true)
        #expect(response.schemaVersion == 1)
        // Late SlowBackend ask must never win the race.
        #expect(response.verdict != .ask)
        #expect(response.verdict != .askStickyCandidate)
        #expect(response.explain == nil)

        // Completes near timeout, not full 2s sleep (slack for CI scheduler).
        #expect(elapsed < .milliseconds(800))
        #expect(elapsed >= .milliseconds(50))
        if let latency = response.latencyMs {
            #expect(latency <= 800)
        }
    }

    @Test("per-call timeoutMs override is honored")
    func perCallTimeoutOverride() async {
        // Session default 500; override to 100 with a slow backend.
        let session = StewardSession(
            backend: SlowBackend(delayMs: 2000),
            timeoutMs: 500
        )
        let start = ContinuousClock.now
        let response = await session.classify(neutralCard(), timeoutMs: 100)
        let elapsed = ContinuousClock.now - start

        #expect(response.verdict == .continue)
        #expect(response.timedOut == true)
        #expect(response.fallback == true)
        #expect(elapsed < .milliseconds(800))
    }

    @Test("warm() marks session; subsequent classify reuses without mandatory cold start")
    func warmThenReuse() async {
        let session = StewardSession(backend: UnavailableBackend())
        #expect(await session.isWarmed == false)

        await session.warm()
        #expect(await session.isWarmed == true)

        let r1 = await session.classify(neutralCard(sessionId: "sess-warm-1"))
        let r2 = await session.classify(neutralCard(sessionId: "sess-warm-2"))

        #expect(r1.verdict == .continue)
        #expect(r2.verdict == .continue)
        #expect(await session.isWarmed == true)
    }

    @Test("first classify without warm still marks session warmed")
    func classifyImpliesWarm() async {
        let session = StewardSession(backend: UnavailableBackend())
        #expect(await session.isWarmed == false)
        _ = await session.classify(neutralCard())
        #expect(await session.isWarmed == true)
    }

    @Test("unavailable backend through session: continue + fallback; never ask-spam")
    func unavailableNeverAskSpam() async {
        let session = StewardSession(backend: UnavailableBackend())
        for i in 0..<5 {
            let response = await session.classify(neutralCard(sessionId: "sess-unavail-\(i)"))
            #expect(response.verdict == .continue)
            #expect(response.fallback == true)
            #expect(response.timedOut == false)
            #expect(response.modelAvailable == false)
            #expect(response.verdict != .ask)
            #expect(response.verdict != .askStickyCandidate)
        }
    }

    @Test("rules pre-pass still short-circuits before backend (executed=false without waiting on SlowBackend)")
    func rulesShortCircuitBeforeBackend() async throws {
        let session = StewardSession(
            backend: SlowBackend(delayMs: 2000),
            timeoutMs: 100
        )
        let card = try loadFixture("grep_rm_rf")

        let start = ContinuousClock.now
        let response = await session.classify(card)
        let elapsed = ContinuousClock.now - start

        #expect(response.verdict == .continue)
        #expect(response.timedOut == false)
        #expect(response.fallback == false)
        #expect(response.modelAvailable == false)
        // Must not wait on SlowBackend sleep.
        #expect(elapsed < .milliseconds(500))
    }

    @Test("backend ask without explain through session falls back to continue")
    func brokenBackendAskFallsBack() async {
        let broken = BrokenAskBackend()
        let session = StewardSession(backend: broken, timeoutMs: 500)
        let response = await session.classify(neutralCard())

        #expect(response.verdict == .continue)
        #expect(response.fallback == true)
        #expect(response.timedOut == false)
    }

    @Test("slow few-shot retrieve past timeout → continue + timed_out; wall ~timeout; empty hits")
    func slowRetrieverTimesOutNearBound() async {
        // Retrieve sleeps 2s but session timeout 100ms — must not wait for full retrieve.
        let counter = LockedCounter()
        let lateExample = FewShotExample(
            command: "should-not-inject",
            expectedVerdict: "ask",
            why: "slow spy must not block past timeout"
        )
        let session = StewardSession(
            backend: UnavailableBackend(),
            timeoutMs: 100,
            fewShotRetriever: SlowFewShotRetriever(
                delayMs: 2000,
                examples: [lateExample],
                callCount: counter
            )
        )
        let start = ContinuousClock.now
        let response = await session.classify(neutralCard())
        let elapsed = ContinuousClock.now - start

        #expect(response.verdict == .continue)
        #expect(response.timedOut == true)
        #expect(response.fallback == true)
        #expect(response.verdict != .ask)
        #expect(await session.lastFewShotHits == 0)
        // Retrieve was started (residual path) but cancelled / emptied under budget.
        #expect(counter.count == 1)
        // Completes near timeout, not full 2s retrieve sleep (slack for CI scheduler).
        #expect(elapsed < .milliseconds(800))
        #expect(elapsed >= .milliseconds(50))
        if let latency = response.latencyMs {
            #expect(latency <= 800)
        }
    }

    @Test("cancellation-blind backend: wall exceeds timeout; timed_out continue; never late ask")
    func cancellationBlindBackendExceedsWallTimeout() async {
        // Residual honesty: non-cooperative backend ignores Task cancel, so the
        // session must drain the child after the timer wins. timeoutMs=80,
        // delay=450 → wall on classify return exceeds timeout by a clear margin.
        // Do not claim hard wall-clock kill of non-cooperative FM.
        let session = StewardSession(
            backend: CancellationBlindBackend(delayMs: 450),
            timeoutMs: 80
        )
        let start = ContinuousClock.now
        let response = await session.classify(neutralCard())
        let elapsed = ContinuousClock.now - start

        #expect(response.verdict == .continue)
        #expect(response.timedOut == true)
        #expect(response.fallback == true)
        #expect(response.verdict != .ask)
        #expect(response.verdict != .askStickyCandidate)
        #expect(response.explain == nil)

        // Wall exceeds timeout by clear margin (80ms budget, ~450ms blind work).
        #expect(elapsed >= .milliseconds(300))
        // First-win latency recorded near the timer, not full drain.
        if let latency = response.latencyMs {
            #expect(latency < 300)
        }
    }

    @Test("cancellation-blind: next classify delayed by prior drain residual")
    func cancellationBlindNextClassifyDelayedByDrain() async {
        // After a blind timeout, the actor is free only once drain completes.
        // A second classify right after should still succeed; the first call's
        // wall already embeds the drain (proven above). Here we show sequential
        // work does not surface the late ask from the blind child.
        let session = StewardSession(
            backend: CancellationBlindBackend(delayMs: 350),
            timeoutMs: 70
        )
        let first = await session.classify(neutralCard(sessionId: "blind-1"))
        #expect(first.timedOut == true)
        #expect(first.verdict == .continue)

        // Immediate follow-up with a cooperative fast path (rules short-circuit
        // would skip backend; use residual UnavailableBackend-style by swapping —
        // same blind backend still: use short timeout and small delay isn't
        // available. Second call with same blind backend + short timeout will
        // again time out; prove it never returns the late ask.
        let secondStart = ContinuousClock.now
        let second = await session.classify(neutralCard(sessionId: "blind-2"), timeoutMs: 60)
        let secondElapsed = ContinuousClock.now - secondStart
        #expect(second.verdict == .continue)
        #expect(second.timedOut == true)
        #expect(second.verdict != .ask)
        // Second call still pays drain residual (blind delay ~350ms).
        #expect(secondElapsed >= .milliseconds(250))
    }
}

/// Test double: returns ask* with empty explain (invalid). Shared with BackendAndExplainTests.
struct BrokenAskBackend: FoundationModelBackend {
    func classify(_ card: RiskCard) async -> ClassifyResponse {
        ClassifyResponse(
            verdict: .ask,
            why: "broken",
            explain: nil,
            timedOut: false,
            fallback: false,
            modelAvailable: true
        )
    }
}
