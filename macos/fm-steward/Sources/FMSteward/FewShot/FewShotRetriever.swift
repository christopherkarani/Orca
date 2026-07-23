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

/// Test double: sleeps before returning examples (proves session timeout bounds retrieve).
///
/// On task cancellation (session timer win), returns empty — fail-open assist.
public struct SlowFewShotRetriever: FewShotRetriever {
    public let delayMs: Int
    public let examples: [FewShotExample]
    public let callCount: LockedCounter?

    public init(
        delayMs: Int,
        examples: [FewShotExample] = [],
        callCount: LockedCounter? = nil
    ) {
        self.delayMs = max(0, delayMs)
        self.examples = examples
        self.callCount = callCount
    }

    public func retrieve(for card: RiskCard, limit: Int) async -> [FewShotExample] {
        _ = card
        callCount?.increment()
        let ns = UInt64(delayMs) * 1_000_000
        do {
            try await Task.sleep(nanoseconds: ns)
        } catch {
            // Cancelled by StewardSession timeout race — empty fail-open.
            return []
        }
        let k = max(0, min(limit, examples.count))
        return Array(examples.prefix(k))
    }
}

/// Load seed JSON array of `FewShotExample`.
public enum FewShotSeedLoader {
    /// Max seed file / payload size (1 MiB), matching CLI `maxCardFileBytes`.
    public static let maxSeedFileBytes = 1_048_576

    /// Cap on seed example `command` UTF-8 byte length.
    public static let maxCommandBytes = 8_192

    /// Cap on seed example `why` UTF-8 byte length.
    public static let maxWhyBytes = 2_048

    /// Hard-rule catastrophe substrings that must never appear in seed commands.
    ///
    /// Mirrors `GLOBAL_EXCLUSIONS` in `scripts/compile-residual-knowledge.py`
    /// (case-insensitive substring match on the command). Keep in sync with the
    /// compiler smoke list **and** HardDanger catastrophe / RCE / exfil smokes
    /// (pipe-to-shell, force-push, base64|shell, secret|curl) when either side changes.
    /// Legal residual greys (`npm install`, `rm -rf ./build`, normal `git push -u`) must load.
    public static let globalHardRuleExclusions: [String] = [
        "rm -rf /",
        "rm -rf/",
        // Pipe-to-shell (space and no-space forms) — bash/sh + expanded shells.
        "| bash",
        "|bash",
        "| sh",
        "|sh",
        "| zsh",
        "|zsh",
        "| fish",
        "|fish",
        "| dash",
        "|dash",
        "| ksh",
        "|ksh",
        // Path forms commonly used after a pipe.
        "| /bin/bash",
        "|/bin/bash",
        "| /bin/sh",
        "|/bin/sh",
        "| /bin/zsh",
        "|/bin/zsh",
        "| /usr/bin/bash",
        "|/usr/bin/bash",
        "| /usr/bin/zsh",
        "|/usr/bin/zsh",
        "| /usr/bin/fish",
        "|/usr/bin/fish",
        "| /bin/dash",
        "|/bin/dash",
        "| /bin/ksh",
        "|/bin/ksh",
        // curl|shell / wget|shell compact forms.
        "curl|bash",
        "curl|sh",
        "curl|zsh",
        "curl|fish",
        "curl|dash",
        "curl|ksh",
        "wget|bash",
        "wget|sh",
        "wget|zsh",
        "wget|fish",
        "wget|dash",
        "wget|ksh",
        // HardDanger catastrophe smokes (force-push, base64|shell, secret-exfil).
        "git push --force",
        "git push -f",
        "base64 | bash",
        "base64|bash",
        "base64 | sh",
        "base64|sh",
        ".ssh | curl",
        ".ssh|curl",
        "credentials | curl",
        "credentials|curl",
    ]

    public static func load(from url: URL) throws -> [FewShotExample] {
        try enforceSeedFileSize(at: url)
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    public static func load(from data: Data) throws -> [FewShotExample] {
        guard data.count <= maxSeedFileBytes else {
            throw SeedError.seedTooLarge(data.count, max: maxSeedFileBytes)
        }
        let decoder = JSONDecoder()
        let items = try decoder.decode([FewShotExample].self, from: data)
        for item in items {
            guard item.isValidVerdict else {
                throw SeedError.invalidVerdict(item.expectedVerdict, command: item.command)
            }
            guard !item.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SeedError.emptyCommand
            }
            if item.command.utf8.count > maxCommandBytes {
                throw SeedError.fieldTooLong(field: "command", length: item.command.utf8.count, max: maxCommandBytes)
            }
            if item.why.utf8.count > maxWhyBytes {
                throw SeedError.fieldTooLong(field: "why", length: item.why.utf8.count, max: maxWhyBytes)
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

    /// Reject oversized seed files before reading into memory.
    public static func enforceSeedFileSize(at url: URL) throws {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > maxSeedFileBytes
        {
            throw SeedError.seedTooLarge(size.intValue, max: maxSeedFileBytes)
        }
    }

    public enum SeedError: Error, CustomStringConvertible {
        case invalidVerdict(String, command: String)
        case emptyCommand
        /// Command hits a hard-rule exclusion (mirrors compiler GLOBAL_EXCLUSIONS).
        case hardRuleExclusion(String, command: String)
        /// Seed file or payload exceeds `maxSeedFileBytes`.
        case seedTooLarge(Int, max: Int)
        /// Seed example field exceeds its length cap.
        case fieldTooLong(field: String, length: Int, max: Int)

        public var description: String {
            switch self {
            case .invalidVerdict(let v, let command):
                return "invalid expected_verdict '\(v)' for command '\(command)'"
            case .emptyCommand:
                return "seed example has empty command"
            case .hardRuleExclusion(let pattern, let command):
                return "seed command hits hard_rule_exclusion '\(pattern)': '\(command)'"
            case .seedTooLarge(let size, let max):
                return "seed file too large (\(size) bytes; max \(max))"
            case .fieldTooLong(let field, let length, let max):
                return "seed example \(field) too long (\(length) bytes; max \(max))"
            }
        }
    }
}
