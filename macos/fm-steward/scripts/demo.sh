#!/usr/bin/env bash
# Demo bar for Phase 3 fm-steward fixtures (§6.4).
# Run from anywhere; resolves package root relative to this script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE_FLAG="--human"
if [[ "${1:-}" == "--json" ]]; then
  MODE_FLAG="--json"
fi

run_one() {
  local card="$1"
  local label="$2"
  echo "======== ${label} (${card}) ========"
  swift run fm-steward classify --card "Fixtures/${card}" ${MODE_FLAG}
  echo
}

echo "fm-steward demo (rules pre-pass; default timeout 500ms)"
echo "Package: ${ROOT}"
echo

run_one "bulk_email.json" "bulk outbound → ask + explain"
run_one "vip_email.json" "VIP → ask_sticky_candidate + explain"
run_one "grep_rm_rf.json" "non-executed grep → continue"
run_one "npm_test_loop.json" "test loop → continue"

echo "Done. (W4 hook wiring NOT done; Linux product path skips FM.)"
