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
