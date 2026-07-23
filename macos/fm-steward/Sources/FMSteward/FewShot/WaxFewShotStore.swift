import Foundation

#if canImport(Wax)
import Wax
#endif

/// Search mode for Wax-backed residual few-shots.
public enum WaxSearchMode: String, Sendable, Equatable {
    /// Full-text only (deterministic CI; no embedder required).
    case text
    /// Hybrid text+vector when embedder ready; falls back to text on open/search failure paths.
    case hybrid
}

/// Wax-backed few-shot store for residual FM.
///
/// Assist only: open/seed/search failures → empty retrieve (fail-open).
/// Prefer **text** mode for CI; hybrid when MiniLM is available.
public actor WaxFewShotStore: FewShotRetriever {
    public static let defaultLimit: Int = 3

    private let storeURL: URL
    private let searchMode: WaxSearchMode
    #if canImport(Wax)
    private var memory: Memory?
    #endif
    private var openFailed: Bool = false

    public init(storeURL: URL, searchMode: WaxSearchMode = .text) {
        self.storeURL = storeURL
        self.searchMode = searchMode
    }

    /// Whether the Wax module is linked in this build.
    public nonisolated static var isWaxLinked: Bool {
        #if canImport(Wax)
        true
        #else
        false
        #endif
    }

    /// Seed (or re-seed) from curated examples. Idempotent for tests: clears prior file.
    public func seed(examples: [FewShotExample]) async throws {
        #if canImport(Wax)
        try await ensureOpen(create: true)
        guard let memory else {
            throw StoreError.notOpen
        }
        for ex in examples {
            try await memory.save(
                ex.documentText(),
                metadata: [
                    "kind": "shell-ambig",
                    "verdict": ex.expectedVerdict,
                    "id": ex.id ?? "",
                    "tags": ex.tags.joined(separator: ","),
                    "domain": ex.effectiveDomain,
                ]
            )
        }
        try await memory.flush()
        #else
        throw StoreError.waxNotLinked
        #endif
    }

    public func seed(fromSeedJSON url: URL) async throws {
        let examples = try FewShotSeedLoader.load(from: url)
        try await seed(examples: examples)
    }

    public func retrieve(for card: RiskCard, limit: Int) async -> [FewShotExample] {
        let query = card.command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { return [] }
        let k = max(0, min(limit, 8))
        guard k > 0 else { return [] }

        #if canImport(Wax)
        do {
            try await ensureOpen(create: false)
            guard let memory else { return [] }
            let mode: Memory.RetrievalMode = switch searchMode {
            case .text: .textOnly
            case .hybrid: .hybrid(alpha: 0.55)
            }
            let results = try await memory.search(
                query,
                options: Memory.SearchOptions(topK: k, mode: mode)
            )
            var out: [FewShotExample] = []
            var seen = Set<String>()
            for item in results.items {
                guard let ex = FewShotExample.parseDocument(item.text) ?? parseMetadata(item) else {
                    continue
                }
                let key = ex.command
                if seen.contains(key) { continue }
                seen.insert(key)
                out.append(ex)
                if out.count >= k { break }
            }
            return out
        } catch {
            return []
        }
        #else
        return []
        #endif
    }

    public func close() async {
        #if canImport(Wax)
        if let memory {
            try? await memory.close()
        }
        memory = nil
        #endif
    }

    // MARK: - Internals

    public enum StoreError: Error, CustomStringConvertible {
        case waxNotLinked
        case notOpen

        public var description: String {
            switch self {
            case .waxNotLinked: return "Wax package not linked"
            case .notOpen: return "Wax store not open"
            }
        }
    }

    #if canImport(Wax)
    private func ensureOpen(create: Bool) async throws {
        if memory != nil { return }
        if openFailed, !create { return }

        let fm = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        if create, fm.fileExists(atPath: storeURL.path) {
            try? fm.removeItem(at: storeURL)
        }

        do {
            // Build Config as a Sendable value — avoid non-Sendable configure closures
            // crossing actor isolation into Memory.init.
            let config = Memory.Config(
                enableTextSearch: true,
                // Text mode disables vector; hybrid leaves vector on (MiniLM when trait present).
                enableVectorSearch: (searchMode == .hybrid),
                enableStructuredMemory: false,
                enableAccessStatsScoring: false,
                enableAsyncEnrichment: false,
                requireOnDeviceProviders: false
            )
            let mem = try await Memory(at: storeURL, config: config)
            memory = mem
            openFailed = false
        } catch {
            openFailed = true
            memory = nil
            throw error
        }
    }

    private func parseMetadata(_ item: RAGContext.Item) -> FewShotExample? {
        let meta = item.metadata
        guard meta["kind"] == "shell-ambig" || item.text.contains("[shell-ambig]") else {
            return nil
        }
        if let parsed = FewShotExample.parseDocument(item.text) {
            return parsed
        }
        let verdict = meta["verdict"] ?? "continue"
        guard FewShotExample.validVerdicts.contains(verdict) else { return nil }
        var command = ""
        for line in item.text.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("command:") {
                command = String(s.dropFirst("command:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !command.isEmpty else { return nil }
        let tags = (meta["tags"] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
        let id = meta["id"].flatMap { $0.isEmpty ? nil : $0 }
        let domain = meta["domain"].flatMap { $0.isEmpty ? nil : $0 } ?? "shell"
        return FewShotExample(
            id: id,
            command: command,
            expectedVerdict: verdict,
            why: "curated gray example",
            tags: tags,
            domain: domain
        )
    }
    #endif
}
