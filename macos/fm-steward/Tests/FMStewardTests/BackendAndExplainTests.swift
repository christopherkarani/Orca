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
        let card = RiskCard(
            schemaVersion: 1,
            sessionId: "sess-neutral",
            tool: "bash",
            command: "echo hi",
            features: RiskCard.Features(executed: true, sameIntent: nil),
            thresholds: nil,
            meta: nil
        )
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

    @Test("recipient_count >= bulk_recipient_min triggers ask without bulk_outbound flag")
    func recipientCountThresholdAsks() async throws {
        let card = RiskCard(
            schemaVersion: 1,
            sessionId: "sess-bulk-threshold",
            tool: "send_email",
            command: nil,
            features: RiskCard.Features(
                executed: true,
                bulkOutbound: false,
                vip: false,
                recipientCount: 1500
            ),
            thresholds: RiskCard.Thresholds(bulkRecipientMin: 1000),
            meta: nil
        )
        let response = await Classifier(backend: UnavailableBackend()).classify(card)

        #expect(response.verdict == .ask || response.verdict == .askStickyCandidate)
        let explain = try #require(response.explain)
        #expect(!explain.isEmpty)
    }

    @Test("Classifier: backend ask without explain demotes to fallback continue")
    func classifierBrokenAskDemotesToContinue() async {
        let card = RiskCard(
            schemaVersion: 1,
            sessionId: "sess-broken-ask",
            tool: "bash",
            command: "echo hi",
            features: RiskCard.Features(executed: true, bulkOutbound: false, vip: false, sameIntent: nil),
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
        // On-device model may continue (or rarely ask) for a neutral shell card;
        // never invent deny/allow and never hang-flag unless cancelled.
        #expect(response.verdict == .continue || response.verdict == .ask || response.verdict == .askStickyCandidate)
        #expect(response.timedOut == false)
        if LiveBackend.isOnDeviceModelAvailable {
            // Real generation or demotion path still reports model presence unless unavailable mid-flight.
            #expect(response.modelAvailable == true || response.fallback == true)
        } else {
            #expect(response.fallback == true)
            #expect(response.modelAvailable == false)
        }
    }

    @Test("RiskCard + ClassifyResponse Codable round-trip keys match schema snake_case")
    func codableRoundTrip() throws {
        let card = try loadFixture("bulk_email")
        let encoded = try JSONEncoder().encode(card)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["schema_version"] as? Int == 1)
        #expect(object["session_id"] as? String == card.sessionId)
        #expect(object["tool"] as? String == "send_email")

        let response = try ClassifyResponse.make(
            verdict: .ask,
            why: "Bulk outbound exceeds threshold.",
            explain: "Confirm bulk send is intentional.",
            suggestedStickyScope: "effect_class",
            suggestedEffectClass: "external-message",
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
        #expect(responseObject["suggested_sticky_scope"] as? String == "effect_class")
    }
}
