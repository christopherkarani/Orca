import Foundation

/// Pure string shape analysis for shell commands (no full shell parse).
/// Used by `RulesPrePass` to skip FM on over-nanny false-ask shapes and YOLO-safe clean allowlists.
public struct CommandShapeAnalysis: Sendable, Equatable {
    public var isCommentOnly: Bool
    public var isEchoOnly: Bool
    public var isSearchOnly: Bool
    public var isPrintOnly: Bool
    public var isSafeDevClean: Bool
    public var isVarAssignEcho: Bool
    /// Any of the above that means continue without FM.
    public var skipFM: Bool
    /// Short why for `rulesContinue`.
    public var reason: String

    public init(
        isCommentOnly: Bool = false,
        isEchoOnly: Bool = false,
        isSearchOnly: Bool = false,
        isPrintOnly: Bool = false,
        isSafeDevClean: Bool = false,
        isVarAssignEcho: Bool = false,
        skipFM: Bool = false,
        reason: String = ""
    ) {
        self.isCommentOnly = isCommentOnly
        self.isEchoOnly = isEchoOnly
        self.isSearchOnly = isSearchOnly
        self.isPrintOnly = isPrintOnly
        self.isSafeDevClean = isSafeDevClean
        self.isVarAssignEcho = isVarAssignEcho
        self.skipFM = skipFM
        self.reason = reason
    }
}

/// Conservative pure-string command shape heuristics (v1 shell steward).
public enum CommandShape {
    /// Relative basenames (or `./basename`) allowed for agentic `rm -rf` clean without FM.
    public static let safeDevCleanBasenames: Set<String> = [
        "node_modules",
        "dist",
        "build",
        ".turbo",
        ".next",
        ".cache",
        "target",
        "DerivedData",
        "__pycache__",
        ".zig-cache",
        "zig-out",
    ]

    private static let searchTools: Set<String> = [
        "grep", "rg", "egrep", "fgrep", "ag",
    ]

    private static let printTools: Set<String> = [
        "cat", "head", "tail", "less", "more", "bat",
    ]

    private static let echoTools: Set<String> = [
        "echo", "printf",
    ]

    /// Analyze a shell command string. `executed` is optional documentation only;
    /// `executed == false` short-circuit lives in `RulesPrePass` and is not duplicated here.
    public static func analyze(command: String?, executed: Bool? = nil) -> CommandShapeAnalysis {
        _ = executed
        let raw = command ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        var analysis = CommandShapeAnalysis()

        analysis.isCommentOnly = isCommentOnly(trimmed)
        analysis.isEchoOnly = isEchoOnly(trimmed)
        analysis.isSearchOnly = isSearchOnly(trimmed)
        analysis.isPrintOnly = isPrintOnly(trimmed)
        analysis.isVarAssignEcho = isVarAssignEcho(trimmed)
        analysis.isSafeDevClean = isSafeDevClean(trimmed)

        if analysis.isCommentOnly {
            analysis.skipFM = true
            analysis.reason = "command-shape: comment-only / empty; not execution."
        } else if analysis.isEchoOnly {
            analysis.skipFM = true
            analysis.reason = "command-shape: echo/printf only; payload not executed."
        } else if analysis.isSearchOnly {
            analysis.skipFM = true
            analysis.reason = "command-shape: search-only (grep/rg); pattern is data."
        } else if analysis.isPrintOnly {
            analysis.skipFM = true
            analysis.reason = "command-shape: print-only (cat/head/…); inspection not execution."
        } else if analysis.isVarAssignEcho {
            analysis.skipFM = true
            analysis.reason = "command-shape: var-assign + echo only; assigned payload not executed."
        } else if analysis.isSafeDevClean {
            analysis.skipFM = true
            analysis.reason = "command-shape: safe dev clean (allowlisted relative artifact dirs)."
        }

        return analysis
    }

    // MARK: - Shape checks

