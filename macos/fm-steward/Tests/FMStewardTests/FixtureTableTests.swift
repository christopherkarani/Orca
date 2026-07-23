import Foundation
import Testing
@testable import FMSteward

/// v1 shell fixture table: rules short-circuit safe cases; danger cases hit backend.
@Suite("Fixture table (v1 shell)")
struct FixtureTableTests {
    private let classifier = Classifier(backend: UnavailableBackend())

    @Test("grep_rm_rf: executed=false → continue (rules)")
    func grepRmRfContinues() async throws {
        let card = try loadFixture("grep_rm_rf")
        let response = await classifier.classify(card)

        #expect(response.verdict == .continue)
        #expect(response.schemaVersion == 1)
        #expect(response.timedOut == false)
        #expect(response.fallback == false)
        #expect(response.modelAvailable == false)
    }

    @Test("npm_test_loop: same_intent=test_loop → continue (rules)")
    func npmTestLoopContinues() async throws {
        let card = try loadFixture("npm_test_loop")
        let response = await classifier.classify(card)

        #expect(response.verdict == .continue)
        #expect(response.timedOut == false)
        #expect(response.fallback == false)
        #expect(response.modelAvailable == false)
    }

    @Test("curl_pipe_sh: hard-danger rules ask even without FM")
    func curlPipeShHardAsk() async throws {
        let card = try loadFixture("curl_pipe_sh")
        let hit = RulesPrePass.evaluate(card)
        #expect(hit?.verdict == .ask)
        let response = await classifier.classify(card)
        #expect(response.verdict == .ask)
        #expect(response.fallback == false)
        #expect(!(response.explain ?? "").isEmpty)
    }

    @Test("rm_rf_workdir: home data wipe → hard-ask (not allowlisted clean)")
    func rmRfWorkdirHardAsk() async throws {
        let card = try loadFixture("rm_rf_workdir")
        // rm -rf ~/Documents/… — HardDanger home path (not CommandShape safe clean)
        #expect(RulesPrePass.evaluate(card)?.verdict == .ask)
        let response = await classifier.classify(card)

        #expect(response.verdict == .ask)
        #expect(response.fallback == false)
        #expect(!(response.explain ?? "").isEmpty)
    }
}

// MARK: - Fixture loading

func packageRootURL(filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
        .deletingLastPathComponent() // FMStewardTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // fm-steward
}

func loadFixture(_ id: String, filePath: String = #filePath) throws -> RiskCard {
    let url = packageRootURL(filePath: filePath)
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("\(id).json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(RiskCard.self, from: data)
}
