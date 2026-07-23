import Foundation
import Testing
@testable import FMSteward

/// Core `FewShotRuntime` modes + reseed/wax happy paths (G3.1–G3.8).
@Suite("FewShotRuntime core modes")
struct FewShotRuntimeTests {
    // MARK: - Helpers

    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fm-steward-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func packageFixturesRoot(filePath: String = #filePath) -> URL {
        // Tests/FMStewardTests/FewShotRuntimeTests.swift → package root → Fixtures
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent() // FMStewardTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Fixtures")
    }

    private func packageSeedURL() -> URL {
        packageFixturesRoot().appendingPathComponent("ambig-fewshot/seed.json")
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

    private func closeIfWax(_ retriever: any FewShotRetriever) async {
        if let store = retriever as? WaxFewShotStore {
            await store.close()
        }
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

    // MARK: - G3.2 auto reseed when store missing

    @Test("G3.2 .auto + missing store + valid seed → seeds store + sidecar hash")
    func autoReseedWhenStoreMissing() async throws {
        guard WaxFewShotStore.isWaxLinked else { return }

        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let seedURL = packageSeedURL()
        #expect(FileManager.default.fileExists(atPath: seedURL.path))

        let storeURL = root.appendingPathComponent("ambig.wax")
        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
        #expect(FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))

        let retriever = try await FewShotRuntime.makeRetriever(
            mode: .auto,
            seedURL: seedURL,
            storeURL: storeURL,
            searchMode: .text
        )
        await closeIfWax(retriever)

        #expect(!(retriever is NullFewShotRetriever))
        #expect(retriever is WaxFewShotStore)
        #expect(FileManager.default.fileExists(atPath: storeURL.path))

        let sidecar = FewShotSeedBootstrap.seedHashSidecarURL(for: storeURL)
        #expect(FileManager.default.fileExists(atPath: sidecar.path))

        let recorded = try String(contentsOf: sidecar, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedSeedHash = try FewShotSeedBootstrap.seedContentSHA256(of: seedURL)
        let expectedStoreHash = try FewShotSeedBootstrap.storeContentSHA256(of: storeURL)
        let expected = FewShotSeedBootstrap.encodeSidecarValue(
            seedHash: expectedSeedHash,
            storeHash: expectedStoreHash
        )
        #expect(recorded == expected)
        #expect(recorded.hasPrefix("v\(FewShotSeedBootstrap.storeFormatVersion):"))
        #expect(recorded.split(separator: ":").count == 3)
        #expect(!FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))
    }

    // MARK: - G3.3 auto no-reseed when hash matches

    @Test("G3.3 .auto + matching sidecar → does not re-seed")
    func autoNoReseedWhenHashMatches() async throws {
        guard WaxFewShotStore.isWaxLinked else { return }

        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let seedURL = packageSeedURL()
        let storeURL = root.appendingPathComponent("ambig.wax")

        // First factory call: seed + write sidecar
        let first = try await FewShotRuntime.makeRetriever(
            mode: .auto,
            seedURL: seedURL,
            storeURL: storeURL,
            searchMode: .text
        )
        await closeIfWax(first)
        #expect(first is WaxFewShotStore)

        let sidecar = FewShotSeedBootstrap.seedHashSidecarURL(for: storeURL)
        let hashBefore = try String(contentsOf: sidecar, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedSeedHash = try FewShotSeedBootstrap.seedContentSHA256(of: seedURL)
        let expectedStoreHash = try FewShotSeedBootstrap.storeContentSHA256(of: storeURL)
        let expected = FewShotSeedBootstrap.encodeSidecarValue(
            seedHash: expectedSeedHash,
            storeHash: expectedStoreHash
        )
        #expect(hashBefore == expected)
        #expect(!FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))

        let storeAttrsBefore = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        let storeMtimeBefore = storeAttrsBefore[.modificationDate] as? Date
        let sidecarAttrsBefore = try FileManager.default.attributesOfItem(atPath: sidecar.path)
        let sidecarMtimeBefore = sidecarAttrsBefore[.modificationDate] as? Date

        // Allow filesystem mtime resolution if a reseed incorrectly rewrote files
        try await Task.sleep(for: .milliseconds(100))

        // Second call with same seed + matching sidecar must not re-seed
        #expect(!FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))
        let second = try await FewShotRuntime.makeRetriever(
            mode: .auto,
            seedURL: seedURL,
            storeURL: storeURL,
            searchMode: .text
        )
        await closeIfWax(second)
        #expect(second is WaxFewShotStore)
        #expect(!(second is NullFewShotRetriever))

        let hashAfter = try String(contentsOf: sidecar, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(hashAfter == hashBefore)
        #expect(!FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))

        let storeAttrsAfter = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        let storeMtimeAfter = storeAttrsAfter[.modificationDate] as? Date
        let sidecarAttrsAfter = try FileManager.default.attributesOfItem(atPath: sidecar.path)
        let sidecarMtimeAfter = sidecarAttrsAfter[.modificationDate] as? Date
        #expect(storeMtimeBefore == storeMtimeAfter)
        #expect(sidecarMtimeBefore == sidecarMtimeAfter)
    }

    // MARK: - G3.7 wax seed OK → usable retrieve k≤3

    @Test("G3.7 .wax + seed OK → retriever usable; retrieve limit ≤3")
    func waxSeedOKRetrieverUsable() async throws {
        guard WaxFewShotStore.isWaxLinked else { return }

        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let seedURL = packageSeedURL()
        let storeURL = root.appendingPathComponent("ambig.wax")

        let retriever = try await FewShotRuntime.makeRetriever(
            mode: .wax,
            seedURL: seedURL,
            storeURL: storeURL,
            searchMode: .text
        )
        #expect(retriever is WaxFewShotStore)
        #expect(!(retriever is NullFewShotRetriever))

        // Sidecar written on seed path
        let sidecar = FewShotSeedBootstrap.seedHashSidecarURL(for: storeURL)
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        #expect(!FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))

        let hits = await retriever.retrieve(for: grayCard(command: "npm install foo"), limit: 3)
        #expect(hits.count <= 3)
        #expect(hits.count >= 1)
        let hasInstall = hits.contains {
            $0.command.lowercased().contains("npm") || $0.tags.contains("install")
        }
        #expect(hasInstall)

        await closeIfWax(retriever)
    }

    // MARK: - R6 concurrent reseed stress

    @Test("R6 concurrent makeRetriever(.auto) ≥4 tasks: exclusive seed + stable sidecar")
    func concurrentAutoReseedStress() async throws {
        guard WaxFewShotStore.isWaxLinked else { return }

        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let seedURL = packageSeedURL()
        #expect(FileManager.default.fileExists(atPath: seedURL.path))
        let storeURL = root.appendingPathComponent("ambig.wax")
        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
        #expect(FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))

        let taskCount = 4
        let results: [any FewShotRetriever] = try await withThrowingTaskGroup(
            of: (any FewShotRetriever).self
        ) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    try await FewShotRuntime.makeRetriever(
                        mode: .auto,
                        seedURL: seedURL,
                        storeURL: storeURL,
                        searchMode: .text
                    )
                }
            }
            var collected: [any FewShotRetriever] = []
            for try await retriever in group {
                collected.append(retriever)
            }
            return collected
        }

        #expect(results.count == taskCount)
        // Process-local non-reentrant gate + flock: same-PID concurrent cold start
        // should yield live Wax stores (not systemic fail-open to Null under false
        // contention). Crash-only is insufficient for R6 exclusive-seed ownership.
        var waxCount = 0
        for r in results {
            #expect(r is WaxFewShotStore || r is NullFewShotRetriever)
            if r is WaxFewShotStore { waxCount += 1 }
            await closeIfWax(r)
        }
        #expect(waxCount >= 1)
        // Under exclusive same-PID ownership, all waiters re-check under lock and
        // open the already-seeded store — expect every concurrent attach to be Wax.
        #expect(waxCount == taskCount)

        #expect(FileManager.default.fileExists(atPath: storeURL.path))
        let sidecar = FewShotSeedBootstrap.seedHashSidecarURL(for: storeURL)
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        #expect(!FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))

        // Single stable fingerprint: one seeder wrote seed+store hashes once.
        let recorded = try String(contentsOf: sidecar, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedSeedHash = try FewShotSeedBootstrap.seedContentSHA256(of: seedURL)
        let expectedStoreHash = try FewShotSeedBootstrap.storeContentSHA256(of: storeURL)
        let expected = FewShotSeedBootstrap.encodeSidecarValue(
            seedHash: expectedSeedHash,
            storeHash: expectedStoreHash
        )
        #expect(recorded == expected)
        #expect(recorded.split(separator: ":").count == 3)

        // Post single-threaded auto: fast path, still no reseed thrash.
        let post = try await FewShotRuntime.makeRetriever(
            mode: .auto,
            seedURL: seedURL,
            storeURL: storeURL,
            searchMode: .text
        )
        #expect(post is WaxFewShotStore)
        #expect(!FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))
        let recordedAfter = try String(contentsOf: sidecar, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(recordedAfter == recorded)
        await closeIfWax(post)
    }

    // MARK: - Store fingerprint stability (open/search must not thrash reseed)

    @Test("M-12 store fingerprint stable after seed + retrieve + close")
    func storeFingerprintStableAfterOpenSearch() async throws {
        guard WaxFewShotStore.isWaxLinked else { return }

        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let seedURL = packageSeedURL()
        let storeURL = root.appendingPathComponent("ambig.wax")

        // Seed once via factory (writes store + sidecar).
        let retriever = try await FewShotRuntime.makeRetriever(
            mode: .wax,
            seedURL: seedURL,
            storeURL: storeURL,
            searchMode: .text
        )
        #expect(retriever is WaxFewShotStore)
        #expect(!FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))

        let sidecar = FewShotSeedBootstrap.seedHashSidecarURL(for: storeURL)
        let hashBefore = try String(contentsOf: sidecar, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let storeHashBefore = try FewShotSeedBootstrap.storeContentSHA256(of: storeURL)

        // Open/search path (retrieve) must not mutate store bytes in a way that
        // flips needsReseed / thrash-reseeds on the next attach.
        let hits = await retriever.retrieve(for: grayCard(command: "npm install foo"), limit: 3)
        #expect(hits.count >= 1)
        await closeIfWax(retriever)

        let storeHashAfter = try FewShotSeedBootstrap.storeContentSHA256(of: storeURL)
        let hashAfter = try String(contentsOf: sidecar, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(storeHashAfter == storeHashBefore)
        #expect(hashAfter == hashBefore)
        #expect(!FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))

        // Second factory attach must take the no-reseed fast path (same fingerprint).
        let second = try await FewShotRuntime.makeRetriever(
            mode: .auto,
            seedURL: seedURL,
            storeURL: storeURL,
            searchMode: .text
        )
        #expect(second is WaxFewShotStore)
        #expect(!FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL))
        let hashFinal = try String(contentsOf: sidecar, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(hashFinal == hashBefore)
        await closeIfWax(second)
    }
}
