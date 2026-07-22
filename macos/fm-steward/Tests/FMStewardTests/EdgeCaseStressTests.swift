import Foundation
import Testing
@testable import FMSteward

// MARK: - Helpers

private func card(
    tool: String = "send_email",
    command: String? = nil,
    executed: Bool? = true,
    bulkOutbound: Bool? = nil,
    vip: Bool? = nil,
    sameIntent: String? = nil,
    recipientCount: Int? = nil,
    effectHints: [String]? = nil,
    bulkRecipientMin: Int? = nil,
    sessionId: String = "stress"
) -> RiskCard {
    RiskCard(
        schemaVersion: 1,
        sessionId: sessionId,
        tool: tool,
        command: command,
        features: RiskCard.Features(
            executed: executed,
            bulkOutbound: bulkOutbound,
            vip: vip,
            sameIntent: sameIntent,
            recipientCount: recipientCount,
            effectHints: effectHints
        ),
        thresholds: bulkRecipientMin.map { RiskCard.Thresholds(bulkRecipientMin: $0) },
        meta: RiskCard.Meta(host: "stress")
    )
}

private func isAsk(_ v: Verdict) -> Bool {
    v == .ask || v == .askStickyCandidate
}

/// Backend that returns a fixed response (for parity / injection tests).
private struct FixedBackend: FoundationModelBackend {
    let response: ClassifyResponse
    func classify(_ card: RiskCard) async -> ClassifyResponse {
        _ = card
        return response
    }
}

// MARK: - Rule priority (first hit wins)

@Suite("Stress: rule priority")
struct RulePriorityStressTests {
    @Test("executed=false wins over vip → continue (never ask)")
    func executedFalseBeatsVip() async {
        let c = card(executed: false, bulkOutbound: true, vip: true, recipientCount: 50_000)
        let r = await Classifier().classify(c)
        #expect(r.verdict == Verdict.continue)
        #expect(r.fallback == false)
        #expect(r.explain == nil)
    }

    @Test("executed=false wins over bulk → continue")
    func executedFalseBeatsBulk() async {
        let c = card(tool: "bash", command: "grep rm", executed: false, bulkOutbound: true, recipientCount: 99_999)
        let r = await Classifier().classify(c)
        #expect(r.verdict == Verdict.continue)
    }

    @Test("test_loop wins over vip → continue")
    func testLoopBeatsVip() async {
        let c = card(executed: true, vip: true, sameIntent: "test_loop")
        let r = await Classifier().classify(c)
        #expect(r.verdict == Verdict.continue)
        #expect(r.why.contains("test_loop"))
    }

    @Test("test_loop wins over bulk → continue")
    func testLoopBeatsBulk() async {
        let c = card(executed: true, bulkOutbound: true, sameIntent: "test_loop", recipientCount: 50_000)
        let r = await Classifier().classify(c)
        #expect(r.verdict == Verdict.continue)
    }

    @Test("vip wins over bulk → ask_sticky_candidate (not plain ask)")
    func vipBeatsBulk() async {
        let c = card(executed: true, bulkOutbound: true, vip: true, recipientCount: 50_000)
        let r = await Classifier().classify(c)
        #expect(r.verdict == .askStickyCandidate)
        #expect(r.explain != nil && !(r.explain ?? "").isEmpty)
    }

    @Test("executed=true is not a free pass; bulk still asks")
    func executedTrueStillBulkAsks() async {
        let c = card(executed: true, bulkOutbound: true, recipientCount: 50_000)
        let r = await Classifier().classify(c)
        #expect(r.verdict == .ask)
    }

    @Test("executed=nil is not treated as false; bulk still asks")
    func executedNilNotFalse() async {
        let c = card(executed: nil, bulkOutbound: true, recipientCount: 50_000)
        let r = await Classifier().classify(c)
        #expect(isAsk(r.verdict))
    }