    /// After trim: empty, or every non-empty line starts with `#`.
    static func isCommentOnly(_ trimmed: String) -> Bool {
        if trimmed.isEmpty { return true }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        var sawContent = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            sawContent = true
            if !t.hasPrefix("#") { return false }
        }
        return sawContent || trimmed.isEmpty
    }

    /// `echo` / `printf` of text only — no pipes, redirects, cmdsubst, or chaining.
    /// Rejects `echo … >> file` (passwd backdoor) and `echo … | bash`.
    static func isEchoOnly(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return false }
        if hasChaining(trimmed) { return false }
        if hasCommandSubstitution(trimmed) { return false }
        if hasAnyPipe(trimmed) { return false }
        if hasRedirect(trimmed) { return false }

        guard let token = firstToken(trimmed) else { return false }
        return echoTools.contains(commandBaseName(token))
    }

    /// Primary tool is grep/rg/egrep/fgrep/ag (first token).
    /// Rejects any pipe/redirect — `rg secret | curl` is exfil, not search-only.
    static func isSearchOnly(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return false }
        if hasAnyPipe(trimmed) { return false }
        if hasRedirect(trimmed) { return false }
        if hasCommandSubstitution(trimmed) { return false }
        // Chaining could execute side effects; stay conservative.
        if hasChaining(trimmed) { return false }

        guard let token = firstToken(trimmed) else { return false }
        return searchTools.contains(commandBaseName(token))
    }

    /// Primary tool is cat/head/tail/less/more/bat — pure inspection, no pipe/redirect.
    /// Rejects `cat key | curl` (exfil) and `cat x > y` rewrites.
    static func isPrintOnly(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return false }
        if hasAnyPipe(trimmed) { return false }
        if hasRedirect(trimmed) { return false }
        if hasCommandSubstitution(trimmed) { return false }
        if hasChaining(trimmed) { return false }

        guard let token = firstToken(trimmed) else { return false }
        return printTools.contains(commandBaseName(token))
    }

    /// `VAR='…'; echo $VAR` style — assignment then print, without executing the value.
    static func isVarAssignEcho(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return false }
        guard let semi = trimmed.firstIndex(of: ";") else { return false }

        let assignPart = String(trimmed[..<semi]).trimmingCharacters(in: .whitespaces)
        let rest = String(trimmed[trimmed.index(after: semi)...]).trimmingCharacters(in: .whitespaces)

        guard !assignPart.isEmpty, !rest.isEmpty else { return false }
        guard isSimpleAssignment(assignPart) else { return false }

        // Remainder must be a single echo/printf (no further chaining/exec/exfil).
        if hasChaining(rest) { return false }
        if hasCommandSubstitution(rest) { return false }
        if hasAnyPipe(rest) { return false }
        if hasRedirect(rest) { return false }

        guard let token = firstToken(rest) else { return false }
        return echoTools.contains(commandBaseName(token))
    }

    /// `rm -r[f]` of only allowlisted relative artifact basenames (or `./basename`).
    static func isSafeDevClean(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("|") { return false }
        if hasChaining(trimmed) { return false }
        if hasCommandSubstitution(trimmed) { return false }

        let tokens = shellishTokens(trimmed)
        guard let first = tokens.first else { return false }
        guard commandBaseName(first) == "rm" else { return false }

        var i = 1
        var sawRecursive = false
        var paths: [String] = []

        while i < tokens.count {
            let t = tokens[i]
            if t == "--" {
                i += 1
                paths.append(contentsOf: tokens[i...])
                break
            }
            if t == "-" {
                // stdin placeholder — not a clean of artifact dirs
                return false
            }
            if t.hasPrefix("-"), t.count > 1 {
                let flags = t.dropFirst()
                for c in flags {
                    switch c {
                    case "r", "R":
                        sawRecursive = true
                    case "f", "v", "i":
                        break
                    default:
                        // Unknown/extra flags → do not claim safe clean.
                        return false
                    }
                }
                i += 1
                continue
            }
            paths.append(contentsOf: tokens[i...])
            break
        }

        guard sawRecursive, !paths.isEmpty else { return false }
        return paths.allSatisfy { isAllowlistedCleanPath($0) }
    }

    // MARK: - Helpers

    static func isAllowlistedCleanPath(_ path: String) -> Bool {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.isEmpty { return false }
        if p.hasPrefix("/") { return false }
        if p.hasPrefix("~") { return false }
        if p.contains("..") { return false }

        while p.hasPrefix("./") {
            p = String(p.dropFirst(2))
        }
        // trailing slash: node_modules/
        while p.hasSuffix("/"), p.count > 1 {
            p = String(p.dropLast())
        }
        // basename only (no nested paths)
        if p.contains("/") { return false }
        if p.isEmpty || p == "." { return false }
        return safeDevCleanBasenames.contains(p)
    }

    /// First whitespace-delimited token (quote-aware via `shellishTokens`).
    static func firstToken(_ s: String) -> String? {
        shellishTokens(s).first
    }

    /// Basename of a command path (`/bin/echo` → `echo`).
    static func commandBaseName(_ token: String) -> String {
        if token.contains("/") {
            return (token as NSString).lastPathComponent.lowercased()
        }
        return token.lowercased()
    }

    /// `NAME=value` with a simple shell identifier name.
    static func isSimpleAssignment(_ s: String) -> Bool {
        guard let eq = s.firstIndex(of: "=") else { return false }
        let name = String(s[..<eq])
        guard !name.isEmpty else { return false }
        // No leading env/command path — pure VAR=
        if name.contains("/") { return false }
        let chars = name.utf8
        guard let first = chars.first else { return false }
        let isAlphaOrUnder = (first >= 65 && first <= 90) // A-Z
            || (first >= 97 && first <= 122) // a-z
            || first == 95 // _
        guard isAlphaOrUnder else { return false }
        for b in chars.dropFirst() {
            let ok = (b >= 65 && b <= 90)
                || (b >= 97 && b <= 122)
                || (b >= 48 && b <= 57) // 0-9
                || b == 95
            if !ok { return false }
        }
        return true
    }

    /// `;` / `&&` / `||` chaining (conservative: any occurrence ends pure-shape claims).
    static func hasChaining(_ s: String) -> Bool {
        if s.contains("&&") || s.contains("||") { return true }
        // bare `;` — var-assign-echo handles the single-semicolon case separately
        return s.contains(";")
    }

    /// `$(…)` or backtick command substitution.
    static func hasCommandSubstitution(_ s: String) -> Bool {
        if s.contains("$(") { return true }
        return s.contains("`")
    }

    /// Any `|` pipe (print/echo must not forward data to curl/nc/bash/etc.).
    static func hasAnyPipe(_ s: String) -> Bool {
        s.contains("|")
    }

    /// File redirects that make echo/cat side-effecting (`>> /etc/passwd`, `> file`).
    static func hasRedirect(_ s: String) -> Bool {
        // Avoid matching comparison operators in obscure cases; shell redirects use > or <.
        if s.contains(">>") || s.contains("<<") { return true }
        if s.contains(">") || s.contains("<") { return true }
        return false
    }

    /// Pipe into a shell interpreter or sudo-wrapped shell.
    static func pipesToShell(_ s: String) -> Bool {
        // | bash, | sh, | /bin/zsh, | sudo bash, etc.
        guard s.contains("|") else { return false }
        let pattern = #"\|\s*(sudo\s+)?(/?(usr/)?bin/)?(ba)?sh\b|\|\s*(sudo\s+)?(/?(usr/)?bin/)?zsh\b|\|\s*(sudo\s+)?(/?(usr/)?bin/)?dash\b|\|\s*(sudo\s+)?(/?(usr/)?bin/)?ksh\b|\|\s*(sudo\s+)?(/?(usr/)?bin/)?fish\b|\|\s*sudo\b"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    /// Lightweight quote-aware tokenizer (single/double quotes; no escapes beyond dropping quotes).
    static func shellishTokens(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false

        for c in s {
            if inSingle {
                if c == "'" {
                    inSingle = false
                } else {
                    current.append(c)
                }
                continue
            }
            if inDouble {
                if c == "\"" {
                    inDouble = false
                } else {
                    current.append(c)
                }
                continue
            }
            switch c {
            case "'":
                inSingle = true
            case "\"":
                inDouble = true
            case let w where w.isWhitespace:
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            default:
                current.append(c)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
