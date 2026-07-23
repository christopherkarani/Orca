import Foundation
import Testing
@testable import FMSteward

@Suite("Contract validation (validate.sh gated)")
struct ContractValidationTests {
    @Test("Fixtures/validate.sh exits 0")
    func validateScriptPasses() throws {
        let root = packageRootURL()
        let script = root.appendingPathComponent("Fixtures/validate.sh")
        #expect(FileManager.default.fileExists(atPath: script.path))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        #expect(
            process.terminationStatus == 0,
            "validate.sh failed (exit \(process.terminationStatus)):\n\(output)"
        )
    }

    @Test("bulk_recipient_min clamp still works for host thresholds")
    func bulkMinClamp() {
        #expect(RulesPrePass.clampBulkRecipientMin(nil) == RiskCard.defaultBulkRecipientMin)
        #expect(RulesPrePass.clampBulkRecipientMin(1000) == 1000)
        #expect(RulesPrePass.clampBulkRecipientMin(0) == RiskCard.defaultBulkRecipientMin)
        #expect(RulesPrePass.clampBulkRecipientMin(50_000_000) == RiskCard.defaultBulkRecipientMin)
    }

    @Test("unknown effect class falls back to shell")
    func effectClassAllowlist() {
        let card = RiskCard(
            sessionId: "s",
            tool: "bash",
            command: "true",
            features: RiskCard.Features(executed: true, effectHints: ["not-a-real-class"])
        )
        #expect(RulesPrePass.stickyEffectClass(for: card) == RulesPrePass.defaultEffectClass)
        #expect(RulesPrePass.defaultEffectClass == "shell")
    }
}