    @Test("same_intent other than test_loop does not short-circuit")
    func sameIntentOtherDoesNotContinue() async {
        let c = card(executed: true, bulkOutbound: false, vip: false, sameIntent: "deploy_loop")
        // No rules hit → UnavailableBackend fallback continue
        let r = await Classifier(backend: UnavailableBackend()).classify(c)
        #expect(r.verdict == Verdict.continue)
        #expect(r.fallback == true)
        #expect(r.modelAvailable == false)
    }
}

// MARK: - Bulk threshold boundaries

@Suite("Stress: bulk thresholds")
struct BulkThresholdStressTests {
    @Test("recipient_count 999 < default min 1000 → continue (backend)")
    func underDefaultMin() async {
        let c = card(bulkOutbound: false, vip: false, recipientCount: 999)
        let r = await Classifier(backend: UnavailableBackend()).classify(c)
        #expect(r.verdict == Verdict.continue)
        #expect(r.fallback == true) // no rules hit
    }

    @Test("recipient_count 1000 == default min → ask")
    func atDefaultMin() async {
        let c = card(bulkOutbound: false, vip: false, recipientCount: 1000)
        let r = await Classifier().classify(c)
        #expect(r.verdict == .ask)
        #expect(!(r.explain ?? "").isEmpty)
    }

    @Test("recipient_count 1001 > default min → ask")
    func overDefaultMin() async {
        let c = card(bulkOutbound: false, vip: false, recipientCount: 1001)
        let r = await Classifier().classify(c)
        #expect(r.verdict == .ask)
    }

    @Test("bulk_outbound true with low count still asks")
    func bulkFlagIgnoresCount() async {
        let c = card(bulkOutbound: true, vip: false, recipientCount: 1)
        let r = await Classifier().classify(c)
        #expect(r.verdict == .ask)
    }

    @Test("custom bulk_recipient_min 100: count 100 asks")
    func customThresholdAtBoundary() async {
        let c = card(bulkOutbound: false, vip: false, recipientCount: 100, bulkRecipientMin: 100)
        let r = await Classifier().classify(c)
        #expect(r.verdict == .ask)
    }

    @Test("custom bulk_recipient_min 100: count 99 continues (backend)")
    func customThresholdUnder() async {
        let c = card(bulkOutbound: false, vip: false, recipientCount: 99, bulkRecipientMin: 100)
        let r = await Classifier(backend: UnavailableBackend()).classify(c)
        #expect(r.verdict == Verdict.continue)
        #expect(r.fallback == true)
    }

    @Test("recipient_count 0 with bulk false → continue backend")
    func zeroRecipients() async {
        let c = card(bulkOutbound: false, vip: false, recipientCount: 0)
        let r = await Classifier(backend: UnavailableBackend()).classify(c)
        #expect(r.verdict == Verdict.continue)
        #expect(r.fallback == true)
    }

    @Test("huge recipient_count still asks with explain")
    func hugeRecipientCount() async {
        let c = card(bulkOutbound: true, recipientCount: Int.max)
        let r = await Classifier().classify(c)
        #expect(r.verdict == .ask)
        #expect(!(r.explain ?? "").isEmpty)
    }
}

// MARK: - VIP / sticky suggestions

@Suite("Stress: VIP and sticky scope")
struct VipStickyStressTests {
    @Test("vip true → ask_sticky_candidate + non-empty explain")
    func vipAskSticky() async {
        let r = await Classifier().classify(card(vip: true))
        #expect(r.verdict == .askStickyCandidate)
        #expect(!(r.explain ?? "").isEmpty)
        #expect(r.suggestedStickyScope == "effect_class")
    }

    @Test("vip false alone does not ask")
    func vipFalseNoAsk() async {
        let r = await Classifier(backend: UnavailableBackend()).classify(card(bulkOutbound: false, vip: false))
        #expect(r.verdict == Verdict.continue)
        #expect(r.fallback == true)
    }

