import Foundation
import Testing
@testable import FMSteward

/// §6.4 fixture table + unit acceptance: rules pre-pass via Classifier.
@Suite("Fixture table (§6.4)")
struct FixtureTableTests {
    private let classifier = Classifier(backend: UnavailableBackend())

    @Test("grep_rm_rf: executed=false → continue")
    func grepRmRfContinues() async throws {
        let card = try loadFixture("grep_rm_rf")
        let response = await classifier.classify(card)

        #expect(response.verdict == .continue)
        #expect(response.schemaVersion == 1)
        #expect(response.timedOut == false)
        #expect(response.fallback == false)
    }

    @Test("npm_test_loop: same_intent=test_loop → continue")
    func npmTestLoopContinues() async throws {
        let card = try loadFixture("npm_test_loop")
        let response = await classifier.classify(card)

        #expect(response.verdict == .continue)
        #expect(response.timedOut == false)
        #expect(response.fallback == false)
    }

    @Test("bulk_email: bulk_outbound → ask or ask_sticky_candidate with non-empty explain")
    func bulkEmailAsksWithExplain() async throws {
        let card = try loadFixture("bulk_email")
        let response = await classifier.classify(card)

        #expect(response.verdict == .ask || response.verdict == .askStickyCandidate)
        let explain = try #require(response.explain)
        #expect(!explain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(response.timedOut == false)
        #expect(response.fallback == false)
    }

    @Test("vip_email: vip → ask or ask_sticky_candidate with non-empty explain")
    func vipEmailAsksWithExplain() async throws {
        let card = try loadFixture("vip_email")
        let response = await classifier.classify(card)

        #expect(response.verdict == .ask || response.verdict == .askStickyCandidate)
        let explain = try #require(response.explain)
        #expect(!explain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(response.timedOut == false)
        #expect(response.fallback == false)
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
