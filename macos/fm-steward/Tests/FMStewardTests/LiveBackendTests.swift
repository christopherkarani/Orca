import Foundation
import Testing
@testable import FMSteward

@Suite("Live on-device Foundation Models")
struct LiveBackendTests {
    @Test("framework + availability probes are coherent")
    func availabilityProbes() {
        #expect(LiveBackend.isFoundationModelsFrameworkPresent == true)
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
            #expect(response.modelAvailable == true || response.fallback == true)
        } else {
            #expect(response.fallback == true)
            #expect(response.modelAvailable == false)
        }
    }

    @Test(
        "gray shell card without rules hit uses LiveBackend when available",
        .enabled(if: LiveBackend.isOnDeviceModelAvailable)
    )
    func grayShellHitsLiveModel() async {
        let card = RiskCard(
            sessionId: "gray-live",
            tool: "bash",
            command: "make release",
            features: RiskCard.Features(
                executed: true,
                sameIntent: nil,
                paths: nil,
                effectHints: ["shell"]
            )
        )
        #expect(RulesPrePass.evaluate(card) == nil)

        let backend = LiveBackend()
        await backend.prepareWarm()
        let response = await backend.classify(card)

        #expect(response.schemaVersion == 1)
        #expect(response.timedOut == false)
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
        "StewardSession warm + live classify for residual shell card",
        .enabled(if: LiveBackend.isOnDeviceModelAvailable)
    )
    func sessionWarmLive() async {
        let card = RiskCard(
            sessionId: "session-live",
            tool: "bash",
            command: "git push --force origin main",
            features: RiskCard.Features(executed: true, effectHints: ["shell"])
        )
        let session = StewardSession(backend: LiveBackend(), timeoutMs: 5_000)
        await session.warm()
        #expect(await session.isWarmed == true)
        let response = await session.classify(card)
        #expect(response.schemaVersion == 1)
        #expect(response.verdict != .ask || !(response.explain ?? "").isEmpty)
    }

    @Test("prompt builder is shell-focused, caps command, and requires print/search continue")
    func promptBuilder() {
        #if canImport(FoundationModels)
        let longCmd = String(repeating: "x", count: 500)
        let card = RiskCard(
            sessionId: "p",
            tool: "bash",
            command: longCmd,
            features: RiskCard.Features(executed: true, paths: ["./a"])
        )
        let prompt = LiveBackend.prompt(for: card)
        #expect(prompt.contains("tool: bash"))
        #expect(prompt.contains("command:"))
        #expect(prompt.contains("features.executed:"))
        #expect(prompt.contains("If the command only prints, searches, or comments about danger without executing it, verdict must be continue."))
        #expect(!prompt.contains("bulk_outbound"))
        #expect(!prompt.contains("vip"))
        // Command capped at 300 + ellipsis — full 500-char body must not appear.
        #expect(!prompt.contains(longCmd))
        #expect(prompt.contains(String(longCmd.prefix(300)) + "…"))
        #expect(prompt.count < 900)

        let instructions = LiveBackend.systemInstructions
        #expect(instructions.contains("NEGATIVE"))
        #expect(instructions.contains("POSITIVE"))
        #expect(instructions.contains("echo") || instructions.contains("printf"))
        #expect(instructions.contains("Residual bias") || instructions.contains("always ask"))
        #endif
    }
}
