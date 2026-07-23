import Foundation
import Testing
@testable import FMSteward

/// Core `FewShotRuntime` modes: off → Null; auto fail-open; wax missing seed throws;
/// product search mode is text. Reseed happy-path / wax usable store → u4.
@Suite("FewShotRuntime core modes")
struct FewShotRuntimeTests {
    // MARK: - Helpers

    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fm-steward-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func grayCard(command: String = "npm install lodash") -> RiskCard {
        RiskCard(
            sessionId: "runtime-test",
            tool: "bash",
            command: command,
            features: RiskCard.Features(executed: true, effectHints: ["shell"])
        )
    }

    private func writePoisonSeed(at url: URL) throws {
        let poison: [[String: Any]] = [
            [
                "id": "P_runtime",
                "command": "rm -rf /",
                "expected_verdict": "ask",
                "why": "poison for load-fail fail-open",
                "tags": ["ambig", "test"],
                "domain": "shell",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: poison)
        try data.write(to: url)
    }

    // MARK: - G3.1 off → Null

    @Test("G3.1 .off returns NullFewShotRetriever (empty retrieve)")
    func offReturnsNull() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let seedURL = root.appendingPathComponent("missing-seed.json")
        let storeURL = root.appendingPathComponent("ambig.wax")

        let retriever = try await FewShotRuntime.makeRetriever(
            mode: .off,
            seedURL: seedURL,
            storeURL: storeURL
        )

        #expect(retriever is NullFewShotRetriever)
        let hits = await retriever.retrieve(for: grayCard(), limit: 3)
        #expect(hits.isEmpty)
    }

    // MARK: - G3.4 auto + missing seed → Null fail-open

    @Test("G3.4 .auto + missing seed file → Null, no throw")
    func autoMissingSeedFailOpen() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let seedURL = root.appendingPathComponent("does-not-exist.json")
        let storeURL = root.appendingPathComponent("ambig.wax")

        let retriever = try await FewShotRuntime.makeRetriever(
            mode: .auto,
            seedURL: seedURL,
            storeURL: storeURL
        )

        #expect(retriever is NullFewShotRetriever)
        let hits = await retriever.retrieve(for: grayCard(), limit: 3)
        #expect(hits.isEmpty)
    }

    // MARK: - G3.5 auto + seed load failure → Null fail-open

    @Test("G3.5 .auto + seed load failure (poison exclusion) → Null, no throw")
    func autoSeedLoadFailureFailOpen() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let seedURL = root.appendingPathComponent("poison.json")
        let storeURL = root.appendingPathComponent("ambig.wax")
        try writePoisonSeed(at: seedURL)

        let retriever = try await FewShotRuntime.makeRetriever(
            mode: .auto,
            seedURL: seedURL,
            storeURL: storeURL
        )

        #expect(retriever is NullFewShotRetriever)
        let hits = await retriever.retrieve(for: grayCard(), limit: 3)
        #expect(hits.isEmpty)
    }

    // MARK: - G3.6 wax + missing seed throws

    @Test("G3.6 .wax + missing seed throws")
    func waxMissingSeedThrows() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let seedURL = root.appendingPathComponent("does-not-exist.json")
        let storeURL = root.appendingPathComponent("ambig.wax")

        await #expect(throws: FewShotRuntime.Error.self) {
            _ = try await FewShotRuntime.makeRetriever(
                mode: .wax,
                seedURL: seedURL,
                storeURL: storeURL
            )
        }
    }

    // MARK: - G3.8 product search mode is text

    @Test("G3.8 product factory default search mode is text")
    func productSearchModeIsText() {
        #expect(FewShotRuntime.defaultSearchMode == .text)
        #expect(FewShotRuntime.defaultSearchMode == WaxSearchMode.text)
    }
}
