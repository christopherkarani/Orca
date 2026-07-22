# Shell engine parity exclusions

Intentional allow/deny divergences from the frozen oracle corpus / regressions.

| Case | Rationale |
|------|-----------|
| *(none)* | Default empty — full decision parity required. |

## Ported regression surfaces (not excluded)

| Surface | Zig fixture / gate |
|---------|-------------------|
| Oracle `tests/corpus/**` | `src/shell_engine/parity_corpus.jsonl` (351 cases, 100% decision + rule_id when provided) via `zig build test-shell-engine` |
| `security_regressions_v2` quoting / wrapper / heredoc-delimiter | `src/shell_engine/security_regressions.jsonl` |
| `security_regressions_v3` internal-escape / mixed-quote / heredoc `<<\EOF` | same JSONL |
| `repro_normalization_bypass` (path-prefixed git/rm) | same JSONL |
| `repro_safe_pattern_bypass` (safe-prefix + destructive compound) | same JSONL |
| `repro_line_continuation_split` / `repro_line_continuation_bypass` | same JSONL |
| `repro_echo_fp` (`echo rm -rf /` → allow) | same JSONL (u01 allow/deny port) |
| `repro_comment_fp` (`ls -la # rm -rf /` → allow) | same JSONL (u01 allow/deny port) |
| `repro_rm_multi_arg` (multi-arg `rm` with sensitive path → deny) | same JSONL (u01 allow/deny port) |
| `repro_newline_separator` (newline in commit message / separator → deny) | same JSONL (u01 allow/deny port) |
| `repro_redirection_bypass` (`git>/dev/null` / quoted argv0 / `command >>/dev/null git …`) | same JSONL + unit tests in `normalize.zig` / `mod.zig` |
| Remaining `repro_*.rs` / `security_regressions*.rs` that only assert daemon lifecycle, TUI, or non-allow/deny transport | Out of scope per plan non-goals (not decision parity) |

Decision exclusions stay empty: every extractable oracle allow/deny case belongs in corpus or `security_regressions.jsonl`, not here.

## Documented rule_id aliases (decision still matches)

| Oracle `rule_id` | Zig `rule_id` | Notes |
|------------------|---------------|-------|
| `heredoc.python:shutil_rmtree` | `core.filesystem:rm-rf-*` | Embed body evaluated as pack pattern |
| `heredoc.bash:rm_rf` | `core.filesystem:rm-rf-*` | Same |
| Family `rm-*` / `push-force*` / `find-delete*` | same family | Exact pattern name preferred when identical |

## Intentional product differences (not exclusions)

| Topic | Notes |
|-------|-------|
| Evaluator / registry init failure | Zig **fail-closed** deny (Rust hook transport often fail-open). |
| Empty command | No-op **allow** (matches oracle). |
| Default pack set | Matches Rust `Config::default()`: category `core` + `system.disk`. Full 85 packs via `EvaluateOptions.default_packs_only = false`. |
