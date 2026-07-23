import Foundation

/// Deterministic soft-ask for commands that must escalate even if FM is wrong or slow.
/// Complements Zig hard fence (which may deny some of these entirely in production).
/// These never unlock deny→allow; they only force **ask** with explain.
public enum HardDangerRules {
    /// Basename-aware shell binary: `bash`, `sh`, `zsh`, `dash`, `ksh`, `fish`
    /// with optional path prefix (absolute, relative `./`/`../`, or `~/…`).
    /// Matches `/opt/local/bin/bash`, `/nix/store/…/bin/bash`, `./bash`, bare names.
    private static let shellBin =
        #"(?:(?:\./|\.\./|~/|/)(?:[^\s/]+/)*)?(?:bash|sh|zsh|dash|ksh|fish)\b"#

    /// Optional `sudo` with short flags (`-E`, `-n`, `-i`, `-s`, `-H`, … or `-u user`)
    /// then optional `env`/`command`. `-u user` is matched before bare short clusters.
    private static let shellPrefix =
        #"(?:sudo\s+(?:(?:-u\s+\S+|-[A-Za-z]+)\s+)*)?(?:(?:env|command)\s+)?"#

    /// `sudo -s` / `sudo -i` / `sudo -is` (any short-flag cluster containing `i` or `s`)
    /// as a shell sink **without** requiring a trailing shell binary.
    /// Real sudo: `-s`/`-i` already launch a shell.
    private static let sudoInteractiveShell =
        #"sudo\s+(?:(?:-u\s+\S+|-[A-Za-z]+)\s+)*(?:-[A-Za-z]*[is][A-Za-z]*)\b"#

    /// Full pipe/exec sink: (optional sudo/env + path-optional shell)
    /// **or** bare interactive sudo (`sudo -s` / `sudo -i`) with no shell argv.
    private static var shellSink: String {
        #"(?:\#(shellPrefix)\#(shellBin)|\#(sudoInteractiveShell))"#
    }

    /// `$HOME` / `${HOME}` plus parameter-expansion forms that still expand to home:
    /// `${HOME:-x}`, `${HOME:=x}`, `${HOME:+x}`, `${HOME:?x}`, `${HOME/foo/bar}`, etc.
    private static let homeEnv =
        #"\$home\b|\$\{home(?:[-:=?+/%#][^}]*)?\}"#

    /// If matched, returns an ask* response; else nil (fall through to FM).
    public static func evaluate(_ card: RiskCard) -> ClassifyResponse? {
        guard let raw = card.command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }
        // Only when host says this would execute.
        if card.features.executed == false {
            return nil
        }

        // Collapse newlines / runs of whitespace so multi-line pipe-to-shell cannot bypass.
        let command = normalizeCommand(raw)

