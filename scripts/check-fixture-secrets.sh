#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Scans fixtures/ and tests/ only. src/ test strings use separate synthetic markers
# and are covered by unit tests plus redact_bridge fuzz fixtures.

# Synthetic markers documented in docs/credentials.md — allowed in fixtures/tests.
ALLOW_SYNTHETIC=(
  'fakeSynthetic'
  'ghp_fake'
  'sk-fake'
  'sk-ant-fake'
  'fake_p05_'
  'sk-legacyWorkspaceSyntheticSecret'
  'fake_secret_value'
)

# High-signal secret shapes that must not appear unless allowlisted.
PATTERNS=(
  'sk-[A-Za-z0-9]{20,}'
  'sk-ant-[A-Za-z0-9]{20,}'
  'ghp_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  'AKIA[0-9A-Z]{16}'
)

SCAN_PATHS=(
  fixtures
  tests
)

is_allowlisted() {
  local line="$1"
  for marker in "${ALLOW_SYNTHETIC[@]}"; do
    if [[ "$line" == *"$marker"* ]]; then
      return 0
    fi
  done
  return 1
}

violations=0

for scan_root in "${SCAN_PATHS[@]}"; do
  [[ -d "$scan_root" ]] || continue
  while IFS= read -r -d '' file; do
    line_no=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      line_no=$((line_no + 1))
      for pattern in "${PATTERNS[@]}"; do
        if [[ "$line" =~ $pattern ]] && ! is_allowlisted "$line"; then
          echo "fixture-secret-violation: ${file}:${line_no}: matches /${pattern}/ without synthetic allowlist marker" >&2
          violations=$((violations + 1))
          break
        fi
      done
    done <"$file"
  done < <(find "$scan_root" -type f \( -name '*.zig' -o -name '*.yaml' -o -name '*.yml' -o -name '*.md' -o -name '*.json' -o -name '*.jsonl' -o -name '*.ts' -o -name '*.env' \) -print0)
done

if [[ "$violations" -gt 0 ]]; then
  echo "check-fixture-secrets: ${violations} violation(s); use synthetic markers from docs/credentials.md" >&2
  exit 1
fi

echo "check-fixture-secrets: ok (${#PATTERNS[@]} patterns, ${#ALLOW_SYNTHETIC[@]} synthetic allowlist markers)"