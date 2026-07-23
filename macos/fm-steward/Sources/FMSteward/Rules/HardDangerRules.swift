import Foundation

/// Deterministic soft-ask for commands that must escalate even if FM is wrong or slow.
/// Complements Zig hard fence (which may deny some of these entirely in production).
/// These never unlock deny→allow; they only force **ask** with explain.
public enum HardDangerRules {
    /// If matched, returns an ask* response; else nil (fall through to FM).
    public static func evaluate(_ card: RiskCard) -> ClassifyResponse? {
        guard let command = card.command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty
        else {
            return nil
        }
        // Only when host says this would execute.
        if card.features.executed == false {
            return nil
        }

        // Match case-insensitively on the original string. Do **not** lowercase first:
        // lowercasing turns `tar -C /` into `tar -c /` and breaks case-sensitive `-C` patterns.
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]

        // Catastrophic / high-impact patterns (soft ask; Zig may hard-deny separately).
        let patterns: [(String, String, String)] = [
            (#"rm\s+(-[a-zA-Z]*r[a-zA-Z]*|--recursive).*/\s*$|rm\s+(-[a-zA-Z]*r[a-zA-Z]*|--recursive).*\s+/"#,
             "Recursive rm targeting filesystem root.",
             "This command recursively deletes from the filesystem root. Confirm before running."),
            (#"rm\s+(-[a-zA-Z]*r[a-zA-Z]*|--recursive).*(~|/users|/home|/library|/system)"#,
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
            (#"\b(curl|wget)\b[^\n]*\|\s*(sudo\s+)?(ba)?sh\b"#,
             "Download piped into a shell.",
             "This downloads and executes remote code via a shell pipe. Confirm before running."),
            // Multi-stage: download to file then run with a shell.
            (#"\b(curl|wget)\b[^\n]*(-o|--output)\s+\S+[^\n]*(&&|;)\s*(sudo\s+)?(ba)?sh\b"#,
             "Download to file then execute with a shell.",
             "This downloads a script and then runs it. Confirm before running."),
            // bash -c "$(curl …)" / bash -c 'curl …'
            (#"\b(ba)?sh\b\s+-c\b[^\n]*\b(curl|wget)\b"#,
             "Shell -c invoking curl/wget.",
             "This runs a shell that fetches remote content. Confirm before running."),
            // Process substitution: bash <(curl …)
            (#"\b(ba)?sh\b\s+<\([^\n]*\b(curl|wget)\b"#,
             "Shell process-substitution of remote download.",
             "This executes a remote download via process substitution. Confirm before running."),
            (#"\bbase64\b[^\n]*\|\s*(ba)?sh\b"#,
             "Base64 decode piped into shell.",
             "This decodes and executes a payload in a shell. Confirm before running."),
            // Secret-ish paths or general pipe to network tools (exfil sinks).
            (#"\bcat\s+[^\n]*(\.ssh|/id_|credentials|\.env|secrets)[^\n]*\|\s*(curl|nc|ncat|wget)\b"#,
             "Secret file piped to network tool.",
             "This may exfiltrate secrets over the network. Confirm before running."),
            (#"\|\s*(curl|nc|ncat|wget)\b"#,
             "Pipeline into a network tool.",
             "This pipes data into a network client (possible exfil). Confirm before running."),
            // tar extract onto filesystem root (-C / or --directory /).
            (#"\btar\b[^\n]*(-C|--directory)\s*/($|\s)"#,
             "tar extract into filesystem root.",
             "Extracting an archive onto / can overwrite system files. Confirm before running."),
            (#"\btar\b[^\n]*(-C|--directory)=/"#,
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
            (#"\bfind\b[^\n]*-delete\b"#,
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
