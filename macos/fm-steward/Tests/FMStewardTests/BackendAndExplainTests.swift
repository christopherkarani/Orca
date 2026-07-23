import Foundation
import Testing
@testable import FMSteward

@Suite("FoundationModelBackend + explain enforcement")
struct BackendAndExplainTests {
    @Test("UnavailableBackend returns continue + fallback=true + model_available=false")
    func unavailableBackendFallback() async {
        let backend = UnavailableBackend()
        let card = RiskCard(
            schemaVersion: 1,
            sessionId: "sess-test",
            tool: "bash",
            command: "echo hi",
            features: RiskCard.Features(executed: true),
            thresholds: nil,
            meta: nil
        )
        let response = await backend.classify(card)

        #expect(response.verdict == .continue)
        #expect(response.fallback == true)
        #expect(response.modelAvailable == false)
        #expect(response.timedOut == false)
        #expect(response.schemaVersion == 1)
    }

    @Test("Classifier falls through to backend when no rules hit")
    func classifierUsesBackendWhenNoRules() async {
        // Neutral residual: not echo/search/print/safe-clean shape (echo would short-circuit rules).
        let card = RiskCard(
            schemaVersion: 1,
            sessionId: "sess-neutral",
            tool: "bash",
            command: "make release",
            features: RiskCard.Features(executed: true, sameIntent: nil),
            thresholds: nil,
            meta: nil
        )
        #expect(RulesPrePass.evaluate(card) == nil)
        let response = await Classifier(backend: UnavailableBackend()).classify(card)

        #expect(response.verdict == .continue)
        #expect(response.fallback == true)
        #expect(response.modelAvailable == false)
    }

    @Test("Ask* factory rejects empty explain")
    func askRequiresNonEmptyExplain() {
        #expect(throws: ClassifyResponseError.explainRequired) {
            try ClassifyResponse.make(
                verdict: .ask,
                why: "test",
                explain: nil,
                timedOut: false,
                fallback: false,
                modelAvailable: true
            )
        }
        #expect(throws: ClassifyResponseError.explainRequired) {
            try ClassifyResponse.make(
                verdict: .askStickyCandidate,
                why: "test",
                explain: "   ",
                timedOut: false,
                fallback: false,
                modelAvailable: true
            )
        }
    }

    @Test("Classifier: backend ask without explain demotes to fallback continue")
    func classifierBrokenAskDemotesToContinue() async {
        let card = RiskCard(
            schemaVersion: 1,
            sessionId: "sess-broken-ask",
            tool: "bash",
            command: "rm -rf ./out",
            features: RiskCard.Features(executed: true, sameIntent: nil),
            thresholds: nil,
            meta: nil
        )
        let response = await Classifier(backend: BrokenAskBackend()).classify(card)

        #expect(response.verdict == .continue)
        #expect(response.fallback == true)
        #expect(response.timedOut == false)
        #expect(response.modelAvailable == true)
        #expect(response.explain == nil)
        #expect(response.verdict != .ask)
        #expect(response.verdict != .askStickyCandidate)
    }

    @Test("LiveBackend is injectable and returns a valid classify-response")
    func liveBackendValidResponse() async {
        let card = RiskCard(
            schemaVersion: 1,
            sessionId: "sess-live",
            tool: "bash",
            command: "true",
            features: RiskCard.Features(executed: true),
            thresholds: nil,
            meta: nil
        )
        let response = await Classifier(backend: LiveBackend()).classify(card)
        #expect(response.schemaVersion == 1)
        #expect(response.verdict == .continue || response.verdict == .ask || response.verdict == .askStickyCandidate)
        #expect(response.timedOut == false)
        if LiveBackend.isOnDeviceModelAvailable {
            #expect(response.modelAvailable == true || response.fallback == true)
        } else {
            #expect(response.fallback == true)
            #expect(response.modelAvailable == false)
        }
    }

    @Test("RiskCard + ClassifyResponse Codable round-trip keys match schema snake_case")
    func codableRoundTrip() throws {
        let card = try loadFixture("rm_rf_workdir")
        let encoded = try JSONEncoder().encode(card)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["schema_version"] as? Int == 1)
        #expect(object["session_id"] as? String == card.sessionId)
        #expect(object["tool"] as? String == "bash")

        let response = try ClassifyResponse.make(
            verdict: .ask,
            why: "Recursive delete of build artifacts is high impact.",
            explain: "Confirm wiping dist/build/node_modules is intentional.",
            suggestedStickyScope: nil,
            suggestedEffectClass: nil,
            timedOut: false,
            fallback: false,
            modelAvailable: true,
            latencyMs: 12
        )
        let responseData = try JSONEncoder().encode(response)
        let responseObject = try JSONSerialization.jsonObject(with: responseData) as! [String: Any]
        #expect(responseObject["verdict"] as? String == "ask")
        #expect(responseObject["model_available"] as? Bool == true)
        #expect(responseObject["timed_out"] as? Bool == false)
    }
}
