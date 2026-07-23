import Foundation

/// One curated gray-shell example for residual FM few-shot prompting.
///
/// Assist only — never a security authority. Verdicts are soft-interrupt labels
/// (`continue` | `ask` | `ask_sticky_candidate`); never deny/allow.
public struct FewShotExample: Sendable, Equatable, Codable {
    public var id: String?
    public var command: String
    /// Labeled soft verdict: `continue` | `ask` | `ask_sticky_candidate`.
    public var expectedVerdict: String
    public var why: String
    public var tags: [String]
    /// Residual domain: `shell` (v1 coding), reserved `email` | `pay` | `social`.
    public var domain: String?

    public init(
        id: String? = nil,
        command: String,
        expectedVerdict: String,
        why: String,
        tags: [String] = [],
        domain: String? = "shell"
    ) {
        self.id = id
        self.command = command
        self.expectedVerdict = expectedVerdict
        self.why = why
        self.tags = tags
        self.domain = domain
    }

    enum CodingKeys: String, CodingKey {
        case id
        case command
        case expectedVerdict = "expected_verdict"
        case why
        case tags
        case domain
    }

    /// Valid soft-interrupt verdict labels only.
    public static let validVerdicts: Set<String> = [
        "continue",
        "ask",
        "ask_sticky_candidate",
    ]

    /// Known residual domains (coding + reserved employee surfaces).
    public static let knownDomains: Set<String> = [
        "shell",
        "email",
        "pay",
        "social",
    ]

    public var isValidVerdict: Bool {
        Self.validVerdicts.contains(expectedVerdict)
    }

    /// Effective domain for display / storage (defaults to shell).
    public var effectiveDomain: String {
        let d = domain?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return d.isEmpty ? "shell" : d
    }

    /// Stable document text for Wax storage / text search.
    public func documentText() -> String {
        let tagStr = tags.joined(separator: ",")
        let idPart = id.map { " id=\($0)" } ?? ""
        let domainPart = " domain=\(effectiveDomain)"
        return """
        [shell-ambig]\(idPart)\(domainPart) verdict=\(expectedVerdict) tags=\(tagStr)
        command: \(command)
        why: \(why)
        """
    }

    /// Parse a Wax document (or seed-shaped text) back into an example. Fail-open → nil.
    ///
    /// Requires an explicit valid `verdict=` token; does **not** invent `continue`.
    public static func parseDocument(_ text: String) -> FewShotExample? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("[shell-ambig]") else { return nil }

        var verdict: String?
        var tags: [String] = []
        var command = ""
        var why = ""
        var id: String?
        var domain: String? = "shell"

        for line in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("[shell-ambig]") {
                if let vRange = s.range(of: "verdict=") {
                    let rest = s[vRange.upperBound...]
                    if let token = rest.split(separator: " ").first.map(String.init), !token.isEmpty {
                        verdict = token
                    }
                }
                if let tRange = s.range(of: "tags=") {
                    let rest = s[tRange.upperBound...]
                    let token = rest.split(separator: " ").first.map(String.init) ?? ""
                    tags = token.split(separator: ",").map(String.init).filter { !$0.isEmpty }
                }
                if let iRange = s.range(of: "id=") {
                    let rest = s[iRange.upperBound...]
                    id = rest.split(separator: " ").first.map(String.init)
                }
                if let dRange = s.range(of: "domain=") {
                    let rest = s[dRange.upperBound...]
                    let token = rest.split(separator: " ").first.map(String.init)
                    if let token, !token.isEmpty {
                        domain = token
                    }
                }
            } else if s.hasPrefix("command:") {
                command = String(s.dropFirst("command:".count)).trimmingCharacters(in: .whitespaces)
            } else if s.hasPrefix("why:") {
                why = String(s.dropFirst("why:".count)).trimmingCharacters(in: .whitespaces)
            }
        }

        guard !command.isEmpty,
              let verdict,
              validVerdicts.contains(verdict)
        else {
            return nil
        }
        return FewShotExample(
            id: id,
            command: command,
            expectedVerdict: verdict,
            why: why.isEmpty ? "curated gray example" : why,
            tags: tags,
            domain: domain
        )
    }
}
