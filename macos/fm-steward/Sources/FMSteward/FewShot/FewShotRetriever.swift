import Foundation

/// Retrieves curated ambiguous-shell few-shots for residual FM only.
///
/// Product law: call **only after** `RulesPrePass` returns nil. Never on the
/// hard-rules path. Errors → empty array (fail-open assist).
public protocol FewShotRetriever: Sendable {
    /// Top-k gray examples for residual FM. Empty on miss/error.
    func retrieve(for card: RiskCard, limit: Int) async -> [FewShotExample]
}

/// Default: no few-shots (product-safe when Wax/store is off).
public struct NullFewShotRetriever: FewShotRetriever {
    public init() {}

    public func retrieve(for card: RiskCard, limit: Int) async -> [FewShotExample] {
        _ = card
        _ = limit
        return []
    }
}

/// In-memory / static map for unit tests (no Wax dependency).
public struct StaticFewShotRetriever: FewShotRetriever {
    public var examples: [FewShotExample]
    /// Optional spy: increments on every retrieve call.
    public let callCount: LockedCounter?

    public init(examples: [FewShotExample], callCount: LockedCounter? = nil) {
        self.examples = examples
        self.callCount = callCount
    }

    public func retrieve(for card: RiskCard, limit: Int) async -> [FewShotExample] {
        callCount?.increment()
        let q = (card.command ?? "").lowercased()
        guard !q.isEmpty else { return [] }
        // Prefer examples whose command shares a token with the query; else first N.
        let scored = examples.map { ex -> (Int, FewShotExample) in
            let cmd = ex.command.lowercased()
            var score = 0
            for token in q.split(whereSeparator: { $0.isWhitespace || $0 == "/" || $0 == "-" }) {
                let t = String(token)
                if t.count >= 2, cmd.contains(t) { score += 1 }
            }
            return (score, ex)
        }
        .sorted { $0.0 > $1.0 }

        let top = scored.prefix(max(0, limit)).map(\.1)
        if top.isEmpty {
            return Array(examples.prefix(max(0, limit)))
        }
        return Array(top)
    }
}

/// Thread-safe counter for tests (spy “retriever was/wasn’t called”).
public final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int = 0

    public init() {}

    public func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Load seed JSON array of `FewShotExample`.
public enum FewShotSeedLoader {
    /// Hard-rule catastrophe substrings that must never appear in seed commands.
    ///
    /// Mirrors `GLOBAL_EXCLUSIONS` in `scripts/compile-residual-knowledge.py`
    /// (case-insensitive substring match on the command). Keep in sync with the
    /// compiler smoke list when either side changes.
    public static let globalHardRuleExclusions: [String] = [
        "rm -rf /",
        "rm -rf/",
        "| bash",
        "|bash",
        "| sh",
        "|sh",
        "curl|bash",
        "curl|sh",
        "wget|bash",
        "wget|sh",
    ]

    public static func load(from url: URL) throws -> [FewShotExample] {
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    public static func load(from data: Data) throws -> [FewShotExample] {
        let decoder = JSONDecoder()
        let items = try decoder.decode([FewShotExample].self, from: data)
        for item in items {
            guard item.isValidVerdict else {
                throw SeedError.invalidVerdict(item.expectedVerdict, command: item.command)
            }
            guard !item.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SeedError.emptyCommand
            }
            if let pattern = matchingHardRuleExclusion(command: item.command) {
                throw SeedError.hardRuleExclusion(pattern, command: item.command)
            }
        }
        return items
    }

    /// Returns the first global exclusion whose lowercased form is a substring of
    /// the lowercased command, or nil if clean.
    public static func matchingHardRuleExclusion(command: String) -> String? {
        let cmd = command.lowercased()
        for pattern in globalHardRuleExclusions {
            if cmd.contains(pattern.lowercased()) {
                return pattern
            }
        }
        return nil
    }

    public enum SeedError: Error, CustomStringConvertible {
        case invalidVerdict(String, command: String)
        case emptyCommand
        /// Command hits a hard-rule exclusion (mirrors compiler GLOBAL_EXCLUSIONS).
        case hardRuleExclusion(String, command: String)

        public var description: String {
            switch self {
            case .invalidVerdict(let v, let command):
                return "invalid expected_verdict '\(v)' for command '\(command)'"
            case .emptyCommand:
                return "seed example has empty command"
            case .hardRuleExclusion(let pattern, let command):
                return "seed command hits hard_rule_exclusion '\(pattern)': '\(command)'"
            }
        }
    }
}