        // Match case-insensitively on the original string. Do **not** lowercase first:
        // lowercasing turns `tar -C /` into `tar -c /` and breaks case-sensitive `-C` patterns.
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]

        // Catastrophic / high-impact patterns (soft ask; Zig may hard-deny separately).
        let patterns: [(String, String, String)] = [
            (#"rm\s+(-[a-zA-Z]*r[a-zA-Z]*|--recursive).*/\s*$|rm\s+(-[a-zA-Z]*r[a-zA-Z]*|--recursive).*\s+/"#,
             "Recursive rm targeting filesystem root.",
             "This command recursively deletes from the filesystem root. Confirm before running."),
            // Catastrophic globs: rm -rf /*, rm -rf *, rm -rf ./*
            (#"rm\s+(-[a-zA-Z]*r[a-zA-Z]*|--recursive).*(?:/\*|\./\*|(?<=\s)\*(?:\s|$))"#,
             "Recursive rm with catastrophic root/glob wipe.",
             "This command recursively deletes via a root or wildcard path. Confirm before running."),
            // Home / system paths, including $HOME / ${HOME} and parameter expansions.
            (#"rm\s+(-[a-zA-Z]*r[a-zA-Z]*|--recursive).*(~|/users|/home|/library|/system|"# + homeEnv + #")"#,
             "Recursive rm of home or system paths.",
             "This command recursively deletes home or system paths. Confirm before running."),
            // Obfuscated rm: ${IFS}, $IFS, and quote-split r""m style.
            (#"rm\$\{ifs\}|rm\$ifs\b|r[\"']{1,2}m\s+(-[a-zA-Z]*r|--recursive)"#,
             "Obfuscated recursive rm.",
             "This command uses shell obfuscation around rm. Confirm before running."),
            (#"\bdd\b.*of=/dev/"#,
             "dd writing to a raw device.",
             "This command writes raw data to a disk device. Confirm before running."),
            (#"diskutil\s+erase|mkfs\."#,
             "Disk erase / format tool.",
             "This command erases or formats a disk. Confirm before running."),
            // curl/wget piped to shell (including nested in bash -c '…').
            (#"\b(curl|wget)\b.*\|\s*"# + shellSink,
             "Download piped into a shell.",
             "This downloads and executes remote code via a shell pipe. Confirm before running."),
            // Multi-stage: download to file then run with a shell.
            (#"\b(curl|wget)\b.*(-o|--output)\s+\S+.*(&&|;)\s*"# + shellSink,
             "Download to file then execute with a shell.",
             "This downloads a script and then runs it. Confirm before running."),
            // bash -c "$(curl …)" / zsh -c 'curl …' / /bin/bash -c …
            // Leading optional path so absolute shell paths match without a word-boundary
            // between whitespace and `/` (ICU `\b` is word↔nonword only).
            (#"(?:^|[\s;|&])"# + shellBin + #"\s+-c\b.*\b(curl|wget)\b"#,
             "Shell -c invoking curl/wget.",
             "This runs a shell that fetches remote content. Confirm before running."),
            // Process substitution: bash <(curl …) / zsh <(wget …)
            (#"(?:^|[\s;|&])"# + shellBin + #"\s+<\(.*\b(curl|wget)\b"#,
             "Shell process-substitution of remote download.",
             "This executes a remote download via process substitution. Confirm before running."),
            // eval "$(curl…)" / eval $(wget…) / eval `curl…`
            (#"\beval\b.*\b(curl|wget)\b"#,
             "Eval of remote download.",
             "This evals remote content fetched by curl/wget. Confirm before running."),
            // source <(curl…) / . <(curl…)
            (#"(\bsource\b|(?:^|[\s;|&])\.)\s+<\(.*\b(curl|wget)\b"#,
             "Source process-substitution of remote download.",
             "This sources remote content via process substitution. Confirm before running."),
            (#"\bbase64\b.*\|\s*"# + shellSink,
             "Base64 decode piped into shell.",
             "This decodes and executes a payload in a shell. Confirm before running."),
            // Secret-ish paths or general pipe to network tools (exfil sinks).
            (#"\bcat\s+.*(\.ssh|/id_|credentials|\.env|secrets).*\|\s*(curl|nc|ncat|wget)\b"#,
             "Secret file piped to network tool.",
             "This may exfiltrate secrets over the network. Confirm before running."),
            (#"\|\s*(curl|nc|ncat|wget)\b"#,
             "Pipeline into a network tool.",
             "This pipes data into a network client (possible exfil). Confirm before running."),
            // tar extract onto filesystem root (-C / or --directory /).
            (#"\btar\b.*(-C|--directory)\s*/($|\s)"#,
             "tar extract into filesystem root.",
             "Extracting an archive onto / can overwrite system files. Confirm before running."),
            (#"\btar\b.*(-C|--directory)=/"#,
             "tar extract into filesystem root.",
             "Extracting an archive onto / can overwrite system files. Confirm before running."),
            (#"/dev/tcp/|bash\s+-i\s+>&"#,
             "Reverse shell pattern.",
             "This looks like a reverse shell. Confirm before running."),
            (#"git\s+push\s+.*--force|git\s+push\s+-f\b"#,
             "Git force-push.",
             "Force-push rewrites remote history. Confirm before running."),
            (#"git\s+reset\s+--hard\b"#,
             "Git hard reset.",
             "Hard reset discards local commits and changes. Confirm before running."),
            (#"chmod\s+(-R\s+)?777\s+.*(\.ssh|\.aws|\.gnupg|secrets|credentials|\.env)|chmod\s+(-R\s+)?777\s+~/.ssh"#,
             "World-writable secrets path.",
             "World-writable permissions on credential paths are high risk. Confirm before running."),
            (#">>\s*/etc/passwd|>>\s*/etc/shadow"#,
             "Write to system password database.",
             "This writes to the system password database. Confirm before running."),
            (#"chmod\s+u\+s\s+/bin/bash|chmod\s+u\+s\s+/bin/sh"#,
             "SUID shell binary.",
             "Making a shell SUID is a privilege-escalation risk. Confirm before running."),
            (#"os\.system\s*\(\s*['\"]rm\s+"#,
             "Python os.system recursive delete.",
             "This runs a destructive rm via Python. Confirm before running."),
            (#"\bfind\b.*-delete\b"#,
             "find with -delete.",
             "This bulk-deletes files via find -delete. Confirm before running."),
            (#"\bxargs\s+rm\b|\bxargs\s+.*\brm\b"#,
             "xargs rm bulk delete.",
             "This bulk-deletes via xargs rm. Confirm before running."),
        ]

        for (pattern, why, explain) in patterns {
            if command.range(of: pattern, options: options) != nil {
                return hardAsk(why: why, explain: explain)
            }
        }
        return nil
    }

    /// Collapse `\r`/`\n` and runs of whitespace to a single space so multi-line
    /// `curl …\n| bash` cannot bypass pipe-to-shell patterns.
    static func normalizeCommand(_ command: String) -> String {
        command
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func hardAsk(why: String, explain: String) -> ClassifyResponse {
        // explain is a non-empty constant — make() cannot fail for ask*.
        (try? ClassifyResponse.make(
            verdict: .ask,
            why: why,
            explain: explain,
            suggestedStickyScope: nil,
            suggestedEffectClass: nil,
            timedOut: false,
            fallback: false,
            modelAvailable: false
        )) ?? ClassifyResponse(
            verdict: .ask,
            why: why,
            explain: explain,
            timedOut: false,
            fallback: false,
            modelAvailable: false
        )
    }
}
