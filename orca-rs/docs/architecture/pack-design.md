# Pack Architecture Decisions

This document captures the architectural decisions required before expanding
pack coverage. It is the canonical reference for pack authors and reviewers.

## 1) REST API Pattern Detection (curl/httpie)

**Decision**: Hybrid detection (keyword gate + lightweight argument parsing).

- **Gate** on `curl`, `http`, or `httpie` keywords to avoid touching every command.
- **Parse** method flags (`-X`, `--request`, `--method`) and extract the URL.
- **Pack-specific host filters**: each pack owns its hostnames or URL prefixes.
- **Decision rule**: only treat `DELETE` (and other explicitly destructive methods)
  as destructive when the host/path match a pack.

**Rationale**: A pure keyword scan is too noisy; full AST parsing is too slow.
The hybrid approach is fast, deterministic, and maintainable.

## 2) Pack Overlap Resolution

**Decision**: Keep packs separate but clarify boundaries.

From `git_safety_guard-qdhh`: `cicd.github_actions` is for CI operations
(secrets, variables, workflows, runs). `platform.github` is for broader platform
operations (repos, releases, deploy keys, webhooks, collaborators). Do not
duplicate patterns across packs; document scope in pack descriptions.

**Rationale**: Separation reduces regex scope and allows users to enable only
what they need. Clear boundaries avoid duplication and false positives.

## 3) Command Alias Handling

**Decision**: Explicit aliases for high-impact, common tools plus opt-in config.

- Include **well-known aliases** in keywords (e.g., `k` for `kubectl`).
- Avoid regex alias heuristics that cause false positives.
- Allow **user config** to add custom aliases via pack enablement/keywords.

**Rationale**: Minimizes noise while still covering common shortcuts.

## 4) Performance Budget Per Pack

**Decision**: Enforce a per-pack budget and pattern cap.

- **Budget**: < 500 microseconds per pack evaluation.
- **Pattern cap**: < 50 total patterns per pack.
- **Keywords**: minimal and specific; avoid broad single-letter keywords.

**Rationale**: Keeps pack expansion from degrading hook latency.

## 5) Safe vs Destructive Threshold

**Decision**: Flag-aware matching with explicit safe overrides.

- **Destructive by default**: commands known to delete or destroy data (e.g.,
  `rclone sync`, `aws s3 rm --recursive`) should be blocked even without flags.
- **Flag-sensitive**: allow **dry-run/preview** flags and safe variants.
- **Ambiguous commands**: only block when flags or subcommands are clearly
  destructive; otherwise allow with high-signal patterns.

**Rationale**: Reduces false positives while still blocking dangerous actions.

## Acceptance Criteria Mapping

- Decisions documented with rationale (this doc).
- Performance budget defined and referenced by pack checklist.
- Pack overlap resolution aligned with `git_safety_guard-qdhh`.

## Open Questions

- Which alias list should be system defaults vs per-user config?
- How to represent host allowlists for REST APIs in pack metadata?