    @Test("effect_hints first entry becomes suggested_effect_class")
    func effectHintsPropagate() async {
        let c = card(vip: true, effectHints: ["external-message", "pay"])
        let r = await Classifier().classify(c)
        #expect(r.suggestedEffectClass == "external-message")
    }

    @Test("empty effect_hints uses default external-message")
    func emptyHintsDefaultClass() async {
        let c = card(vip: true, effectHints: [])
        let r = await Classifier().classify(c)
        #expect(r.suggestedEffectClass == "external-message")
    }

    @Test("bulk ask also suggests sticky effect_class")
    func bulkSuggestsStickyFields() async {
        let r = await Classifier().classify(card(bulkOutbound: true, recipientCount: 5000))
        #expect(r.verdict == .ask)
        #expect(r.suggestedStickyScope == "effect_class")
        #expect(r.suggestedEffectClass != nil)
    }
}

// MARK: - Explain enforcement

@Suite("Stress: explain enforcement")
struct ExplainStressTests {
    @Test("make(ask, explain:nil) throws")
    func makeNilExplainThrows() {
        #expect(throws: ClassifyResponseError.explainRequired) {
            _ = try ClassifyResponse.make(verdict: .ask, why: "x", explain: nil, modelAvailable: true)
        }
    }

    @Test("make(ask, explain:whitespace) throws")
    func makeWhitespaceExplainThrows() {
        #expect(throws: ClassifyResponseError.explainRequired) {
            _ = try ClassifyResponse.make(verdict: .ask, why: "x", explain: "   \n\t", modelAvailable: true)
        }
    }

    @Test("make(ask_sticky, explain empty) throws")
    func makeStickyEmptyThrows() {
        #expect(throws: ClassifyResponseError.explainRequired) {
            _ = try ClassifyResponse.make(
                verdict: .askStickyCandidate,
                why: "x",
                explain: "",
                modelAvailable: true
            )
        }
    }

    @Test("make(continue, explain:nil) ok")
    func makeContinueOk() throws {
        let r = try ClassifyResponse.make(verdict: .continue, why: "ok", explain: nil, modelAvailable: true)
        #expect(r.verdict == Verdict.continue)
    }

    @Test("Classifier: backend ask without explain → fallback continue")
    func classifierBrokenAsk() async {
        let broken = FixedBackend(
            response: ClassifyResponse(
                verdict: .ask,
                why: "broken",
                explain: nil,
                timedOut: false,
                fallback: false,
                modelAvailable: true
            )
        )
        let r = await Classifier(backend: broken).classify(card(bulkOutbound: false, vip: false))
        #expect(r.verdict == Verdict.continue)
        #expect(r.fallback == true)
        #expect(r.explain == nil)
    }

    @Test("Classifier: backend ask with whitespace explain → fallback continue")
    func classifierWhitespaceExplain() async {
        let broken = FixedBackend(
            response: ClassifyResponse(
                verdict: .askStickyCandidate,
                why: "broken",
                explain: "  ",
                timedOut: false,
                fallback: false,
                modelAvailable: true
            )
        )
        let r = await Classifier(backend: broken).classify(card(bulkOutbound: false, vip: false))
        #expect(r.verdict == Verdict.continue)
        #expect(r.fallback == true)
    }

    @Test("all ask* rule hits have non-empty explain")
    func allRuleAsksHaveExplain() async {
        let cards = [
            card(vip: true),
            card(bulkOutbound: true, recipientCount: 2000),
            card(bulkOutbound: false, recipientCount: 1000),
        ]
        for c in cards {
            let r = await Classifier().classify(c)
            #expect(isAsk(r.verdict), "expected ask* for card tool=\(c.tool)")
            #expect(!(r.explain ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

// MARK: - Timeout / clamp / race

@Suite("Stress: timeout race and clamp")
struct TimeoutStressTests {
    private func neutral() -> RiskCard {
        card(tool: "bash", command: "echo", executed: true, bulkOutbound: false, vip: false)
    }

    @Test("clamp matrix: 0,-1,1,500,60000,60001,Int.max")
    func clampMatrix() {
        #expect(StewardSession.clampTimeoutMs(0) == 500)
        #expect(StewardSession.clampTimeoutMs(-1) == 500)
        #expect(StewardSession.clampTimeoutMs(-999_999) == 500)
        #expect(StewardSession.clampTimeoutMs(1) == 1)
        #expect(StewardSession.clampTimeoutMs(500) == 500)
        #expect(StewardSession.clampTimeoutMs(60_000) == 60_000)
        #expect(StewardSession.clampTimeoutMs(60_001) == 60_000)
        #expect(StewardSession.clampTimeoutMs(Int.max) == 60_000)
    }

    @Test("late SlowBackend ask never surfaces after timeout")
    func lateAskNeverWins() async {
        let session = StewardSession(backend: SlowBackend(delayMs: 1500), timeoutMs: 80)
        let r = await session.classify(neutral())
        #expect(r.verdict == Verdict.continue)
        #expect(r.timedOut == true)
        #expect(r.fallback == true)
        #expect(r.modelAvailable == false)
        #expect(!isAsk(r.verdict))
    }

    @Test("fast backend continue wins before timeout")
    func fastBackendWins() async {
        let session = StewardSession(backend: UnavailableBackend(), timeoutMs: 500)
        let r = await session.classify(neutral())
        #expect(r.verdict == Verdict.continue)
        #expect(r.fallback == true)
        #expect(r.timedOut == false)
        #expect(r.modelAvailable == false)
    }

    @Test("fast backend valid ask surfaces when no rules hit")
    func fastAskSurfaces() async {
        let ask = try! ClassifyResponse.make(
            verdict: .ask,
            why: "backend nuance",
            explain: "Please confirm this gray action.",
            modelAvailable: true
        )
        let session = StewardSession(backend: FixedBackend(response: ask), timeoutMs: 500)
        let r = await session.classify(neutral())
        #expect(r.verdict == .ask)
        #expect(r.explain == "Please confirm this gray action.")
        #expect(r.fallback == false)
        #expect(r.timedOut == false)
    }

    @Test("rules short-circuit even with SlowBackend (no wait)")
    func rulesIgnoreSlowBackend() async {
        let session = StewardSession(backend: SlowBackend(delayMs: 5000), timeoutMs: 500)
        let start = ContinuousClock.now
        let r = await session.classify(card(bulkOutbound: true, recipientCount: 50_000))
        let elapsed = ContinuousClock.now - start
        #expect(r.verdict == .ask)
        #expect(r.timedOut == false)
        #expect(elapsed < .milliseconds(500))
    }

    @Test("per-call timeout 0 clamps to default; still times out SlowBackend")
    func perCallZeroClamps() async {
        // clamp(0)=500; SlowBackend 2000ms should still timeout under 500ms default.
        let session = StewardSession(backend: SlowBackend(delayMs: 2000), timeoutMs: 1000)
        let start = ContinuousClock.now
        let r = await session.classify(neutral(), timeoutMs: 0)
        let elapsed = ContinuousClock.now - start
        #expect(r.timedOut == true)
        #expect(r.verdict == Verdict.continue)
        #expect(elapsed < .milliseconds(1200))
    }

    @Test("session broken ask → continue fallback never ask-spam")
    func sessionBrokenAsk() async {
        let broken = FixedBackend(
            response: ClassifyResponse(
                verdict: .ask,
                why: "x",
                explain: nil,
                timedOut: false,
                fallback: false,
                modelAvailable: true
            )
        )
        let session = StewardSession(backend: broken, timeoutMs: 500)
        for _ in 0..<5 {
            let r = await session.classify(neutral())
            #expect(r.verdict == Verdict.continue)
            #expect(r.fallback == true)
            #expect(!isAsk(r.verdict))
        }
    }
}

// MARK: - Unavailable never ask-spam

@Suite("Stress: unavailable fallback")
struct UnavailableStressTests {
    @Test("50 unavailable classifies: always continue, never ask")
    func fiftyUnavailableNeverAsk() async {
        let clf = Classifier(backend: UnavailableBackend())
        let c = card(tool: "bash", executed: true, bulkOutbound: false, vip: false)
        for i in 0..<50 {
            let r = await clf.classify(c)
            #expect(r.verdict == Verdict.continue, "iteration \(i)")
            #expect(r.fallback == true)
            #expect(r.modelAvailable == false)
            #expect(r.timedOut == false)
            #expect(r.explain == nil)
        }
    }

    @Test("UnavailableBackend response shape is valid classify-response-v1")
    func unavailableShape() async {
        let r = await UnavailableBackend().classify(card())
        #expect(r.schemaVersion == 1)
        #expect(r.verdict == Verdict.continue)
        #expect(r.fallback == true)
        #expect(r.modelAvailable == false)
        #expect(!r.why.isEmpty)
    }
}

// MARK: - Classifier ↔ Session parity on fixtures + matrix

@Suite("Stress: Classifier vs StewardSession parity")
struct ParityStressTests {
    @Test("fixture table: Classifier and Session agree on verdict")
    func fixturesAgree() async {
        let names = ["grep_rm_rf", "npm_test_loop", "bulk_email", "vip_email"]
        let session = StewardSession(backend: UnavailableBackend())
        let classifier = Classifier(backend: UnavailableBackend())

        for name in names {
            let path = fixturePath(name)
            let data = try! Data(contentsOf: URL(fileURLWithPath: path))
            let risk = try! JSONDecoder().decode(RiskCard.self, from: data)
            let a = await classifier.classify(risk)
            let b = await session.classify(risk)
            #expect(a.verdict == b.verdict, "mismatch on \(name): \(a.verdict) vs \(b.verdict)")
            if isAsk(a.verdict) {
                #expect(!(a.explain ?? "").isEmpty)
                #expect(!(b.explain ?? "").isEmpty)
            }
        }
    }

    @Test("matrix of edge cards: Classifier and Session same verdict class")
    func edgeMatrixAgree() async {
        let cases: [(String, RiskCard)] = [
            ("exec_false_vip", card(executed: false, vip: true)),
            ("test_loop_bulk", card(bulkOutbound: true, sameIntent: "test_loop", recipientCount: 50_000)),
            ("vip_only", card(vip: true)),
            ("bulk_at_1000", card(recipientCount: 1000)),
            ("bulk_under", card(recipientCount: 999)),
            ("neutral", card(tool: "bash", executed: true, bulkOutbound: false, vip: false)),
            ("custom_thresh", card(recipientCount: 50, bulkRecipientMin: 50)),
        ]
        let session = StewardSession(backend: UnavailableBackend())
        let classifier = Classifier(backend: UnavailableBackend())
        for (name, c) in cases {
            let a = await classifier.classify(c)
            let b = await session.classify(c)
            #expect(a.verdict == b.verdict, "parity fail \(name)")
        }
    }

    private func fixturePath(_ name: String) -> String {
        // Tests run with cwd = package root (macos/fm-steward)
        let candidates = [
            "Fixtures/\(name).json",
            "macos/fm-steward/Fixtures/\(name).json",
        ]
        for c in candidates {
            if FileManager.default.fileExists(atPath: c) { return c }
        }
        // Walk from #filePath
        let this = URL(fileURLWithPath: #filePath)
        let root = this
            .deletingLastPathComponent() // FMStewardTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package
        return root.appendingPathComponent("Fixtures/\(name).json").path
    }
}

// MARK: - Warm / reuse

@Suite("Stress: warm session reuse")
struct WarmStressTests {
    @Test("warm then many classifies stay warmed; verdicts stable")
    func warmReuseStable() async {
        let session = StewardSession(backend: UnavailableBackend())
        await session.warm()
        #expect(await session.isWarmed)
        for _ in 0..<20 {
            let r = await session.classify(card(vip: true))
            #expect(r.verdict == .askStickyCandidate)
            #expect(await session.isWarmed)
        }
    }

    @Test("first classify warms without explicit warm()")
    func firstClassifyWarms() async {
        let session = StewardSession(backend: UnavailableBackend())
        #expect(await session.isWarmed == false)
        _ = await session.classify(card(executed: false))
        #expect(await session.isWarmed == true)
    }
}

// MARK: - Codable / schema edge

@Suite("Stress: Codable edges")
struct CodableStressTests {
    @Test("decode fixture bulk_email round-trips features")
    func decodeBulk() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/bulk_email.json")
        let data = try Data(contentsOf: path)
        let card = try JSONDecoder().decode(RiskCard.self, from: data)
        #expect(card.features.bulkOutbound == true)
        #expect(card.features.recipientCount == 50_000)
        let encoded = try JSONEncoder().encode(card)
        let again = try JSONDecoder().decode(RiskCard.self, from: encoded)
        #expect(again == card)
    }

    @Test("unknown feature keys decode via ignoring extras (no crash)")
    func unknownFeatureKeys() throws {
        // RiskCard Features has fixed CodingKeys; unknown keys at features level are ignored by default Codable.
        let json = """
        {
          "schema_version": 1,
          "session_id": "s",
          "tool": "bash",
          "command": null,
          "features": {
            "executed": true,
            "future_flag": true,
            "bulk_outbound": false
          }
        }
        """.data(using: .utf8)!
        let card = try JSONDecoder().decode(RiskCard.self, from: json)
        #expect(card.features.executed == true)
        #expect(card.features.bulkOutbound == false)
    }

    @Test("verdict raw values match schema enum exactly")
    func verdictRawValues() {
        #expect(Verdict.continue.rawValue == "continue")
        #expect(Verdict.ask.rawValue == "ask")
        #expect(Verdict.askStickyCandidate.rawValue == "ask_sticky_candidate")
    }
}

// MARK: - Authority / product law smoke

@Suite("Stress: product law (no unlock, no ask-spam)")
struct ProductLawStressTests {
    @Test("timeout never upgrades to ask")
    func timeoutNeverAsk() async {
        let session = StewardSession(backend: SlowBackend(delayMs: 2000), timeoutMs: 50)
        let r = await session.classify(card(tool: "bash", executed: true, bulkOutbound: false, vip: false))
        #expect(r.verdict == Verdict.continue)
        #expect(r.timedOut == true)
        #expect(r.fallback == true)
    }

    @Test("no path returns deny/allow — only continue|ask|ask_sticky_candidate")
    func onlyThreeVerdicts() async {
        let cards = [
            card(executed: false),
            card(sameIntent: "test_loop"),
            card(vip: true),
            card(bulkOutbound: true, recipientCount: 10_000),
            card(tool: "bash", executed: true, bulkOutbound: false, vip: false),
        ]
        let session = StewardSession(backend: UnavailableBackend())
        for c in cards {
            let r = await session.classify(c)
            switch r.verdict {
            case .continue, .ask, .askStickyCandidate:
                break
            }
        }
    }

    @Test("hard-catastrophe-shaped shell card with executed=false continues (FM does not deny)")
    func catastropheTextAsDataContinues() async {
        // Steward must not pretend to hard-deny; executed=false → continue.
        // Hard fence is Zig's job and never reaches FM.
        let c = card(
            tool: "bash",
            command: "grep -n 'rm -rf /' notes.md",
            executed: false
        )
        let r = await Classifier().classify(c)
        #expect(r.verdict == Verdict.continue)
        #expect(r.fallback == false)
    }
}
