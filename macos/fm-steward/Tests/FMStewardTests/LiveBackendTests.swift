import Foundation
import Testing
@testable import FMSteward

@Suite("Live on-device Foundation Models")
struct LiveBackendTests {
    @Test("framework + availability probes are coherent")
    func availabilityProbes() {
        #expect(LiveBackend.isFoundationModelsFrameworkPresent == true)
        // Runtime may still be unavailable without Apple Intelligence assets.
        _ = LiveBackend.isOnDeviceModelAvailable
        #expect(!LiveBackend.availabilityDescription.isEmpty)
    }

    @Test("preferredDefault picks Live when on-device model is ready")
    func preferredDefault() async {
        let backend = LiveBackend.preferredDefault()
        let card = RiskCard(
            sessionId: "pref",
            tool: "bash",
            command: "echo hi",
            features: RiskCard.Features(executed: true)
        )
        let response = await backend.classify(card)
        #expect(response.schemaVersion == 1)
        if LiveBackend.isOnDeviceModelAvailable {
            // Live path: either a real model verdict or soft fallback after error.
            #expect(response.modelAvailable == true || response.fallback == true)
        } else {
            #expect(response.fallback == true)
            #expect(response.modelAvailable == false)
        }
    }

    @Test(
        "gray card without rules hit uses LiveBackend (on-device) when available",
        .enabled(if: LiveBackend.isOnDeviceModelAvailable)
    )
    func grayCardHitsLiveModel() async {
        // No rules: executed true, not vip/bulk/test_loop.
        let card = RiskCard(
            sessionId: "gray-live",
            tool: "send_email",
            command: nil,
            features: RiskCard.Features(
                executed: true,
                bulkOutbound: false,
                vip: false,
                sameIntent: nil,
                recipientCount: 3,
                recipientClass: "external",
                effectHints: ["external-message"]
            )
        )
        #expect(RulesPrePass.evaluate(card) == nil)

        let backend = LiveBackend()
        await backend.prepareWarm()
        let response = await backend.classify(card)

        #expect(response.schemaVersion == 1)
        #expect(response.timedOut == false)
        // Real generation should not look like pure unavailable fallback.
        // modelAvailable true on success; fallback only on generation error.
        if response.fallback {
            #expect(response.verdict == .continue)
            #expect(response.modelAvailable == true)
        } else {
            #expect(response.modelAvailable == true)
            #expect(
                response.verdict == .continue || response.verdict == .ask
                    || response.verdict == .askStickyCandidate
            )
            if response.verdict.requiresExplain {
                #expect(!(response.explain ?? "").isEmpty)
            }
        }
    }

    @Test(
        "StewardSession warm + live classify for residual gray card",
        .enabled(if: LiveBackend.isOnDeviceModelAvailable)
    )
    func sessionWarmLive() async {
        let card = RiskCard(
            sessionId: "session-live",
            tool: "browser",
            command: nil,
            features: RiskCard.Features(
                executed: true,
                bulkOutbound: false,
                vip: false,
                recipientCount: 1,
                effectHints: ["browser"]
            )
        )
        let session = StewardSession(backend: LiveBackend(), timeoutMs: 5_000)
        await session.warm()
        #expect(await session.isWarmed == true)
        let response = await session.classify(card)
        #expect(response.schemaVersion == 1)
        #expect(response.verdict != .ask || !(response.explain ?? "").isEmpty)
    }

    @Test("prompt builder is compact and includes tool")
    func promptBuilder() {
        #if canImport(FoundationModels)
        let card = RiskCard(
            sessionId: "p",
            tool: "send_email",
            command: String(repeating: "x", count: 500),
            features: RiskCard.Features(executed: true, vip: true)
        )
        let prompt = LiveBackend.prompt(for: card)
        #expect(prompt.contains("tool: send_email"))
        #expect(prompt.contains("features.vip: true"))
        // Command clipped to ~400 chars + ellipsis, not full 500.
        #expect(prompt.count < 900)
        #endif
    }
}
